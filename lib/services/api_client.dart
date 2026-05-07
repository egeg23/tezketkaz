import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _tokenKey = 'auth_token';
  late final Dio _dio = _createDio();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.timeout,
      receiveTimeout: ApiConfig.timeout,
      headers: {'Content-Type': 'application/json'},
    ));

    // Auth interceptor — attach token to every request
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Auto-logout on 401
        if (error.response?.statusCode == 401) {
          await clearToken();
        }
        handler.next(error);
      },
    ));

    return dio;
  }

  Future<String?> getToken() async => (await _prefs).getString(_tokenKey);
  Future<void> saveToken(String token) async => (await _prefs).setString(_tokenKey, token);
  Future<void> clearToken() async => (await _prefs).remove(_tokenKey);

  Future<Response> get(String path, {Map<String, dynamic>? query}) async {
    try {
      return await _dio.get(path, queryParameters: query);
    } on DioException catch (e) { throw _toException(e); }
  }

  Future<Response> post(String path, [dynamic data]) async {
    try {
      return await _dio.post(path, data: data);
    } on DioException catch (e) { throw _toException(e); }
  }

  Future<Response> patch(String path, [dynamic data]) async {
    try {
      return await _dio.patch(path, data: data);
    } on DioException catch (e) { throw _toException(e); }
  }

  Future<Response> delete(String path) async {
    try {
      return await _dio.delete(path);
    } on DioException catch (e) { throw _toException(e); }
  }

  ApiException _toException(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
      return ApiException('Internet aloqasi yo\'q. Iltimos, qayta urinib ko\'ring.');
    }
    final code = e.response?.statusCode;
    final msg = e.response?.data is Map
      ? (e.response!.data['error'] ?? 'Server xatosi') as String
      : 'Server xatosi';
    return ApiException(msg, code);
  }
}
