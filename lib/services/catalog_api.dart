import '../models/models.dart';
import '../models/catalog.dart';
import 'api_client.dart';

class CatalogApi {
  CatalogApi._();
  static final CatalogApi instance = CatalogApi._();

  final _api = ApiClient.instance;

  Product _parse(Map<String, dynamic> j) => Product(
    id: j['id'],
    name: j['name'],
    nameUz: j['nameUz'] ?? j['name'],
    price: (j['price'] as num).toDouble(),
    discountPrice: j['discountPrice'] == null ? null : (j['discountPrice'] as num).toDouble(),
    unit: j['unit'] ?? 'шт',
    category: j['category'] ?? '',
    imageUrl: j['imageUrl'] ?? '',
    shopId: j['shopId'] ?? '',
  );

  Future<List<Product>> featured() async {
    final res = await _api.get('/api/products/featured');
    return (res.data['products'] as List).map<Product>((j) => _parse(j as Map<String, dynamic>)).toList();
  }

  Future<List<Product>> list({String? category, String? search}) async {
    final res = await _api.get('/api/products', query: {
      if (category != null && category != 'all') 'category': category,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return (res.data['products'] as List).map<Product>((j) => _parse(j as Map<String, dynamic>)).toList();
  }

  /// Phase 1 — paginated product search with rich filters.
  /// Returns `(items, nextCursor)`.
  Future<({List<Product> items, String? nextCursor})> search({
    String? q,
    String? shopId,
    String? categoryId,
    String? vertical,
    num? priceMin,
    num? priceMax,
    String sort = 'new',
    String? cursor,
    int limit = 20,
  }) async {
    final res = await _api.get('/api/products', query: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (shopId != null) 'shopId': shopId,
      if (categoryId != null) 'categoryId': categoryId,
      if (vertical != null) 'vertical': vertical,
      if (priceMin != null) 'priceMin': priceMin,
      if (priceMax != null) 'priceMax': priceMax,
      'sort': sort,
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
    });
    final data = res.data as Map<String, dynamic>;
    // Backend may use "items" (Phase 1) or legacy "products".
    final rawList = (data['items'] as List?) ?? (data['products'] as List? ?? const []);
    final items = rawList
        .map<Product>((j) => _parse(j as Map<String, dynamic>))
        .toList();
    return (items: items, nextCursor: data['nextCursor'] as String?);
  }

  /// Phase 1 — nearby shops by vertical and location.
  Future<List<Shop>> nearbyShops({
    String? vertical,
    double? lat,
    double? lng,
    double? radiusKm,
    String? q,
    int limit = 30,
  }) async {
    final res = await _api.get('/api/shops', query: {
      if (vertical != null) 'vertical': vertical,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (radiusKm != null) 'radiusKm': radiusKm,
      if (q != null && q.isNotEmpty) 'q': q,
      'limit': limit,
    });
    final raw = (res.data['items'] as List?) ?? (res.data['shops'] as List? ?? const []);
    return raw
        .map((j) => Shop.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Phase 1 — modifier groups for a product.
  Future<List<ModifierGroup>> productModifiers(String productId) async {
    final res = await _api.get('/api/products/$productId/modifier-groups');
    final raw = (res.data['groups'] as List?) ??
        (res.data['modifierGroups'] as List?) ??
        (res.data is List ? res.data as List : const []);
    return raw
        .map((j) => ModifierGroup.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}
