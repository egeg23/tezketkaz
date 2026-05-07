import '../models/catalog.dart';
import 'api_client.dart';

/// Wraps `GET /api/users/addresses`, create / update / delete and
/// `POST /api/users/addresses/:id/default`.
class AddressApi {
  AddressApi._();
  static final AddressApi instance = AddressApi._();

  final _api = ApiClient.instance;

  Future<List<UserAddress>> list() async {
    final res = await _api.get('/api/users/addresses');
    final raw = (res.data['addresses'] as List?) ??
        (res.data is List ? res.data as List : const []);
    return raw
        .map((j) => UserAddress.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<UserAddress> create(UserAddress a) async {
    final res = await _api.post('/api/users/addresses', a.toJson());
    return UserAddress.fromJson(
        (res.data['address'] ?? res.data) as Map<String, dynamic>);
  }

  Future<UserAddress> update(String id, UserAddress a) async {
    final res = await _api.patch('/api/users/addresses/$id', a.toJson());
    return UserAddress.fromJson(
        (res.data['address'] ?? res.data) as Map<String, dynamic>);
  }

  Future<void> remove(String id) async {
    await _api.delete('/api/users/addresses/$id');
  }

  Future<void> setDefault(String id) async {
    await _api.post('/api/users/addresses/$id/default');
  }
}
