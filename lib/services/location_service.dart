import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Phase 6 — geolocation + reverse-geocoding helper.
///
/// Plays nicely with both Android and iOS via `geolocator` +
/// `permission_handler`. Reverse-geocoding hits the Yandex Geocoder HTTP
/// API directly so we don't need a backend round-trip — the API key comes
/// from `--dart-define=YANDEX_GEOCODER_KEY=...`. When the key is missing
/// (typical dev sandbox) [reverseGeocode] silently returns `null` so callers
/// can degrade gracefully.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  static const _geocoderKey = String.fromEnvironment(
    'YANDEX_GEOCODER_KEY',
    defaultValue: '',
  );

  /// Used only for the geocoder HTTP call — the regular `ApiClient` injects
  /// our auth header which Yandex would reject.
  final Dio _httpDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
  ));

  /// Asks for foreground location permission (when in use). Returns `true`
  /// if the user granted it, `false` for denied / restricted / permanently
  /// denied. Never throws.
  Future<bool> requestPermission() async {
    try {
      final status = await Permission.location.request();
      if (status.isGranted || status.isLimited) return true;
      // `permission_handler` returns `permanentlyDenied` when the user
      // checked "don't ask again" — surface to caller as a regular denial
      // and let the UI prompt them to open Settings.
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('LocationService.requestPermission: $e');
      return false;
    }
  }

  /// Returns the current device position with an 8-second timeout. If
  /// permissions or hardware fail, returns `null` instead of throwing so
  /// callers can show a single SnackBar without a try/catch dance.
  Future<Position?> getCurrent() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } on TimeoutException {
      // Often happens when GPS is cold — try last known instead.
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LocationService.getCurrent: $e');
      return null;
    }
  }

  /// Reverse-geocode via Yandex Geocoder. Returns the formatted address line
  /// or `null` when the key is missing / API fails.
  Future<String?> reverseGeocode(double lat, double lng) async {
    if (_geocoderKey.isEmpty) return null;
    try {
      final res = await _httpDio.get(
        'https://geocode-maps.yandex.ru/1.x/',
        queryParameters: {
          'apikey': _geocoderKey,
          'geocode': '$lng,$lat',
          'format': 'json',
          'lang': 'ru_RU',
          'kind': 'house',
          'results': 1,
        },
      );
      final data = res.data is String
          ? jsonDecode(res.data as String) as Map<String, dynamic>
          : res.data as Map<String, dynamic>;
      final feature = (data['response']?['GeoObjectCollection']
              ?['featureMember'] as List?)
          ?.firstWhere((_) => true, orElse: () => null);
      if (feature == null) return null;
      final geo = feature['GeoObject'] as Map<String, dynamic>?;
      final meta = geo?['metaDataProperty']?['GeocoderMetaData']
          as Map<String, dynamic>?;
      final formatted = meta?['text'] as String?;
      // Strip the country prefix Yandex includes for nicer UX.
      if (formatted != null && formatted.contains(', ')) {
        final parts = formatted.split(', ');
        if (parts.length > 1 && parts.first.length <= 12) {
          return parts.sublist(1).join(', ');
        }
      }
      return formatted;
    } catch (e) {
      if (kDebugMode) debugPrint('LocationService.reverseGeocode: $e');
      return null;
    }
  }
}
