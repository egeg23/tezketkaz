import 'api_client.dart';

/// Phase 8.5 — courier instant-payout API client.
///
/// Wraps:
/// - `GET  /api/couriers/me/balance` → [PayoutBalance]
/// - `POST /api/couriers/me/payout/request` → raw payload (Payout JSON)
class PayoutApi {
  PayoutApi._();
  static final PayoutApi instance = PayoutApi._();

  final _api = ApiClient.instance;

  Future<PayoutBalance> myBalance() async {
    final res = await _api.get('/api/couriers/me/balance');
    final raw = res.data;
    if (raw is! Map) return PayoutBalance.empty();
    return PayoutBalance.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Returns the new payout document on success. On a `400` (e.g. balance
  /// below the minimum, pending request), the underlying [ApiException] is
  /// thrown with the backend message — callers should `try/catch` to surface
  /// it via a snackbar.
  Future<Map<String, dynamic>> request() async {
    final res = await _api.post('/api/couriers/me/payout/request');
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}

class PayoutBalance {
  final num availableBalance;
  final String currency;
  final num minPayout;
  final bool hasPending;

  const PayoutBalance({
    required this.availableBalance,
    required this.currency,
    required this.minPayout,
    required this.hasPending,
  });

  factory PayoutBalance.empty() => const PayoutBalance(
        availableBalance: 0,
        currency: 'UZS',
        minPayout: 0,
        hasPending: false,
      );

  bool get canRequest =>
      !hasPending && minPayout > 0 && availableBalance >= minPayout;

  factory PayoutBalance.fromJson(Map<String, dynamic> j) => PayoutBalance(
        availableBalance: _toNum(j['availableBalance'] ?? j['balance']),
        currency: (j['currency'] as String?) ?? 'UZS',
        minPayout: _toNum(j['minPayout']),
        hasPending: j['hasPending'] == true,
      );
}

num _toNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse(v.toString()) ?? 0;
}
