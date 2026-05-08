import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import '../models/models.dart';
import '../config/api_config.dart';
import 'api_client.dart';

/// Shop-side product editing — extension of public catalog API.
class ShopProduct extends Product {
  final String? description;
  final String? ingredients;
  final int stock;
  final DateTime createdAt;

  const ShopProduct({
    required super.id,
    required super.name,
    required super.nameUz,
    required super.price,
    required super.unit,
    required super.category,
    required super.imageUrl,
    required super.shopId,
    super.discountPrice,
    super.isAvailable = true,
    this.description,
    this.ingredients,
    this.stock = 0,
    required this.createdAt,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) => ShopProduct(
    id: json['id'],
    name: json['name'],
    nameUz: json['nameUz'],
    description: json['description'],
    ingredients: json['ingredients'],
    price: (json['price'] as num).toDouble(),
    discountPrice: json['discountPrice'] == null ? null : (json['discountPrice'] as num).toDouble(),
    unit: json['unit'],
    category: json['category'],
    imageUrl: json['imageUrl'] ?? '',
    shopId: json['shopId'],
    stock: json['stock'] ?? 0,
    isAvailable: json['isAvailable'] ?? true,
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class ProductApi {
  ProductApi._();
  static final ProductApi instance = ProductApi._();

  final _api = ApiClient.instance;

  /// Owner view — includes archived/unavailable items
  Future<List<ShopProduct>> forShopOwner(String shopId) async {
    final res = await _api.get('/api/products/shop/$shopId');
    return (res.data['products'] as List)
        .map((j) => ShopProduct.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ShopProduct> create({
    required String shopId,
    required String name,
    required String nameUz,
    String? description,
    String? ingredients,
    required double price,
    double? discountPrice,
    required String unit,
    required String category,
    required String imageUrl,
    int stock = 100,
  }) async {
    final res = await _api.post('/api/products', {
      'shopId': shopId,
      'name': name,
      'nameUz': nameUz,
      if (description != null) 'description': description,
      if (ingredients != null) 'ingredients': ingredients,
      'price': price,
      if (discountPrice != null) 'discountPrice': discountPrice,
      'unit': unit,
      'category': category,
      'imageUrl': imageUrl,
      'stock': stock,
    });
    return ShopProduct.fromJson(res.data['product']);
  }

  Future<ShopProduct> update(String id, Map<String, dynamic> patch) async {
    final res = await _api.patch('/api/products/$id', patch);
    return ShopProduct.fromJson(res.data['product']);
  }

  Future<void> delete(String id, {bool hard = false}) async {
    await _api.delete('/api/products/$id${hard ? '?hard=1' : ''}');
  }

  /// Upload image (bytes) and get back a URL to put into product.imageUrl.
  /// Goes through the shared [ApiClient] so 401s trigger refresh automatically.
  Future<String> uploadImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: MediaType.parse(_guessMime(filename)),
      ),
    });
    final res = await _api.postMultipart('/api/products/upload-image', form);
    final url = res.data['url'] as String;
    // Backend returns relative URL like "/uploads/products/foo.jpg"
    if (url.startsWith('http')) return url;
    return '${ApiConfig.baseUrl}$url';
  }

  /// Bulk import from XLSX/CSV bytes. Routes through [ApiClient] for 401 refresh.
  Future<ImportResult> importFromFile({
    required String shopId,
    required Uint8List bytes,
    required String filename,
    bool dryRun = false,
  }) async {
    final form = FormData.fromMap({
      'shopId': shopId,
      'dryRun': dryRun ? '1' : '0',
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: MediaType.parse(_guessSheetMime(filename)),
      ),
    });
    final res = await _api.postMultipart('/api/products/import', form);
    return ImportResult.fromJson(res.data);
  }

  String templateUrl({bool xlsx = true}) =>
      '${ApiConfig.baseUrl}/api/products/template?format=${xlsx ? 'xlsx' : 'csv'}';

  String _guessMime(String filename) {
    final f = filename.toLowerCase();
    if (f.endsWith('.png')) return 'image/png';
    if (f.endsWith('.webp')) return 'image/webp';
    if (f.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _guessSheetMime(String filename) {
    final f = filename.toLowerCase();
    if (f.endsWith('.csv')) return 'text/csv';
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
}

class ImportResult {
  final int total;
  final int created;
  final List<ImportError> errors;
  ImportResult({required this.total, required this.created, required this.errors});

  factory ImportResult.fromJson(Map<String, dynamic> json) => ImportResult(
    total: json['total'] ?? 0,
    created: json['created'] ?? 0,
    errors: ((json['errors'] as List?) ?? [])
        .map((e) => ImportError(row: e['row'] ?? 0, error: e['error'] ?? ''))
        .toList(),
  );
}

class ImportError {
  final int row;
  final String error;
  ImportError({required this.row, required this.error});
}
