import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../models/catalog.dart';
import '../services/address_api.dart';

/// Selected modifier set for a single cart line.
class CartModifierSelection {
  final String groupId;
  final List<String> optionIds;
  const CartModifierSelection({required this.groupId, required this.optionIds});

  Map<String, dynamic> toApiJson() => {
    'groupId': groupId,
    'optionIds': List<String>.from(optionIds),
  };
}

/// One line in the cart. The `key` deduplicates lines so the same product with
/// different modifier sets becomes a separate line.
class CartLine {
  final String key;
  final Product product;
  int quantity;
  final double unitPrice;
  final List<CartModifierSelection> modifiers;
  final List<ModifierSnapshot> snapshot;

  CartLine({
    required this.key,
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.modifiers = const [],
    this.snapshot = const [],
  });

  double get lineTotal => unitPrice * quantity;
}

/// Cached pricing breakdown returned by `POST /api/orders/estimate`. Stored
/// on the cart provider so navigating away and back to the cart screen does
/// not immediately re-fetch.
class CartEstimate {
  final double subtotal;
  final double deliveryFee;
  final double total;
  final double minOrder;
  final bool minOrderMet;
  final double? distanceKm;
  final int? etaMinutes;
  final double surgeFactor;
  final String? surgeReason;
  final String? zoneId;
  final bool outOfZone;
  // Phase 3 — coupon + loyalty deductions surfaced separately so the cart
  // breakdown can render them as individual rows.
  final double couponDiscount;
  final double loyaltyDiscount;
  final DateTime fetchedAt;

  const CartEstimate({
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.minOrder,
    required this.minOrderMet,
    this.distanceKm,
    this.etaMinutes,
    this.surgeFactor = 1.0,
    this.surgeReason,
    this.zoneId,
    this.outOfZone = false,
    this.couponDiscount = 0,
    this.loyaltyDiscount = 0,
    required this.fetchedAt,
  });

  factory CartEstimate.fromJson(Map<String, dynamic> j) => CartEstimate(
    subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0,
    deliveryFee: (j['deliveryFee'] as num?)?.toDouble() ?? 0,
    total: (j['total'] as num?)?.toDouble() ?? 0,
    minOrder: (j['minOrder'] as num?)?.toDouble() ?? 0,
    minOrderMet: j['minOrderMet'] as bool? ?? true,
    distanceKm: (j['distanceKm'] as num?)?.toDouble(),
    etaMinutes: (j['etaMinutes'] as num?)?.toInt(),
    surgeFactor: (j['surgeFactor'] as num?)?.toDouble() ?? 1.0,
    surgeReason: j['surgeReason'] as String?,
    zoneId: j['zoneId'] as String?,
    outOfZone: j['outOfZone'] as bool? ?? false,
    couponDiscount: (j['couponDiscount'] as num?)?.toDouble() ??
        (j['discount'] as num?)?.toDouble() ?? 0,
    loyaltyDiscount: (j['loyaltyDiscount'] as num?)?.toDouble() ?? 0,
    fetchedAt: DateTime.now(),
  );

  CartEstimate copyWith({bool? outOfZone}) => CartEstimate(
    subtotal: subtotal,
    deliveryFee: deliveryFee,
    total: total,
    minOrder: minOrder,
    minOrderMet: minOrderMet,
    distanceKm: distanceKm,
    etaMinutes: etaMinutes,
    surgeFactor: surgeFactor,
    surgeReason: surgeReason,
    zoneId: zoneId,
    outOfZone: outOfZone ?? this.outOfZone,
    couponDiscount: couponDiscount,
    loyaltyDiscount: loyaltyDiscount,
    fetchedAt: fetchedAt,
  );
}

class CartProvider extends ChangeNotifier {
  CartProvider() {
    // Restore the last-used address asynchronously — UI starts up immediately
    // with `null` and refreshes once SharedPreferences resolves.
    _restoreDeliveryAddress();
  }

  static const _kPrefAddressId = 'cart.lastAddressId';

  /// Lines keyed by `productId|sortedOptionIds`.
  final Map<String, CartLine> _lines = {};
  String? _currentShopId;
  CartEstimate? _lastEstimate;
  String? _lastEstimateKey;

  // ── Phase 3 — promo / loyalty / scheduling fields ─────────────────────────
  String? _couponCode;
  int _loyaltyPoints = 0;
  DateTime? _scheduledFor;

  // ── Phase 6 — selected delivery address (saved from address book) ─────────
  UserAddress? _deliveryAddress;
  UserAddress? get deliveryAddress => _deliveryAddress;

  void setDeliveryAddress(UserAddress? address) {
    _deliveryAddress = address;
    // Persist `lastAddressId` so a fresh launch can preselect the same one.
    // Fire-and-forget: SharedPreferences errors are non-fatal here.
    SharedPreferences.getInstance().then((p) {
      if (address?.id != null && address!.id.isNotEmpty) {
        p.setString(_kPrefAddressId, address.id);
      } else {
        p.remove(_kPrefAddressId);
      }
    }).catchError((_) {});
    notifyListeners();
  }

  Future<void> _restoreDeliveryAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kPrefAddressId);
      if (id == null || id.isEmpty) return;
      final list = await AddressApi.instance.list();
      final match = list.where((a) => a.id == id);
      if (match.isNotEmpty) {
        _deliveryAddress = match.first;
        notifyListeners();
      }
    } catch (_) {
      // Silent — address restore is best-effort and shouldn't break the cart.
    }
  }

  String? get couponCode => _couponCode;
  int get loyaltyPoints => _loyaltyPoints;
  DateTime? get scheduledFor => _scheduledFor;

  void setCouponCode(String? code) {
    _couponCode = (code == null || code.isEmpty) ? null : code;
    notifyListeners();
  }

  void setLoyaltyPoints(int points) {
    _loyaltyPoints = points < 0 ? 0 : points;
    notifyListeners();
  }

  void setScheduledFor(DateTime? when) {
    _scheduledFor = when;
    notifyListeners();
  }

  CartEstimate? get lastEstimate => _lastEstimate;

  /// Build a fingerprint that changes whenever the estimate inputs change so
  /// the cart screen can decide to skip a refetch. `promoCode` defaults to
  /// the cart's persisted coupon and `loyaltyPoints` to the slider value so
  /// callers don't have to thread state through manually.
  String estimateKey({
    required String shopId,
    required String? addressKey,
    String? promoCode,
    int? loyaltyPoints,
  }) {
    final items = _lines.values.map((l) => '${l.product.id}:${l.quantity}')
        .toList()
      ..sort();
    final pc = promoCode ?? _couponCode ?? '';
    final lp = loyaltyPoints ?? _loyaltyPoints;
    return '$shopId|${addressKey ?? ''}|${items.join(',')}|$pc|$lp';
  }

  void setEstimate(CartEstimate? est, {String? key}) {
    _lastEstimate = est;
    _lastEstimateKey = key;
    notifyListeners();
  }

  String? get lastEstimateKey => _lastEstimateKey;

  // ─── Read API ────────────────────────────────────────────────────────────────

  List<CartLine> get lines => List.unmodifiable(_lines.values);

  bool get isEmpty => _lines.isEmpty;

  int get itemCount => _lines.values.fold(0, (a, l) => a + l.quantity);

  /// Backwards-compat: legacy callers want `Map<productId, qty>`. We sum
  /// quantities across modifier variants of the same product.
  Map<String, int> get items {
    final result = <String, int>{};
    for (final l in _lines.values) {
      result.update(l.product.id, (v) => v + l.quantity, ifAbsent: () => l.quantity);
    }
    return Map.unmodifiable(result);
  }

  double get subtotal =>
      _lines.values.fold(0.0, (sum, l) => sum + l.lineTotal);

  double get deliveryFee {
    if (subtotal >= 100000) return 0;
    return 12000;
  }

  double get total => subtotal + deliveryFee;

  /// Materialise lines into the legacy `OrderItem` shape used by existing UI
  /// (cart screen, order provider).
  List<OrderItem> get orderItems => _lines.values
      .map((l) => OrderItem(product: l.product, quantity: l.quantity))
      .toList();

  /// Total quantity across all variants of this product.
  int quantityOf(String productId) => _lines.values
      .where((l) => l.product.id == productId)
      .fold(0, (a, l) => a + l.quantity);

  /// Backend payload — what `POST /api/orders` expects under `items`.
  List<Map<String, dynamic>> toApiPayload() => _lines.values.map((l) => {
    'productId': l.product.id,
    'quantity': l.quantity,
    if (l.modifiers.isNotEmpty)
      'modifiers': l.modifiers.map((m) => m.toApiJson()).toList(),
  }).toList();

  // ─── Mutations ───────────────────────────────────────────────────────────────

  static String _keyFor(String productId, List<CartModifierSelection> mods) {
    if (mods.isEmpty) return productId;
    final allOpts = <String>[];
    for (final m in mods) {
      allOpts.addAll(m.optionIds);
    }
    allOpts.sort();
    return '$productId|${allOpts.join('|')}';
  }

  /// Legacy add (no modifiers). Returns false on shop conflict.
  bool add(Product product) {
    if (_currentShopId != null && _currentShopId != product.shopId && !isEmpty) {
      return false;
    }
    _currentShopId = product.shopId;
    final key = _keyFor(product.id, const []);
    final existing = _lines[key];
    if (existing != null) {
      existing.quantity += 1;
    } else {
      _lines[key] = CartLine(
        key: key,
        product: product,
        quantity: 1,
        unitPrice: product.effectivePrice,
      );
    }
    notifyListeners();
    return true;
  }

  /// Add a product with a specific modifier selection. Same product with
  /// different modifiers occupies a separate line.
  bool addWithModifiers(
    Product product,
    int qty,
    List<CartModifierSelection> modifiers,
    double unitPrice, {
    List<ModifierSnapshot> snapshot = const [],
  }) {
    if (qty <= 0) return false;
    if (_currentShopId != null && _currentShopId != product.shopId && !isEmpty) {
      return false;
    }
    _currentShopId = product.shopId;
    final key = _keyFor(product.id, modifiers);
    final existing = _lines[key];
    if (existing != null) {
      existing.quantity += qty;
    } else {
      _lines[key] = CartLine(
        key: key,
        product: product,
        quantity: qty,
        unitPrice: unitPrice,
        modifiers: List.unmodifiable(modifiers),
        snapshot: List.unmodifiable(snapshot),
      );
    }
    notifyListeners();
    return true;
  }

  /// Decrement by one. For lines without modifiers we look up by productId so
  /// the existing UI keeps working.
  void remove(String productId) {
    // Find the first matching line — prefer the no-modifier line, otherwise
    // any line for this product.
    CartLine? target;
    final noModKey = _keyFor(productId, const []);
    if (_lines.containsKey(noModKey)) {
      target = _lines[noModKey];
    } else {
      for (final l in _lines.values) {
        if (l.product.id == productId) { target = l; break; }
      }
    }
    if (target == null) return;
    if (target.quantity > 1) {
      target.quantity -= 1;
    } else {
      _lines.remove(target.key);
    }
    if (_lines.isEmpty) _currentShopId = null;
    notifyListeners();
  }

  /// Decrement a specific cart line (used when modifier variants exist).
  void removeLine(String key) {
    final line = _lines[key];
    if (line == null) return;
    if (line.quantity > 1) {
      line.quantity -= 1;
    } else {
      _lines.remove(key);
    }
    if (_lines.isEmpty) _currentShopId = null;
    notifyListeners();
  }

  void clearForNewShop() {
    _lines.clear();
    _currentShopId = null;
    _lastEstimate = null;
    _lastEstimateKey = null;
    _couponCode = null;
    _loyaltyPoints = 0;
    _scheduledFor = null;
    notifyListeners();
  }

  void clear() => clearForNewShop();
}
