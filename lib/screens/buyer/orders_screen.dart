import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../services/order_api.dart';
import '../../services/review_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rating_dialog.dart';

/// ORDERS — master.html .orders (lines 6851-6954).
///
/// Playfair "Buyurtmalar" header, 2-segment toggle (Faol · N / Tarix), then
/// `.order-card.active` card with shop logo + status badge + live dot + total,
/// followed by `.order-card` history rows with done-checkmark badges, item
/// bubble row, "Kuzatish →" or "Qaytarish →" right-aligned action.
class BuyerOrdersScreen extends StatefulWidget {
  const BuyerOrdersScreen({super.key});
  @override
  State<BuyerOrdersScreen> createState() => _BuyerOrdersScreenState();
}

class _BuyerOrdersScreenState extends State<BuyerOrdersScreen> {
  int _seg = 0; // 0 = Active, 1 = History

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>().all;
    final active = orders
        .where((o) =>
            o.status != AppOrderStatus.delivered &&
            o.status != AppOrderStatus.confirmedByBuyer &&
            o.status != AppOrderStatus.cancelled)
        .toList();
    final history = orders
        .where((o) =>
            o.status == AppOrderStatus.delivered ||
            o.status == AppOrderStatus.confirmedByBuyer ||
            o.status == AppOrderStatus.cancelled)
        .toList();

    final shown = _seg == 0 ? active : history;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A10), Color(0xFF050507)],
          ),
        ),
        child: SafeArea(
          child: orders.isEmpty
              ? Column(
                  children: [
                    _Header(),
                    Expanded(child: _Empty()),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: [
                    _Header(),
                    _Seg(
                      active: _seg,
                      activeCount: active.length,
                      onTap: (i) => setState(() => _seg = i),
                    ),
                    const SizedBox(height: 16),
                    if (shown.isEmpty)
                      _EmptyMini(message: _seg == 0
                          ? 'Активных заказов нет'
                          : 'История пуста'),
                    for (final o in shown) _OrderRow(order: o),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
        child: Text(
          'Заказы',
          style: GoogleFonts.playfairDisplay(
            fontSize: 30,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
      );
}

class _Seg extends StatelessWidget {
  final int active;
  final int activeCount;
  final ValueChanged<int> onTap;
  const _Seg({
    required this.active,
    required this.activeCount,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            _SegBtn(
              label: 'Активные · $activeCount',
              active: active == 0,
              onTap: () => onTap(0),
            ),
            _SegBtn(
              label: 'История',
              active: active == 1,
              onTap: () => onTap(1),
            ),
          ],
        ),
      );
}

class _SegBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.bg : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
}

class _OrderRow extends StatelessWidget {
  final AppOrder order;
  const _OrderRow({required this.order});

  String _fmt(double v) => v
      .toInt()
      .toString()
      .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');

  Future<void> _reorder(BuildContext context) async {
    try {
      final draft = await OrderApi.instance.reorder(order.id);
      if (!context.mounted) return;
      final cart = context.read<CartProvider>();
      final skipped = cart.replaceFromDraft(draft);
      final txt = skipped.isEmpty
          ? 'Корзина обновлена'
          : 'Эти товары недоступны: ${skipped.join(', ')}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txt)));
      context.go('/buyer/cart');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _rate(BuildContext context) async {
    final api = ReviewApi.instance;
    final shopRes = await RatingDialog.show(
      context,
      title: 'Оцените ресторан',
      subtitle: order.shopName,
    );
    if (shopRes != null) {
      try {
        await api.create(order.id,
            targetType: 'shop',
            targetId: order.shopId,
            rating: shopRes.rating,
            text: shopRes.text,
            photos: shopRes.photos);
      } catch (_) {}
    }
    if (order.courierId != null && context.mounted) {
      final r = await RatingDialog.show(context,
          title: 'Оцените курьера',
          subtitle: order.courierName,
          allowPhotos: false);
      if (r != null) {
        try {
          await api.create(order.id,
              targetType: 'courier',
              targetId: order.courierId!,
              rating: r.rating,
              text: r.text);
        } catch (_) {}
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Спасибо! Оценка отправлена.')));
    }
  }

  bool get _isActive =>
      order.status != AppOrderStatus.delivered &&
      order.status != AppOrderStatus.confirmedByBuyer &&
      order.status != AppOrderStatus.cancelled;

  String _statusLabel() {
    switch (order.status) {
      case AppOrderStatus.pending:
        return 'Принят';
      case AppOrderStatus.collecting:
        return 'Сборка';
      case AppOrderStatus.readyForPickup:
        return 'Готов';
      case AppOrderStatus.courierAssigned:
      case AppOrderStatus.pickedUp:
      case AppOrderStatus.inDelivery:
        return 'Курьер в пути';
      case AppOrderStatus.arrivedAtCustomer:
        return 'У двери';
      case AppOrderStatus.delivered:
      case AppOrderStatus.confirmedByBuyer:
        return '✓ Доставлен';
      case AppOrderStatus.cancelled:
        return 'Отменён';
      default:
        return order.statusLabel;
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _isActive
            ? () => context.go('/buyer/tracking/${order.id}')
            : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _isActive
                ? AppColors.primary.withValues(alpha: 0.06)
                : const Color(0x09FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isActive
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A2618),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.storefront_rounded,
                        color: AppColors.textSecondary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.shopName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _StatusBadge(
                          label: _statusLabel(),
                          live: _isActive,
                          minutesAgo: order.minutesAgo,
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
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
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
              Container(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Item bubbles
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: Stack(
                        children: [
                          for (var i = 0;
                              i < order.items.length.clamp(0, 3);
                              i++)
                            Positioned(
                              left: i * 22.0,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.bg, width: 2),
                                  color: const Color(0xFFF5B95C),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: order.items[i].product.imageUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl:
                                            order.items[i].product.imageUrl,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            Container(),
                                      )
                                    : null,
                              ),
                            ),
                          if (order.items.length > 3)
                            Positioned(
                              left: 3 * 22.0 + 4,
                              top: 6,
                              child: Text(
                                '+${order.items.length - 3}',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _isActive
                        ? () => context.go('/buyer/tracking/${order.id}')
                        : () => _reorder(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isActive ? 'Отследить' : 'Повторить',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded,
                            size: 14, color: AppColors.primary),
                      ],
                    ),
                  ),
                ],
              ),
              if (!_isActive &&
                  order.status == AppOrderStatus.delivered) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _rate(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_outline_rounded,
                          size: 14, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Text(
                        'Оценить заказ',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool live;
  final String minutesAgo;
  const _StatusBadge({
    required this.label,
    required this.live,
    required this.minutesAgo,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: live
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (live) ...[
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.7),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: live ? AppColors.primary : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '· $minutesAgo',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textHint,
            ),
          ),
        ],
      );
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📦', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              const Text(
                'Заказов пока нет',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Найдите любимое заведение на главной',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
}

class _EmptyMini extends StatelessWidget {
  final String message;
  const _EmptyMini({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            message,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
}
