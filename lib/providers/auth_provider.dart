import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../constants/legal.dart';
import '../models/models.dart';
import '../services/analytics_service.dart';
import '../services/api_client.dart';
import '../services/firebase_setup.dart';
import '../services/membership_api.dart';
import '../services/push_service.dart';
import '../services/social_auth_service.dart';
import '../services/socket_service.dart';

enum AuthState { unknown, unauthenticated, authenticated }

class AuthProvider extends ChangeNotifier {
  AuthState _state = AuthState.unknown;
  User? _user;
  bool _isLoading = false;
  String? _error;
  bool _legalUpdateRequired = false;
  String? _currentLegalVersion;

  // Phase 7.2 — cached buyer membership row. Refreshed once on login and
  // every 30 minutes after that while the auth provider is alive.
  Membership? _membership;
  Timer? _membershipTimer;

  AuthState get state => _state;
  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isCourier => _user?.activeRole == UserRole.courier;
  bool get isShop => _user?.activeRole == UserRole.shop;

  /// Phase 7.2 — current buyer membership (`null` when not subscribed).
  Membership? get membership => _membership;

  /// True when the most recent verify-otp told us the user needs to re-accept
  /// the latest T&C / Privacy Policy. UI should prompt and call [acceptLegal].
  bool get legalUpdateRequired => _legalUpdateRequired;
  String? get currentLegalVersion => _currentLegalVersion;

  final _api = ApiClient.instance;

  /// Convenience: any caller with a `BuildContext` can poke a refresh
  /// without holding a reference to the provider directly. Used by the
  /// subscription screen after subscribe / cancel / reactivate.
  static Future<void> refreshMembershipFromAnywhere(BuildContext ctx) async {
    try {
      await ctx.read<AuthProvider>().refreshMembership();
    } catch (_) {/* ignore — best effort */}
  }

  Future<void> refreshMembership() async {
    if (!isAuthenticated) return;
    try {
      _membership = await MembershipApi.instance.me();
      notifyListeners();
    } catch (e) {
      // Membership refresh failing isn't fatal — buyer can still order,
      // they just won't see their subscription tier. Log debug-only so we
      // don't pollute Sentry with expected 404s on free users.
      if (kDebugMode) debugPrint('refreshMembership failed: $e');
    }
  }

  void _startMembershipTimer() {
    _membershipTimer?.cancel();
    // 30 minutes — light enough that we never hammer the endpoint while still
    // catching billing-cycle rollovers without a manual pull-to-refresh.
    _membershipTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      refreshMembership();
    });
  }

  void _stopMembershipTimer() {
    _membershipTimer?.cancel();
    _membershipTimer = null;
    _membership = null;
  }

  @override
  void dispose() {
    _membershipTimer?.cancel();
    super.dispose();
  }

  /// Phase 7.1 — push country + locale to the backend.
  /// `PATCH /api/users/me` accepts `{country, locale}` and returns the
  /// updated user object.
  Future<void> updateCountryLocale({
    required String country,
    required String locale,
  }) async {
    try {
      final res = await _api.patch('/api/users/me', {
        'country': country,
        'locale': locale,
      });
      final body = res.data;
      final userJson = body is Map && body['user'] is Map
          ? body['user'] as Map<String, dynamic>
          : body is Map<String, dynamic>
              ? body
              : null;
      if (userJson != null) {
        _user = _parseUser(userJson);
      } else if (_user != null) {
        _user = _user!.copyWith(country: country);
      }
      notifyListeners();
    } catch (_) {
      // Backend write failed — keep the local locale change in any case so
      // the user isn't stuck with an unwanted language.
      if (_user != null) {
        _user = _user!.copyWith(country: country);
        notifyListeners();
      }
      rethrow;
    }
  }

  /// On app start — try to restore session from saved tokens
  Future<void> tryRestoreSession() async {
    try {
      final token =
          await _api.getAccessToken().timeout(const Duration(seconds: 3));
      if (token == null) {
        _state = AuthState.unauthenticated;
        notifyListeners();
        return;
      }
      final res = await _api.get('/api/auth/me');
      _user = _parseUser(res.data['user']);
      _state = AuthState.authenticated;
      SocketService.instance.connect();
      // Phase 13.1.6 — only attempt push registration when Firebase actually
      // initialised at boot. Without `FirebaseSetup.isReady` the plugin call
      // would throw "[core/no-app]" and Sentry would log noise.
      if (FirebaseSetup.isReady) {
        unawaited(PushService.instance.init());
      }
      _startMembershipTimer();
      unawaited(refreshMembership());
      if (_user != null) {
        unawaited(AnalyticsService.instance.setUser(_user!.id, {
          if (_user!.country != null) 'country': _user!.country!,
        }));
      }
    } catch (_) {
      try { await _api.clearTokens(); } catch (_) {}
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

  Future<bool> verifyOtp(
    String phone,
    String code, {
    String acceptedLegalVersion = kCurrentLegalVersion,
  }) async {
    _setLoading(true);
    try {
      final res = await _api.post('/api/auth/verify-otp', {
        'phone': phone,
        'code': code,
        'acceptedLegalVersion': acceptedLegalVersion,
      });
      await _ingestAuthResponse(res.data, res.statusCode, method: 'otp');
      _setLoading(false);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    }
  }

  /// Records acceptance of the current legal version against the backend and
  /// clears the [legalUpdateRequired] flag on success.
  Future<bool> acceptLegal({String version = kCurrentLegalVersion}) async {
    try {
      await _api.post('/api/auth/accept-legal', {'version': version});
      _legalUpdateRequired = false;
      _currentLegalVersion = version;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Phase 9.3 — Apple Sign-In flow.
  ///
  /// 1. Trigger the native Apple credential prompt (returns a signed JWT).
  /// 2. POST that JWT to `/api/auth/oauth/apple`. The backend validates
  ///    the token against Apple's JWKS and returns our token pair + user.
  /// 3. Run the same post-login bookkeeping as [verifyOtp].
  Future<bool> loginWithApple() async {
    _setLoading(true);
    try {
      final idToken = await SocialAuthService.instance.appleSignIn();
      if (idToken == null) {
        // User cancelled — not an error, just not a success.
        _setLoading(false);
        return false;
      }
      final res = await _api.post('/api/auth/oauth/apple', {'idToken': idToken});
      await _ingestAuthResponse(res.data, res.statusCode, method: 'apple');
      _setLoading(false);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      // Sentinel error code — UI translates via l10n key
      // `auth.social_apple_error`. Falls back to the raw key when missing.
      _error = 'auth.social_apple_error';
      _setLoading(false);
      return false;
    }
  }

  /// Phase 9.3 — Google Sign-In flow. Mirrors [loginWithApple].
  Future<bool> loginWithGoogle() async {
    _setLoading(true);
    try {
      final idToken = await SocialAuthService.instance.googleSignIn();
      if (idToken == null) {
        _setLoading(false);
        return false;
      }
      final res = await _api.post('/api/auth/oauth/google', {'idToken': idToken});
      await _ingestAuthResponse(res.data, res.statusCode, method: 'google');
      _setLoading(false);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'auth.social_google_error';
      _setLoading(false);
      return false;
    }
  }

  /// Shared post-login bookkeeping for OTP and OAuth flows.
  ///
  /// Persists the token pair (or legacy single token), parses the user,
  /// flips state to authenticated, kicks off socket/push/membership/
  /// analytics. Throws [ApiException] when the response shape is invalid.
  Future<void> _ingestAuthResponse(
    dynamic body,
    int? statusCode, {
    required String method,
  }) async {
    if (body is! Map) {
      throw ApiException('Server javobi noto\'g\'ri', statusCode);
    }
    final access = body['accessToken'] as String?;
    final refresh = body['refreshToken'] as String?;
    if (access != null && refresh != null) {
      await _api.saveTokens(access, refresh);
    } else if (body['token'] is String) {
      if (kDebugMode) {
        debugPrint('$method auth returned legacy {token} shape — '
            'no refresh token will be persisted.');
      }
      await _api.saveToken(body['token'] as String);
    } else {
      throw ApiException('Server javobi noto\'g\'ri', statusCode);
    }
    _user = _parseUser(body['user']);
    _legalUpdateRequired = body['legalUpdateRequired'] == true;
    _currentLegalVersion = body['currentLegalVersion'] as String?;
    _state = AuthState.authenticated;
    SocketService.instance.connect();
    // Phase 13.1.6 — guard against unconfigured Firebase (e.g. dev runs
    // without google-services.json). PushService.init() is itself try/catch
    // safe, but skipping the call keeps logs clean.
    if (FirebaseSetup.isReady) {
      unawaited(PushService.instance.init());
    }
    _startMembershipTimer();
    unawaited(refreshMembership());
    if (_user != null) {
      unawaited(AnalyticsService.instance.setUser(_user!.id, {
        if (_user!.country != null) 'country': _user!.country!,
      }));
      unawaited(AnalyticsService.instance.logEvent('login', {
        'method': method,
      }));
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
    // Best-effort: unregister FCM token before clearing auth.
    try {
      await PushService.instance.dispose();
    } catch (_) {}

    // Best-effort: tell backend to invalidate the refresh token.
    try {
      final refresh = await _api.getRefreshToken();
      if (refresh != null) {
        await _api.post('/api/auth/logout', {'refreshToken': refresh});
      }
    } catch (_) {}

    await _api.clearTokens();
    // Best-effort: drop the cached Google account so the next sign-in
    // re-prompts the picker. No-op for Apple.
    unawaited(SocialAuthService.instance.signOut());
    SocketService.instance.disconnect();
    _stopMembershipTimer();
    unawaited(AnalyticsService.instance.setUser(null));
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
      country: json['country'] as String?,
      // Phase 11 — null means the user hasn't seen the tutorial.
      onboardedAt: _parseDate(json['onboardedAt']),
    );
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  /// Phase 11 — flip the local user object to "onboarded" after completing the
  /// tutorial. Backend write is owned by `OnboardingApi.markOnboarded`; this
  /// just nudges the in-memory state so the router redirect stops firing.
  void markOnboardedLocally() {
    if (_user == null) return;
    _user = _user!.copyWith(onboardedAt: DateTime.now());
    notifyListeners();
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
