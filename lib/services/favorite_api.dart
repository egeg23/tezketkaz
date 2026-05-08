import '../models/catalog.dart';
import '../models/models.dart';
import 'api_client.dart';

/// Phase 7.3 — single favourite entry. Either `productId` or `shopId` is set
/// (never both). When the backend includes the embedded `product` / `shop`
/// payload we keep them on the Dart side for the favourites list UI so we
/// don't have to refetch every entry by id.
class Favorite {
  final String id;
  final String? productId;
  final String? shopId;
  final Product? product;
  final Shop? shop;
  final DateTime? createdAt;

  const Favorite({
    required this.id,
    this.productId,
    this.shopId,
    this.product,
    this.shop,
    this.createdAt,
  });

  bool get isProduct => productId != null;
  bool get isShop => shopId != null;

  factory Favorite.fromJson(Map<String, dynamic> j) {
    Product? prod;
    final p = j['product'];
    if (p is Map) {
      // Backend product payload may not match the legacy `Product` shape
      // exactly — pick out only what the favourites list needs.
      prod = Product(
        id: (p['id'] as String?) ?? '',
        name: (p['name'] as String?) ?? '',
        nameUz: (p['nameUz'] as String?) ?? (p['name'] as String?) ?? '',
        price: (p['price'] as num?)?.toDouble() ?? 0,
        unit: (p['unit'] as String?) ?? '',
        category: (p['category'] as String?) ?? '',
        imageUrl: (p['imageUrl'] as String?) ?? '',
        shopId: (p['shopId'] as String?) ?? '',
        isAvailable: p['isAvailable'] as bool? ?? true,
      );
    }
    Shop? shop;
    final s = j['shop'];
    if (s is Map) {
      shop = Shop.fromJson(Map<String, dynamic>.from(s));
    }
    return Favorite(
      id: j['id'] as String,
      productId: j['productId'] as String?,
      shopId: j['shopId'] as String?,
      product: prod,
      shop: shop,
      createdAt: j['createdAt'] != null
          ? DateTime.tryParse(j['createdAt'] as String)
          : null,
    );
  }
}

class FavoriteApi {
  FavoriteApi._();
  static final FavoriteApi instance = FavoriteApi._();

  final _api = ApiClient.instance;

  Future<List<Favorite>> list() async {
    final res = await _api.get('/api/favorites/me');
    final raw = res.data;
    final list = raw is List
        ? raw
        : (raw is Map && raw['favorites'] is List
            ? raw['favorites'] as List
            : const <dynamic>[]);
    return list
        .map((j) => Favorite.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  Future<void> addProduct(String productId) async {
    await _api.post('/api/favorites/me/products/$productId');
  }

  Future<void> removeProduct(String productId) async {
    await _api.delete('/api/favorites/me/products/$productId');
  }

  Future<void> addShop(String shopId) async {
    await _api.post('/api/favorites/me/shops/$shopId');
  }

  Future<void> removeShop(String shopId) async {
    await _api.delete('/api/favorites/me/shops/$shopId');
  }

  /// `GET /api/favorites/me/check?productId=&shopId=` — single-entity probe.
  /// Pass exactly one id at a time.
  Future<bool> check({String? productId, String? shopId}) async {
    try {
      final res = await _api.get('/api/favorites/me/check', query: {
        if (productId != null) 'productId': productId,
        if (shopId != null) 'shopId': shopId,
      });
      final data = res.data;
      if (data is Map) return data['isFavorite'] as bool? ?? false;
      return false;
    } catch (_) {
      return false;
    }
  }
}
