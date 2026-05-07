import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';
import 'shop_shell.dart';

// ── History ──────────────────────────────────────────────────────────────────

class ShopHistoryScreen extends StatelessWidget {
  const ShopHistoryScreen({super.key});

  static const _shopId = 'shop_korzinka';
  String _fmt(double v) => '${v.toInt()
    .toString()
    .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  @override
  Widget build(BuildContext context) {
    final orderProv = context.watch<OrderProvider>();
    final done = orderProv.doneForShop(_shopId);
    final delivered = done.where((o) => o.status == AppOrderStatus.delivered).toList();
    final todayTotal = delivered.fold(0.0, (s, o) => s + o.total);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        title: const Text('Tarix'),
      ),
      body: Column(
        children: [
          // Summary card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kShopColor, Color(0xFF2F4AC0)]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bugungi tushum', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(_fmt(todayTotal),
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                )),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Buyurtmalar', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${delivered.length} ta',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: done.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('📋', style: TextStyle(fontSize: 52)),
                      SizedBox(height: 12),
                      Text('Tarix yo\'q', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: done.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final o = done[i];
                    final isOk = o.status == AppOrderStatus.delivered;
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: isOk ? AppColors.primaryLight : const Color(0xFFFFEEEE),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(child: Text(isOk ? '✅' : '❌', style: const TextStyle(fontSize: 20))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (o.orderNumber != null)
                                      Text(o.orderNumber!,
                                          style: const TextStyle(fontWeight: FontWeight.w800, color: kShopColor, fontSize: 13)),
                                    if (o.orderNumber != null) const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(o.customerName,
                                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  o.items.map((i) => i.product.name).join(', '),
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isOk ? '+ ${_fmt(o.total)}' : '—',
                            style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13,
                              color: isOk ? AppColors.success : AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

// ── Profile ───────────────────────────────────────────────────────────────────

class ShopProfileScreen extends StatelessWidget {
  const ShopProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>();
    const shopId = 'shop_korzinka';
    final delivered = orders.doneForShop(shopId)
        .where((o) => o.status == AppOrderStatus.delivered).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        title: const Text('Do\'kon profili'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () => context.push('/switch-role'),
              icon: const Text('⇄', style: TextStyle(fontSize: 16)),
              label: const Text('Rol', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Shop card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(child: Text('🏪', style: TextStyle(fontSize: 40))),
                ),
                const SizedBox(height: 12),
                const Text('Korzinka — Yunusobod',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Text('ID: shop_korzinka',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat('4.8 ⭐', 'Reyting'),
                    _Stat('$delivered', 'Buyurtmalar'),
                    _Stat('98%', 'Vaqtida'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _Card(title: 'Ish vaqti', tiles: [
            ('🕐', 'Ish soatlari', '09:00 – 22:00'),
            ('📅', 'Dam olish', 'Har kuni ishlaydi'),
            ('⏸️', 'Vaqtinchalik yopish', 'Barcha buyurtmalarni to\'xtatish'),
          ]),
          const SizedBox(height: 12),
          _Card(title: 'To\'lov usullari', tiles: [
            ('💳', 'Click', 'Ulangan ✓'),
            ('💳', 'Payme', 'Ulangan ✓'),
            ('💜', 'Uzum Pay', 'Ulangan ✓'),
            ('💵', 'Naqd pul', 'Faol'),
          ]),
          const SizedBox(height: 12),
          _Card(title: 'Bildirishnomalar', tiles: [
            ('🔔', 'Yangi buyurtmalar', 'Push + Ovoz'),
            ('📱', 'SMS', 'Faol'),
          ]),
          const SizedBox(height: 24),
          const Center(
            child: Text('TezKetKaz Do\'kon v1.0.0',
                style: TextStyle(color: AppColors.textHint, fontSize: 12)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kShopColor)),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    ],
  );
}

class _Card extends StatelessWidget {
  final String title;
  final List<(String, String, String)> tiles;
  const _Card({required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontSize: 13)),
      ),
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: tiles.asMap().entries.map((e) => Column(
            children: [
              ListTile(
                leading: Text(e.value.$1, style: const TextStyle(fontSize: 22)),
                title: Text(e.value.$2, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                subtitle: Text(e.value.$3, style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
                onTap: () {},
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              ),
              if (e.key < tiles.length - 1) const Divider(height: 1, indent: 56, endIndent: 16),
            ],
          )).toList(),
        ),
      ),
    ],
  );
}
