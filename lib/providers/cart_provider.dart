import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../models/catalog.dart';

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

class CartProvider extends ChangeNotifier {
  /// Lines keyed by `productId|sortedOptionIds`.
  final Map<String, CartLine> _lines = {};
  String? _currentShopId;

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
    notifyListeners();
  }

  void clear() => clearForNewShop();
}
