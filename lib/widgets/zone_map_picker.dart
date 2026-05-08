import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

/// Shows a shop's delivery zones (drawn as semi-transparent polygons) and an
/// optional pin for the user's address. Used by the cart screen as a
/// fallback when `dispatchApi.estimate` returns `outOfZone` so the user can
/// visually verify whether their address is in range.
///
/// `zones` should be a list of zone payloads — each must have a `polygon`
/// list of `{lat, lng}` points.
class ZoneMapPicker extends StatelessWidget {
  final List<Map<String, dynamic>> zones;
  final LatLng? userLocation;
  final String? title;

  const ZoneMapPicker({
    super.key,
    required this.zones,
    this.userLocation,
    this.title,
  });

  static List<LatLng> _polygonOf(Map<String, dynamic> zone) {
    final raw = zone['polygon'] as List? ?? const [];
    return raw
        .map<LatLng?>((p) {
          if (p is Map) {
            final lat = (p['lat'] as num?)?.toDouble();
            final lng = (p['lng'] as num?)?.toDouble();
            if (lat == null || lng == null) return null;
            return LatLng(lat, lng);
          }
          return null;
        })
        .whereType<LatLng>()
        .toList();
  }

  LatLng _initialCenter() {
    if (userLocation != null) return userLocation!;
    for (final z in zones) {
      final pts = _polygonOf(z);
      if (pts.isNotEmpty) {
        final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) /
            pts.length;
        final lng = pts.map((p) => p.longitude).reduce((a, b) => a + b) /
            pts.length;
        return LatLng(lat, lng);
      }
    }
    return const LatLng(41.2995, 69.2401);
  }

  @override
  Widget build(BuildContext context) {
    final polygons = zones
        .map((z) {
          final pts = _polygonOf(z);
          if (pts.length < 3) return null;
          return Polygon(
            points: pts,
            color: AppColors.primary.withValues(alpha: 0.12),
            borderColor: AppColors.primary,
            borderStrokeWidth: 2,
          );
        })
        .whereType<Polygon>()
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(title ?? "Yetkazib berish hududi")),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: _initialCenter(),
          initialZoom: 12,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.tezketkaz.app',
          ),
          if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
          if (userLocation != null)
            MarkerLayer(markers: [
              Marker(
                point: userLocation!,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_pin,
                  color: AppColors.error,
                  size: 36,
                ),
              ),
            ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).maybePop(true),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: const Text("Manzil hudud ichida ekanini tasdiqlayman"),
          ),
        ),
      ),
    );
  }
}
