import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

/// Shared TileLayer factory used everywhere we render a map.
///
/// Why centralise: when we want to switch providers (Yandex → 2GIS →
/// CartoDB → self-hosted), there's one place. Also lets us tweak request
/// headers, max-zoom, retina-density per-platform without touching every
/// screen that renders a map.
///
/// Yandex serves tiles from `core-renderer-tiles.maps.yandex.net`. The map
/// style is dark to match our brand. Anti-bot enforces a sane User-Agent —
/// flutter_map defaults are fine on mobile; on web the browser supplies it
/// automatically. We pass through the package id so Yandex's traffic logs
/// can attribute requests.
TileLayer tezketkazTiles({TileLayerStyle style = TileLayerStyle.dark}) {
  // `lang` matches our app locale; for now pin to ru_RU. Hardcoded to keep
  // dependencies minimal — when we ship multi-locale, plumb it through.
  // The {x},{y},{z} placeholders are filled by flutter_map.
  // `scale=2` requests @2x tiles for retina screens; flutter_map will
  // request 256px-virtual but Yandex returns 512px (and we get crisp text).
  final layer = style == TileLayerStyle.dark
      ? 'map'   // Yandex doesn't ship a true dark style on the free tier;
                // we apply our own dim overlay above the map widget instead.
      : 'map';
  return TileLayer(
    urlTemplate: 'https://core-renderer-tiles.maps.yandex.net/tiles?'
        'l=$layer&v=23.04.30-0&x={x}&y={y}&z={z}&scale=2&lang=ru_RU',
    userAgentPackageName: 'uz.tezketkaz.app',
    maxNativeZoom: 19,
    maxZoom: 19,
    additionalOptions: const {
      // Yandex sometimes 403s requests from anonymous referers — adding our
      // origin helps when we deploy behind a real domain. Harmless on dev.
      'origin': 'https://tezketkaz.uz',
    },
    // Fall back gracefully when the tile load fails (rate-limit / region):
    // flutter_map renders an empty cell with the layer's background colour.
    errorTileCallback: (tile, error, stack) {
      if (kDebugMode) {
        debugPrint('tile load failed @ ${tile.coordinates}: $error');
      }
    },
  );
}

enum TileLayerStyle { dark, light }
