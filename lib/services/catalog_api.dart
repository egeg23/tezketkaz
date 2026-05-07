import '../models/models.dart';
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
}
