import '../config/api_config.dart';

abstract final class ImageUrlHelper {
  /// Normalizes an avatar or profile image URL.
  ///
  /// - Strips whitespace and nulls empty strings.
  /// - If relative (e.g. `/uploads/...`), prepends [ApiConfig.baseUrl].
  /// - Rewrites `localhost:3000` to [ApiConfig.baseUrl] if pointing to local host in API responses.
  static String? normalize(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed == 'null') return null;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      if (trimmed.contains('localhost:3000') ||
          trimmed.contains('127.0.0.1:3000') ||
          trimmed.contains('10.0.2.2:3000')) {
        return trimmed.replaceFirst(
          RegExp(r'https?://(localhost|127\.0\.0\.1|10\.0\.2\.2):3000'),
          ApiConfig.baseUrl,
        );
      }
      return trimmed;
    }

    if (trimmed.startsWith('/')) {
      return '${ApiConfig.baseUrl}$trimmed';
    }
    return '${ApiConfig.baseUrl}/$trimmed';
  }
}
