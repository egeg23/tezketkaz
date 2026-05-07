import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

class CourierHomeScreen extends StatefulWidget {
  const CourierHomeScreen({super.key});
  @override
  State<CourierHomeScreen> createState() => _CourierHomeScreenState();
}

class _CourierHomeScreenState extends State<CourierHomeScreen> {
  bool _isOnline = true;
  double _todayEarnings = 67500;
  int _todayOrders = 5;

  static const _courierId = 'courier_demo';

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>();
    final available = orders.availableForCourier();
    final active = orders.activeForCourier(_courierId);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
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
                    const Text('Bobur K.', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(_isOnline ? 'Onlayn' : 'Oflayn',
                        style: TextStyle(fontSize: 12,
                            color: _isOnline ? AppColors.success : AppColors.textHint)),
                  ],
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); setState(() => _isOnline = !_isOnline); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isOnline ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_isOnline ? Icons.wifi : Icons.wifi_off, color: Colors.white, size: 15),
                        const SizedBox(width: 5),
                        Text(_isOnline ? 'Onlayn' : 'Oflayn',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats card
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _StatsCard(earnings: _todayEarnings, count: _todayOrders, isOnline: _isOnline),
                ),

                // Active order banner
                if (active != null) Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: GestureDetector(
                    onTap: () => context.go('/courier/order/${active.id}'),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.courierLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.courier.withValues(alpha: 0.4), width: 2),
                      ),
                      child: Row(
                        children: [
                          const Text('🛵', style: TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Faol buyurtma', style: TextStyle(color: AppColors.courier, fontWeight: FontWeight.w700, fontSize: 13)),
                                Text(active.deliveryAddress, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.courier),
                        ],
                      ),
                    ),
                  ),
                ),

                // Available orders header
                if (_isOnline) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(
                      children: [
                        Text('Yangi buyurtmalar', style: Theme.of(context).textTheme.headlineMedium),
                        if (available.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.courier, borderRadius: BorderRadius.circular(10)),
                            child: Text('${available.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (available.isEmpty)
                    _EmptyCard(hasActive: active != null)
                  else
                    ...available.map((o) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _OrderCard(
                        order: o,
                        isDisabled: active != null,
                        onAccept: () {
                          HapticFeedback.mediumImpact();
                          context.read<OrderProvider>().courierAcceptOrder(o.id);
                          context.go('/courier/order/${o.id}');
                        },
                        onDecline: () {
                          // В реальности — записываем отказ, не удаляем из списка
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Buyurtma rad etildi'), behavior: SnackBarBehavior.floating));
                        },
                      ),
                    )),
                ],

                if (!_isOnline) _OfflineCard(onGoOnline: () => setState(() => _isOnline = true)),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widgets ─────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final double earnings;
  final int count;
  final bool isOnline;
  const _StatsCard({required this.earnings, required this.count, required this.isOnline});
  String _fmt(double v) => '${(v / 1000).toStringAsFixed(0)} ming so\'m';

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: isOnline ? [AppColors.courier, const Color(0xFFE55A2B)] : [const Color(0xFF888), const Color(0xFF666)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: _Stat(emoji: '💰', value: _fmt(earnings), label: 'Bugungi daromad')),
            Container(width: 1, height: 48, color: Colors.white24),
            Expanded(child: _Stat(emoji: '📦', value: '$count ta', label: 'Buyurtmalar')),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white70, size: 15),
              const SizedBox(width: 6),
              Text(isOnline ? '⭐ Reyting: 4.9 · O\'rtacha: 18 min' : 'Buyurtma olish uchun onlayn bo\'ling',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  final String emoji, value, label;
  const _Stat({required this.emoji, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(emoji, style: const TextStyle(fontSize: 22)),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
  ]);
}

class _OrderCard extends StatelessWidget {
  final AppOrder order;
  final bool isDisabled;
  final VoidCallback onAccept, onDecline;
  const _OrderCard({required this.order, required this.isDisabled, required this.onAccept, required this.onDecline});

  String _fmtR(double v) => '${v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: isDisabled ? 0.5 : 1,
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Tags row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(17))),
            child: Row(
              children: [
                _Tag('💰 ${_fmtR(order.reward)}', AppColors.success),
                const SizedBox(width: 6),
                _Tag('📍 ${order.deliveryFee == 0 ? '~1.5' : '~2'} km', AppColors.info),
                const SizedBox(width: 6),
                _Tag('⏱ ~18 min', AppColors.warning),
                const Spacer(),
                _Tag('💳 ${order.isPaid ? 'To\'langan' : 'Naqd'}', AppColors.textSecondary),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RouteRow(icon: Icons.store_outlined, color: AppColors.primary, address: order.shopName, sub: order.shopAddress),
                Padding(padding: const EdgeInsets.only(left: 12), child: Container(height: 18, width: 2, color: AppColors.border)),
                _RouteRow(icon: Icons.home_outlined, color: AppColors.courier, address: order.deliveryAddress),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                ...order.items.map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    const Icon(Icons.circle, size: 5, color: AppColors.textHint),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i.product.name, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                    Text('× ${i.quantity}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                )),
                const SizedBox(height: 14),
                if (!isDisabled) Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDecline,
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), foregroundColor: AppColors.textSecondary, side: const BorderSide(color: AppColors.border)),
                        child: const Text('O\'tkazib yuborish'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: onAccept,
                        style: ElevatedButton.styleFrom(minimumSize: const Size(0, 46), backgroundColor: AppColors.courier),
                        child: const Text('Qabul qilish'),
                      ),
                    ),
                  ],
                ),
                if (isDisabled)
                  const Center(child: Text('Avval joriy buyurtmani tugatíng',
                      style: TextStyle(color: AppColors.textHint, fontSize: 13))),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  final String text; final Color color;
  const _Tag(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

class _RouteRow extends StatelessWidget {
  final IconData icon; final Color color; final String address; final String? sub;
  const _RouteRow({required this.icon, required this.color, required this.address, this.sub});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(width: 24, height: 24, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 14)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(address, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ])),
    ],
  );
}

class _EmptyCard extends StatelessWidget {
  final bool hasActive;
  const _EmptyCard({required this.hasActive});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        const Text('🕐', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text(hasActive ? 'Joriy buyurtmani yetkazing' : 'Yangi buyurtmalar kutilmoqda...',
            style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
      ]),
    ),
  );
}

class _OfflineCard extends StatelessWidget {
  final VoidCallback onGoOnline;
  const _OfflineCard({required this.onGoOnline});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        const Text('💤', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text('Siz oflayn rejimdasiz', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('Buyurtma olish uchun onlayn rejimga o\'ting',
            style: TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onGoOnline,
          icon: const Icon(Icons.wifi),
          label: const Text('Onlayn rejimga o\'tish'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.courier),
        ),
      ]),
    ),
  );
}
