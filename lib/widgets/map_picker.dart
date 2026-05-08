import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// A map view that lets the user place / move a single pin and confirm a
/// `LatLng` via [onConfirm]. Uses `flutter_map` (OSM tiles) so we don't need
/// any platform-specific Yandex / Google keys here.
///
/// Tapping the map moves the pin. The "Confirm" button at the bottom returns
/// the picked coordinates.
class MapPicker extends StatefulWidget {
  final LatLng? initial;
  final ValueChanged<LatLng> onConfirm;
  final String? title;

  const MapPicker({
    super.key,
    this.initial,
    required this.onConfirm,
    this.title,
  });

  @override
  State<MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<MapPicker> {
  // Default — central Tashkent.
  static const _fallback = LatLng(41.2995, 69.2401);

  late LatLng _picked;
  final _mapCtrl = MapController();

  @override
  void initState() {
    super.initState();
    _picked = widget.initial ?? _fallback;
  }

  @override
  void dispose() {
    _mapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? t(context, 'map_pick_location'))),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _picked,
              initialZoom: 14,
              onTap: (_, latlng) {
                setState(() => _picked = latlng);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tezketkaz.app',
              ),
              MarkerLayer(markers: [
                Marker(
                  point: _picked,
                  width: 40, height: 40,
                  child: const Icon(
                    Icons.location_pin,
                    color: AppColors.primary,
                    size: 40,
                  ),
                ),
              ]),
            ],
          ),
          Positioned(
            left: 16, right: 16, bottom: 16,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      boxShadow: AppShadows.card,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.place_rounded,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_picked.latitude.toStringAsFixed(5)}, '
                            '${_picked.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        widget.onConfirm(_picked);
                        Navigator.of(context).maybePop(_picked);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(t(context, 'common.confirm')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
