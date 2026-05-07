import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/socket_service.dart';

enum AuthState { unknown, unauthenticated, authenticated }

class AuthProvider extends ChangeNotifier {
  AuthState _state = AuthState.unknown;
  User? _user;
  bool _isLoading = false;
  String? _error;

  AuthState get state => _state;
  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isCourier => _user?.activeRole == UserRole.courier;
  bool get isShop => _user?.activeRole == UserRole.shop;

  final _api = ApiClient.instance;

  /// On app start — try to restore session from saved token
  Future<void> tryRestoreSession() async {
    try {
      final token = await _api.getToken().timeout(const Duration(seconds: 3));
      if (token == null) {
        _state = AuthState.unauthenticated;
        notifyListeners();
        return;
      }
      final res = await _api.get('/api/auth/me');
      _user = _parseUser(res.data['user']);
      _state = AuthState.authenticated;
      SocketService.instance.connect();
    } catch (_) {
      try { await _api.clearToken(); } catch (_) {}
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> sendOtp(String phone) async {
    _setLoading(true);
    try {
      await _api.post('/api/auth/send-otp', {'phone': phone});
      _setLoading(false);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    }
  }

  Future<bool> verifyOtp(String phone, String code) async {
    _setLoading(true);
    try {
      final res = await _api.post('/api/auth/verify-otp', {'phone': phone, 'code': code});
      await _api.saveToken(res.data['token']);
      _user = _parseUser(res.data['user']);
      _state = AuthState.authenticated;
      SocketService.instance.connect();
      _setLoading(false);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    }
  }

  Future<void> setName(String name) async {
    try {
      final res = await _api.patch('/api/auth/me', {'name': name});
      _user = _parseUser(res.data['user']);
      notifyListeners();
    } catch (_) {}
  }

  /// Switch active role (purely local — no API call)
  Future<bool> switchRole(UserRole newRole) async {
    if (_user == null) return false;
    if (newRole == UserRole.courier && !_user!.canSwitchToCourier) return false;
    if (newRole == UserRole.shop && !_user!.isShopOwner) return false;

    _user = _user!.copyWith(activeRole: newRole);
    notifyListeners();
    return true;
  }

  Future<bool> submitCourierVerification({
    required String stir,
    required String passportSeries,
    required String fullName,
  }) async {
    _setLoading(true);
    try {
      final res = await _api.post('/api/couriers/apply', {
        'stir': stir,
        'passportSeries': passportSeries,
        'fullName': fullName,
      });
      _user = _parseUser(res.data['user']);
      _setLoading(false);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    }
  }

  /// Dev-only: instantly approve courier (production: admin panel)
  Future<void> mockApproveCourier() async {
    try {
      final res = await _api.post('/api/couriers/me/approve');
      _user = _parseUser(res.data['user']);
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> connectShop(String shopId) async {
    try {
      await _api.post('/api/shops/connect', {'shopId': shopId});
      // Reload user
      final res = await _api.get('/api/auth/me');
      _user = _parseUser(res.data['user'])?.copyWith(activeRole: UserRole.shop);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    await _api.clearToken();
    SocketService.instance.disconnect();
    _user = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  User? _parseUser(Map<String, dynamic>? json) {
    if (json == null) return null;
    final shops = (json['shops'] as List? ?? []);
    final firstShop = shops.isNotEmpty ? shops.first : null;
    return User(
      id: json['id'],
      phone: json['phone'],
      name: json['name'],
      avatarUrl: json['avatarUrl'],
      activeRole: UserRole.buyer, // Default after login
      isCourierApproved: json['isCourier'] ?? false,
      courierStatus: _parseCourierStatus(json['courierStatus']),
      shopId: firstShop?['id'],
      shopName: firstShop?['name'],
    );
  }

  CourierVerificationStatus _parseCourierStatus(String? s) {
    return switch (s) {
      'pending' => CourierVerificationStatus.pending,
      'approved' => CourierVerificationStatus.approved,
      'rejected' => CourierVerificationStatus.rejected,
      _ => CourierVerificationStatus.none,
    };
  }

  void _setLoading(bool v) {
    _isLoading = v;
    if (v) _error = null;
    notifyListeners();
  }
}
