import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/money.dart';
import '../../providers/courier_state_provider.dart';
import '../../providers/order_provider.dart';
import '../../services/heatmap_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_shimmer.dart';

/// Phase 2 courier home — shift toggle, live map and incoming dispatch
/// offer banner. Wraps the legacy "available orders" list so the existing
/// flow keeps working when no `dispatch:offer` socket events are flowing.
class CourierHomeScreen extends StatefulWidget {
  const CourierHomeScreen({super.key});
  @override
  State<CourierHomeScreen> createState() => _CourierHomeScreenState();
}

class _CourierHomeScreenState extends State<CourierHomeScreen> {
  static const _courierId = 'courier_demo';
  static const _fallbackCenter = LatLng(41.2995, 69.2401); // Tashkent.

  final _mapCtrl = MapController();

  // Phase 8.4 — heatmap state. Cells are refreshed every 60s while the
  // courier is online. The toggle hides/shows the layer locally without
  // dropping the cached cells, so toggling back on is instant.
  List<HeatmapCell> _heatmapCells = const [];
  bool _heatmapVisible = false;
  Timer? _heatmapTimer;
  bool _heatmapBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CourierStateProvider>().bootstrap();
    });
  }

  @override
  void dispose() {
    _heatmapTimer?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshHeatmap() async {
    if (_heatmapBusy) return;
    final courier = context.read<CourierStateProvider>();
    if (!courier.isOnline) return;
    final loc = courier.lastLocation ?? _fallbackCenter;
    _heatmapBusy = true;
    try {
      final cells = await HeatmapApi.instance.me(
        lat: loc.latitude,
        lng: loc.longitude,
      );
      if (!mounted) return;
      setState(() => _heatmapCells = cells);
    } catch (_) {
      // Best-effort — keep the previously cached cells on failure.
    } finally {
      _heatmapBusy = false;
    }
  }

  void _toggleHeatmap() {
    setState(() => _heatmapVisible = !_heatmapVisible);
    if (_heatmapVisible) {
      _refreshHeatmap();
      _heatmapTimer ??= Timer.periodic(
        const Duration(seconds: 60),
        (_) => _refreshHeatmap(),
      );
    } else {
      _heatmapTimer?.cancel();
      _heatmapTimer = null;
    }
  }

  Future<void> _toggleShift() async {
    HapticFeedback.mediumImpact();
    final courier = context.read<CourierStateProvider>();
    if (courier.isOnline) {
      await courier.goOffline();
      // Stop polling heatmap once we're off-shift.
      _heatmapTimer?.cancel();
      _heatmapTimer = null;
      if (mounted) setState(() => _heatmapVisible = false);
    } else {
      await courier.goOnline();
    }
  }

  @override
  Widget build(BuildContext context) {
    final courier = context.watch<CourierStateProvider>();
    final orders = context.watch<OrderProvider>();
    final available = orders.availableForCourier();
    final active = orders.activeForCourier(_courierId);

    final pendingOffer = courier.pendingOffer;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // Phase 13.3.4 — pull-to-refresh re-syncs courier state (online flag,
      // shift stats) AND re-fetches available orders. Shows the platform
      // RefreshIndicator at the top of the CustomScrollView.
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            context.read<CourierStateProvider>().bootstrap(),
            context.read<OrderProvider>().loadCourierData(),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          // AppBar
          SliverAppBar(
            floating: true,
            backgroundColor: AppColors.surface,
            title: Row(
              children: [
                const Text('🛵', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bobur K.',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(courier.isOnline ? 'Onlayn' : 'Oflayn',
                        style: TextStyle(
                            fontSize: 12,
                            color: courier.isOnline
                                ? AppColors.success
                                : AppColors.textHint)),
                  ],
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: GestureDetector(
                  onTap: courier.busy ? null : _toggleShift,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: courier.isOnline
                          ? AppColors.primary
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            courier.isOnline ? Icons.wifi : Icons.wifi_off,
                            color: Colors.white,
                            size: 15),
                        const SizedBox(width: 5),
                        Text(courier.isOnline ? 'Я на смене' : 'Off duty',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Pending offer banner — top of scroll, always visible when active.
          if (pendingOffer != null)
            SliverToBoxAdapter(
              child: _PendingOfferBanner(
                offer: pendingOffer,
                secondsLeft: courier.offerSecondsLeft,
                onAccept: () async {
                  HapticFeedback.mediumImpact();
                  final ok = await courier.acceptOffer();
                  if (!ok || !mounted) return;
                  context.go('/courier/order/${pendingOffer.orderId}');
                },
                onDecline: () {
                  HapticFeedback.lightImpact();
                  courier.declineOffer();
                },
              ),
            ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Big shift toggle / stats card.
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ShiftCard(
                    state: courier,
                    onToggle: _toggleShift,
                  ),
                ),

                // Live map + heatmap toggle.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    height: 220,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          _CourierMap(
                            controller: _mapCtrl,
                            center: courier.lastLocation ?? _fallbackCenter,
                            offerHint: pendingOffer,
                            heatmapCells:
                                _heatmapVisible ? _heatmapCells : const [],
                          ),
                          if (courier.isOnline)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: _HeatmapToggle(
                                visible: _heatmapVisible,
                                onTap: _toggleHeatmap,
                              ),
                            ),
                          // Phase 13.2.8 — quick link to the full-screen
                          // heatmap with bottom-sheet directions handoff.
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Material(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              elevation: 4,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => context.push('/courier/heatmap'),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.map_outlined,
                                          size: 14,
                                          color: AppColors.textPrimary),
                                      SizedBox(width: 4),
                                      Text('Talab xaritasi',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary,
                                          )),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Active order banner.
                if (active != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: GestureDetector(
                      onTap: () => context.go('/courier/order/${active.id}'),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.courierLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.courier.withValues(alpha: 0.4),
                              width: 2),
                        ),
                        child: Row(
                          children: [
                            const Text('🛵',
                                style: TextStyle(fontSize: 28)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('Faol buyurtma',
                                      style: TextStyle(
                                          color: AppColors.courier,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                  Text(active.deliveryAddress,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: AppColors.courier),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Available orders header.
                if (courier.isOnline) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(
                      children: [
                        Text('Yangi buyurtmalar',
                            style: Theme.of(context).textTheme.headlineMedium),
                        if (available.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: AppColors.courier,
                                borderRadius: BorderRadius.circular(10)),
                            child: Text('${available.length}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (available.isEmpty && pendingOffer == null)
                    // Phase 13.3.4 — show shimmer skeleton while the first
                    // fetch is in flight; once it lands and we still have no
                    // orders, fall through to the "waiting" empty state.
                    orders.isLoading
                        ? const SizedBox(
                            height: 320,
                            child: LoadingShimmer(itemCount: 3, itemHeight: 96),
                          )
                        : _WaitingForOrders(hasActive: active != null)
                  else
                    ...available.map((o) => Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _OrderCard(
                            order: o,
                            isDisabled: active != null,
                            onAccept: () {
                              HapticFeedback.mediumImpact();
                              context
                                  .read<OrderProvider>()
                                  .courierAcceptOrder(o.id);
                              context.go('/courier/order/${o.id}');
                            },
                            onDecline: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Buyurtma rad etildi'),
                                      behavior: SnackBarBehavior.floating));
                            },
                          ),
                        )),
                ],

                if (!courier.isOnline)
                  _OfflineCard(
                      onGoOnline: courier.busy ? null : _toggleShift),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ── Shift card — toggle + stats ──────────────────────────────────────────────

class _ShiftCard extends StatelessWidget {
  final CourierStateProvider state;
  final VoidCallback onToggle;
  const _ShiftCard({required this.state, required this.onToggle});

  String _fmtMoney(double v) =>
      '${(v / 1000).toStringAsFixed(0)} ming so\'m';

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}s ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final shift = state.currentShift;
    final isOnline = state.isOnline;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOnline
              ? [AppColors.courier, const Color(0xFFE55A2B)]
              : [const Color(0xFF888888), const Color(0xFF666666)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _Stat(
                      emoji: '💰',
                      value: _fmtMoney(shift?.earnings ?? 0),
                      label: 'Smena daromadi')),
              Container(width: 1, height: 48, color: Colors.white24),
              Expanded(
                  child: _Stat(
                      emoji: '⏱',
                      value: shift == null
                          ? '0m'
                          : _fmtDuration(shift.duration),
                      label: 'Smena vaqti')),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: state.busy ? null : onToggle,
              icon: Icon(isOnline ? Icons.power_settings_new : Icons.play_arrow,
                  size: 18),
              label: Text(isOnline ? 'Off duty' : 'Я на смене',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor:
                    isOnline ? AppColors.courier : AppColors.primary,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(state.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String emoji, value, label;
  const _Stat({required this.emoji, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            textAlign: TextAlign.center),
      ]);
}

// ── Pending offer banner ─────────────────────────────────────────────────────

class _PendingOfferBanner extends StatelessWidget {
  final DispatchOffer offer;
  final int secondsLeft;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _PendingOfferBanner({
    required this.offer,
    required this.secondsLeft,
    required this.onAccept,
    required this.onDecline,
  });

  String _fmtMoney(double v) =>
      '${v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  @override
  Widget build(BuildContext context) {
    final progress = (secondsLeft / 60).clamp(0.0, 1.0);
    final locale = L10n.instance.locale.languageCode;
    // Phase 8.1 — when a batchId is present, the headline payout becomes the
    // total estimatedReward across the whole batch. Falls back to the
    // single-order `payout` for non-batch offers.
    final headlinePayout = offer.isBatch
        ? (offer.estimatedReward?.toDouble() ?? offer.payout)
        : offer.payout;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.courier,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.courierButton,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase 8.1 — prominent BATCH × N badge sits above the regular
          // header for stacked offers. Non-batch offers skip it.
          if (offer.isBatch) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                L10n.instance.t('dispatch.batch_badge').replaceAll(
                      '{count}',
                      '${offer.totalDeliveries ?? 2}',
                    ),
                style: const TextStyle(
                    color: AppColors.courier,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              const Text('📢',
                  style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Yangi taklif',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${secondsLeft}s',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (headlinePayout != null)
                _PendingChip('💰 ${_fmtMoney(headlinePayout.toDouble())}'),
              // Phase 8.2 — tip estimate chip. Only shown when the backend
              // attached a positive `tipEstimate` to the offer.
              if ((offer.tipEstimate ?? 0) > 0)
                _PendingChip(
                  L10n.instance.t('dispatch.tip_estimate_chip').replaceAll(
                        '{amount}',
                        Money(offer.tipEstimate!, 'UZS').format(locale),
                      ),
                ),
              if (offer.distanceKm != null)
                _PendingChip('📍 ${offer.distanceKm!.toStringAsFixed(1)} km'),
              if (offer.etaMinutes != null)
                _PendingChip('⏱ ~${offer.etaMinutes} min'),
              if (offer.shopName != null) _PendingChip(offer.shopName!),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('❌ Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: secondsLeft > 0 ? onAccept : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.courier,
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('✅ Accept',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  final String text;
  const _PendingChip(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );
}

// ── Live map ────────────────────────────────────────────────────────────────

class _CourierMap extends StatelessWidget {
  final MapController controller;
  final LatLng center;
  // Reserved for future use (e.g. drop a pin for the offered shop). Already
  // forwarded by the parent screen, just not yet visualised.
  final DispatchOffer? offerHint;

  /// Phase 8.4 — heatmap cells from `HeatmapApi.me`. When empty no heatmap
  /// layer is drawn, so callers can pass `[]` to hide the layer.
  final List<HeatmapCell> heatmapCells;

  const _CourierMap({
    required this.controller,
    required this.center,
    this.offerHint,
    this.heatmapCells = const [],
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 13,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.tezketkaz.app',
        ),
        if (heatmapCells.isNotEmpty)
          CircleLayer(
            circles: [
              for (final c in heatmapCells)
                CircleMarker(
                  point: LatLng(c.lat, c.lng),
                  // 100m + up to 400m extra by intensity.
                  radius: 100 + 400 * c.intensity,
                  useRadiusInMeter: true,
                  color: const Color(0xFFFF3B30)
                      .withValues(alpha: 0.2 + 0.5 * c.intensity),
                  borderStrokeWidth: 0,
                ),
            ],
          ),
        MarkerLayer(markers: [
          Marker(
            point: center,
            width: 40,
            height: 40,
            child: const Icon(Icons.delivery_dining,
                color: AppColors.courier, size: 36),
          ),
        ]),
      ],
    );
  }
}

class _HeatmapToggle extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;
  const _HeatmapToggle({required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.instance
                    .t(visible ? 'heatmap.toggle_hide' : 'heatmap.toggle_show'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty / offline states ──────────────────────────────────────────────────

class _WaitingForOrders extends StatelessWidget {
  final bool hasActive;
  const _WaitingForOrders({required this.hasActive});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border)),
          child: Column(children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.courier),
              ),
            ),
            const SizedBox(height: 14),
            Text(
                hasActive
                    ? 'Joriy buyurtmani yetkazing'
                    : 'Buyurtmalar kutilmoqda...',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            const Text("Yangi taklif kelganda sizga xabar beramiz",
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                textAlign: TextAlign.center),
          ]),
        ),
      );
}

class _OfflineCard extends StatelessWidget {
  final VoidCallback? onGoOnline;
  const _OfflineCard({required this.onGoOnline});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border)),
          child: Column(children: [
            const Text('💤', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text('Siz oflayn rejimdasiz',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text("Buyurtma olish uchun smenani boshlang",
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onGoOnline,
              icon: const Icon(Icons.wifi),
              label: const Text("Я на смене"),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.courier),
            ),
          ]),
        ),
      );
}

// ── Legacy order card (kept for parity with Phase 1 list) ───────────────────

class _OrderCard extends StatelessWidget {
  final AppOrder order;
  final bool isDisabled;
  final VoidCallback onAccept, onDecline;
  const _OrderCard(
      {required this.order,
      required this.isDisabled,
      required this.onAccept,
      required this.onDecline});

  String _fmtR(double v) =>
      '${v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: isDisabled ? 0.5 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(
            children: [
              // Tags row.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                    color: AppColors.bg,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(17))),
                child: Row(
                  children: [
                    _Tag('💰 ${_fmtR(order.reward)}', AppColors.success),
                    const SizedBox(width: 6),
                    _Tag(
                        '📍 ${order.deliveryFee == 0 ? '~1.5' : '~2'} km',
                        AppColors.info),
                    const SizedBox(width: 6),
                    _Tag('⏱ ~18 min', AppColors.warning),
                    const Spacer(),
                    _Tag('💳 ${order.isPaid ? 'To\'langan' : 'Naqd'}',
                        AppColors.textSecondary),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RouteRow(
                        icon: Icons.store_outlined,
                        color: AppColors.primary,
                        address: order.shopName,
                        sub: order.shopAddress),
                    Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Container(
                            height: 18, width: 2, color: AppColors.border)),
                    _RouteRow(
                        icon: Icons.home_outlined,
                        color: AppColors.courier,
                        address: order.deliveryAddress),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    ...order.items.map((i) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(children: [
                            const Icon(Icons.circle,
                                size: 5, color: AppColors.textHint),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(i.product.name,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary))),
                            Text('× ${i.quantity}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        )),
                    const SizedBox(height: 14),
                    if (!isDisabled)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onDecline,
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 46),
                                  foregroundColor: AppColors.textSecondary,
                                  side: const BorderSide(
                                      color: AppColors.border)),
                              child: const Text('O\'tkazib yuborish'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: onAccept,
                              style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 46),
                                  backgroundColor: AppColors.courier),
                              child: const Text('Qabul qilish'),
                            ),
                          ),
                        ],
                      ),
                    if (isDisabled)
                      const Center(
                          child: Text('Avval joriy buyurtmani tugating',
                              style: TextStyle(
                                  color: AppColors.textHint, fontSize: 13))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String address;
  final String? sub;
  const _RouteRow(
      {required this.icon,
      required this.color,
      required this.address,
      this.sub});
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 14)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(address,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 14)),
                if (sub != null)
                  Text(sub!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
              ])),
        ],
      );
}
