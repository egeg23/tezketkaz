import 'dart:io';

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/order_api.dart';
import '../services/socket_service.dart';

// ─── Order status & model ────────────────────────────────────────────────────

enum AppOrderStatus {
  pending, confirmed, collecting, readyForPickup,
  courierAssigned, pickedUp, inDelivery, arrivedAtCustomer,
  delivered, confirmedByBuyer, cancelled,
}

class AppOrder {
  final String id;
  final String shopId;
  final String shopName;
  final String shopAddress;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final String? customerComment;
  final List<OrderItem> items;
  final double deliveryFee;
  final String paymentMethod;
  final bool isPaid;
  AppOrderStatus status;
  String? orderNumber;
  String? courierId;
  String? courierName;
  double reward;
  // Phase 8.1 — stacked dispatch. `batchId` groups multiple orders that the
  // courier picks up together. `batchSequence` is the 1-based position of
  // this order within the batch (e.g. 2 of 3).
  final String? batchId;
  final int? batchSequence;
  final int? batchTotal;
  // Phase 13.2.5 — courier delivery-photo proof. Surfaced on the buyer's
  // tracking screen once the courier marks the order delivered.
  final String? deliveryPhotoUrl;
  final DateTime? deliveryPhotoAt;
  final DateTime createdAt;

  AppOrder({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.shopAddress,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    this.customerComment,
    required this.items,
    required this.deliveryFee,
    required this.paymentMethod,
    required this.isPaid,
    this.status = AppOrderStatus.pending,
    this.orderNumber,
    this.courierId,
    this.courierName,
    this.reward = 12000,
    this.batchId,
    this.batchSequence,
    this.batchTotal,
    this.deliveryPhotoUrl,
    this.deliveryPhotoAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get subtotal => items.fold(0, (s, i) => s + i.total);
  double get total => subtotal + deliveryFee;

  String get statusLabel => switch (status) {
    AppOrderStatus.pending         => 'Yangi buyurtma',
    AppOrderStatus.confirmed       => 'Qabul qilindi',
    AppOrderStatus.collecting      => 'Yig\'ilmoqda',
    AppOrderStatus.readyForPickup  => 'Kuryer kutilmoqda',
    AppOrderStatus.courierAssigned => 'Kuryer yo\'lda',
    AppOrderStatus.pickedUp        => 'Kuryer oldi',
    AppOrderStatus.inDelivery      => 'Yetkazib berilmoqda',
    AppOrderStatus.arrivedAtCustomer => 'Kuryer eshik oldida',
    AppOrderStatus.delivered       => 'Topshirildi',
    AppOrderStatus.confirmedByBuyer => 'Yetkazib berildi',
    AppOrderStatus.cancelled       => 'Bekor qilindi',
  };

  String get statusEmoji => switch (status) {
    AppOrderStatus.pending         => '🔔',
    AppOrderStatus.confirmed       => '✅',
    AppOrderStatus.collecting      => '📦',
    AppOrderStatus.readyForPickup  => '🏪',
    AppOrderStatus.courierAssigned => '🛵',
    AppOrderStatus.pickedUp        => '🛵',
    AppOrderStatus.inDelivery      => '🛵',
    AppOrderStatus.arrivedAtCustomer => '🚪',
    AppOrderStatus.delivered       => '✅',
    AppOrderStatus.confirmedByBuyer => '🎉',
    AppOrderStatus.cancelled       => '❌',
  };

  double get buyerProgress => switch (status) {
    AppOrderStatus.pending         => 0.1,
    AppOrderStatus.confirmed       => 0.3,
    AppOrderStatus.collecting      => 0.3,
    AppOrderStatus.readyForPickup  => 0.5,
    AppOrderStatus.courierAssigned => 0.7,
    AppOrderStatus.pickedUp        => 0.7,
    AppOrderStatus.inDelivery      => 0.85,
    AppOrderStatus.arrivedAtCustomer => 0.92,
    AppOrderStatus.delivered       => 0.97,
    AppOrderStatus.confirmedByBuyer => 1.0,
    AppOrderStatus.cancelled       => 0.0,
  };

  String get minutesAgo {
    final diff = DateTime.now().difference(createdAt).inMinutes;
    if (diff < 1) return 'Hozir';
    if (diff < 60) return '$diff daqiqa oldin';
    return '${diff ~/ 60} soat oldin';
  }

  CourierOrder toCourierOrder() => CourierOrder(
    id: id, shopName: shopName, shopAddress: shopAddress,
    deliveryAddress: deliveryAddress, distanceKm: 1.8,
    reward: reward, estimatedMinutes: 18, items: items,
    orderNumber: orderNumber, customerName: customerName,
    customerPhone: customerPhone, customerComment: customerComment,
  );
}

// ─── Provider — backed by real API ───────────────────────────────────────────

class OrderProvider extends ChangeNotifier {
  final List<AppOrder> _orders = [];
  bool _isLoading = false;
  String? _error;

  List<AppOrder> get all => List.unmodifiable(_orders);
  bool get isLoading => _isLoading;
  String? get error => _error;

  static const _terminal = {
    AppOrderStatus.confirmedByBuyer,
    AppOrderStatus.cancelled,
  };

  // ── Buyer ─────────────────────────────────────────────────────────────────
  AppOrder? activeOrderForBuyer(String userId) {
    try {
      return _orders.firstWhere((o) => !_terminal.contains(o.status));
    } catch (_) { return null; }
  }

  // ── Shop ──────────────────────────────────────────────────────────────────
  List<AppOrder> pendingForShop(String shopId) =>
    _orders.where((o) => o.shopId == shopId && o.status == AppOrderStatus.pending).toList();

  List<AppOrder> activeForShop(String shopId) =>
    _orders.where((o) => o.shopId == shopId && [
      AppOrderStatus.confirmed, AppOrderStatus.collecting, AppOrderStatus.readyForPickup,
    ].contains(o.status)).toList();

  List<AppOrder> doneForShop(String shopId) =>
    _orders.where((o) => o.shopId == shopId && [
      AppOrderStatus.courierAssigned, AppOrderStatus.pickedUp, AppOrderStatus.inDelivery,
      AppOrderStatus.arrivedAtCustomer, AppOrderStatus.delivered,
      AppOrderStatus.confirmedByBuyer, AppOrderStatus.cancelled,
    ].contains(o.status)).toList();

  // ── Courier ───────────────────────────────────────────────────────────────
  List<AppOrder> availableForCourier() =>
    _orders.where((o) =>
        (o.status == AppOrderStatus.collecting || o.status == AppOrderStatus.readyForPickup) &&
        o.courierId == null).toList();

  AppOrder? activeForCourier(String courierId) {
    try {
      return _orders.firstWhere(
        (o) => o.courierId == courierId && !_terminal.contains(o.status),
      );
    } catch (_) { return null; }
  }

  AppOrder? findById(String id) {
    try { return _orders.firstWhere((o) => o.id == id); } catch (_) { return null; }
  }

  // ─── Loading from API ───────────────────────────────────────────────────────

  Future<void> loadBuyerOrders() async {
    _setLoading(true);
    try {
      final orders = await OrderApi.instance.myOrders();
      _replaceAll(orders);
      _error = null;
    } catch (e) { _error = e.toString(); }
    _setLoading(false);
  }

  Future<void> loadShopOrders(String shopId) async {
    _setLoading(true);
    try {
      final orders = await OrderApi.instance.forShop(shopId);
      _replaceAll(orders);
      _error = null;
    } catch (e) { _error = e.toString(); }
    _setLoading(false);
  }

  Future<void> loadCourierData() async {
    _setLoading(true);
    try {
      final available = await OrderApi.instance.courierAvailable();
      final active = await OrderApi.instance.courierActive();
      _orders.clear();
      _orders.addAll(available);
      if (active != null) _orders.add(active);
      _error = null;
    } catch (e) { _error = e.toString(); }
    _setLoading(false);
  }

  // ─── Buyer actions ──────────────────────────────────────────────────────────
  Future<AppOrder> placeOrder({
    required String shopId,
    required List<OrderItem> items,
    required String deliveryAddress,
    String? customerComment,
    required String paymentMethod,
    double? lat,
    double? lng,
    /// Phase 1 — pre-built items payload from `CartProvider.toApiPayload()`.
    List<Map<String, dynamic>>? itemsPayload,
    // Phase 3 extensions
    String? couponCode,
    int? loyaltyPoints,
    DateTime? scheduledFor,
    // Phase 6 — id of a saved payment method (from /api/payment-methods/me).
    String? paymentMethodId,
  }) async {
    final order = await OrderApi.instance.placeOrder(
      shopId: shopId,
      items: items,
      itemsPayload: itemsPayload,
      deliveryAddress: deliveryAddress,
      customerComment: customerComment,
      paymentMethod: paymentMethod,
      lat: lat,
      lng: lng,
      couponCode: couponCode,
      loyaltyPoints: loyaltyPoints,
      scheduledFor: scheduledFor,
      paymentMethodId: paymentMethodId,
    );
    _orders.insert(0, order);
    SocketService.instance.subscribeToOrder(order.id);
    notifyListeners();
    return order;
  }

  /// Phase 6 — buyer adds a tip after the order has been delivered.
  Future<void> sendTip(String orderId, num amount) =>
      OrderApi.instance.sendTip(orderId, amount);

  // ─── Shop actions ──────────────────────────────────────────────────────────
  Future<void> shopAcceptOrder(String orderId) async {
    final updated = await OrderApi.instance.shopAccept(orderId);
    _replace(updated);
  }

  Future<void> shopMarkReady(String orderId) async {
    final updated = await OrderApi.instance.shopMarkReady(orderId);
    _replace(updated);
  }

  Future<void> shopCancelOrder(String orderId, [String reason = 'Other']) async {
    final updated = await OrderApi.instance.shopCancel(orderId, reason);
    _replace(updated);
  }

  // ─── Courier actions ───────────────────────────────────────────────────────
  Future<AppOrder> courierAcceptOrder(String orderId) async {
    final updated = await OrderApi.instance.courierAccept(orderId);
    _replace(updated);
    return updated;
  }

  Future<bool> courierPickup(String orderId, String enteredNumber) async {
    try {
      final updated = await OrderApi.instance.courierPickup(orderId, enteredNumber);
      _replace(updated);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> courierStartDelivery(String orderId) async {
    final updated = await OrderApi.instance.courierStart(orderId);
    _replace(updated);
  }

  Future<void> courierArrived(String orderId) async {
    final updated = await OrderApi.instance.courierArrived(orderId);
    _replace(updated);
  }

  Future<void> courierComplete(String orderId) async {
    final updated = await OrderApi.instance.courierComplete(orderId);
    _replace(updated);
  }

  /// Phase 13.2.5 — mark delivered with the courier's freshly-captured photo.
  /// The Flutter active-order screen drives this; tests for the underlying
  /// multipart upload live in the backend (delivery-photo.test.js).
  Future<void> courierMarkDelivered(String orderId, File photoFile) async {
    final updated =
        await OrderApi.instance.courierMarkDelivered(orderId, photoFile);
    _replace(updated);
  }

  Future<void> buyerConfirm(String orderId) async {
    final updated = await OrderApi.instance.buyerConfirm(orderId);
    _replace(updated);
  }

  // ─── Real-time updates from socket ──────────────────────────────────────────

  void connectSockets() {
    final s = SocketService.instance;
    s.connect();

    s.on('order:new', (data) {
      try {
        final order = OrderApi.instance.byId(data['id']);
        order.then((o) { _orders.insert(0, o); notifyListeners(); });
      } catch (_) {}
    });

    s.on('order:updated', (data) {
      try {
        OrderApi.instance.byId(data['id']).then((o) => _replace(o));
      } catch (_) {}
    });

    s.on('order:available', (data) {
      try {
        OrderApi.instance.byId(data['id']).then((o) {
          if (!_orders.any((x) => x.id == o.id)) {
            _orders.insert(0, o);
            notifyListeners();
          }
        });
      } catch (_) {}
    });

    s.on('order:taken', (data) {
      _orders.removeWhere((o) => o.id == data['orderId']);
      notifyListeners();
    });
  }

  // ─── Internal helpers ──────────────────────────────────────────────────────

  void _replace(AppOrder order) {
    final i = _orders.indexWhere((o) => o.id == order.id);
    if (i >= 0) {
      _orders[i] = order;
    } else {
      _orders.insert(0, order);
    }
    notifyListeners();
  }

  void _replaceAll(List<AppOrder> orders) {
    _orders.clear();
    _orders.addAll(orders);
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void clear() {
    _orders.clear();
    notifyListeners();
  }
}
