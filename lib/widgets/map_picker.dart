import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../l10n/l10n.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

/// A map view that lets the user place / move a single pin and confirm a
/// `LatLng` via [onConfirm]. Uses `flutter_map` (OSM tiles) so we don't need
/// any platform-specific Yandex / Google keys here.
///
/// Tapping the map moves the pin. The "Confirm" button at the bottom returns
/// the picked coordinates. Phase 6 added a "Use current location" CTA + an
/// optional [addressController] which gets filled with the reverse-geocoded
/// address line when the user taps the GPS button.
class MapPicker extends StatefulWidget {
  final LatLng? initial;
  final ValueChanged<LatLng> onConfirm;
  final String? title;

  /// When supplied, "Use current location" auto-fills this controller with
  /// the reverse-geocoded address line. The pickers in
  /// `address_book_screen.dart` thread their address TextField through here.
  final TextEditingController? addressController;

  const MapPicker({
    super.key,
    this.initial,
    required this.onConfirm,
    this.title,
    this.addressController,
  });

  @override
  State<MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<MapPicker> {
  // Default — central Tashkent.
  static const _fallback = LatLng(41.2995, 69.2401);

  late LatLng _picked;
  final _mapCtrl = MapController();
  bool _gpsLoading = false;

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

  Future<void> _useCurrentLocation() async {
    if (_gpsLoading) return;
    setState(() => _gpsLoading = true);
    try {
      final loc = LocationService.instance;
      final granted = await loc.requestPermission();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(context, 'location.permission_denied')),
        ));
        return;
      }
      final pos = await loc.getCurrent();
      if (!mounted) return;
      if (pos == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(context, 'location.permission_denied')),
        ));
        return;
      }
      final next = LatLng(pos.latitude, pos.longitude);
      setState(() => _picked = next);
      _mapCtrl.move(next, 16);
      // Reverse-geocode in the background — failure here just leaves the
      // address field as-is, never blocks the pick.
      final line =
          await loc.reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      if (line != null && widget.addressController != null) {
        widget.addressController!.text = line;
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
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
            right: 16,
            top: 16,
            child: SafeArea(
              child: FloatingActionButton.small(
                heroTag: 'map_picker_gps',
                onPressed: _gpsLoading ? null : _useCurrentLocation,
                tooltip: t(context, 'location.current'),
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.primary,
                child: _gpsLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
              ),
            ),
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _gpsLoading ? null : _useCurrentLocation,
                          icon: _gpsLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location_rounded),
                          label: Text(t(context, 'location.current')),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
