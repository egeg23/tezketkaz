import 'package:dio/dio.dart';
import 'api_client.dart';

/// Phase 2 dispatch / pricing endpoints. Wraps `ApiClient` so auth + refresh
/// behave the same way as the rest of the app.
class DispatchApi {
  DispatchApi._();
  static final DispatchApi instance = DispatchApi._();

  final _api = ApiClient.instance;

  /// `POST /api/orders/estimate`.
  ///
  /// Returns the raw response map from the backend so callers can pull out
  /// `subtotal / deliveryFee / total / minOrder / minOrderMet / distanceKm /
  /// etaMinutes / surgeFactor / surgeReason / zoneId`.
  ///
  /// On `400` with body `{error: 'outOfZone'}` we re-throw an [ApiException]
  /// with the same code; callers should treat statusCode == 400 + message
  /// containing `outOfZone` as the out-of-zone case.
  Future<Map<String, dynamic>> estimate({
    required String shopId,
    required Map<String, dynamic> address,
    required List<Map<String, dynamic>> items,
    String? promoCode,
    String? couponCode,
    int? loyaltyPoints,
  }) async {
    final code = couponCode ?? promoCode;
    final res = await _api.post('/api/orders/estimate', {
      'shopId': shopId,
      'address': address,
      'items': items,
      if (code != null && code.isNotEmpty) 'couponCode': code,
      if (code != null && code.isNotEmpty) 'promoCode': code,
      if (loyaltyPoints != null && loyaltyPoints > 0)
        'loyaltyPoints': loyaltyPoints,
    });
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    return Map<String, dynamic>.from(data as Map);
  }

  /// `POST /api/couriers/me/shifts/start`.
  Future<Map<String, dynamic>> startShift({List<String>? zoneIds}) async {
    final res = await _api.post('/api/couriers/me/shifts/start', {
      if (zoneIds != null) 'zoneIds': zoneIds,
    });
    return _shiftFrom(res);
  }

  /// `GET /api/couriers/me/shifts/current`. Returns `null` when no active
  /// shift is open.
  Future<Map<String, dynamic>?> currentShift() async {
    try {
      final res = await _api.get('/api/couriers/me/shifts/current');
      final data = res.data;
      if (data == null) return null;
      if (data is Map) {
        if (data.isEmpty) return null;
        // Explicit `{shift: null}` shape from backend.
        if (data.containsKey('shift') && data['shift'] == null) return null;
      }
      return _shiftFrom(res);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// `POST /api/couriers/me/shifts/end`.
  Future<void> endShift() async {
    await _api.post('/api/couriers/me/shifts/end');
  }

  /// `POST /api/couriers/me/online`.
  Future<void> setOnline(bool online) async {
    await _api.post('/api/couriers/me/online', {'isOnline': online});
  }

  /// `POST /api/orders/:orderId/dispatch/accept`.
  Future<void> acceptOffer(String orderId) async {
    await _api.post('/api/orders/$orderId/dispatch/accept');
  }

  /// `POST /api/orders/:orderId/dispatch/decline`.
  Future<void> declineOffer(String orderId, {String? reason}) async {
    await _api.post('/api/orders/$orderId/dispatch/decline', {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  /// `GET /api/shops/:shopId/zones`. Returns a list of zones, each one a
  /// `Map<String,dynamic>` with at least `id`, `name`, `polygon`
  /// (list of `{lat,lng}` points).
  Future<List<Map<String, dynamic>>> shopZones(String shopId) async {
    final res = await _api.get('/api/shops/$shopId/zones');
    final raw = (res.data is Map && (res.data as Map).containsKey('zones'))
        ? (res.data['zones'] as List? ?? const [])
        : (res.data is List ? res.data as List : const []);
    return raw
        .map<Map<String, dynamic>>((z) => Map<String, dynamic>.from(z as Map))
        .toList();
  }

  Map<String, dynamic> _shiftFrom(Response res) {
    final data = res.data;
    if (data is Map) {
      final shift = data['shift'];
      if (shift is Map) return Map<String, dynamic>.from(shift);
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }
}
