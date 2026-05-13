import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

/// NOTIFICATIONS — master.html .notif (lines 6425-6522).
///
/// `screen-header` with back/tick chips + "Уведомления" title, then dated
/// groupings (Сегодня / Вчера / На неделе) with `.notif-card` rows:
/// 42×42 lime/warm/gray icon block, title + msg + time, unread dot accent.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String _bodyFor(AppOrder o) {
    switch (o.status) {
      case AppOrderStatus.pending:
        return 'Заказ принят';
      case AppOrderStatus.collecting:
        return 'Заведение собирает заказ';
      case AppOrderStatus.readyForPickup:
        return 'Готов к выдаче, курьер в пути';
      case AppOrderStatus.courierAssigned:
        return 'Курьер назначен';
      case AppOrderStatus.pickedUp:
        return 'Курьер забрал заказ';
      case AppOrderStatus.inDelivery:
        return 'Заказ в пути';
      case AppOrderStatus.arrivedAtCustomer:
        return 'Курьер у двери';
      case AppOrderStatus.delivered:
        return 'Заказ доставлен';
      case AppOrderStatus.confirmedByBuyer:
        return 'Подтверждено · спасибо!';
      case AppOrderStatus.cancelled:
        return 'Заказ отменён';
      default:
        return o.statusLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = context.watch<OrderProvider>().all;
    final items = [...all]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // Group by recency
    final now = DateTime.now();
    final today = items.where((o) => _sameDay(o.createdAt, now)).toList();
    final yesterday = items
        .where((o) =>
            _sameDay(o.createdAt, now.subtract(const Duration(days: 1))))
        .toList();
    final older = items.where((o) {
      final d = now.difference(o.createdAt).inDays;
      return d >= 2;
    }).toList();

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
          child: Column(
            children: [
              _Header(
                onBack: () => Navigator.of(context).maybePop(),
                onMarkRead: () {},
              ),
              Expanded(
                child: items.isEmpty
                    ? _Empty()
                    : ListView(
                        padding:
                            const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        children: [
                          if (today.isNotEmpty) ...[
                            _GroupTitle('Сегодня'),
                            for (final o in today)
                              _NotifCard(
                                order: o,
                                body: _bodyFor(o),
                                unread: _isActive(o),
                              ),
                          ],
                          if (yesterday.isNotEmpty) ...[
                            _GroupTitle('Вчера'),
                            for (final o in yesterday)
                              _NotifCard(
                                order: o,
                                body: _bodyFor(o),
                                unread: false,
                              ),
                          ],
                          if (older.isNotEmpty) ...[
                            _GroupTitle('На неделе'),
                            for (final o in older)
                              _NotifCard(
                                order: o,
                                body: _bodyFor(o),
                                unread: false,
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isActive(AppOrder o) =>
      o.status != AppOrderStatus.delivered &&
      o.status != AppOrderStatus.confirmedByBuyer &&
      o.status != AppOrderStatus.cancelled;
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onMarkRead;
  const _Header({required this.onBack, required this.onMarkRead});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            _GlassChip(icon: Icons.chevron_left_rounded, onTap: onBack),
            const Spacer(),
            const Text(
              'Уведомления',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            _GlassChip(icon: Icons.done_all_rounded, onTap: onMarkRead),
          ],
        ),
      );
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassChip({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      );
}

class _GroupTitle extends StatelessWidget {
  final String text;
  const _GroupTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      );
}

class _NotifCard extends StatelessWidget {
  final AppOrder order;
  final String body;
  final bool unread;
  const _NotifCard({
    required this.order,
    required this.body,
    required this.unread,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unread
            ? AppColors.primary.withValues(alpha: 0.06)
            : const Color(0x09FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: unread
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.border,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconFor(order.status),
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.shopName,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      order.minutesAgo,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (unread)
            Positioned(
              top: 4,
              right: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.6),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(AppOrderStatus s) {
    switch (s) {
      case AppOrderStatus.delivered:
      case AppOrderStatus.confirmedByBuyer:
        return Icons.check_rounded;
      case AppOrderStatus.cancelled:
        return Icons.cancel_outlined;
      case AppOrderStatus.inDelivery:
      case AppOrderStatus.pickedUp:
      case AppOrderStatus.courierAssigned:
        return Icons.delivery_dining_rounded;
      default:
        return Icons.shopping_bag_rounded;
    }
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
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: const Text('🔔', style: TextStyle(fontSize: 48)),
              ),
              const SizedBox(height: 20),
              const Text(
                'Уведомлений нет',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Когда статус заказа изменится — увидите здесь',
                textAlign: TextAlign.center,
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
