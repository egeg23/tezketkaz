import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'dart:async';

import 'firebase_options.dart';
import 'services/push_service.dart';
import 'services/sentry_service.dart';
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
import 'screens/buyer/country_settings_screen.dart';
import 'screens/buyer/data_privacy_screen.dart';
import 'screens/buyer/favorites_screen.dart';
import 'screens/buyer/orders_screen.dart';
import 'screens/buyer/subscription_screen.dart';
import 'screens/buyer/tracking_screen.dart';
import 'screens/buyer/profile_screen.dart';
import 'screens/buyer/shops_screen.dart';
import 'screens/buyer/address_book_screen.dart';
import 'screens/buyer/payment_methods_screen.dart';
import 'screens/buyer/promo_screen.dart';
import 'screens/buyer/loyalty_screen.dart';
import 'screens/courier/courier_shell.dart';
import 'screens/courier/courier_home_screen.dart';
import 'screens/courier/active_order_screen.dart';
import 'screens/courier/earnings_screen.dart';
import 'screens/courier/performance_screen.dart';
import 'screens/courier/courier_profile_screen.dart';
import 'screens/shop/shop_shell.dart';
import 'screens/shop/shop_orders_screen.dart';
import 'screens/shop/shop_other_screens.dart';
import 'screens/shop/shop_products_screen.dart';
import 'screens/shop/shop_settings_screen.dart';
import 'screens/shared/role_switcher_screen.dart';
import 'screens/shared/courier_verification_screen.dart';
import 'screens/shared/chat_screen.dart';
import 'screens/shared/reviews_screen.dart';

Future<void> main() async {
  // SENTRY_DSN is optional. When omitted (local dev) SentryService.init becomes
  // a pass-through and just runs the app directly.
  const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  await SentryService.init(
    () async {
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
    },
    dsn: sentryDsn.isEmpty ? null : sentryDsn,
  );
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

  StreamSubscription<dynamic>? _pushTapSub;

  @override
  void initState() {
    super.initState();
    // Phase 6 — deep-link FCM taps into the right screen. The push service
    // exposes `onTap` which fires for foreground / background / cold-start
    // notifications.
    _pushTapSub = PushService.instance.onTap.listen((msg) {
      try {
        final data = msg.data;
        final type = data['type']?.toString();
        final orderId = data['orderId']?.toString();
        if (type == null) return;
        if (type == 'chat_message' && orderId != null && orderId.isNotEmpty) {
          _router.go('/order/$orderId/chat');
        } else if (type == 'promo') {
          _router.go('/buyer/promo');
        } else if (type.startsWith('order_')) {
          if (orderId != null && orderId.isNotEmpty) {
            _router.go('/buyer/tracking/$orderId');
          } else {
            _router.go('/buyer/orders');
          }
        }
      } catch (_) {
        // Bad payload — silently ignore so a single malformed push doesn't
        // crash the whole app.
      }
    });
  }

  @override
  void dispose() {
    _pushTapSub?.cancel();
    super.dispose();
  }

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

      // Phase 3 — chat / reviews / loyalty / promo (modal screens, no shell).
      GoRoute(
        path: '/order/:orderId/chat',
        builder: (_, s) => ChatScreen(
          orderId: s.pathParameters['orderId'] ?? '',
          receiverName: s.extra is Map
              ? (s.extra as Map)['receiverName'] as String?
              : null,
        ),
      ),
      GoRoute(
        path: '/reviews/:targetType/:targetId',
        builder: (_, s) => ReviewsScreen(
          targetType: s.pathParameters['targetType'] ?? 'shop',
          targetId: s.pathParameters['targetId'] ?? '',
          title: s.extra is String ? s.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/buyer/promo',
        builder: (_, s) {
          final extra = s.extra is Map<String, dynamic>
              ? s.extra as Map<String, dynamic>
              : const <String, dynamic>{};
          return PromoScreen(
            shopId: extra['shopId'] as String?,
            subtotal: extra['subtotal'] as num?,
          );
        },
      ),
      GoRoute(
        path: '/buyer/loyalty',
        builder: (_, __) => const LoyaltyScreen(),
      ),

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
          GoRoute(
            path: '/buyer/payment-methods',
            builder: (_, __) => const PaymentMethodsScreen(),
          ),
          GoRoute(
            path: '/buyer/subscription',
            builder: (_, __) => const SubscriptionScreen(),
          ),
          GoRoute(
            path: '/buyer/favorites',
            builder: (_, __) => const FavoritesScreen(),
          ),
          GoRoute(
            path: '/buyer/country-settings',
            builder: (_, __) => const CountrySettingsScreen(),
          ),
          GoRoute(
            path: '/buyer/data-privacy',
            builder: (_, __) => const DataPrivacyScreen(),
          ),
        ],
      ),

      ShellRoute(
        builder: (_, __, child) => CourierShell(child: child),
        routes: [
          GoRoute(path: '/courier', builder: (_, __) => const CourierHomeScreen()),
          GoRoute(path: '/courier/order/:orderId', builder: (_, s) => ActiveOrderScreen(orderId: s.pathParameters['orderId'] ?? '')),
          GoRoute(path: '/courier/earnings', builder: (_, __) => const EarningsScreen()),
          GoRoute(path: '/courier/performance', builder: (_, __) => const PerformanceScreen()),
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
          GoRoute(path: '/shop/settings', builder: (_, __) => const ShopSettingsScreen()),
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
