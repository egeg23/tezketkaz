import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map_tile_layer.dart';

/// Tap-to-pick address screen — UberEats-style:
///   - flutter_map (OSM tiles) with a fixed center pin
///   - panning the map reverse-geocodes via free Nominatim
///   - bottom card shows the current text + Save CTA
///
/// Returns `(LatLng, String address)` via Navigator.pop.
class AddressPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const AddressPickerScreen({super.key, this.initial});

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  static const _tashkentCenter = LatLng(41.3617, 69.2877);
  late final MapController _mapCtl = MapController();
  late LatLng _center = widget.initial ?? _tashkentCenter;
  String _addressText = '...';
  bool _loading = false;
  Timer? _debounce;
  final _dio = Dio();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reverseGeocode(_center));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dio.close(force: true);
    super.dispose();
  }

  void _onMapMoved(MapCamera cam) {
    _center = cam.center;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _reverseGeocode(_center));
  }

  Future<void> _reverseGeocode(LatLng p) async {
    setState(() => _loading = true);
    try {
      final res = await _dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': p.latitude.toStringAsFixed(6),
          'lon': p.longitude.toStringAsFixed(6),
          'format': 'json',
          'accept-language': 'uz,ru,en',
          'zoom': 18,
        },
        options: Options(headers: {'User-Agent': 'uz.tezketkaz.app/1.0'}),
      );
      final txt = (res.data['display_name'] as String?) ?? '';
      if (!mounted) return;
      setState(() {
        _addressText = txt.isEmpty
            ? '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'
            : txt;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addressText = '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
        _loading = false;
      });
    }
  }

  void _confirm() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop({
      'lat': _center.latitude,
      'lng': _center.longitude,
      'address': _addressText,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manzil tanlash')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtl,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 16,
              onMapEvent: (event) {
                if (event.source == MapEventSource.mapController) return;
                _onMapMoved(event.camera);
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              tezketkazTiles(),
            ],
          ),
          // Center pin
          const Center(
            child: IgnorePointer(child: _CenterPin()),
          ),

          // Bottom address card + CTA
          Positioned(
            left: 16, right: 16, bottom: 16,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadii.xl),
                  boxShadow: AppShadows.elevated,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 22),
                        const SizedBox(width: 8),
                        const Text('Yetkazib berish manzili',
                            style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary, letterSpacing: 0.3,
                            )),
                        const Spacer(),
                        if (_loading)
                          const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _addressText,
                      style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary, height: 1.3,
                      ),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _confirm,
                        child: const Text('Bu manzilni tanlash'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterPin extends StatelessWidget {
  const _CenterPin();
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.45),
            blurRadius: 14, spreadRadius: 2,
          )],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.home_rounded, color: AppColors.neutralInk, size: 20),
      ),
      const SizedBox(height: 2),
      Container(width: 2, height: 18, color: AppColors.neutralInk),
    ],
  );
}
