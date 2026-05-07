/// Phase 1 catalog models — categories, shops (with distance), modifier groups,
/// addresses. Kept separate from the legacy `models.dart` so the existing
/// types stay untouched.

class Category {
  final String id;
  final String slug;
  final String nameUz;
  final String nameRu;
  final String? iconUrl;
  final int sortOrder;
  final int productCount;
  final List<Category> children;

  const Category({
    required this.id,
    required this.slug,
    required this.nameUz,
    required this.nameRu,
    this.iconUrl,
    this.sortOrder = 0,
    this.productCount = 0,
    this.children = const [],
  });

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as String,
    slug: j['slug'] as String? ?? '',
    nameUz: j['nameUz'] as String? ?? j['name'] as String? ?? '',
    nameRu: j['nameRu'] as String? ?? j['name'] as String? ?? '',
    iconUrl: j['iconUrl'] as String?,
    sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
    productCount: (j['productCount'] as num?)?.toInt() ?? 0,
    children: ((j['children'] as List?) ?? const [])
        .map((c) => Category.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}

/// Vertical / shop type — matches backend enum.
enum ShopVertical {
  grocery,
  restaurant,
  pharmacy,
  electronics,
  other,
}

ShopVertical shopVerticalFromString(String? s) {
  switch (s) {
    case 'grocery': return ShopVertical.grocery;
    case 'restaurant': return ShopVertical.restaurant;
    case 'pharmacy': return ShopVertical.pharmacy;
    case 'electronics': return ShopVertical.electronics;
    default: return ShopVertical.other;
  }
}

String shopVerticalToString(ShopVertical v) {
  switch (v) {
    case ShopVertical.grocery: return 'grocery';
    case ShopVertical.restaurant: return 'restaurant';
    case ShopVertical.pharmacy: return 'pharmacy';
    case ShopVertical.electronics: return 'electronics';
    case ShopVertical.other: return 'other';
  }
}

class Shop {
  final String id;
  final String name;
  final String? logoUrl;
  final String? address;
  final ShopVertical vertical;
  final double? distanceKm;
  final double? rating;
  final int? reviewsCount;
  final String? workingHours;
  final bool isOpen;
  final double? lat;
  final double? lng;

  const Shop({
    required this.id,
    required this.name,
    this.logoUrl,
    this.address,
    this.vertical = ShopVertical.other,
    this.distanceKm,
    this.rating,
    this.reviewsCount,
    this.workingHours,
    this.isOpen = true,
    this.lat,
    this.lng,
  });

  factory Shop.fromJson(Map<String, dynamic> j) => Shop(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    logoUrl: j['logoUrl'] as String?,
    address: j['address'] as String?,
    vertical: shopVerticalFromString(j['vertical'] as String?),
    distanceKm: (j['distanceKm'] as num?)?.toDouble(),
    rating: (j['rating'] as num?)?.toDouble(),
    reviewsCount: (j['reviewsCount'] as num?)?.toInt(),
    workingHours: j['workingHours'] as String?,
    isOpen: j['isOpen'] as bool? ?? true,
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
  );
}

class ModifierOption {
  final String id;
  final String name;
  final double priceDelta;
  final bool isAvailable;

  const ModifierOption({
    required this.id,
    required this.name,
    this.priceDelta = 0,
    this.isAvailable = true,
  });

  factory ModifierOption.fromJson(Map<String, dynamic> j) => ModifierOption(
    id: j['id'] as String,
    name: (j['name'] ?? j['nameUz'] ?? j['nameRu'] ?? '') as String,
    priceDelta: (j['priceDelta'] as num?)?.toDouble() ?? 0,
    isAvailable: j['isAvailable'] as bool? ?? true,
  );
}

class ModifierGroup {
  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<ModifierOption> options;

  const ModifierGroup({
    required this.id,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    required this.options,
  });

  bool get isRequired => minSelect > 0;
  bool get isSingleSelect => maxSelect == 1;

  factory ModifierGroup.fromJson(Map<String, dynamic> j) => ModifierGroup(
    id: j['id'] as String,
    name: (j['name'] ?? j['nameUz'] ?? j['nameRu'] ?? '') as String,
    minSelect: (j['minSelect'] as num?)?.toInt() ?? 0,
    maxSelect: (j['maxSelect'] as num?)?.toInt() ?? 1,
    options: ((j['options'] as List?) ?? const [])
        .map((o) => ModifierOption.fromJson(o as Map<String, dynamic>))
        .toList(),
  );
}

/// A snapshot of selected modifier options — used by the cart so we can show
/// "Cheese (+5 000)" lines without re-fetching the modifier groups later.
class ModifierSnapshot {
  final String groupId;
  final String groupName;
  final List<ModifierOption> options;

  const ModifierSnapshot({
    required this.groupId,
    required this.groupName,
    required this.options,
  });
}

class UserAddress {
  final String id;
  final String label;
  final String fullAddress;
  final double? lat;
  final double? lng;
  final String? entrance;
  final String? floor;
  final String? apartment;
  final String? intercom;
  final String? instructions;
  final bool isDefault;

  const UserAddress({
    required this.id,
    required this.label,
    required this.fullAddress,
    this.lat,
    this.lng,
    this.entrance,
    this.floor,
    this.apartment,
    this.intercom,
    this.instructions,
    this.isDefault = false,
  });

  factory UserAddress.fromJson(Map<String, dynamic> j) => UserAddress(
    id: j['id'] as String,
    label: j['label'] as String? ?? '',
    fullAddress: j['fullAddress'] as String? ?? '',
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
    entrance: j['entrance'] as String?,
    floor: j['floor'] as String?,
    apartment: j['apartment'] as String?,
    intercom: j['intercom'] as String?,
    instructions: j['instructions'] as String?,
    isDefault: j['isDefault'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'fullAddress': fullAddress,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (entrance != null) 'entrance': entrance,
    if (floor != null) 'floor': floor,
    if (apartment != null) 'apartment': apartment,
    if (intercom != null) 'intercom': intercom,
    if (instructions != null) 'instructions': instructions,
    'isDefault': isDefault,
  };
}
