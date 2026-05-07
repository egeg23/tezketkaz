import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

class BuyerOrdersScreen extends StatelessWidget {
  const BuyerOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>().all;
    final active = orders.where((o) =>
      o.status != AppOrderStatus.delivered &&
      o.status != AppOrderStatus.cancelled).toList();
    final history = orders.where((o) =>
      o.status == AppOrderStatus.delivered ||
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

  @override
  Widget build(BuildContext context) {
    final isActive = order.status != AppOrderStatus.delivered &&
                     order.status != AppOrderStatus.cancelled;

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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
