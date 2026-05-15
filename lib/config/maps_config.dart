/// Maps-related configuration read from --dart-define at build time.
///
/// Three keys, three Yandex products (see backend/.env for full notes):
///
///   - JS_API_KEY   — Yandex JavaScript Maps API v3. Used if we embed the
///                    full JS map widget on web (not done today).
///   - MAPKIT_KEY   — Yandex MapKit mobile SDK. For future native builds.
///   - GEOCODER_KEY — NOT used on the client (server proxies geocoding).
///
/// Pass them at build time:
///
///   flutter build web --release \
///     --dart-define=YANDEX_JS_API_KEY=$YANDEX_JS_API_KEY \
///     --dart-define=YANDEX_MAPKIT_API_KEY=$YANDEX_MAPKIT_API_KEY
///
/// Empty string when not provided — every call site already gracefully
/// degrades (tiles work without a key on the free tier).
class MapsConfig {
  static const yandexJsApiKey =
      String.fromEnvironment('YANDEX_JS_API_KEY', defaultValue: '');
  static const yandexMapKitKey =
      String.fromEnvironment('YANDEX_MAPKIT_API_KEY', defaultValue: '');
}
