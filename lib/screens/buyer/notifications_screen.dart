import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

/// Inbox-style notifications screen. Reads from the order timeline
/// (every order:updated event is implicitly a notification) and renders
/// a Wolt/UberEats-flavoured feed. Empty state shows a friendly placeholder.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String _bodyFor(AppOrder o) {
    switch (o.status) {
      case AppOrderStatus.pending:          return "Buyurtmangiz qabul qilindi";
      case AppOrderStatus.collecting:       return "Do'kon yig'moqda";
      case AppOrderStatus.readyForPickup:   return "Buyurtma tayyor, kuryer yo'lda";
      case AppOrderStatus.courierAssigned:  return "Kuryer tayinlandi";
      case AppOrderStatus.pickedUp:         return "Kuryer buyurtmani oldi";
      case AppOrderStatus.inDelivery:       return "Buyurtmangiz yo'lda";
      case AppOrderStatus.arrivedAtCustomer:return "Kuryer eshik oldida";
      case AppOrderStatus.delivered:        return "Yetkazib berildi";
      case AppOrderStatus.confirmedByBuyer: return "Tasdiqlangan · rahmat!";
      case AppOrderStatus.cancelled:        return "Bekor qilindi";
      default:                              return o.statusLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = context.watch<OrderProvider>().all;
    final items = [...all]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Bildirishnomalar')),
      body: items.isEmpty
          ? _Empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: items.length,
              itemBuilder: (_, i) => _NotificationTile(order: items[i],
                  body: _bodyFor(items[i])),
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppRadii.xl),
            ),
            alignment: Alignment.center,
            child: const Text('🔔', style: TextStyle(fontSize: 48)),
          ),
          const SizedBox(height: 20),
          Text("Bildirishnomalar yo'q",
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            "Buyurtma holati o'zgarsa, bu yerda ko'rinadi",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ),
  );
}

class _NotificationTile extends StatelessWidget {
  final AppOrder order;
  final String body;
  const _NotificationTile({required this.order, required this.body});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = order.status != AppOrderStatus.delivered &&
        order.status != AppOrderStatus.confirmedByBuyer &&
        order.status != AppOrderStatus.cancelled;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? null : AppShadows.card,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primaryLight : Theme.of(context).colorScheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(order.statusEmoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body,
                    style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    )),
                const SizedBox(height: 2),
                Text(order.shopName,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    )),
              ],
            ),
          ),
          Text(order.minutesAgo,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11, fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}
