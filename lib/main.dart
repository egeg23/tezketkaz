import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'models/models.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/courier_state_provider.dart';
import 'providers/order_provider.dart';

import 'screens/auth/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/name_screen.dart';
import 'screens/buyer/buyer_shell.dart';
import 'screens/buyer/home_screen.dart';
import 'screens/buyer/catalog_screen.dart';
import 'screens/buyer/cart_screen.dart';
import 'screens/buyer/orders_screen.dart';
import 'screens/buyer/tracking_screen.dart';
import 'screens/buyer/profile_screen.dart';
import 'screens/buyer/shops_screen.dart';
import 'screens/buyer/address_book_screen.dart';
import 'screens/courier/courier_shell.dart';
import 'screens/courier/courier_home_screen.dart';
import 'screens/courier/active_order_screen.dart';
import 'screens/courier/earnings_screen.dart';
import 'screens/courier/courier_profile_screen.dart';
import 'screens/shop/shop_shell.dart';
import 'screens/shop/shop_orders_screen.dart';
import 'screens/shop/shop_other_screens.dart';
import 'screens/shop/shop_products_screen.dart';
import 'screens/shared/role_switcher_screen.dart';
import 'screens/shared/courier_verification_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const TezKetKazApp());
}

class TezKetKazApp extends StatefulWidget {
  const TezKetKazApp({super.key});
  @override
  State<TezKetKazApp> createState() => _TezKetKazAppState();
}

class _TezKetKazAppState extends State<TezKetKazApp> {
  final _auth = AuthProvider();
  final _cart = CartProvider();
  final _orders = OrderProvider();
  final _courier = CourierStateProvider();
  late final GoRouter _router = _buildRouter(_auth);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _cart),
        ChangeNotifierProvider.value(value: _orders),
        ChangeNotifierProvider.value(value: _courier),
      ],
      child: MaterialApp.router(
        title: 'TezKetKaz',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }

  GoRouter _buildRouter(AuthProvider auth) => GoRouter(
    refreshListenable: auth,
    initialLocation: '/splash',
    redirect: (context, state) {
      final isAuth = auth.isAuthenticated;
      final loc = state.matchedLocation;
      final isOnAuth = loc.startsWith('/auth') || loc == '/splash';
      if (!isAuth && !isOnAuth) return '/auth/login';
      if (isAuth && loc == '/splash') {
        if (auth.user?.name == null) return '/auth/name';
        return _homeForRole(auth);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/auth/otp', builder: (_, s) => OtpScreen(phone: s.extra as String? ?? '')),
      GoRoute(path: '/auth/name', builder: (_, __) => const NameScreen()),
      GoRoute(path: '/switch-role', builder: (_, __) => const RoleSwitcherScreen()),
      GoRoute(path: '/courier-verification', builder: (_, __) => const CourierVerificationScreen()),

      ShellRoute(
        builder: (_, __, child) => BuyerShell(child: child),
        routes: [
          GoRoute(path: '/buyer', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/buyer/shops', builder: (_, __) => const ShopsScreen()),
          GoRoute(
            path: '/buyer/catalog/:category',
            builder: (_, s) {
              final extra = s.extra is Map<String, dynamic>
                  ? s.extra as Map<String, dynamic>
                  : const <String, dynamic>{};
              return CatalogScreen(
                category: s.pathParameters['category'] ?? 'all',
                shopId: extra['shopId'] as String?,
                shopName: extra['shopName'] as String?,
              );
            },
          ),
          GoRoute(path: '/buyer/cart', builder: (_, __) => const CartScreen()),
          GoRoute(path: '/buyer/orders', builder: (_, __) => const BuyerOrdersScreen()),
          GoRoute(path: '/buyer/tracking/:orderId', builder: (_, s) => TrackingScreen(orderId: s.pathParameters['orderId'] ?? '')),
          GoRoute(path: '/buyer/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/buyer/address-book', builder: (_, __) => const AddressBookScreen()),
        ],
      ),

      ShellRoute(
        builder: (_, __, child) => CourierShell(child: child),
        routes: [
          GoRoute(path: '/courier', builder: (_, __) => const CourierHomeScreen()),
          GoRoute(path: '/courier/order/:orderId', builder: (_, s) => ActiveOrderScreen(orderId: s.pathParameters['orderId'] ?? '')),
          GoRoute(path: '/courier/earnings', builder: (_, __) => const EarningsScreen()),
          GoRoute(path: '/courier/profile', builder: (_, __) => const CourierProfileScreen()),
        ],
      ),

      ShellRoute(
        builder: (_, __, child) => ShopShell(child: child),
        routes: [
          GoRoute(path: '/shop', builder: (_, __) => const ShopOrdersScreen()),
          GoRoute(path: '/shop/products', builder: (_, __) => const ShopProductsScreen()),
          GoRoute(path: '/shop/history', builder: (_, __) => const ShopHistoryScreen()),
          GoRoute(path: '/shop/profile', builder: (_, __) => const ShopProfileScreen()),
        ],
      ),
    ],
  );

  String _homeForRole(AuthProvider auth) {
    switch (auth.user?.activeRole) {
      case UserRole.courier: return '/courier';
      case UserRole.shop: return '/shop';
      default: return '/buyer';
    }
  }
}
