enum UserRole { buyer, courier, shop }

enum CourierVerificationStatus {
  none,           // Не подавал заявку
  pending,        // На проверке
  approved,       // Одобрен
  rejected,       // Отклонён
}

class User {
  final String id;
  final String phone;        // +998 XX XXX XX XX
  final String? name;
  final String? avatarUrl;
  UserRole activeRole;
  final bool isCourierApproved;
  final CourierVerificationStatus courierStatus;

  // Данные самозанятого (для курьеров)
  final String? stir;        // ИНН / СТИР (9 цифр в Узбекистане)
  final String? passportSeries; // AA 1234567
  final String? selfEmployedCertUrl; // Справка о самозанятости

  User({
    required this.id,
    required this.phone,
    this.name,
    this.avatarUrl,
    this.activeRole = UserRole.buyer,
    this.isCourierApproved = false,
    this.courierStatus = CourierVerificationStatus.none,
    this.stir,
    this.passportSeries,
    this.selfEmployedCertUrl,
    this.shopId,
    this.shopName,
  });

  User copyWith({
    String? name,
    String? avatarUrl,
    UserRole? activeRole,
    bool? isCourierApproved,
    CourierVerificationStatus? courierStatus,
    String? stir,
    String? passportSeries,
    String? selfEmployedCertUrl,
    String? shopId,
    String? shopName,
  }) => User(
    id: id,
    phone: phone,
    name: name ?? this.name,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    activeRole: activeRole ?? this.activeRole,
    isCourierApproved: isCourierApproved ?? this.isCourierApproved,
    courierStatus: courierStatus ?? this.courierStatus,
    stir: stir ?? this.stir,
    passportSeries: passportSeries ?? this.passportSeries,
    selfEmployedCertUrl: selfEmployedCertUrl ?? this.selfEmployedCertUrl,
    shopId: shopId ?? this.shopId,
    shopName: shopName ?? this.shopName,
  );

  // Shop data
  final String? shopId;
  final String? shopName;

  bool get canSwitchToCourier =>
    courierStatus == CourierVerificationStatus.approved;

  bool get hasAppliedForCourier =>
    courierStatus != CourierVerificationStatus.none;

  bool get isShopOwner => shopId != null;
}

class Product {
  final String id;
  final String name;
  final String nameUz;        // Название на узбекском
  final double price;         // В сумах
  final String unit;          // кг, шт, л
  final String category;
  final String imageUrl;
  final String shopId;
  final double? discountPrice;
  final bool isAvailable;

  const Product({
    required this.id,
    required this.name,
    required this.nameUz,
    required this.price,
    required this.unit,
    required this.category,
    required this.imageUrl,
    required this.shopId,
    this.discountPrice,
    this.isAvailable = true,
  });

  double get effectivePrice => discountPrice ?? price;
  bool get hasDiscount => discountPrice != null;
  double get discountPercent => hasDiscount
    ? ((price - discountPrice!) / price * 100).roundToDouble()
    : 0;
}

enum OrderStatus {
  pending,      // Ожидает подтверждения магазина
  confirmed,    // Подтверждён
  collecting,   // Сборка
  readyForPickup, // Готов к выдаче курьеру
  inDelivery,   // В пути
  delivered,    // Доставлен
  cancelled,    // Отменён
}

class OrderItem {
  final Product product;
  final int quantity;

  const OrderItem({required this.product, required this.quantity});
  double get total => product.effectivePrice * quantity;
}

class Order {
  final String id;
  final String userId;
  final String shopId;
  final String shopName;
  final List<OrderItem> items;
  final OrderStatus status;
  final DateTime createdAt;
  final String? courierId;
  final String deliveryAddress;
  final double? courierLat;
  final double? courierLng;
  final double deliveryFee;
  final String paymentMethod;
  final bool isPaid;
  final String? orderNumber;     // Номер заказа от магазина (напр. "K-247")
  final String? shopComment;     // Комментарий магазина курьеру
  final DateTime? readyAt;       // Когда магазин поставил "готово"

  const Order({
    required this.id,
    required this.userId,
    required this.shopId,
    required this.shopName,
    required this.items,
    required this.status,
    required this.createdAt,
    required this.deliveryAddress,
    required this.deliveryFee,
    required this.paymentMethod,
    this.courierId,
    this.courierLat,
    this.courierLng,
    this.isPaid = false,
    this.orderNumber,
    this.shopComment,
    this.readyAt,
  });

  double get subtotal => items.fold(0, (sum, i) => sum + i.total);
  double get total => subtotal + deliveryFee;
}

// Для курьера
class CourierOrder {
  final String id;
  final String shopName;
  final String shopAddress;
  final String deliveryAddress;
  final double distanceKm;
  final double reward;         // Вознаграждение курьера в сумах
  final int estimatedMinutes;
  final List<OrderItem> items;
  final String? orderNumber;    // Номер на стикере/чеке магазина
  final String customerName;
  final String customerPhone;
  final String? customerComment;

  const CourierOrder({
    required this.id,
    required this.shopName,
    required this.shopAddress,
    required this.deliveryAddress,
    required this.distanceKm,
    required this.reward,
    required this.estimatedMinutes,
    required this.items,
    this.orderNumber,
    this.customerName = 'Xaridor',
    this.customerPhone = '+998 90 000 00 00',
    this.customerComment,
  });
}
