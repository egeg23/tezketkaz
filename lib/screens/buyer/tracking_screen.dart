import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../models/money.dart';
import '../../providers/order_provider.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';

/// TRACKING — master.html .tracking (lines 6689-6843).
///
/// Top-bar: glass back-chip on the left + tracking-status-pill (lime dot +
/// "Курьер в пути" + ETA in JetBrainsMono). Dark map fills the screen; bottom
/// glass sheet hosts a 4-step horizontal timeline, courier card (photo +
/// name + ★ rating · plate), chat & call actions, lime confirm CTA.
class TrackingScreen extends StatefulWidget {
  final String orderId;
  const TrackingScreen({super.key, required this.orderId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  static const _shopPoint = LatLng(41.3617, 69.2877);
  static const _customerPoint = LatLng(41.3700, 69.2890);

  LatLng? _courierPoint;
  bool _confirming = false;
  late final void Function(dynamic) _locHandler;

  @override
  void initState() {
    super.initState();
    final socket = SocketService.instance;
    socket.subscribeToOrder(widget.orderId);
    _locHandler = (data) {
      if (!mounted) return;
      if (data is Map) {
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          setState(() => _courierPoint = LatLng(lat, lng));
        }
      }
    };
    socket.on('courier:location', _locHandler);
  }

  @override
  void dispose() {
    SocketService.instance.off('courier:location', _locHandler);
    SocketService.instance.unsubscribeFromOrder(widget.orderId);
    super.dispose();
  }

  Future<void> _confirmReceived() async {
    setState(() => _confirming = true);
    try {
      await context.read<OrderProvider>().buyerConfirm(widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Доставка подтверждена 🎉'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = context.watch<OrderProvider>().findById(widget.orderId);
    if (order == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text(
            'Заказ не найден',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final isHanded = order.status == AppOrderStatus.delivered;
    final isDone = order.status == AppOrderStatus.confirmedByBuyer;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // ─ Map ────────────────────────────────────────────────────────
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _courierPoint ?? _shopPoint,
                initialZoom: 14,
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
                MarkerLayer(
                  markers: [
                    const Marker(
                      point: _shopPoint,
                      width: 36,
                      height: 36,
                      child: _ShopPin(),
                    ),
                    const Marker(
                      point: _customerPoint,
                      width: 32,
                      height: 32,
                      child: _DestPin(),
                    ),
                    if (_courierPoint != null)
                      Marker(
                        point: _courierPoint!,
                        width: 60,
                        height: 60,
                        child: _PulsingPin(),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ─ Top bar (back + status pill) ───────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _BackChip(onTap: () => context.go('/buyer')),
                  const SizedBox(width: 12),
                  Expanded(child: _StatusPill(order: order, hasCourier: _courierPoint != null)),
                ],
              ),
            ),
          ),

          // ─ Bottom sheet ───────────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: _Sheet(
              order: order,
              isHanded: isHanded,
              isDone: isDone,
              confirming: _confirming,
              onConfirm: _confirmReceived,
              onChat: () => context.push('/order/${order.id}/chat'),
              onCall: () {},
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top-bar chips ───────────────────────────────────────────────────────
class _BackChip extends StatelessWidget {
  final VoidCallback onTap;
  const _BackChip({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xCC0F0F16),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(Icons.chevron_left_rounded,
              size: 18, color: Colors.white),
        ),
      );
}

class _StatusPill extends StatelessWidget {
  final AppOrder order;
  final bool hasCourier;
  const _StatusPill({required this.order, required this.hasCourier});

  String _label() {
    switch (order.status) {
      case AppOrderStatus.pending:
        return 'Подтверждение';
      case AppOrderStatus.collecting:
        return 'Сборка';
      case AppOrderStatus.readyForPickup:
        return 'Ожидает курьера';
      case AppOrderStatus.courierAssigned:
        return 'Курьер в ресторан';
      case AppOrderStatus.pickedUp:
      case AppOrderStatus.inDelivery:
        return 'Курьер в пути';
      case AppOrderStatus.arrivedAtCustomer:
        return 'У двери';
      case AppOrderStatus.delivered:
        return 'Подтвердите';
      default:
        return order.statusLabel;
    }
  }

  String _eta() {
    switch (order.status) {
      case AppOrderStatus.collecting:
        return '~12 мин';
      case AppOrderStatus.readyForPickup:
        return '~10 мин';
      case AppOrderStatus.pickedUp:
      case AppOrderStatus.inDelivery:
        return hasCourier ? '~6 мин' : '~12 мин';
      case AppOrderStatus.arrivedAtCustomer:
        return 'У вас';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xCC0F0F16),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.7),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _label(),
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              _eta(),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
}

// ─── Pins ────────────────────────────────────────────────────────────────
class _ShopPin extends StatelessWidget {
  const _ShopPin();
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(Icons.storefront_rounded, color: AppColors.bg, size: 18),
      );
}

class _DestPin extends StatelessWidget {
  const _DestPin();
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary, width: 3),
        ),
      );
}

class _PulsingPin extends StatefulWidget {
  @override
  State<_PulsingPin> createState() => _PulsingPinState();
}

class _PulsingPinState extends State<_PulsingPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final t = _c.value;
              return Opacity(
                opacity: (1 - t).clamp(0.0, 0.5),
                child: Container(
                  width: 30 + t * 30,
                  height: 30 + t * 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
            ),
            child: Container(
              margin: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                color: Color(0xFF003A1F),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      );
}

// ─── Bottom sheet ────────────────────────────────────────────────────────
class _Sheet extends StatelessWidget {
  final AppOrder order;
  final bool isHanded;
  final bool isDone;
  final bool confirming;
  final VoidCallback onConfirm;
  final VoidCallback onChat;
  final VoidCallback onCall;
  const _Sheet({
    required this.order,
    required this.isHanded,
    required this.isDone,
    required this.confirming,
    required this.onConfirm,
    required this.onChat,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xF20F0F16),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: AppColors.border),
            left: BorderSide(color: AppColors.border),
            right: BorderSide(color: AppColors.border),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Timeline(current: order.status),
                  const SizedBox(height: 20),
                  if (order.courierName != null) ...[
                    _CourierCard(
                      name: order.courierName!,
                      onChat: onChat,
                      onCall: onCall,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (isHanded)
                    _ConfirmCta(
                        confirming: confirming, onTap: onConfirm),
                  if (isDone) ...[
                    _TipCard(
                        orderId: order.id, subtotal: order.subtotal),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

class _Timeline extends StatelessWidget {
  final AppOrderStatus current;
  const _Timeline({required this.current});

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

  int _bucket(AppOrderStatus s) {
    // Map to 4 visual buckets: Приём → Готов → В пути → Доставлен
    final idx = _order.indexOf(s);
    if (idx <= 0) return 0;
    if (idx <= 2) return 1;
    if (idx <= 5) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final steps = const ['Приём', 'Готов', 'В пути', 'Доставлен'];
    final activeBucket = _bucket(current);
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: i <= activeBucket
                        ? AppColors.primary
                        : AppColors.border,
                    shape: BoxShape.circle,
                    boxShadow: i == activeBucket
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.5),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  steps[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == activeBucket
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: i <= activeBucket
                        ? Colors.white
                        : AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          if (i < steps.length - 1)
            Container(
              width: 24,
              height: 2,
              color: i < activeBucket
                  ? AppColors.primary
                  : AppColors.border,
              margin: const EdgeInsets.only(bottom: 22),
            ),
        ],
      ],
    );
  }
}

class _CourierCard extends StatelessWidget {
  final String name;
  final VoidCallback onChat;
  final VoidCallback onCall;
  const _CourierCard({
    required this.name,
    required this.onChat,
    required this.onCall,
  });
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.30),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '★ 4.92',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('·',
                          style: TextStyle(
                              color: AppColors.textHint, fontSize: 11)),
                      const SizedBox(width: 6),
                      Text(
                        'Мото · 01 A 234 BC',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _ActionBtn(icon: Icons.chat_bubble_outline_rounded, onTap: onChat),
            const SizedBox(width: 8),
            _ActionBtn(
              icon: Icons.phone_rounded,
              lime: true,
              onTap: onCall,
            ),
          ],
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final bool lime;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    this.lime = false,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: lime ? AppColors.primary : AppColors.surfaceMuted,
            shape: BoxShape.circle,
            border: lime ? null : Border.all(color: AppColors.border),
          ),
          child: Icon(
            icon,
            size: 16,
            color: lime ? AppColors.bg : Colors.white,
          ),
        ),
      );
}

class _ConfirmCta extends StatelessWidget {
  final bool confirming;
  final VoidCallback onTap;
  const _ConfirmCta({required this.confirming, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: confirming ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.30),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: confirming
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Color(0xFF050507),
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  'Я получил заказ',
                  style: TextStyle(
                    color: AppColors.bg,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      );
}

/// Phase 6 — courier tip CTA shown after the order is `confirmedByBuyer`.
class _TipCard extends StatefulWidget {
  final String orderId;
  final double subtotal;
  const _TipCard({required this.orderId, required this.subtotal});
  @override
  State<_TipCard> createState() => _TipCardState();
}

class _TipCardState extends State<_TipCard> {
  static const _percents = [5, 10, 15];
  int? _selected = 10;
  bool _custom = false;
  final _ctrl = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _amount {
    if (_custom) {
      return double.tryParse(_ctrl.text.trim().replaceAll(' ', '')) ?? 0;
    }
    if (_selected == null) return 0;
    return widget.subtotal * _selected! / 100.0;
  }

  Future<void> _send() async {
    if (_amount <= 0) return;
    setState(() => _sending = true);
    try {
      await context
          .read<OrderProvider>()
          .sendTip(widget.orderId, _amount.round());
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'tip.success'))));
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'СПАСИБО КУРЬЕРУ',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              if (_amount > 0)
                Text(
                  Money(_amount).format(L10n.instance.locale.languageCode),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final p in _percents)
                _TipChip(
                  label: '$p%',
                  active: !_custom && _selected == p,
                  onTap: _sent
                      ? null
                      : () => setState(() {
                            _custom = false;
                            _selected = p;
                          }),
                ),
              _TipChip(
                label: 'Свой',
                active: _custom,
                onTap: _sent
                    ? null
                    : () => setState(() {
                          _custom = true;
                          _selected = null;
                        }),
              ),
            ],
          ),
          if (_custom) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                enabled: !_sent,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Введите сумму',
                  hintStyle: TextStyle(color: Color(0x59FFFFFF)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _sending || _sent || _amount <= 0 ? null : _send,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _sent
                      ? AppColors.success
                      : AppColors.primary
                          .withValues(alpha: _amount <= 0 ? 0.4 : 1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Color(0xFF050507),
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _sent ? 'Спасибо отправлено' : 'Отправить чаевые',
                        style: TextStyle(
                          color: AppColors.bg,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;
  const _TipChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.bg : Colors.white,
            ),
          ),
        ),
      );
}
