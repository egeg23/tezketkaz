import '../models/payment_method.dart';
import 'api_client.dart';

/// Result of `POST /api/payment-methods/me/tokenize`.
///
/// In production the backend returns a `redirectUrl` to open in a WebView;
/// in dev mode it short-circuits and gives back a `mockToken` so the buyer
/// can confirm the card without leaving the app.
class TokenizeResult {
  final String? redirectUrl;
  final String? mockToken;
  final String state;

  const TokenizeResult({
    this.redirectUrl,
    this.mockToken,
    required this.state,
  });

  factory TokenizeResult.fromJson(Map<String, dynamic> j) => TokenizeResult(
        redirectUrl: j['redirectUrl'] as String?,
        mockToken: j['mockToken'] as String?,
        state: (j['state'] as String?) ?? '',
      );
}

/// Wraps Phase 6 saved payment-method endpoints. Uses the same `ApiClient`
/// as the rest of the app so refresh-on-401 keeps working.
class PaymentMethodApi {
  PaymentMethodApi._();
  static final PaymentMethodApi instance = PaymentMethodApi._();

  final _api = ApiClient.instance;

  Future<List<PaymentMethod>> list() async {
    final res = await _api.get('/api/payment-methods/me');
    final raw = res.data;
    final list = raw is List
        ? raw
        : (raw is Map && raw['paymentMethods'] is List
            ? raw['paymentMethods'] as List
            : (raw is Map && raw['methods'] is List
                ? raw['methods'] as List
                : const <dynamic>[]));
    return list
        .map((j) => PaymentMethod.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<TokenizeResult> startTokenize(String provider) async {
    final res = await _api.post('/api/payment-methods/me/tokenize', {
      'provider': provider,
    });
    final data = res.data;
    if (data is Map<String, dynamic>) return TokenizeResult.fromJson(data);
    return TokenizeResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<PaymentMethod> confirm({
    required String provider,
    String? mockToken,
    String? last4,
    String? brand,
  }) async {
    final res = await _api.post('/api/payment-methods/me/confirm', {
      'provider': provider,
      if (mockToken != null) 'mockToken': mockToken,
      if (last4 != null) 'last4': last4,
      if (brand != null) 'brand': brand,
    });
    final data = res.data;
    final payload = data is Map && data['paymentMethod'] != null
        ? data['paymentMethod']
        : data;
    return PaymentMethod.fromJson(
        Map<String, dynamic>.from(payload as Map));
  }

  Future<void> setDefault(String id) async {
    await _api.post('/api/payment-methods/$id/default');
  }

  Future<void> delete(String id) async {
    await _api.delete('/api/payment-methods/$id');
  }
}
