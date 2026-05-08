import '../models/models.dart';
import '../providers/cart_provider.dart';
import '../providers/order_provider.dart';
import 'api_client.dart';

class OrderApi {
  OrderApi._();
  static final OrderApi instance = OrderApi._();

  final _api = ApiClient.instance;

  AppOrder _parseOrder(Map<String, dynamic> json) {
    return AppOrder(
      id: json['id'],
      shopId: json['shopId'],
      shopName: json['shop']?['name'] ?? '',
      shopAddress: json['shop']?['address'] ?? '',
      customerName: json['customerName'],
      customerPhone: json['customerPhone'],
      deliveryAddress: json['deliveryAddress'],
      customerComment: json['customerComment'],
      items: (json['items'] as List? ?? []).map<OrderItem>((i) => OrderItem(
        product: Product(
          id: i['productId'],
          name: i['productName'],
          nameUz: i['productName'],
          price: (i['price'] as num).toDouble(),
          unit: 'шт',
          category: '',
          imageUrl: '',
          shopId: json['shopId'],
        ),
        quantity: i['quantity'],
      )).toList(),
      deliveryFee: (json['deliveryFee'] as num).toDouble(),
      paymentMethod: json['paymentMethod'],
      isPaid: json['isPaid'],
      status: _parseStatus(json['status']),
      orderNumber: json['orderNumber'],
      courierId: json['courierId'],
      courierName: json['courier']?['name'],
      reward: (json['courierReward'] as num? ?? 12000).toDouble(),
      // Phase 8.1 — backend may attach stacked-dispatch metadata.
      batchId: json['batchId'] as String?,
      batchSequence: (json['batchSequence'] as num?)?.toInt(),
      batchTotal: (json['batchTotal'] as num?)?.toInt() ??
          (json['totalDeliveries'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  /// Phase 8.1 — fetch all orders that share the given batchId. Falls back
  /// to a `[order]` list of the courier's active order when the dedicated
  /// endpoint is unavailable.
  Future<List<AppOrder>> courierBatch(String batchId) async {
    try {
      final res = await _api.get('/api/orders/courier/batch/$batchId');
      final data = res.data;
      final list = (data is Map && data['orders'] is List)
          ? data['orders'] as List
          : (data is List ? data : const []);
      return list
          .map<AppOrder>((o) => _parseOrder(Map<String, dynamic>.from(o)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  AppOrderStatus _parseStatus(String s) {
    return switch (s) {
      'pending'         => AppOrderStatus.pending,
      'confirmed'       => AppOrderStatus.confirmed,
      'collecting'      => AppOrderStatus.collecting,
      'readyForPickup'  => AppOrderStatus.readyForPickup,
      'courierAssigned' => AppOrderStatus.courierAssigned,
      'pickedUp'        => AppOrderStatus.pickedUp,
      'inDelivery'      => AppOrderStatus.inDelivery,
      'arrivedAtCustomer' => AppOrderStatus.arrivedAtCustomer,
      'delivered'       => AppOrderStatus.delivered,
      'confirmedByBuyer' => AppOrderStatus.confirmedByBuyer,
      'cancelled'       => AppOrderStatus.cancelled,
      _                 => AppOrderStatus.pending,
    };
  }

  // ── Buyer actions ────────────────────────────────────────────────────────
  Future<AppOrder> placeOrder({
    required String shopId,
    required List<OrderItem> items,
    required String deliveryAddress,
    String? customerComment,
    required String paymentMethod,
    double? lat,
    double? lng,
    /// Optional Phase 1 payload — when provided, replaces the items array.
    /// Used by `CartProvider.toApiPayload()` so modifier selections survive.
    List<Map<String, dynamic>>? itemsPayload,
    // Phase 3 extensions
    String? couponCode,
    int? loyaltyPoints,
    DateTime? scheduledFor,
    // Phase 6 — id of a saved card / cash entry from
    // `GET /api/payment-methods/me`. When provided the backend uses that
    // entry's provider/last4 instead of the legacy `paymentMethod` string.
    String? paymentMethodId,
  }) async {
    final itemsJson = itemsPayload ??
        items.map((i) => {
          'productId': i.product.id,
          'quantity': i.quantity,
        }).toList();
    final res = await _api.post('/api/orders', {
      'shopId': shopId,
      'items': itemsJson,
      'deliveryAddress': deliveryAddress,
      'deliveryLat': lat,
      'deliveryLng': lng,
      'customerComment': customerComment,
      'paymentMethod': paymentMethod,
      if (paymentMethodId != null && paymentMethodId.isNotEmpty)
        'paymentMethodId': paymentMethodId,
      if (couponCode != null && couponCode.isNotEmpty) 'couponCode': couponCode,
      if (loyaltyPoints != null && loyaltyPoints > 0)
        'loyaltyPoints': loyaltyPoints,
      if (scheduledFor != null)
        'scheduledFor': scheduledFor.toUtc().toIso8601String(),
    });
    return _parseOrder(res.data['order']);
  }

  /// Phase 6 — `POST /api/orders/:orderId/tip`. Adds a courier tip after
  /// delivery. Accepts a numeric `amount` (server normalises to UZS).
  Future<void> sendTip(String orderId, num amount) async {
    await _api.post('/api/orders/$orderId/tip', {'amount': amount});
  }

  Future<List<AppOrder>> myOrders() async {
    final res = await _api.get('/api/orders/mine');
    return (res.data['orders'] as List).map((o) => _parseOrder(o)).toList();
  }

  Future<AppOrder> byId(String id) async {
    final res = await _api.get('/api/orders/$id');
    return _parseOrder(res.data['order']);
  }

  Future<void> rate(String orderId, int rating, [String? review]) async {
    await _api.post('/api/orders/$orderId/rate', {'rating': rating, 'review': review});
  }

  /// Phase 7.3 — `POST /api/orders/:id/reorder`. Returns a `CartDraft`
  /// describing items the buyer can re-add (with availability flags so the
  /// UI can skip discontinued products with a friendly snackbar).
  Future<CartDraft> reorder(String orderId) async {
    final res = await _api.post('/api/orders/$orderId/reorder');
    final data = res.data;
    final payload = data is Map && data['draft'] is Map
        ? Map<String, dynamic>.from(data['draft'] as Map)
        : data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
    return CartDraft.fromJson(payload);
  }

  // ── Shop actions ─────────────────────────────────────────────────────────
  Future<List<AppOrder>> forShop(String shopId) async {
    final res = await _api.get('/api/orders/shop/$shopId');
    return (res.data['orders'] as List).map((o) => _parseOrder(o)).toList();
  }

  Future<AppOrder> shopAccept(String orderId) async {
    final res = await _api.post('/api/orders/$orderId/shop/accept');
    return _parseOrder(res.data['order']);
  }

  Future<AppOrder> shopMarkReady(String orderId) async {
    final res = await _api.post('/api/orders/$orderId/shop/ready');
    return _parseOrder(res.data['order']);
  }

  Future<AppOrder> shopCancel(String orderId, String reason) async {
    final res = await _api.post('/api/orders/$orderId/shop/cancel', {'reason': reason});
    return _parseOrder(res.data['order']);
  }

  // ── Courier actions ──────────────────────────────────────────────────────
  Future<List<AppOrder>> courierAvailable() async {
    final res = await _api.get('/api/orders/courier/available');
    return (res.data['orders'] as List).map((o) => _parseOrder(o)).toList();
  }

  Future<AppOrder?> courierActive() async {
    final res = await _api.get('/api/orders/courier/active');
    if (res.data['order'] == null) return null;
    return _parseOrder(res.data['order']);
  }

  Future<AppOrder> courierAccept(String orderId) async {
    final res = await _api.post('/api/orders/$orderId/courier/accept');
    return _parseOrder(res.data['order']);
  }

  Future<AppOrder> courierPickup(String orderId, String orderNumber) async {
    final res = await _api.post('/api/orders/$orderId/courier/pickup', {'orderNumber': orderNumber});
    return _parseOrder(res.data['order']);
  }

  Future<AppOrder> courierStart(String orderId) async {
    final res = await _api.post('/api/orders/$orderId/courier/start');
    return _parseOrder(res.data['order']);
  }

  Future<AppOrder> courierArrived(String orderId) async {
    final res = await _api.post('/api/orders/$orderId/courier/arrived');
    return _parseOrder(res.data['order']);
  }

  Future<AppOrder> courierComplete(String orderId) async {
    final res = await _api.post('/api/orders/$orderId/courier/complete');
    return _parseOrder(res.data['order']);
  }

  Future<AppOrder> buyerConfirm(String orderId) async {
    final res = await _api.post('/api/orders/$orderId/buyer/confirm');
    return _parseOrder(res.data['order']);
  }

  Future<void> reportCourierLocation({
    required double lat,
    required double lng,
    String? orderId,
  }) async {
    await _api.post('/api/couriers/location', {
      'lat': lat,
      'lng': lng,
      if (orderId != null) 'orderId': orderId,
    });
  }
}
