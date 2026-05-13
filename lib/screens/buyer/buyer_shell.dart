import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

/// Frosted glass dock (master.html .tabbar) with a floating role/route pill
/// suspended above the dock. The pill doubles as the role switcher — tapping
/// it pushes /switch-role.
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
    final route = GoRouterState.of(context).uri.path;

    final activeCount = orders.all
        .where((o) =>
            o.status != AppOrderStatus.confirmedByBuyer &&
            o.status != AppOrderStatus.cancelled)
        .length;

    final items = <_NavItem>[
      const _NavItem(icon: Icons.home_outlined, label: 'Главная'),
      const _NavItem(icon: Icons.search_rounded, label: 'Поиск'),
      _NavItem(icon: Icons.shopping_bag_outlined, label: 'Корзина', badge: cart.itemCount),
      _NavItem(icon: Icons.receipt_long_outlined, label: 'Заказы', badge: activeCount),
      const _NavItem(icon: Icons.person_outline_rounded, label: 'Профиль'),
    ];

    return Scaffold(
      body: child,
      extendBody: true,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // Frosted glass dock
            Container(
              decoration: BoxDecoration(
                color: const Color(0xB30F0F16),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.border),
                boxShadow: const [BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 60, offset: Offset(0, 20),
                )],
              ),
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 12),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _Tab(
                        item: items[i],
                        selected: i == idx,
                        onTap: () => _go(context, i),
                      ),
                    ),
                ],
              ),
            ),

            // Floating role / route pill — taps open the role switcher.
            Positioned(
              top: -14,
              child: _RoleRoutePill(route: route),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final int? badge;
  const _NavItem({required this.icon, required this.label, this.badge});
}

class _Tab extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textHint;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lime dot indicator above the icon (master.html .tab.active::before)
              SizedBox(
                height: 6,
                child: selected
                    ? Center(
                        child: Container(
                          width: 4, height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.7),
                              blurRadius: 8, spreadRadius: 1,
                            )],
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 2),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(item.icon, size: 22, color: color),
                  if ((item.badge ?? 0) > 0)
                    Positioned(
                      top: -4, right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: AppColors.bg, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text('${item.badge}',
                            style: const TextStyle(
                              color: Color(0xFF003A1F),
                              fontSize: 9, fontWeight: FontWeight.w800,
                            )),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleRoutePill extends StatelessWidget {
  final String route;
  const _RoleRoutePill({required this.route});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      context.push('/switch-role');
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xE6000000),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(
          color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 6),
        )],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.7),
                blurRadius: 6, spreadRadius: 1,
              )],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'ПОКУПАТЕЛЬ',
            style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          Text(' · ',
              style: TextStyle(
                fontSize: 9.5, fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.35),
              )),
          Text(
            route.isEmpty ? '/home' : route,
            style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    ),
  );
}
