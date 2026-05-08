import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 10.3 — drives [MaterialApp.themeMode].
///
/// Persists the buyer's choice in `SharedPreferences` under `prefs.themeMode`
/// (values: `system` | `light` | `dark`). Defaults to `system` so the first
/// install respects the OS palette.
class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'prefs.themeMode';

  ThemeMode _themeMode = ThemeMode.system;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  bool get isLoaded => _loaded;

  /// Call once at app boot — non-blocking; UI should still render before this
  /// resolves (defaults to system).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      _themeMode = _parse(raw);
    } catch (_) {
      _themeMode = ThemeMode.system;
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _serialise(mode));
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }

  static ThemeMode _parse(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _serialise(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
