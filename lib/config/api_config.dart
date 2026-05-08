import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  /// Build-time override. Pass `--dart-define=API_BASE_URL=https://api.tezketkaz.uz`
  /// in production builds. Empty string in dev — we fall back per-platform below.
  static const _envBase = String.fromEnvironment('API_BASE_URL');

  /// Resolves the right base URL depending on the runtime:
  /// - Web build: same origin as the served page (Flutter web bundled into backend).
  /// - Build-time override: whatever was passed via `--dart-define=API_BASE_URL`.
  /// - Android emulator: 10.0.2.2 reaches the host's localhost.
  /// - iOS simulator / desktop: localhost.
  /// - Real device: the override is required; localhost would point at the device itself.
  static String get baseUrl {
    if (kIsWeb) return Uri.base.origin;
    if (_envBase.isNotEmpty) return _envBase;
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://localhost:3000';
  }

  static const Duration timeout = Duration(seconds: 15);
  static const bool useMockData = false;
}
