import '../models/catalog.dart';
import 'api_client.dart';

/// Wraps `GET /api/categories` and `GET /api/categories/tree`.
class CategoryApi {
  CategoryApi._();
  static final CategoryApi instance = CategoryApi._();

  final _api = ApiClient.instance;

  /// Flat list. All filters are optional.
  Future<List<Category>> list({
    String? vertical,
    String? parentId,
    String? shopId,
  }) async {
    final res = await _api.get('/api/categories', query: {
      if (vertical != null) 'vertical': vertical,
      if (parentId != null) 'parentId': parentId,
      if (shopId != null) 'shopId': shopId,
    });
    final raw = (res.data['categories'] as List? ?? const []);
    return raw
        .map((j) => Category.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Hierarchical tree (`children` populated).
  Future<List<Category>> tree({String? vertical}) async {
    final res = await _api.get('/api/categories/tree', query: {
      if (vertical != null) 'vertical': vertical,
    });
    // Backend may wrap the tree under "categories" or return a bare list.
    final raw = res.data is Map && res.data['categories'] is List
        ? res.data['categories'] as List
        : (res.data as List? ?? const []);
    return raw
        .map((j) => Category.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}
