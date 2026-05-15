import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';

/// Legacy palette tokens — `shop_other_screens.dart` and a couple of older
/// helper screens still import these. The master rewrite uses `AppColors.*`
/// everywhere instead; we keep the names alive so we don't ripple-rebuild the
/// stale screens in this commit.
const kShopColor = AppColors.primary;
const kShopLight = AppColors.surfaceMuted;

/// SHOP SHELL — wraps `/shop/*` routes with the master design's bottom dock.
/// Matches the `.tab-nav` block in master.html .s-dash (lines 8889-8907):
/// 4 lime-pill tabs, active item shaded with lime-soft + lime icon/label.
class ShopShell extends StatelessWidget {
  final Widget child;
  const ShopShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    if (loc.startsWith('/shop/products')) return 1;
    if (loc.startsWith('/shop/history')) return 2;
    if (loc.startsWith('/shop/settings')) return 3;
    if (loc.startsWith('/shop/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xB30F0F16),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                _TabItem(
                  icon: Icons.home_rounded,
                  label: 'Главная',
                  active: idx == 0,
                  onTap: () => context.go('/shop'),
                ),
                _TabItem(
                  icon: Icons.restaurant_menu_rounded,
                  label: 'Меню',
                  active: idx == 1,
                  onTap: () => context.go('/shop/products'),
                ),
                _TabItem(
                  icon: Icons.bar_chart_rounded,
                  label: 'Отчёты',
                  active: idx == 2,
                  onTap: () => context.go('/shop/history'),
                ),
                _TabItem(
                  icon: Icons.settings_outlined,
                  label: 'Настр.',
                  active: idx == 3,
                  onTap: () => context.go('/shop/settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: active ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
