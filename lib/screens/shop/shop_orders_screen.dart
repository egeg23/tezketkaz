import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_shimmer.dart';
import 'shop_shell.dart';

class ShopOrdersScreen extends StatefulWidget {
  const ShopOrdersScreen({super.key});
  @override
  State<ShopOrdersScreen> createState() => _ShopOrdersScreenState();
}

class _ShopOrdersScreenState extends State<ShopOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  static const _shopId = 'shop_korzinka';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>();
    final pending = orders.pendingForShop(_shopId);
    final active  = orders.activeForShop(_shopId);
    final done    = orders.doneForShop(_shopId);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Korzinka — Yunusobod',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text('Do\'kon paneli',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'Sozlamalar',
            onSelected: (value) {
              if (value == 'settings') {
                context.push('/shop/settings');
              } else if (value == 'switch') {
                context.push('/switch-role');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'settings',
                child: Row(children: [
                  Icon(Icons.tune, size: 18),
                  SizedBox(width: 10),
                  Text("Do'kon sozlamalari"),
                ]),
              ),
              PopupMenuItem(
                value: 'switch',
                child: Row(children: [
                  Icon(Icons.swap_horiz, size: 18),
                  SizedBox(width: 10),
                  Text('Rol almashish'),
                ]),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: [
            _Tab('Yangi', pending.length),
            _Tab('Jarayonda', active.length),
            _Tab('Tayyor/Yetkazildi', null),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OrdersList(
            orders: pending,
            emptyText: 'Yangi buyurtmalar yo\'q',
            emptyEmoji: '✅',
          ),
          _OrdersList(
            orders: active,
            emptyText: 'Jarayondagi buyurtmalar yo\'q',
            emptyEmoji: '📦',
          ),
          _OrdersList(
            orders: done,
            emptyText: 'Tugallangan buyurtmalar yo\'q',
            emptyEmoji: '🏁',
            readonly: true,
          ),
        ],
      ),
    );
  }
}

Tab _Tab(String label, int? count) => Tab(
  text: count != null && count > 0 ? '$label ($count)' : label,
);

class _OrdersList extends StatelessWidget {
  final List<AppOrder> orders;
  final String emptyText, emptyEmoji;
  final bool readonly;
  const _OrdersList({
    required this.orders,
    required this.emptyText,
    required this.emptyEmoji,
    this.readonly = false,
  });

  @override
  Widget build(BuildContext context) {
    // Phase 13.3.4 — RefreshIndicator wraps every tab so the operator can
    // pull-to-refresh from any of the three (Yangi / Jarayonda / Tayyor).
    // Shimmer kicks in during the initial load when the list is empty AND
    // the provider is actively loading.
    final provider = context.watch<OrderProvider>();
    Widget content;
    if (provider.isLoading && orders.isEmpty) {
      content = const LoadingShimmer(itemCount: 4, itemHeight: 140);
    } else if (orders.isEmpty) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emptyEmoji, style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(emptyText,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
              ],
            ),
          ),
        ],
      );
    } else {
      content = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ShopOrderCard(order: orders[i], readonly: readonly),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () =>
          context.read<OrderProvider>().loadShopOrders('shop_korzinka'),
      child: content,
    );
  }
}

class _ShopOrderCard extends StatelessWidget {
  final AppOrder order;
  final bool readonly;
  const _ShopOrderCard({required this.order, this.readonly = false});

  String _fmt(double v) => '${v.toInt().toString()
    .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  bool get _isNew => order.status == AppOrderStatus.pending;
  bool get _isCollecting => order.status == AppOrderStatus.collecting;
  bool get _isReady => order.status == AppOrderStatus.readyForPickup;

  @override
  Widget build(BuildContext context) {
    final orderProv = context.read<OrderProvider>();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor(), width: _isNew ? 2 : 1),
        boxShadow: _isNew
          ? [BoxShadow(color: kShopColor.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4))]
          : null,
      ),
      child: Column(
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _headerColor(),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                _StatusPill(order.status),
                if (order.orderNumber != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(order.orderNumber!,
                        style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13,
                          color: _borderColor(),
                        )),
                  ),
                ],
                const Spacer(),
                Text(order.minutesAgo,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Customer row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: kShopLight,
                      child: Text(order.customerName[0],
                          style: const TextStyle(color: kShopColor, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order.customerName,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(order.deliveryAddress,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    // Payment
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: order.isPaid ? AppColors.primaryLight : AppColors.courierLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        order.isPaid ? '✓ ${order.paymentMethod}' : '💵 Naqd',
                        style: TextStyle(
                          color: order.isPaid ? AppColors.primary : AppColors.courier,
                          fontSize: 11, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                // Comment
                if (order.customerComment != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Text('💬', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(order.customerComment!,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF795548))),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Items
                ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      Container(width: 6, height: 6,
                          decoration: BoxDecoration(color: _borderColor(), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.product.name, style: const TextStyle(fontSize: 13))),
                      Text('${item.quantity} ${item.product.unit}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 10),
                      Text(_fmt(item.total),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                )),

                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Jami', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(_fmt(order.total),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ],
                ),

                // Action buttons
                if (!readonly) ...[
                  const SizedBox(height: 14),
                  if (_isNew) _NewActions(
                    onAccept: () { HapticFeedback.mediumImpact(); orderProv.shopAcceptOrder(order.id); },
                    onDecline: () => _showCancelDialog(context, orderProv),
                  ),
                  if (_isCollecting) _CollectingActions(
                    orderNumber: order.orderNumber ?? '',
                    onReady: () => _showReadyDialog(context, orderProv),
                  ),
                  if (_isReady) _ReadyActions(
                    orderNumber: order.orderNumber ?? '',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _borderColor() {
    if (_isNew) return kShopColor;
    if (_isCollecting) return AppColors.warning;
    if (_isReady) return AppColors.success;
    if (order.status == AppOrderStatus.cancelled) return AppColors.error;
    return AppColors.border;
  }

  Color _headerColor() {
    if (_isNew) return kShopLight;
    if (_isCollecting) return const Color(0xFFFFF3CD);
    if (_isReady) return AppColors.primaryLight;
    return AppColors.bg;
  }

  void _showReadyDialog(BuildContext context, OrderProvider prov) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Buyurtma tayyor?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Barcha mahsulotlar qo\'shildimi?'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  const Text('Buyurtma raqami', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(order.orderNumber ?? '',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.primary)),
                  const SizedBox(height: 4),
                  const Text('Bu raqamni kuryer so\'raydi', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Orqaga')),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              prov.shopMarkReady(order.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Tayyor ✓'),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog(BuildContext context, OrderProvider prov) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Buyurtmani rad etish?'),
        content: const Text('Xaridor pul qaytaradi. Bu reytingingizga ta\'sir qiladi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bekor')),
          TextButton(
            onPressed: () { prov.shopCancelOrder(order.id); Navigator.pop(context); },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Rad etish'),
          ),
        ],
      ),
    );
  }
}

// ── Action widgets ──────────────────────────────────────────────────────────

class _NewActions extends StatelessWidget {
  final VoidCallback onAccept, onDecline;
  const _NewActions({required this.onAccept, required this.onDecline});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton(
          onPressed: onDecline,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 46),
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
          ),
          child: const Text('Rad etish'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: ElevatedButton(
          onPressed: onAccept,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 46), backgroundColor: kShopColor,
          ),
          child: const Text('✓ Qabul qilish'),
        ),
      ),
    ],
  );
}

class _CollectingActions extends StatelessWidget {
  final String orderNumber;
  final VoidCallback onReady;
  const _CollectingActions({required this.orderNumber, required this.onReady});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3CD),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            Text('📋', style: TextStyle(fontSize: 16)),
            SizedBox(width: 8),
            Expanded(
              child: Text('Mahsulotlarni yig\'ing va «Tayyor» tugmasini bosing',
                  style: TextStyle(fontSize: 12, color: Color(0xFF795548))),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      ElevatedButton.icon(
        onPressed: onReady,
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('Tayyor ✓'),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 46),
          backgroundColor: AppColors.success,
        ),
      ),
    ],
  );
}

class _ReadyActions extends StatelessWidget {
  final String orderNumber;
  const _ReadyActions({required this.orderNumber});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Text('🛵', style: TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kuryer yo\'lda', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
              const Text('Kuryer buyurtma raqamini so\'raydi:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              Text(orderNumber,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.primary,
                  )),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final AppOrderStatus status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      AppOrderStatus.pending         => ('🔔 Yangi', kShopColor, kShopLight),
      AppOrderStatus.collecting      => ('📦 Yig\'ilmoqda', AppColors.warning, const Color(0xFFFFF3CD)),
      AppOrderStatus.readyForPickup  => ('✅ Tayyor', AppColors.success, AppColors.primaryLight),
      AppOrderStatus.courierAssigned => ('🛵 Kuryer yo\'lda', AppColors.info, const Color(0xFFE3F2FD)),
      AppOrderStatus.pickedUp        => ('🛵 Olib ketildi', AppColors.textSecondary, AppColors.bg),
      AppOrderStatus.inDelivery      => ('🚀 Yetkazilmoqda', AppColors.textSecondary, AppColors.bg),
      AppOrderStatus.delivered       => ('🎉 Yetkazildi', AppColors.success, AppColors.primaryLight),
      AppOrderStatus.cancelled       => ('❌ Rad etildi', AppColors.error, const Color(0xFFFFEEEE)),
      _                              => ('—', AppColors.textHint, AppColors.bg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
