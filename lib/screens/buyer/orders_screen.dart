import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../services/order_api.dart';
import '../../services/review_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rating_dialog.dart';

class BuyerOrdersScreen extends StatelessWidget {
  const BuyerOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>().all;
    final active = orders.where((o) =>
      o.status != AppOrderStatus.delivered &&
      o.status != AppOrderStatus.confirmedByBuyer &&
      o.status != AppOrderStatus.cancelled).toList();
    final history = orders.where((o) =>
      o.status == AppOrderStatus.delivered ||
      o.status == AppOrderStatus.confirmedByBuyer ||
      o.status == AppOrderStatus.cancelled).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mening buyurtmalarim')),
      body: orders.isEmpty
        ? const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('📦', style: TextStyle(fontSize: 64)),
                SizedBox(height: 16),
                Text('Hali buyurtma yo\'q',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (active.isNotEmpty) ...[
                const _SectionHeader('Faol buyurtmalar'),
                ...active.map((o) => _OrderCard(order: o)),
                const SizedBox(height: 8),
              ],
              if (history.isNotEmpty) ...[
                const _SectionHeader('Tarix'),
                ...history.map((o) => _OrderCard(order: o)),
              ],
            ],
          ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: AppColors.textSecondary,
        )),
  );
}

class _OrderCard extends StatelessWidget {
  final AppOrder order;
  const _OrderCard({required this.order});

  String _fmt(double v) =>
    '${v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  /// Phase 7.3 — fetches a CartDraft from `POST /api/orders/:id/reorder`,
  /// pushes it into the cart provider (skipping unavailable items), and
  /// surfaces a snackbar with the skip reasons before navigating to the
  /// cart screen.
  Future<void> _reorder(BuildContext context) async {
    try {
      final draft = await OrderApi.instance.reorder(order.id);
      if (!context.mounted) return;
      final cart = context.read<CartProvider>();
      final skipped = cart.replaceFromDraft(draft);
      final snackText = skipped.isEmpty
          ? 'Savat yangilandi'
          : "Bu mahsulotlar mavjud emas: ${skipped.join(', ')}";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(snackText)),
      );
      context.go('/buyer/cart');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Xatolik: $e')),
      );
    }
  }

  /// Walk through up to three rating dialogs (shop → courier → product).
  /// Each step is independent — a cancelled dialog skips to the next target.
  Future<void> _rateOrder(BuildContext context) async {
    final api = ReviewApi.instance;
    // Shop
    final shopRes = await RatingDialog.show(
      context,
      title: 'Do\'konni baholang',
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
    // Courier (if assigned)
    if (order.courierId != null) {
      if (!context.mounted) return;
      final courierRes = await RatingDialog.show(
        context,
        title: 'Kuryerni baholang',
        subtitle: order.courierName,
        allowPhotos: false,
      );
      if (courierRes != null) {
        try {
          await api.create(order.id,
              targetType: 'courier',
              targetId: order.courierId!,
              rating: courierRes.rating,
              text: courierRes.text);
        } catch (_) {}
      }
    }
    // Optional product review for first item
    if (order.items.isNotEmpty) {
      if (!context.mounted) return;
      final p = order.items.first.product;
      final productRes = await RatingDialog.show(
        context,
        title: 'Mahsulotni baholang',
        subtitle: p.name,
      );
      if (productRes != null) {
        try {
          await api.create(order.id,
              targetType: 'product',
              targetId: p.id,
              rating: productRes.rating,
              text: productRes.text,
              photos: productRes.photos);
        } catch (_) {}
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rahmat! Baho yuborildi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = order.status != AppOrderStatus.delivered &&
                     order.status != AppOrderStatus.cancelled &&
                     order.status != AppOrderStatus.confirmedByBuyer;
    final isComplete = order.status == AppOrderStatus.delivered ||
                       order.status == AppOrderStatus.confirmedByBuyer;

    return GestureDetector(
      onTap: isActive ? () => context.go('/buyer/tracking/${order.id}') : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primaryLight : AppColors.bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Text(order.statusEmoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(order.statusLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isActive ? AppColors.primary : AppColors.textSecondary,
                        fontSize: 13,
                      )),
                  const Spacer(),
                  Text(order.minutesAgo,
                      style: const TextStyle(
                        color: AppColors.textHint, fontSize: 12,
                      )),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress bar for active orders
                  if (isActive) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: order.buyerProgress,
                        backgroundColor: AppColors.border,
                        color: AppColors.primary,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.shopName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14,
                                )),
                            const SizedBox(height: 2),
                            Text(
                              order.items.map((i) => '${i.product.name} ×${i.quantity}').join(', '),
                              style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_fmt(order.total),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15,
                              )),
                          if (order.orderNumber != null)
                            Text('№ ${order.orderNumber}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12, fontWeight: FontWeight.w600,
                                )),
                        ],
                      ),
                    ],
                  ),

                  // Courier info
                  if (order.courierName != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.courierLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🛵', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text('Kuryer: ${order.courierName}',
                              style: const TextStyle(
                                color: AppColors.courier,
                                fontSize: 12, fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ],

                  if (isActive) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/buyer/tracking/${order.id}'),
                        icon: const Icon(Icons.location_on_outlined, size: 16),
                        label: const Text('Buyurtmani kuzatish'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          side: const BorderSide(color: AppColors.primary),
                          foregroundColor: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                  if (isComplete) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _rateOrder(context),
                            icon: const Icon(Icons.star_outline_rounded,
                                size: 18),
                            label: const Text('Baholash'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.warning,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 40),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _reorder(context),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Qayta buyurtma'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              side: const BorderSide(color: AppColors.primary),
                              foregroundColor: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
