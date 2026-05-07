import '../models/models.dart';
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
      createdAt: DateTime.parse(json['createdAt']),
    );
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
      if (couponCode != null && couponCode.isNotEmpty) 'couponCode': couponCode,
      if (loyaltyPoints != null && loyaltyPoints > 0)
        'loyaltyPoints': loyaltyPoints,
      if (scheduledFor != null)
        'scheduledFor': scheduledFor.toUtc().toIso8601String(),
    });
    return _parseOrder(res.data['order']);
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
