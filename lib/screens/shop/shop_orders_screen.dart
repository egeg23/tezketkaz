import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

/// SHOP DASHBOARD — master.html .s-dash (lines 8743-8907).
///
/// Header with Playfair "Boshqaruv" + glass search/notify chips. Hero card
/// (warm-green-radial) with shop logo + Playfair italic name + lime
/// active-status pill + open/closed toggle, and a 4-stat JetBrainsMono grid.
/// Then two sections: "Yangi buyurtmalar" (new orders, lime-tinted cards with
/// Rad etish / Qabul qilish actions) and "Tayyorlanyapti" (collecting, with
/// orange progress bar + ETA).
class ShopOrdersScreen extends StatefulWidget {
  const ShopOrdersScreen({super.key});
  @override
  State<ShopOrdersScreen> createState() => _ShopOrdersScreenState();
}

class _ShopOrdersScreenState extends State<ShopOrdersScreen> {
  bool _isOpen = true;

  String? _shopId(BuildContext ctx) {
    final auth = ctx.read<AuthProvider>();
    return auth.user?.shopId ?? 'shop_korzinka';
  }

  String _shopName(BuildContext ctx) {
    return ctx.read<AuthProvider>().user?.shopName ?? 'Korzinka — Yunusobod';
  }

  @override
  Widget build(BuildContext context) {
    final shopId = _shopId(context) ?? '';
    final orders = context.watch<OrderProvider>();

    // Buckets matching the master mockup
    final pending = orders.pendingForShop(shopId);
    final preparing = orders.activeForShop(shopId)
      ..removeWhere((o) => o.status == AppOrderStatus.readyForPickup);
    final ready = orders.activeForShop(shopId)
        .where((o) => o.status == AppOrderStatus.readyForPickup)
        .toList();

    // Stat values — derived from current order set
    final allShop = orders.all.where((o) => o.shopId == shopId).toList();
    final today = allShop.where((o) {
      final d = o.createdAt;
      final n = DateTime.now();
      return d.year == n.year && d.month == n.month && d.day == n.day;
    }).toList();
    final revenueToday = today
        .where((o) => o.status != AppOrderStatus.cancelled)
        .fold<double>(0, (s, o) => s + o.total);
    final ordersToday = today.length;
    final avgCheck = ordersToday == 0 ? 0 : revenueToday / ordersToday;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A10), Color(0xFF050507)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _Header(onSearch: () {}, onNotify: () {}),
            _StatusHero(
              shopName: _shopName(context),
              isOpen: _isOpen,
              onToggle: () {
                HapticFeedback.lightImpact();
                setState(() => _isOpen = !_isOpen);
              },
              statRevenue: revenueToday,
              statOrders: ordersToday,
              statAvgCheck: avgCheck.toDouble(),
              statRating: 4.9,
            ),
            if (pending.isNotEmpty) ...[
              _SectionTitle(
                label: 'Новые заказы',
                count: pending.length,
                limeBadge: true,
              ),
              for (final o in pending)
                _OrderCardNew(
                  order: o,
                  onAccept: () async {
                    try {
                      await context
                          .read<OrderProvider>()
                          .shopAcceptOrder(o.id);
                    } catch (e) {
                      if (!mounted) return;
                      _toast('Ошибка: $e');
                    }
                  },
                  onDecline: () async {
                    try {
                      await context
                          .read<OrderProvider>()
                          .shopCancelOrder(o.id, 'declined');
                    } catch (e) {
                      if (!mounted) return;
                      _toast('Ошибка: $e');
                    }
                  },
                ),
            ],
            if (preparing.isNotEmpty) ...[
              _SectionTitle(
                label: 'Готовятся',
                count: preparing.length,
                limeBadge: false,
              ),
              for (final o in preparing)
                _OrderCardPrep(
                  order: o,
                  onReady: () async {
                    try {
                      await context
                          .read<OrderProvider>()
                          .shopMarkReady(o.id);
                    } catch (e) {
                      if (!mounted) return;
                      _toast('Ошибка: $e');
                    }
                  },
                ),
            ],
            if (ready.isNotEmpty) ...[
              _SectionTitle(
                label: 'Готов · ожидает курьера',
                count: ready.length,
                limeBadge: false,
              ),
              for (final o in ready) _OrderCardReady(order: o),
            ],
            if (pending.isEmpty && preparing.isEmpty && ready.isEmpty)
              _EmptyState(),
          ],
        ),
      ),
    );
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }
}

// ════════════════════════════════════════════════════════════════════════
// Header (Playfair "Boshqaruv" + search + notif chips)
// ════════════════════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onNotify;
  const _Header({required this.onSearch, required this.onNotify});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                  children: [
                    const TextSpan(text: 'Управ'),
                    TextSpan(
                      text: 'ление',
                      style: GoogleFonts.playfairDisplay(
                        fontStyle: FontStyle.italic,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _IconChip(icon: Icons.search_rounded, onTap: onSearch),
            const SizedBox(width: 8),
            _IconChip(
                icon: Icons.notifications_outlined,
                onTap: onNotify,
                limeDot: true),
          ],
        ),
      );
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool limeDot;
  const _IconChip({
    required this.icon,
    required this.onTap,
    this.limeDot = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 16, color: AppColors.textSecondary),
            ),
            if (limeDot)
              Positioned(
                top: 8,
                right: 9,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bg, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════
// Status hero (warm radial green + logo + name + toggle + 4 stats)
// ════════════════════════════════════════════════════════════════════════
class _StatusHero extends StatelessWidget {
  final String shopName;
  final bool isOpen;
  final VoidCallback onToggle;
  final double statRevenue;
  final int statOrders;
  final double statAvgCheck;
  final double statRating;
  const _StatusHero({
    required this.shopName,
    required this.isOpen,
    required this.onToggle,
    required this.statRevenue,
    required this.statOrders,
    required this.statAvgCheck,
    required this.statRating,
  });

  String _formatShort(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toInt().toString();
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF0D2418), Color(0xFF0A0A10)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: RadialGradient(
                    center: const Alignment(-1, 1),
                    radius: 1.2,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: RadialGradient(
                    center: const Alignment(1, -1),
                    radius: 1.2,
                    colors: [
                      const Color(0xFFF5B95C).withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                Row(
                  children: [
                    _ShopLogo(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 19,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                                letterSpacing: -0.3,
                                height: 1.1,
                              ),
                              children: _splitShopName(shopName),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _PulseDot(),
                              const SizedBox(width: 6),
                              Text(
                                isOpen ? 'Открыто' : 'Закрыто',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isOpen
                                      ? AppColors.primary
                                      : AppColors.warning,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOpen ? '· до 23:00' : '· до 09:00',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _Toggle(value: isOpen, onChanged: onToggle),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _DashStat(value: '$statOrders', label: 'Заказов'),
                    const SizedBox(width: 6),
                    _DashStat(
                      value: _formatShort(statRevenue),
                      label: 'Выручка',
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    _DashStat(
                      value: _formatShort(statAvgCheck),
                      label: 'Ø чек',
                    ),
                    const SizedBox(width: 6),
                    _DashStat(
                      value: '★ ${statRating.toStringAsFixed(1)}',
                      label: 'Рейтинг',
                      color: const Color(0xFFD4A85C),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

  List<TextSpan> _splitShopName(String name) {
    // Try to italic-lime the second word
    final parts = name.split(' ');
    if (parts.length < 2) {
      return [TextSpan(text: name)];
    }
    return [
      TextSpan(text: '${parts.first} '),
      TextSpan(
        text: parts.sublist(1).join(' '),
        style: GoogleFonts.playfairDisplay(
          fontStyle: FontStyle.italic,
          color: AppColors.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    ];
  }
}

class _ShopLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.4),
                radius: 0.85,
                colors: [Color(0xFFF5B95C), Color(0xFF6B3A0E)],
                stops: [0.0, 0.75],
              ),
            ),
          ),
          Positioned(
            bottom: -3,
            right: -3,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0D2418), width: 2),
              ),
              child: Icon(Icons.check_rounded, size: 10, color: AppColors.bg),
            ),
          ),
        ],
      );
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Opacity(
            opacity: 0.4 + 0.6 * t,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _Toggle extends StatelessWidget {
  final bool value;
  final VoidCallback onChanged;
  const _Toggle({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onChanged,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 52,
          height: 30,
          decoration: BoxDecoration(
            color: value ? AppColors.primary : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.border),
            boxShadow: value
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _DashStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  const _DashStat({required this.value, required this.label, this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -0.4,
                  color: color ?? Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════
// Section title (label · count badge)
// ════════════════════════════════════════════════════════════════════════
class _SectionTitle extends StatelessWidget {
  final String label;
  final int count;
  final bool limeBadge;
  const _SectionTitle({
    required this.label,
    required this.count,
    required this.limeBadge,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: limeBadge
                    ? AppColors.primary
                    : const Color(0x12FFFFFF),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: limeBadge ? AppColors.bg : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════
// Order cards
// ════════════════════════════════════════════════════════════════════════
class _OrderCardNew extends StatelessWidget {
  final AppOrder order;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _OrderCardNew({
    required this.order,
    required this.onAccept,
    required this.onDecline,
  });

  String _fmt(double v) => v
      .toInt()
      .toString()
      .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');

  String _itemsLine() {
    final names = order.items.take(3).map((i) {
      final qty = i.quantity > 1 ? ' ×${i.quantity}' : '';
      return '${i.product.name}$qty';
    }).join(' · ');
    final hidden = order.items.length - 3;
    return hidden > 0 ? '$names +$hidden' : names;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.push('/order/${order.id}'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.30),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 24,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${order.orderNumber ?? 'TK-${order.id.substring(0, 4).toUpperCase()}'}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _LiveDot(),
                            const SizedBox(width: 5),
                            Text(
                              '${order.minutesAgo} · Доставка',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmt(order.total),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'сум',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.white,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(
                      text: '${order.items.length} поз: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    TextSpan(text: _itemsLine()),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onDecline,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          'Отклонить',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: onAccept,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.primary.withValues(alpha: 0.30),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          'Принять',
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
            ],
          ),
        ),
      );
}

class _OrderCardPrep extends StatelessWidget {
  final AppOrder order;
  final VoidCallback onReady;
  const _OrderCardPrep({required this.order, required this.onReady});

  String _fmt(double v) => v
      .toInt()
      .toString()
      .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onReady,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x09FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${order.orderNumber ?? 'TK-${order.id.substring(0, 4).toUpperCase()}'}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '~${_eta(order)} мин осталось',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmt(order.total),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'сум',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progress(order),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.warning,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(_progress(order) * 18).toInt()}/18′',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.30)),
                ),
                child: Text(
                  'Готово →',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  double _progress(AppOrder o) {
    final elapsed = DateTime.now().difference(o.createdAt).inSeconds / 60;
    return (elapsed / 18).clamp(0.0, 1.0);
  }

  int _eta(AppOrder o) {
    final elapsed = DateTime.now().difference(o.createdAt).inMinutes;
    return (18 - elapsed).clamp(0, 18);
  }
}

class _OrderCardReady extends StatelessWidget {
  final AppOrder order;
  const _OrderCardReady({required this.order});

  String _fmt(double v) => v
      .toInt()
      .toString()
      .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x09FFFFFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${order.orderNumber ?? 'TK-${order.id.substring(0, 4).toUpperCase()}'}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '✓ Готов · ожидает курьера',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmt(order.total),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'сум',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Opacity(
          opacity: 0.4 + 0.6 * _c.value,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════
// Empty state
// ════════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.inbox_rounded,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'Очередь пуста',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Новые заказы появятся здесь',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
}
