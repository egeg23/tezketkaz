// Phase 13.1.6 — Firebase bootstrap helper.
//
// Wraps `Firebase.initializeApp` with the failure modes we expect during the
// lifetime of the project:
//
//   • Local dev without google-services.json / GoogleService-Info.plist
//     → init throws, we log + return false so PushService.init() is skipped
//     and the app keeps booting (no push, but everything else works).
//   • Real prod (`flutterfire configure` run, real plist + json shipped)
//     → init succeeds, returns true, main.dart proceeds to PushService.init().
//   • Misconfigured release build (stub firebase_options.dart in release)
//     → `DefaultFirebaseOptions.currentPlatform` throws StateError BEFORE the
//     plugin call. We catch + report to Sentry as a critical breadcrumb, then
//     return false so the app still opens (degraded).
//
// This file is intentionally tiny — there's nothing app-specific here, just
// the boot-time error funnel.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'sentry_service.dart';

class FirebaseSetup {
  FirebaseSetup._();

  /// `true` once [initializeFirebase] has run and Firebase is actually usable.
  static bool _ready = false;
  static bool get isReady => _ready;

  /// Initialise Firebase. Always swallows exceptions; the boolean result tells
  /// the caller whether to proceed with FCM / Analytics wiring.
  static Future<bool> initialize() async {
    if (_ready) return true;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _ready = true;
      if (kDebugMode) {
        debugPrint('[firebase_setup] Firebase initialised');
      }
      return true;
    } catch (e, st) {
      // Production: this only happens if the native plist/json is missing
      // even though firebase_options.dart was generated. That's a packaging
      // bug worth alerting on. Local dev: expected, just log.
      if (kReleaseMode) {
        await SentryService.capture(
          StateError('Firebase init failed in release: $e'),
          st,
        );
      } else if (kDebugMode) {
        debugPrint('[firebase_setup] Firebase init skipped: $e');
      }
      _ready = false;
      return false;
    }
  }
}

/// Backwards-compatible top-level alias, matches the function name the
/// runbook + main.dart use.
Future<bool> initializeFirebase() => FirebaseSetup.initialize();
