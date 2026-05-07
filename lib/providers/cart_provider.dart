import 'package:flutter/foundation.dart';
import '../models/models.dart';

class CartProvider extends ChangeNotifier {
  final Map<String, int> _items = {}; // productId → quantity
  final Map<String, Product> _products = {};
  String? _currentShopId;

  Map<String, int> get items => Map.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get itemCount => _items.values.fold(0, (a, b) => a + b);

  double get subtotal => _items.entries.fold(0.0, (sum, e) {
    final product = _products[e.key];
    return sum + (product?.effectivePrice ?? 0) * e.value;
  });

  double get deliveryFee {
    if (subtotal >= 100000) return 0;   // Бесплатно от 100к сум
    return 12000;                        // 12 000 сум базовая доставка
  }

  double get total => subtotal + deliveryFee;

  List<OrderItem> get orderItems => _items.entries
    .where((e) => _products.containsKey(e.key))
    .map((e) => OrderItem(product: _products[e.key]!, quantity: e.value))
    .toList();

  int quantityOf(String productId) => _items[productId] ?? 0;

  /// Добавление товара. Если из другого магазина — предупреждение.
  /// Возвращает true если добавлено, false если конфликт магазинов.
  bool add(Product product) {
    if (_currentShopId != null && _currentShopId != product.shopId && !isEmpty) {
      return false; // Конфликт магазинов — спросить пользователя
    }
    _currentShopId = product.shopId;
    _products[product.id] = product;
    _items[product.id] = (_items[product.id] ?? 0) + 1;
    notifyListeners();
    return true;
  }

  void remove(String productId) {
    if (!_items.containsKey(productId)) return;
    if (_items[productId]! > 1) {
      _items[productId] = _items[productId]! - 1;
    } else {
      _items.remove(productId);
      _products.remove(productId);
    }
    if (_items.isEmpty) _currentShopId = null;
    notifyListeners();
  }

  void clearForNewShop() {
    _items.clear();
    _products.clear();
    _currentShopId = null;
    notifyListeners();
  }

  void clear() => clearForNewShop();
}
