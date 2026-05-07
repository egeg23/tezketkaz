import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';

// Цвет магазина — тёмно-синий, отличается от покупателя (зелёный) и курьера (оранжевый)
const kShopColor = Color(0xFF3B5BDB);
const kShopLight = Color(0xFFEEF2FF);

class ShopShell extends StatelessWidget {
  final Widget child;
  const ShopShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    if (loc.startsWith('/shop/products')) return 1;
    if (loc.startsWith('/shop/history')) return 2;
    if (loc.startsWith('/shop/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: idx,
          selectedItemColor: kShopColor,
          unselectedItemColor: AppColors.textHint,
          type: BottomNavigationBarType.fixed,
          onTap: (i) {
            switch (i) {
              case 0: context.go('/shop'); break;
              case 1: context.go('/shop/products'); break;
              case 2: context.go('/shop/history'); break;
              case 3: context.go('/shop/profile'); break;
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.inbox_outlined),
              activeIcon: Icon(Icons.inbox),
              label: 'Buyurtmalar',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.shopping_basket_outlined),
              activeIcon: Icon(Icons.shopping_basket),
              label: 'Mahsulotlar',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'Tarix',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.store_outlined),
              activeIcon: Icon(Icons.store),
              label: 'Do\'kon',
            ),
          ],
        ),
      ),
    );
  }
}
