import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../providers/courier_state_provider.dart';
import '../../services/heatmap_api.dart';
import '../../theme/app_theme.dart';

/// Phase 13.2.8 — full-screen courier demand heatmap.
///
/// Renders the same `GET /api/couriers/heatmap` cells as the home-screen
/// mini-map, but fills the device viewport and refreshes every 5 minutes.
/// Tapping a hot cell opens a bottom sheet with an "Open directions" CTA
/// that launches Yandex Maps with a `routeto=` link via `url_launcher`.
class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  static const _fallbackCenter = LatLng(41.2995, 69.2401); // Tashkent.
  static const _refreshInterval = Duration(minutes: 5);

  final _mapCtrl = MapController();
  List<HeatmapCell> _cells = const [];
  bool _loading = false;
  bool _refreshError = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _timer = Timer.periodic(_refreshInterval, (_) => _refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  LatLng get _center =>
      context.read<CourierStateProvider>().lastLocation ?? _fallbackCenter;

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _refreshError = false;
    });
    final loc = _center;
    try {
      final cells = await HeatmapApi.instance.me(
        lat: loc.latitude,
        lng: loc.longitude,
      );
      if (!mounted) return;
      setState(() {
        _cells = cells;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshError = true;
      });
    }
  }

  Future<void> _openDirections(HeatmapCell cell) async {
    final yandex = Uri.parse(
      'yandexmaps://maps.yandex.com/?rtext=~${cell.lat},${cell.lng}&rtt=auto',
    );
    final web = Uri.parse(
      'https://yandex.com/maps/?rtext=~${cell.lat},${cell.lng}&rtt=auto',
    );
    try {
      if (await canLaunchUrl(yandex)) {
        await launchUrl(yandex);
      } else {
        await launchUrl(web, mode: LaunchMode.externalApplication);
      }
    } catch (_) {/* swallow — best-effort handoff */}
  }

  void _showCellSheet(HeatmapCell cell) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _DemandBadge(intensity: cell.intensity),
            const SizedBox(height: 14),
            Text(
              t(context, 'heatmap.orders_count')
                  .replaceAll('{count}', '${cell.count}'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openDirections(cell);
                },
                icon: const Icon(Icons.directions_rounded,
                    size: 18, color: AppColors.bg),
                label: Text(t(context, 'heatmap.open_directions')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(t(context, 'heatmap.screen_title')),
        actions: [
          IconButton(
            tooltip: t(context, 'heatmap.refresh'),
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 12,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                  userAgentPackageName: 'uz.tezketkaz.app',
                  maxZoom: 19,
                ),
                CircleLayer(
                  circles: [
                    for (final c in _cells)
                      CircleMarker(
                        point: LatLng(c.lat, c.lng),
                        color: _intensityColor(c.intensity)
                            .withValues(alpha: 0.35),
                        borderColor: _intensityColor(c.intensity),
                        borderStrokeWidth: 1.5,
                        useRadiusInMeter: true,
                        radius: 250 + (c.intensity * 350),
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final c in _cells)
                      Marker(
                        point: LatLng(c.lat, c.lng),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () => _showCellSheet(c),
                          child: const SizedBox.expand(),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Empty state overlay
          if (!_loading && _cells.isEmpty && !_refreshError)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xCC0F0F16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t(context, 'heatmap.empty_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t(context, 'heatmap.empty_subtitle'),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_refreshError)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error),
                ),
                child: Text(
                  t(context, 'heatmap.refresh_failed'),
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          // Legend
          Positioned(
            left: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xCC0F0F16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LegendDot(
                    color: AppColors.error,
                    label: t(context, 'heatmap.legend_high'),
                  ),
                  const SizedBox(height: 4),
                  _LegendDot(
                    color: AppColors.warning,
                    label: t(context, 'heatmap.legend_medium'),
                  ),
                  const SizedBox(height: 4),
                  _LegendDot(
                    color: AppColors.success,
                    label: t(context, 'heatmap.legend_low'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _intensityColor(double intensity) {
    if (intensity >= 0.66) return AppColors.error;
    if (intensity >= 0.33) return AppColors.warning;
    return AppColors.success;
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.7),
              shape: BoxShape.circle,
              border: Border.all(color: color),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _DemandBadge extends StatelessWidget {
  final double intensity;
  const _DemandBadge({required this.intensity});

  @override
  Widget build(BuildContext context) {
    final (String key, Color color) = intensity >= 0.66
        ? ('heatmap.high_demand_card', AppColors.error)
        : intensity >= 0.33
            ? ('heatmap.medium_demand_card', AppColors.warning)
            : ('heatmap.low_demand_card', AppColors.success);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        t(context, key),
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
