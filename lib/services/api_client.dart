import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';
import 'sentry_service.dart';

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

  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';

  // Encrypted storage on Android; Keychain on iOS; localStorage on web.
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  late final Dio _dio = _createDio();

  // A separate Dio used only for the /api/auth/refresh call so that the
  // refresh request itself does not go through the auth interceptor.
  late final Dio _rawDio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: ApiConfig.timeout,
    receiveTimeout: ApiConfig.timeout,
    headers: {'Content-Type': 'application/json'},
  ));

  /// Single in-flight refresh future so concurrent 401s share one refresh.
  Future<bool>? _refreshing;

  Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.timeout,
      receiveTimeout: ApiConfig.timeout,
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        // Skip token attach if caller explicitly disabled it.
        if (options.extra['skipAuth'] != true) {
          final token = await getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final response = error.response;
        final reqOptions = error.requestOptions;

        final is401 = response?.statusCode == 401;
        final alreadyRetried = reqOptions.extra['retried'] == true;
        final skipAuth = reqOptions.extra['skipAuth'] == true;

        if (!is401 || alreadyRetried || skipAuth) {
          return handler.next(error);
        }

        final refresh = await getRefreshToken();
        if (refresh == null || refresh.isEmpty) {
          await clearTokens();
          return handler.next(error);
        }

        // Coalesce concurrent refreshes into one.
        final ok = await (_refreshing ??= _performRefresh(refresh)
            .whenComplete(() => _refreshing = null));

        if (!ok) {
          await clearTokens();
          return handler.next(error);
        }

        // Retry the original request once with the new access token.
        try {
          final newAccess = await getAccessToken();
          final retryOptions = Options(
            method: reqOptions.method,
            headers: {
              ...reqOptions.headers,
              if (newAccess != null) 'Authorization': 'Bearer $newAccess',
            },
            responseType: reqOptions.responseType,
            contentType: reqOptions.contentType,
            sendTimeout: reqOptions.sendTimeout,
            receiveTimeout: reqOptions.receiveTimeout,
            extra: {...reqOptions.extra, 'retried': true},
          );
          final retryRes = await dio.request(
            reqOptions.path,
            data: reqOptions.data,
            queryParameters: reqOptions.queryParameters,
            options: retryOptions,
            cancelToken: reqOptions.cancelToken,
            onReceiveProgress: reqOptions.onReceiveProgress,
            onSendProgress: reqOptions.onSendProgress,
          );
          return handler.resolve(retryRes);
        } catch (_) {
          // Retry itself failed — propagate original 401.
          return handler.next(error);
        }
      },
    ));

    return dio;
  }

  /// Calls /api/auth/refresh with the given refresh token, persists the new
  /// pair, and returns true on success.
  Future<bool> _performRefresh(String refreshToken) async {
    try {
      final res = await _rawDio.post(
        '/api/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = res.data;
      if (data is! Map) return false;
      final newAccess = data['accessToken'] as String?;
      final newRefresh = data['refreshToken'] as String?;
      if (newAccess == null || newAccess.isEmpty) return false;
      await saveTokens(newAccess, newRefresh ?? refreshToken);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Token refresh failed: $e');
      return false;
    }
  }

  // ─── Public token API ──────────────────────────────────────────────────────

  Future<String?> getAccessToken() => _storage.read(key: _accessKey);
  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> saveTokens(String access, String refresh) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  // ─── Backwards-compatible single-token shims ───────────────────────────────
  // Kept so existing callers (product_api.dart, socket_service.dart) keep
  // working without changes. Only the access token is exposed.

  Future<String?> getToken() => getAccessToken();

  Future<void> saveToken(String token) async {
    // Best-effort fallback when the backend still returns the legacy
    // single-token shape.
    await _storage.write(key: _accessKey, value: token);
  }

  Future<void> clearToken() => clearTokens();

  // ─── HTTP verbs ────────────────────────────────────────────────────────────

  Future<Response> get(String path, {Map<String, dynamic>? query}) async {
    try {
      return await _dio.get(path, queryParameters: query);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Response> post(String path, [dynamic data]) async {
    try {
      return await _dio.post(path, data: data);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Response> patch(String path, [dynamic data]) async {
    try {
      return await _dio.patch(path, data: data);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Response> put(String path, [dynamic data]) async {
    try {
      return await _dio.put(path, data: data);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Response> delete(String path, {dynamic data}) async {
    try {
      return await _dio.delete(path, data: data);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Multipart POST helper. `formData` should be a `FormData` instance from
  /// `package:dio` (the same one already imported here). Returns the parsed
  /// response on success, or throws an [ApiException] on failure.
  Future<Response> postMultipart(String path, FormData formData) async {
    try {
      return await _dio.post(
        path,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  ApiException _toException(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return ApiException('Internet aloqasi yo\'q. Iltimos, qayta urinib ko\'ring.');
    }
    final code = e.response?.statusCode;
    final msg = e.response?.data is Map
        ? (e.response!.data['error'] ?? 'Server xatosi') as String
        : 'Server xatosi';
    final exception = ApiException(msg, code);
    // Report 5xx (server-side) failures to Sentry. 4xx are expected user
    // errors (bad input, 401, 404, etc.) so we don't spam the dashboard.
    if (code != null && code >= 500 && code < 600) {
      // Fire-and-forget; capture errors are swallowed when Sentry is disabled.
      SentryService.capture(exception, e.stackTrace);
    }
    return exception;
  }
}
