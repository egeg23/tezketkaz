// Phase 13.2.8 — full-screen courier demand heatmap.
//
// Pulls `GET /api/couriers/heatmap` (server already aggregates last-hour
// unassigned orders into a 1km grid) and overlays the cells as colour-coded
// circles on flutter_map. Tap a hot cell → bottom sheet with a "Open
// directions" CTA that hands off to Yandex Maps via url_launcher.
//
// Auto-refreshes every 5 minutes; the user can also trigger a refresh
// manually via the app-bar action.

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

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  // Tashkent centre — used when the courier hasn't shared a GPS fix yet so we
  // still render something useful (matches CourierHomeScreen's fallback).
  static const _fallbackCenter = LatLng(41.2995, 69.2401);
  // Server defaults to 60-minute window, 10km radius. We poll every 5 minutes
  // to match the "next hour" demand horizon without hammering the API.
  static const _refreshInterval = Duration(minutes: 5);

  final _mapCtrl = MapController();
  List<HeatmapCell> _cells = const [];
  Timer? _timer;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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

  LatLng get _center {
    final loc = context.read<CourierStateProvider>().lastLocation;
    return loc ?? _fallbackCenter;
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final centre = _center;
      final cells = await HeatmapApi.instance.me(
        lat: centre.latitude,
        lng: centre.longitude,
      );
      if (!mounted) return;
      setState(() {
        _cells = cells;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = L10n.instance.t('heatmap.refresh_failed');
      });
    }
  }

  // Bucket intensity into 3 bands so the legend + bottom-sheet copy can speak
  // in plain terms (high/medium/low) instead of leaking the 0..1 float.
  _Band _bandFor(double intensity) {
    if (intensity >= 0.66) return _Band.high;
    if (intensity >= 0.33) return _Band.medium;
    return _Band.low;
  }

  Color _colorForBand(_Band b) {
    switch (b) {
      case _Band.high:
        return const Color(0xFFFF3B30); // red
      case _Band.medium:
        return const Color(0xFFFF9F1C); // amber
      case _Band.low:
        return const Color(0xFF14A44D); // green
    }
  }

  String _labelForBand(_Band b) {
    final l = L10n.instance;
    switch (b) {
      case _Band.high:
        return l.t('heatmap.high_demand_card');
      case _Band.medium:
        return l.t('heatmap.medium_demand_card');
      case _Band.low:
        return l.t('heatmap.low_demand_card');
    }
  }

  Future<void> _openDirections(HeatmapCell cell) async {
    // Yandex Maps universal "build a route here" URL. Works on the mobile
    // apps (deep link) and falls back to maps.yandex.com on the web.
    final uri = Uri.parse(
      'https://yandex.com/maps/?rtext=~${cell.lat},${cell.lng}&rtt=auto',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _onCellTap(HeatmapCell cell) {
    final band = _bandFor(cell.intensity);
    final color = _colorForBand(band);
    final label = _labelForBand(band);
    final l = L10n.instance;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  l.t('heatmap.orders_count').replaceAll(
                        '{count}',
                        '${cell.count}',
                      ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _openDirections(cell);
                  },
                  icon: const Icon(Icons.directions),
                  label: Text(l.t('heatmap.open_directions')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.courier,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.instance;
    final centre = _center;
    // Highest-intensity cell drives the persistent header callout so the
    // courier sees an actionable summary above the fold.
    HeatmapCell? topCell;
    for (final c in _cells) {
      if (topCell == null || c.intensity > topCell.intensity) topCell = c;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(l.t('heatmap.screen_title')),
        actions: [
          IconButton(
            tooltip: l.t('heatmap.refresh'),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: centre,
              initialZoom: 12,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tezketkaz.app',
              ),
              if (_cells.isNotEmpty)
                CircleLayer(
                  circles: [
                    for (final c in _cells)
                      CircleMarker(
                        point: LatLng(c.lat, c.lng),
                        // 200m base + up to 600m by intensity so the visual
                        // weight tracks demand intensity faithfully.
                        radius: 200 + 600 * c.intensity,
                        useRadiusInMeter: true,
                        color: _colorForBand(_bandFor(c.intensity))
                            .withValues(alpha: 0.25 + 0.45 * c.intensity),
                        borderStrokeWidth: 1,
                        borderColor: _colorForBand(_bandFor(c.intensity))
                            .withValues(alpha: 0.6),
                      ),
                  ],
                ),
              // Transparent tap-target markers — flutter_map's CircleMarker
              // doesn't capture gestures, so we overlay invisible Markers on
              // each cell for the bottom-sheet trigger.
              if (_cells.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final c in _cells)
                      Marker(
                        point: LatLng(c.lat, c.lng),
                        width: 60,
                        height: 60,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _onCellTap(c),
                          child: const SizedBox.expand(),
                        ),
                      ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: centre,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.delivery_dining,
                      color: AppColors.courier,
                      size: 32,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Persistent legend (top-right).
          Positioned(
            top: 12,
            right: 12,
            child: _Legend(colorFor: _colorForBand),
          ),

          // Bottom sheet — either the top-demand callout or the empty state.
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: _BottomCard(
              loading: _loading,
              error: _error,
              cell: topCell,
              bandFor: _bandFor,
              colorFor: _colorForBand,
              labelFor: _labelForBand,
              onTap: topCell == null ? null : () => _onCellTap(topCell!),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Band { high, medium, low }

class _Legend extends StatelessWidget {
  final Color Function(_Band) colorFor;
  const _Legend({required this.colorFor});

  @override
  Widget build(BuildContext context) {
    final l = L10n.instance;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendRow(color: colorFor(_Band.high), label: l.t('heatmap.legend_high')),
            const SizedBox(height: 4),
            _LegendRow(color: colorFor(_Band.medium), label: l.t('heatmap.legend_medium')),
            const SizedBox(height: 4),
            _LegendRow(color: colorFor(_Band.low), label: l.t('heatmap.legend_low')),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _BottomCard extends StatelessWidget {
  final bool loading;
  final String? error;
  final HeatmapCell? cell;
  final _Band Function(double) bandFor;
  final Color Function(_Band) colorFor;
  final String Function(_Band) labelFor;
  final VoidCallback? onTap;

  const _BottomCard({
    required this.loading,
    required this.error,
    required this.cell,
    required this.bandFor,
    required this.colorFor,
    required this.labelFor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.instance;
    if (loading && cell == null) {
      return _wrap(
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l.t('heatmap.loading'),
                style: const TextStyle(color: AppColors.textPrimary)),
          ],
        ),
      );
    }
    if (cell == null) {
      return _wrap(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error ?? l.t('heatmap.empty_title'),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.t('heatmap.empty_subtitle'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    final band = bandFor(cell!.intensity);
    final color = colorFor(band);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 5,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.local_fire_department, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labelFor(band),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.t('heatmap.orders_count').replaceAll(
                            '{count}',
                            '${cell!.count}',
                          ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wrap({required Widget child}) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 5,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}
