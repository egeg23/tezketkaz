import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

class BuyerShell extends StatelessWidget {
  final Widget child;
  const BuyerShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    if (loc.startsWith('/buyer/shops')) return 1;
    if (loc.startsWith('/buyer/cart')) return 2;
    if (loc.startsWith('/buyer/orders')) return 3;
    if (loc.startsWith('/buyer/profile')) return 4;
    return 0;
  }

  void _go(BuildContext context, int i) {
    HapticFeedback.lightImpact();
    switch (i) {
      case 0: context.go('/buyer'); break;
      case 1: context.go('/buyer/shops'); break;
      case 2: context.go('/buyer/cart'); break;
      case 3: context.go('/buyer/orders'); break;
      case 4: context.go('/buyer/profile'); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final orders = context.watch<OrderProvider>();
    final idx = _currentIndex(context);

    final activeCount = orders.all
        .where((o) =>
            o.status != AppOrderStatus.confirmedByBuyer &&
            o.status != AppOrderStatus.cancelled)
        .length;

    final items = [
      _NavItem(icon: Icons.home_rounded, label: 'Bosh sahifa'),
      _NavItem(icon: Icons.storefront_rounded, label: "Do'konlar"),
      _NavItem(icon: Icons.shopping_basket_rounded, label: 'Savat', badge: cart.itemCount),
      _NavItem(icon: Icons.receipt_long_rounded, label: 'Buyurtmalar', badge: activeCount, badgeColor: AppColors.courier),
      _NavItem(icon: Icons.person_rounded, label: 'Profil'),
    ];

    return Scaffold(
      body: child,
      extendBody: true,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            boxShadow: AppShadows.elevated,
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavBtn(
                    item: items[i],
                    selected: i == idx,
                    onTap: () => _go(context, i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final int? badge;
  final Color? badgeColor;
  const _NavItem({
    required this.icon, required this.label, this.badge, this.badgeColor,
  });
}

class _NavBtn extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _NavBtn({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(AppRadii.lg),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: selected ? 56 : 36,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primaryLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    item.icon,
                    size: 22,
                    color: selected ? AppColors.primary : AppColors.textHint,
                  ),
                ),
                if ((item.badge ?? 0) > 0)
                  Positioned(
                    top: -4,
                    right: selected ? 4 : -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: item.badgeColor ?? AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${item.badge}',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textHint,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}
