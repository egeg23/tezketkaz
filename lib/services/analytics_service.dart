import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Phase 7.4 — thin wrapper over `firebase_analytics`.
///
/// Every method silently degrades to a debug-print when Firebase isn't
/// configured (e.g. local dev without google-services.json). The rest of the
/// app calls `AnalyticsService.instance.logEvent(...)` without caring whether
/// analytics are actually wired up.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _fa;
  bool _initTried = false;

  void _ensure() {
    if (_initTried) return;
    _initTried = true;
    try {
      _fa = FirebaseAnalytics.instance;
    } catch (e) {
      if (kDebugMode) debugPrint('Analytics disabled: $e');
      _fa = null;
    }
  }

  /// Sanitize parameters: Firebase only accepts num / String / bool values.
  /// Anything else (e.g. enums, DateTime) is coerced via `toString()`.
  Map<String, Object> _sanitize(Map<String, dynamic>? params) {
    if (params == null) return const {};
    final out = <String, Object>{};
    for (final e in params.entries) {
      final v = e.value;
      if (v is num || v is String || v is bool) {
        out[e.key] = v as Object;
      } else if (v != null) {
        out[e.key] = v.toString();
      }
    }
    return out;
  }

  Future<void> logEvent(String name, [Map<String, dynamic>? params]) async {
    _ensure();
    final fa = _fa;
    if (fa == null) {
      if (kDebugMode) debugPrint('analytics: $name $params');
      return;
    }
    try {
      await fa.logEvent(name: name, parameters: _sanitize(params));
    } catch (e) {
      if (kDebugMode) debugPrint('analytics.logEvent failed: $e');
    }
  }

  Future<void> logScreen(String name) async {
    _ensure();
    final fa = _fa;
    if (fa == null) {
      if (kDebugMode) debugPrint('analytics.screen: $name');
      return;
    }
    try {
      await fa.logScreenView(screenName: name);
    } catch (e) {
      if (kDebugMode) debugPrint('analytics.logScreen failed: $e');
    }
  }

  Future<void> setUser(String? userId, [Map<String, String>? properties]) async {
    _ensure();
    final fa = _fa;
    if (fa == null) return;
    try {
      await fa.setUserId(id: userId);
      if (properties != null) {
        for (final e in properties.entries) {
          await fa.setUserProperty(name: e.key, value: e.value);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('analytics.setUser failed: $e');
    }
  }
}
