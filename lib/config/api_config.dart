import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  // For web — same origin as the served page (frontend bundled into backend).
  // For native — Android emulator special host or LAN IP.
  static String get baseUrl {
    if (kIsWeb) return Uri.base.origin;
    return 'http://10.0.2.2:3000';
  }

  static const Duration timeout = Duration(seconds: 15);
  static const bool useMockData = false;
}
