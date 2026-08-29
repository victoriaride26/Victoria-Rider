import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../config/api_config.dart';
import '../services/session_controller.dart';

/// A single binary part of a multipart request.
class MultipartPart {
  const MultipartPart({
    required this.bytes,
    required this.filename,
    this.contentType = 'application/octet-stream',
  });

  final List<int> bytes;
  final String filename;
  final String contentType;
}

/// Error thrown for any non-2xx API response or transport failure.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.errors, this.data});

  final String message;

  /// HTTP status code, `null` for network-level failures.
  final int? statusCode;

  /// Optional field-level validation errors returned by the API.
  final Map<String, dynamic>? errors;

  /// Optional structured payload (e.g. KYC submit's
  /// `missingRequirements` / `missingDocuments` lists).
  final Map<String, dynamic>? data;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  /// True for 5xx responses — transient server-side failures.
  bool get isServerError =>
      statusCode != null && statusCode! >= 500 && statusCode! <= 599;

  @override
  String toString() => message;
}

/// Thin JSON HTTP client for the Victoria Ride API.
///
/// Automatically attaches the driver's bearer token and decodes JSON
/// responses. All repository classes use this as their transport.
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  /// Overridable in widget tests to stub HTTP responses.
  @visibleForTesting
  static void setTestClient(http.Client client) {
    instance._http = client;
  }

  http.Client _http = http.Client();

  static const _timeout = Duration(seconds: 30);

  Map<String, String> get _headers => const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Map<String, String> _authorizedHeaders() {
    final token = SessionController.instance.accessToken;
    return {
      ..._headers,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// In-flight refresh guard so parallel requests share one rotation.
  Future<bool>? _refreshInFlight;

  /// Exchanges the stored refresh token for a fresh pair.
  ///
  /// The backend rotates refresh tokens on every use, so concurrent 401s
  /// must share a single refresh attempt. Returns true when a new access
  /// token is available afterwards.
  Future<bool> _tryRefresh() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refreshToken = SessionController.instance.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await _http
          .post(
            Uri.parse(ApiConfig.refresh),
            headers: _headers,
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return false;
      dynamic body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        return false;
      }
      String? access;
      String? refresh;
      if (body is Map<String, dynamic>) {
        final tokens = body['tokens'];
        if (tokens is Map<String, dynamic>) {
          access = tokens['accessToken'] as String?;
          refresh = tokens['refreshToken'] as String?;
        }
        access ??= body['accessToken'] as String?;
        refresh ??= body['refreshToken'] as String?;
      }
      if (access == null || access.isEmpty) return false;
      await SessionController.instance.save(
        accessToken: access,
        refreshToken: refresh,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Runs [send], transparently refreshing once and retrying when the
  /// API rejects the current access token (15-minute expiry).
  Future<http.Response> _run(Future<http.Response> Function() send) async {
    var response = await send();
    if (response.statusCode == 401 && await _tryRefresh()) {
      response = await send();
    }
    return response;
  }

  Future<dynamic> get(String url, {Map<String, String>? query}) async {
    try {
      return _handle(
        await _run(
          () => _http
              .get(
                Uri.parse(url).replace(
                  queryParameters:
                      (query == null || query.isEmpty) ? null : query,
                ),
                headers: _authorizedHeaders(),
              )
              .timeout(_timeout),
        ),
      );
    } on SocketException {
      throw ApiException('No internet connection. Please try again.');
    }
  }

  Future<dynamic> post(String url, {Object? body}) async {
    try {
      return _handle(
        await _run(
          () => _http
              .post(
                Uri.parse(url),
                headers: _authorizedHeaders(),
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(_timeout),
        ),
      );
    } on SocketException {
      throw ApiException('No internet connection. Please try again.');
    }
  }

  Future<dynamic> patch(String url, {Object? body}) async {
    try {
      return _handle(
        await _run(
          () => _http
              .patch(
                Uri.parse(url),
                headers: _authorizedHeaders(),
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(_timeout),
        ),
      );
    } on SocketException {
      throw ApiException('No internet connection. Please try again.');
    }
  }

  /// Multipart request used by KYC document and driver-profile updates.
  ///
  /// When [fileBytes] is provided it is attached as [fileField]; [parts]
  /// sends any number of named binary parts alongside it (e.g.
  /// `frontView`/`backView` on the vehicle endpoint).
  Future<dynamic> multipartPost(
    String url, {
    required Map<String, String> fields,
    List<int>? fileBytes,
    String? filename,
    String fileField = 'file',
    Map<String, MultipartPart> parts = const {},
    String contentType = 'application/octet-stream',
    String method = 'POST',
  }) async {
    http.MultipartRequest buildRequest() {
      final request = http.MultipartRequest(method, Uri.parse(url))
        ..fields.addAll(fields);
      final bytes = fileBytes;
      if (bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            fileField,
            bytes,
            filename: filename ?? 'upload',
            contentType: http.MediaType.parse(contentType),
          ),
        );
      }
      for (final entry in parts.entries) {
        request.files.add(
          http.MultipartFile.fromBytes(
            entry.key,
            entry.value.bytes,
            filename: entry.value.filename,
            contentType: http.MediaType.parse(entry.value.contentType),
          ),
        );
      }
      request.headers.addAll(_authorizedHeaders());
      return request;
    }

    try {
      Future<http.Response> send() async {
        final streamed =
            await _http.send(buildRequest()).timeout(_timeout);
        return http.Response.fromStream(streamed);
      }

      return _handle(await _run(send));
    } on SocketException {
      throw ApiException('No internet connection. Please try again.');
    }
  }

  dynamic _handle(http.Response response) {
    final code = response.statusCode;
    final ok = code >= 200 && code < 300;
    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = response.body;
      }
    }
    if (!ok) {
      if (body is Map<String, dynamic>) {
        final message = body['message'] ?? body['error'];
        throw ApiException(
          message is String && message.isNotEmpty
              ? message
              : 'Request failed ($code)',
          statusCode: code,
          errors: body['errors'] is Map<String, dynamic>
              ? body['errors'] as Map<String, dynamic>
              : null,
          data: body['data'] is Map<String, dynamic>
              ? body['data'] as Map<String, dynamic>
              : null,
        );
      }
      throw ApiException('Request failed ($code)', statusCode: code);
    }
    return body;
  }

  void dispose() => _http.close();
}
