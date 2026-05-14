import 'package:firebase_core/firebase_core.dart';
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
import 'providers/theme_provider.dart';

import 'screens/auth/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/name_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/onboarding/role_selection_screen.dart';
import 'screens/buyer/buyer_shell.dart';
import 'screens/buyer/home_screen.dart';
import 'screens/buyer/catalog_screen.dart';
import 'screens/buyer/cart_screen.dart';
import 'screens/buyer/country_settings_screen.dart';
import 'screens/buyer/data_privacy_screen.dart';
import 'screens/buyer/favorites_screen.dart';
import 'screens/buyer/group_order_screen.dart';
import 'screens/buyer/group_order_join_screen.dart';
import 'screens/buyer/orders_screen.dart';
import 'screens/buyer/subscription_screen.dart';
import 'screens/buyer/support_inbox_screen.dart';
import 'screens/buyer/support_new_ticket_screen.dart';
import 'screens/buyer/support_thread_screen.dart';
import 'screens/buyer/tracking_screen.dart';
import 'screens/buyer/order_success_screen.dart';
import 'screens/buyer/notifications_screen.dart';
import 'screens/buyer/profile_screen.dart';
import 'screens/buyer/shops_screen.dart';
import 'screens/buyer/shop_detail_screen.dart';
import 'screens/buyer/address_book_screen.dart';
import 'screens/buyer/address_picker_screen.dart';
import 'screens/buyer/payment_methods_screen.dart';
import 'screens/buyer/promo_screen.dart';
import 'screens/buyer/loyalty_screen.dart';
import 'screens/courier/courier_shell.dart';
import 'screens/courier/courier_home_screen.dart';
import 'screens/courier/active_order_screen.dart';
import 'screens/courier/earnings_screen.dart';
import 'screens/courier/performance_screen.dart';
import 'screens/courier/courier_profile_screen.dart';
import 'screens/courier/heatmap_screen.dart';
import 'screens/shop/shop_shell.dart';
import 'screens/shop/shop_orders_screen.dart';
import 'screens/shop/shop_other_screens.dart';
import 'screens/shop/shop_products_screen.dart';
import 'screens/shop/shop_settings_screen.dart';
import 'screens/shop/shop_refunds_screen.dart';
import 'screens/shop/shop_promo_screen.dart';
import 'screens/shop/shop_analytics_screen.dart';
import 'screens/shared/role_switcher_screen.dart';
import 'screens/shared/courier_verification_screen.dart';
import 'screens/shared/chat_screen.dart';
import 'screens/shared/legal_screen.dart';
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
  final _theme = ThemeProvider();
  late final GoRouter _router = _buildRouter(_auth);

  StreamSubscription<dynamic>? _pushTapSub;

  @override
  void initState() {
    super.initState();
    // Phase 10.3 — load persisted theme preference (best-effort; defaults to
    // ThemeMode.system so the first frame uses the OS palette).
    _theme.load();
    // Phase 6 — deep-link FCM taps into the right screen. The push service
    // exposes `onTap` which fires for foreground / background / cold-start
    // notifications.
    _pushTapSub = PushService.instance.onTap.listen((msg) {
      try {
        final data = msg.data;
        final type = data['type']?.toString();
        final orderId = data['orderId']?.toString();
        // Phase 10.1 — group invite deep-link (push payloads can carry a
        // `joinCode` for "joined the group" notifications).
        final joinCode = data['joinCode']?.toString();
        final groupId = data['groupId']?.toString();
        if (groupId != null && groupId.isNotEmpty) {
          _router.go('/buyer/group/$groupId');
          return;
        }
        if (joinCode != null && joinCode.isNotEmpty) {
          _router.go('/buyer/group/join', extra: joinCode);
          return;
        }
        if (type == null) return;
        if (type == 'chat_message' && orderId != null && orderId.isNotEmpty) {
          _router.go('/order/$orderId/chat');
        } else if (type == 'promo') {
          _router.go('/buyer/promo');
        } else if (type == 'support_message') {
          // Phase 10.2 — admin replied to a ticket.
          final ticketId = data['ticketId']?.toString();
          if (ticketId != null && ticketId.isNotEmpty) {
            _router.go('/buyer/support/$ticketId');
          } else {
            _router.go('/buyer/support');
          }
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
        ChangeNotifierProvider.value(value: _theme),
      ],
      // AnimatedBuilder rebuilds MaterialApp.router whenever the theme
      // provider notifies — that way toggling Auto/Light/Dark from the
      // profile screen takes effect immediately without a hot restart.
      child: AnimatedBuilder(
        animation: _theme,
        builder: (_, __) => MaterialApp.router(
          title: 'TezKetKaz',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _theme.themeMode,
          routerConfig: _router,
        ),
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
      // Phase 12 — /legal renders Privacy + Terms which the buyer must be
      // able to read BEFORE creating an account. Allow it for everyone.
      final isPublic = loc == '/legal';
      final isOnboarding = loc == '/onboarding';
      final isOnRoleSelect = loc == '/select-role';
      // Onboarding is a post-login screen; bounce unauth'd users to login
      // even when they deep-link straight to /onboarding.
      if (!isAuth && !isOnAuth && !isPublic) return '/auth/login';
      if (isAuth && loc == '/splash') {
        if (auth.user?.name == null) return '/auth/name';
        // Phase 13.2.3 — first-run role selection happens between name entry
        // and the onboarding tutorial / role-specific shell.
        if (auth.needsRoleSelection) return '/select-role';
        if (_needsOnboarding(auth)) return '/onboarding';
        return _homeForRole(auth);
      }
      // Phase 13.2.3 — once the user types their name, force the role
      // selector before any of the role-specific shells take over.
      if (isAuth &&
          auth.needsRoleSelection &&
          !isOnRoleSelect &&
          !isOnAuth &&
          !isPublic) {
        return '/select-role';
      }
      // Already-selected users shouldn't get stuck on /select-role.
      if (isAuth && isOnRoleSelect && !auth.needsRoleSelection) {
        return _homeForRole(auth);
      }
      // Phase 11 — buyers without `onboardedAt` get bounced into the
      // tutorial the first time they try to enter the buyer shell.
      if (isAuth &&
          loc.startsWith('/buyer') &&
          _needsOnboarding(auth)) {
        return '/onboarding';
      }
      // Already-onboarded users shouldn't get stuck on /onboarding (e.g.
      // after deep-link). Bounce them home.
      if (isAuth && isOnboarding && !_needsOnboarding(auth)) {
        return _homeForRole(auth);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/auth/otp', builder: (_, s) => OtpScreen(phone: s.extra as String? ?? '')),
      GoRoute(path: '/auth/name', builder: (_, __) => const NameScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      // Phase 13.2.3 — first-run role selection (buyer / courier / shop).
      GoRoute(path: '/select-role', builder: (_, __) => const RoleSelectionScreen()),
      GoRoute(path: '/switch-role', builder: (_, __) => const RoleSwitcherScreen()),
      GoRoute(path: '/courier-verification', builder: (_, __) => const CourierVerificationScreen()),
      // Phase 12 — read-only Privacy / Terms viewer (tabbed). Auth-agnostic so
      // store reviewers can reach it from the profile screen / consent links.
      GoRoute(path: '/legal', builder: (_, __) => const LegalScreen()),
      GoRoute(
        path: '/buyer/order-success/:orderId',
        builder: (_, s) => OrderSuccessScreen(orderId: s.pathParameters['orderId'] ?? ''),
      ),

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

      // Phase 10.1 — group orders. Modal-style screens; no shell so the buyer
      // can deep-link into a group from a share link without our bottom nav.
      GoRoute(
        path: '/buyer/group/join',
        builder: (_, s) => GroupOrderJoinScreen(
          // The push handler / link parser passes the join code as `extra`.
          initialCode: s.extra is String ? s.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/buyer/group/:groupId',
        builder: (_, s) => GroupOrderScreen(
          groupId: s.pathParameters['groupId'] ?? '',
        ),
      ),

      // Phase 10.2 — support inbox / threads / new ticket.
      GoRoute(
        path: '/buyer/support',
        builder: (_, __) => const SupportInboxScreen(),
      ),
      GoRoute(
        path: '/buyer/support/new',
        builder: (_, __) => const SupportNewTicketScreen(),
      ),
      GoRoute(
        path: '/buyer/support/:ticketId',
        builder: (_, s) => SupportThreadScreen(
          ticketId: s.pathParameters['ticketId'] ?? '',
        ),
      ),

      ShellRoute(
        builder: (_, __, child) => BuyerShell(child: child),
        routes: [
          GoRoute(path: '/buyer', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/buyer/shops', builder: (_, __) => const ShopsScreen()),
          GoRoute(
            path: '/buyer/shop/:shopId',
            builder: (_, s) {
              final extra = s.extra is Map<String, dynamic>
                  ? s.extra as Map<String, dynamic>
                  : const <String, dynamic>{};
              return ShopDetailScreen(
                shopId: s.pathParameters['shopId'] ?? '',
                shopName: extra['shopName'] as String?,
              );
            },
          ),
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
          GoRoute(path: '/buyer/notifications', builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/buyer/address-picker',
              builder: (_, s) => AddressPickerScreen(
                initial: s.extra is Map<String, dynamic> && (s.extra as Map)['lat'] != null
                    ? null
                    : null,
              )),
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
          // Phase 13.2.8 — full-screen demand heatmap.
          GoRoute(path: '/courier/heatmap', builder: (_, __) => const HeatmapScreen()),
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
          // Phase 13.2.6 — new shop ops screens.
          GoRoute(path: '/shop/refunds', builder: (_, __) => const ShopRefundsScreen()),
          GoRoute(path: '/shop/promo', builder: (_, __) => const ShopPromoScreen()),
          GoRoute(path: '/shop/analytics', builder: (_, __) => const ShopAnalyticsScreen()),
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

  // Phase 11 — only buyers see the tutorial; couriers / shop owners skip it.
  bool _needsOnboarding(AuthProvider auth) {
    final u = auth.user;
    if (u == null) return false;
    if (u.activeRole != UserRole.buyer) return false;
    return u.onboardedAt == null;
  }
}
