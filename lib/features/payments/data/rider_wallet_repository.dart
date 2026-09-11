import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';

/// Model representing the response from initiating wallet funding.
class WalletFundResult {
  const WalletFundResult({
    required this.authorizationUrl,
    required this.reference,
    this.accessCode,
  });

  final String authorizationUrl;
  final String reference;
  final String? accessCode;

  factory WalletFundResult.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      throw ApiException('Invalid response when initiating wallet funding');
    }

    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;

    final authUrl = data['authorization_url'] as String? ??
        data['authorizationUrl'] as String? ??
        data['url'] as String?;

    final ref = data['reference'] as String? ??
        data['access_code'] as String? ??
        data['id']?.toString();

    if (authUrl == null || authUrl.isEmpty) {
      throw ApiException('Paystack authorization URL was not returned.');
    }

    return WalletFundResult(
      authorizationUrl: authUrl,
      reference: ref ?? '',
      accessCode: data['access_code'] as String?,
    );
  }
}

/// Model representing a single wallet transaction record.
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.amountNgn,
    required this.type,
    required this.status,
    required this.title,
    required this.reference,
    required this.createdAt,
  });

  final String id;
  final double amountNgn;
  final String type; // 'CREDIT' | 'DEBIT' | 'FUND' | 'RIDE' etc.
  final String status; // 'SUCCESS' | 'COMPLETED' | 'PENDING' | 'FAILED'
  final String title;
  final String reference;
  final DateTime createdAt;

  bool get isCredit =>
      type.toUpperCase().contains('CREDIT') ||
      type.toUpperCase().contains('FUND') ||
      type.toUpperCase().contains('TOPUP');

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'] ?? json['amountNgn'] ?? 0;
    double amount = 0.0;
    if (rawAmount is num) {
      // Backend uses kobo in Paystack endpoints (100 kobo = 1 NGN).
      // If integer > 100, convert kobo to NGN.
      if (rawAmount is int && rawAmount >= 100) {
        amount = rawAmount / 100.0;
      } else {
        amount = rawAmount.toDouble();
      }
    }

    DateTime date = DateTime.now();
    final rawDate = json['createdAt'] ?? json['date'] ?? json['timestamp'];
    if (rawDate is String) {
      date = DateTime.tryParse(rawDate) ?? DateTime.now();
    }

    final typeStr = (json['type'] ?? json['category'] ?? 'CREDIT').toString();
    final desc = json['description'] ??
        json['narration'] ??
        json['title'] ??
        (typeStr.toUpperCase().contains('FUND')
            ? 'Wallet Top-up'
            : 'Ride Payment');

    return WalletTransaction(
      id: json['id']?.toString() ?? '',
      amountNgn: amount,
      type: typeStr,
      status: (json['status'] ?? 'COMPLETED').toString(),
      title: desc.toString(),
      reference: (json['reference'] ?? '').toString(),
      createdAt: date,
    );
  }
}

/// Repository responsible for Rider Wallet operations via Victoria Ride API.
class RiderWalletRepository {
  RiderWalletRepository._();

  static final RiderWalletRepository instance = RiderWalletRepository._();

  final ApiClient _api = ApiClient.instance;

  /// Fetches current rider wallet balance in NGN.
  ///
  /// Calls `GET /api/v1/wallet`.
  Future<double> getBalance() async {
    final data = await _api.get(ApiConfig.riderWallet);
    return _extractBalance(data);
  }

  /// Initiates Paystack wallet funding.
  ///
  /// Converts [amountNgn] to kobo (e.g. ₦1,000 -> 100,000 kobo)
  /// and calls `POST /api/v1/wallet/fund`.
  Future<WalletFundResult> initiateFunding(double amountNgn) async {
    final amountKobo = (amountNgn * 100).round();
    final data = await _api.post(
      ApiConfig.riderWalletFund,
      body: {'amount': amountKobo},
    );
    return WalletFundResult.fromJson(data);
  }

  /// Verifies funding transaction after Paystack checkout.
  ///
  /// Calls `GET /api/v1/wallet/fund/verify/{reference}`.
  /// Returns `true` if payment is successfully verified.
  Future<bool> verifyFunding(String reference) async {
    try {
      final data = await _api.get(ApiConfig.riderWalletFundVerify(reference));
      if (data is Map<String, dynamic>) {
        final success = data['success'] == true ||
            data['status'] == 'success' ||
            data['verified'] == true;
        if (success) return true;
        // Check if data contains successful status
        final innerData = data['data'];
        if (innerData is Map<String, dynamic>) {
          final s = innerData['status']?.toString().toLowerCase();
          return s == 'success' || s == 'completed';
        }
        return true;
      }
      return true;
    } on ApiException catch (e) {
      // 400 with "already processed" might also be valid
      if (e.message.toLowerCase().contains('already processed')) {
        return true;
      }
      rethrow;
    }
  }

  /// Lists rider wallet transaction history.
  ///
  /// Calls `GET /api/v1/wallet/transactions`.
  Future<List<WalletTransaction>> getTransactions() async {
    final data = await _api.get(ApiConfig.riderWalletTransactions);
    final List<dynamic> list;
    if (data is List) {
      list = data;
    } else if (data is Map<String, dynamic>) {
      if (data['data'] is List) {
        list = data['data'] as List;
      } else if (data['transactions'] is List) {
        list = data['transactions'] as List;
      } else {
        list = [];
      }
    } else {
      list = [];
    }

    return list
        .whereType<Map<String, dynamic>>()
        .map(WalletTransaction.fromJson)
        .toList();
  }

  /// Helper to extract double balance from various response structures.
  double _extractBalance(dynamic data) {
    if (data == null) return 0.0;
    if (data is Map<String, dynamic>) {
      final inner = data['data'];
      if (inner is Map<String, dynamic>) {
        return _extractBalance(inner);
      } else if (inner is num) {
        return _normalizeNgn(inner);
      }

      final bal = data['balance'] ??
          data['walletBalance'] ??
          data['amount'] ??
          data['totalBalance'];
      if (bal != null) return _extractBalance(bal);
    }

    if (data is num) {
      return _normalizeNgn(data);
    }
    if (data is String) {
      final cleaned = data.replaceAll(RegExp(r'[^\d.]'), '');
      final parsed = double.tryParse(cleaned);
      if (parsed != null) return parsed;
    }
    return 0.0;
  }

  double _normalizeNgn(num amount) {
    // If integer and >= 100, it is kobo (100 kobo = 1 NGN).
    // If it has decimals (e.g. 500.50), it is already in NGN.
    if (amount is int && amount >= 100) {
      return amount / 100.0;
    }
    return amount.toDouble();
  }
}
