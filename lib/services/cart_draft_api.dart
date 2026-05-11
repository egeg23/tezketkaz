import 'api_client.dart';

/// Phase 11 — multi-shop cart drafts.
///
/// The buyer can keep one in-progress cart per shop. Backend persists those
/// drafts on `User.cartDrafts` and exposes the CRUD endpoints under
/// `/api/cart-drafts/me*`.
class CartDraftSummary {
  final String shopId;
  final String shopName;
  final String shopVertical;
  final String shopCurrency;
  final String? shopLogoUrl;
  final int itemCount;
  final num subtotal;
  final String? couponCode;
  final int loyaltyPoints;
  final DateTime? scheduledFor;
  final DateTime updatedAt;
  // Count of items whose product was deleted on the shop side. The summary
  // endpoint surfaces this so the UI can warn the buyer before they open the
  // draft.
  final int staleItems;

  const CartDraftSummary({
    required this.shopId,
    required this.shopName,
    required this.shopVertical,
    required this.shopCurrency,
    required this.itemCount,
    required this.subtotal,
    required this.loyaltyPoints,
    required this.updatedAt,
    required this.staleItems,
    this.shopLogoUrl,
    this.couponCode,
    this.scheduledFor,
  });

  factory CartDraftSummary.fromJson(Map<String, dynamic> j) =>
      CartDraftSummary(
        shopId: j['shopId'] as String? ?? '',
        shopName: j['shopName'] as String? ?? '',
        shopVertical: j['shopVertical'] as String? ?? 'other',
        shopCurrency: j['shopCurrency'] as String? ?? 'UZS',
        shopLogoUrl: j['shopLogoUrl'] as String?,
        itemCount: (j['itemCount'] as num?)?.toInt() ?? 0,
        subtotal: (j['subtotal'] as num?) ?? 0,
        couponCode: j['couponCode'] as String?,
        loyaltyPoints: (j['loyaltyPoints'] as num?)?.toInt() ?? 0,
        scheduledFor: _parseDate(j['scheduledFor']),
        updatedAt: _parseDate(j['updatedAt']) ?? DateTime.now(),
        staleItems: (j['staleItems'] as num?)?.toInt() ?? 0,
      );
}

class CartDraftDetail extends CartDraftSummary {
  // Raw items array as stored on the server. Items use the same shape as the
  // existing `POST /api/orders` payload (`{productId, quantity, modifiers?}`)
  // so the local cart can rehydrate without an extra translation step.
  final List<dynamic> payload;

  const CartDraftDetail({
    required super.shopId,
    required super.shopName,
    required super.shopVertical,
    required super.shopCurrency,
    required super.itemCount,
    required super.subtotal,
    required super.loyaltyPoints,
    required super.updatedAt,
    required super.staleItems,
    required this.payload,
    super.shopLogoUrl,
    super.couponCode,
    super.scheduledFor,
  });

  factory CartDraftDetail.fromJson(Map<String, dynamic> j) {
    final base = CartDraftSummary.fromJson(j);
    return CartDraftDetail(
      shopId: base.shopId,
      shopName: base.shopName,
      shopVertical: base.shopVertical,
      shopCurrency: base.shopCurrency,
      shopLogoUrl: base.shopLogoUrl,
      itemCount: base.itemCount,
      subtotal: base.subtotal,
      couponCode: base.couponCode,
      loyaltyPoints: base.loyaltyPoints,
      scheduledFor: base.scheduledFor,
      updatedAt: base.updatedAt,
      staleItems: base.staleItems,
      payload: (j['payload'] as List?) ?? const <dynamic>[],
    );
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is String && v.isNotEmpty) {
    return DateTime.tryParse(v);
  }
  return null;
}

class CartDraftApi {
  CartDraftApi._();
  static final CartDraftApi instance = CartDraftApi._();

  final _api = ApiClient.instance;

  /// Returns one summary per shop with an in-progress draft. Empty list when
  /// the buyer has no drafts.
  Future<List<CartDraftSummary>> listMine() async {
    final res = await _api.get('/api/cart-drafts/me');
    final body = res.data;
    final raw = body is Map ? (body['drafts'] as List?) : null;
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((j) => CartDraftSummary.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  /// Returns the full draft (including the raw items payload) for a shop, or
  /// `null` when the server returns 404.
  Future<CartDraftDetail?> getForShop(String shopId) async {
    try {
      final res = await _api.get('/api/cart-drafts/me/$shopId');
      final body = res.data;
      if (body is Map<String, dynamic>) {
        return CartDraftDetail.fromJson(body);
      }
      if (body is Map) {
        return CartDraftDetail.fromJson(Map<String, dynamic>.from(body));
      }
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Upsert the draft for [shopId]. Returns the persisted detail so callers
  /// can refresh their local copy. An empty payload is allowed — the backend
  /// will treat it as "draft exists but is empty" until the next mutation.
  Future<CartDraftDetail> upsert(
    String shopId, {
    required List<Map<String, dynamic>> payload,
    String? couponCode,
    int? loyaltyPoints,
    DateTime? scheduledFor,
  }) async {
    final body = <String, dynamic>{
      'payload': payload,
      if (couponCode != null) 'couponCode': couponCode,
      if (loyaltyPoints != null) 'loyaltyPoints': loyaltyPoints,
      if (scheduledFor != null)
        'scheduledFor': scheduledFor.toUtc().toIso8601String(),
    };
    final res = await _api.put('/api/cart-drafts/me/$shopId', body);
    final data = res.data;
    if (data is Map<String, dynamic>) {
      return CartDraftDetail.fromJson(data);
    }
    if (data is Map) {
      return CartDraftDetail.fromJson(Map<String, dynamic>.from(data));
    }
    // Defensive fallback: the server didn't echo the persisted row. Build a
    // synthetic detail from the request so callers still get a usable value.
    return CartDraftDetail(
      shopId: shopId,
      shopName: '',
      shopVertical: 'other',
      shopCurrency: 'UZS',
      itemCount: payload.fold<int>(
          0, (a, b) => a + ((b['quantity'] as num?)?.toInt() ?? 0)),
      subtotal: 0,
      couponCode: couponCode,
      loyaltyPoints: loyaltyPoints ?? 0,
      scheduledFor: scheduledFor,
      updatedAt: DateTime.now(),
      staleItems: 0,
      payload: payload,
    );
  }

  Future<void> dropShop(String shopId) async {
    try {
      await _api.delete('/api/cart-drafts/me/$shopId');
    } on ApiException catch (e) {
      // 404 is fine — draft was already gone (e.g. cleared after order POST).
      if (e.statusCode != 404) rethrow;
    }
  }

  Future<void> dropAll() async {
    try {
      await _api.delete('/api/cart-drafts/me');
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
  }
}
