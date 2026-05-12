import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/api_config.dart';
import '../../l10n/l10n.dart';
import '../../models/money.dart';
import '../../providers/order_provider.dart';
import '../../services/api_client.dart';
import '../../services/review_prompt_service.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';

class TrackingScreen extends StatefulWidget {
  final String orderId;
  const TrackingScreen({super.key, required this.orderId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  // Static demo positions — Yunusobod, Tashkent.
  static final _shopPoint = LatLng(41.3617, 69.2877);
  static final _customerPoint = LatLng(41.3700, 69.2890);

  LatLng? _courierPoint;
  bool _confirming = false;
  late final void Function(dynamic) _locationHandler;

  @override
  void initState() {
    super.initState();
    final socket = SocketService.instance;
    socket.subscribeToOrder(widget.orderId);
    _locationHandler = (data) {
      if (!mounted) return;
      if (data is Map) {
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          setState(() => _courierPoint = LatLng(lat, lng));
        }
      }
    };
    socket.on('courier:location', _locationHandler);
  }

  @override
  void dispose() {
    SocketService.instance.off('courier:location', _locationHandler);
    SocketService.instance.unsubscribeFromOrder(widget.orderId);
    super.dispose();
  }

  // Phase 13.3.3 — open the PDF receipt in the system browser. The browser
  // (or PDF viewer) handles the actual download / share flow; we only need
  // to compose a URL with the user's access token attached as a one-shot
  // query param so the route can authenticate cross-app.
  Future<void> _downloadReceipt() async {
    final token = await ApiClient.instance.getAccessToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.instance.t('receipt.error'))),
      );
      return;
    }
    final base = ApiConfig.baseUrl;
    // Receipt download — we open in the system browser which will save / display
    // the PDF. The Authorization header normally comes from the API client, so
    // for the browser hand-off we pass the token via a temporary `?token=`
    // hint (the route accepts both). The user can then "Save as" the file.
    final uri = Uri.parse('$base/api/orders/${widget.orderId}/receipt')
        .replace(queryParameters: {'token': token});
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.instance.t('receipt.error'))),
      );
    }
  }

  Future<void> _confirmReceived() async {
    setState(() => _confirming = true);
    try {
      await context.read<OrderProvider>().buyerConfirm(widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'tracking.confirm_received_snack'))));
      // Phase 12 — bump the per-user "completed orders" counter; once it hits
      // the threshold (5) we surface the native review sheet exactly once.
      // Fire-and-forget — the rating-dialog snackbar above is the primary UX
      // and we don't want to await the platform channel.
      // Delay one frame so the snackbar lands first and the review sheet
      // appears on top of the now-confirmed screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ReviewPromptService.recordOrderCompleted();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t(context, 'tracking.error_prefix')}: $e')));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = context.watch<OrderProvider>().findById(widget.orderId);
    if (order == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(t(context, 'tracking.order_not_found'))),
      );
    }

    final isHandedOver = order.status == AppOrderStatus.delivered;
    final isFullyDone = order.status == AppOrderStatus.confirmedByBuyer;
    final isCancelled = order.status == AppOrderStatus.cancelled;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go('/buyer'),
        ),
        title: Text('Buyurtma ${order.orderNumber ?? '#${order.id.substring(order.id.length - 4)}'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            tooltip: t(context, 'tracking.chat_tooltip'),
            onPressed: () => context.push('/order/${order.id}/chat'),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Map ─────────────────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: _courierPoint ?? _shopPoint,
                    initialZoom: 14,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      // 2GIS-style raster tiles via OpenStreetMap fallback.
                      // Replace with 2GIS tile server + apiKey for production.
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'uz.tezketkaz.app',
                      maxZoom: 19,
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _shopPoint,
                          width: 36, height: 36,
                          child: _Pin(color: AppColors.primary, icon: '🏪'),
                        ),
                        Marker(
                          point: _customerPoint,
                          width: 36, height: 36,
                          child: _Pin(color: Colors.deepPurple, icon: '🏠'),
                        ),
                        if (_courierPoint != null)
                          Marker(
                            point: _courierPoint!,
                            width: 44, height: 44,
                            child: _PulsingPin(),
                          ),
                      ],
                    ),
                  ],
                ),
                if (!isFullyDone && !isCancelled)
                  Positioned(
                    top: 12, left: 16, right: 16,
                    child: Center(child: _EtaPill(status: order.status, hasCourier: _courierPoint != null)),
                  ),
              ],
            ),
          ),

          // ── Status sheet ────────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Color(0x12000000), blurRadius: 20, offset: Offset(0, -4))],
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                    )),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Text(order.statusEmoji, style: const TextStyle(fontSize: 36)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(order.statusLabel,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              Text(order.shopName,
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            ],
                          ),
                        ),
                        if (!isFullyDone && !isCancelled && !isHandedOver)
                          const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                          ),
                      ],
                    ),

                    if (!isCancelled) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: order.buyerProgress,
                          backgroundColor: AppColors.border,
                          color: isFullyDone ? AppColors.success : AppColors.primary,
                          minHeight: 8,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    _Timeline(currentStatus: order.status),

                    if (order.courierName != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.courierLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.courier.withValues(alpha: 0.2),
                              child: Text(
                                order.courierName![0],
                                style: const TextStyle(color: AppColors.courier, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t(context, 'tracking.courier_label'),
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                  Text(order.courierName!,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (order.orderNumber != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🏷️', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Text('${t(context, 'tracking.order_number_prefix')} ',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            Text(order.orderNumber!,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800, fontSize: 15,
                                )),
                          ],
                        ),
                      ),
                    ],

                    // Phase 13.2.5 — delivery-photo proof. Shows once the
                    // courier has marked the order delivered (status =
                    // delivered) or after the buyer confirms (confirmedByBuyer).
                    // Tap opens a full-screen viewer.
                    if ((isHandedOver || isFullyDone) &&
                        order.deliveryPhotoUrl != null &&
                        order.deliveryPhotoUrl!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _DeliveryPhotoCard(
                        url: order.deliveryPhotoUrl!,
                        takenAt: order.deliveryPhotoAt,
                      ),
                    ],

                    // ── Buyer confirm button ──
                    if (isHandedOver) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _confirming ? null : _confirmReceived,
                          icon: _confirming
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.check_circle_outline),
                          label: Text(t(context, 'tracking.confirm_cta'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _TipCard(orderId: order.id, subtotal: order.subtotal),
                    ],

                    if (isFullyDone) ...[
                      const SizedBox(height: 12),
                      _TipCard(orderId: order.id, subtotal: order.subtotal),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => context.go('/buyer'),
                        icon: const Icon(Icons.star_outline),
                        label: Text(t(context, 'tracking.rate_and_close')),
                      ),
                    ],

                    // Phase 13.3.3 — receipt download is available the moment
                    // the courier hands the order over (status = delivered)
                    // and stays available after buyer confirmation. Opens in
                    // the system browser; the PDF route returns the file
                    // with a Content-Disposition: attachment header.
                    if (isHandedOver || isFullyDone) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _downloadReceipt,
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: Text(L10n.instance.t('receipt.download')),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      ),
                    ],
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

class _EtaPill extends StatelessWidget {
  final AppOrderStatus status;
  final bool hasCourier;
  const _EtaPill({required this.status, required this.hasCourier});

  String _text() {
    switch (status) {
      case AppOrderStatus.pending: return 'Tasdiqlanmoqda...';
      case AppOrderStatus.collecting: return 'Yig\'ilmoqda · ~12 daqiqa';
      case AppOrderStatus.readyForPickup: return 'Kuryer kutilmoqda';
      case AppOrderStatus.courierAssigned: return 'Kuryer do\'kon yo\'lida';
      case AppOrderStatus.pickedUp:
      case AppOrderStatus.inDelivery: return hasCourier ? 'Yo\'lda · ~6 daqiqa' : 'Yo\'lda';
      case AppOrderStatus.arrivedAtCustomer: return 'Kuryer eshik oldida';
      case AppOrderStatus.delivered: return 'Topshirildi · tasdiqlang';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(50),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.timer_outlined, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(_text(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    ),
  );
}

class _Pin extends StatelessWidget {
  final Color color;
  final String icon;
  const _Pin({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color, shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10)],
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: Center(child: Text(icon, style: const TextStyle(fontSize: 16))),
  );
}

class _PulsingPin extends StatefulWidget {
  @override
  State<_PulsingPin> createState() => _PulsingPinState();
}

class _PulsingPinState extends State<_PulsingPin> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: Tween(begin: 0.9, end: 1.15).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.courier, shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: AppColors.courier.withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 4)],
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Center(child: Text('🛵', style: TextStyle(fontSize: 22))),
    ),
  );
}

class _Timeline extends StatelessWidget {
  final AppOrderStatus currentStatus;
  const _Timeline({required this.currentStatus});

  static const _order = [
    AppOrderStatus.pending,
    AppOrderStatus.collecting,
    AppOrderStatus.readyForPickup,
    AppOrderStatus.courierAssigned,
    AppOrderStatus.pickedUp,
    AppOrderStatus.arrivedAtCustomer,
    AppOrderStatus.delivered,
    AppOrderStatus.confirmedByBuyer,
  ];

  @override
  Widget build(BuildContext context) {
    final steps = [
      (AppOrderStatus.pending, '🔔', 'Buyurtma qabul qilindi'),
      (AppOrderStatus.collecting, '📦', "Do'kon yig'moqda"),
      (AppOrderStatus.readyForPickup, '🏪', 'Tayyor, kuryer yo\'lda'),
      (AppOrderStatus.pickedUp, '🛵', 'Kuryer olib ketdi'),
      (AppOrderStatus.arrivedAtCustomer, '🚪', 'Eshik oldida'),
      (AppOrderStatus.delivered, '✅', 'Topshirildi'),
      (AppOrderStatus.confirmedByBuyer, '🎉', "Qabul qilindi"),
    ];

    int idxOf(AppOrderStatus s) => _order.indexOf(s);
    final currentIdx = idxOf(currentStatus);

    return Column(
      children: steps.asMap().entries.map((e) {
        final i = e.key;
        final (s, emoji, label) = e.value;
        final stepIdx = idxOf(s);
        final isDone = currentIdx > stepIdx;
        final isCurrent = stepIdx == currentIdx;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: isDone ? AppColors.primary
                      : isCurrent ? AppColors.primaryLight
                      : AppColors.bg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDone || isCurrent ? AppColors.primary : AppColors.border,
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: isDone
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : Text(emoji, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                if (i < steps.length - 1)
                  Container(width: 2, height: 18,
                    color: isDone ? AppColors.primary : AppColors.border),
              ],
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 14),
              child: Text(label,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    color: isCurrent ? AppColors.primary
                      : isDone ? AppColors.textPrimary
                      : AppColors.textHint,
                    fontSize: 13,
                  )),
            ),
          ],
        );
      }).toList(),
    );
  }
}

/// Phase 6 — courier tip CTA shown after the order is `delivered`.
///
/// Four chips (5 / 10 / 15 / Custom) feed a live total and post to
/// `POST /api/orders/:id/tip`. Once a tip lands the button disables so a
/// nervous tap can't double-charge.
class _TipCard extends StatefulWidget {
  final String orderId;
  final double subtotal;
  const _TipCard({required this.orderId, required this.subtotal});

  @override
  State<_TipCard> createState() => _TipCardState();
}

class _TipCardState extends State<_TipCard> {
  static const _percentChoices = [5, 10, 15];
  int? _selectedPercent = 10;
  bool _custom = false;
  final _customCtrl = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  double get _amount {
    if (_custom) {
      return double.tryParse(_customCtrl.text.trim().replaceAll(' ', '')) ??
          0;
    }
    if (_selectedPercent == null) return 0;
    return widget.subtotal * _selectedPercent! / 100.0;
  }

  Future<void> _send() async {
    final amount = _amount;
    if (amount <= 0) return;
    setState(() => _sending = true);
    try {
      await context
          .read<OrderProvider>()
          .sendTip(widget.orderId, amount.round());
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(context, 'tip.success')),
      ));
      setState(() => _sent = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${t(context, 'common.error')}: $e'),
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _money(num v) =>
      Money(v).format(L10n.instance.locale.languageCode);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🙏', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t(context, 'tip.cta'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (_amount > 0)
                Text(_money(_amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    )),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final p in _percentChoices)
                ChoiceChip(
                  label: Text('$p%'),
                  selected: !_custom && _selectedPercent == p,
                  onSelected: _sent
                      ? null
                      : (_) => setState(() {
                            _custom = false;
                            _selectedPercent = p;
                          }),
                ),
              ChoiceChip(
                label: Text(t(context, 'tip.custom')),
                selected: _custom,
                onSelected: _sent
                    ? null
                    : (_) => setState(() {
                          _custom = true;
                          _selectedPercent = null;
                        }),
              ),
            ],
          ),
          if (_custom) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _customCtrl,
              keyboardType: TextInputType.number,
              enabled: !_sent,
              decoration: InputDecoration(
                hintText: t(context, 'tip.custom'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_sending || _sent || _amount <= 0) ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.favorite_rounded),
              label: Text(_sent
                  ? t(context, 'tip.success')
                  : t(context, 'tip.cta')),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _sent ? AppColors.success : AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Delivery-photo card + fullscreen viewer (Phase 13.2.5) ──────────────────

/// Shows the courier's hand-off photo with a receipt-style "delivered at HH:MM"
/// stamp. Tapping the thumbnail opens a fullscreen pinch-zoom viewer.
class _DeliveryPhotoCard extends StatelessWidget {
  final String url;
  final DateTime? takenAt;
  const _DeliveryPhotoCard({required this.url, this.takenAt});

  String get _resolvedUrl =>
      url.startsWith('http') ? url : '${ApiConfig.baseUrl}$url';

  String _stamp() {
    if (takenAt == null) return '';
    final local = takenAt!.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return L10n.instance
        .t('delivery_photo.delivered_at')
        .replaceAll('{time}', '$hh:$mm');
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _DeliveryPhotoViewer(url: _resolvedUrl),
        ),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_camera_outlined,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    L10n.instance.t('delivery_photo.title'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (takenAt != null)
                  Text(
                    _stamp(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: CachedNetworkImage(
                  imageUrl: _resolvedUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: AppColors.border,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.border,
                    height: 160,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: AppColors.textHint),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              L10n.instance.t('delivery_photo.tap_to_view'),
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryPhotoViewer extends StatelessWidget {
  final String url;
  const _DeliveryPhotoViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(L10n.instance.t('delivery_photo.title')),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
