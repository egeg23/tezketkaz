import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tezketkaz/providers/auth_provider.dart';
import 'package:tezketkaz/providers/cart_provider.dart';
import 'package:tezketkaz/providers/courier_state_provider.dart';
import 'package:tezketkaz/providers/order_provider.dart';

/// Wrap [child] with a MaterialApp + the same MultiProvider stack used by
/// `lib/main.dart`. Pass already-constructed provider instances to inject test
/// fakes; otherwise fresh defaults are created. Used by widget tests.
Widget pumpWithProviders(
  Widget child, {
  AuthProvider? auth,
  CartProvider? cart,
  OrderProvider? orders,
  CourierStateProvider? courier,
  ThemeData? theme,
  Locale? locale,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth ?? AuthProvider()),
      ChangeNotifierProvider<CartProvider>.value(value: cart ?? CartProvider()),
      ChangeNotifierProvider<OrderProvider>.value(value: orders ?? OrderProvider()),
      ChangeNotifierProvider<CourierStateProvider>.value(
        value: courier ?? CourierStateProvider(),
      ),
    ],
    child: MaterialApp(
      theme: theme,
      locale: locale,
      home: Material(child: child),
    ),
  );
}
