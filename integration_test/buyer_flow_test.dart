// Buyer happy-path integration test (sketch).
//
// Drives the app from auth screen → shop pick → cart → tracking. Some of the
// glue between this test and the backend stubs still needs to be wired up; see
// `// TODO:` markers below.
//
// Run with:
//   flutter test integration_test/buyer_flow_test.dart \
//     --dart-define=DEMO_AUTOLOGIN=true
//
// `DEMO_AUTOLOGIN=true` is expected to make the backend accept "0000" as a
// universal OTP code.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tezketkaz/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Buyer happy path: login → pick shop → checkout → tracking',
      (tester) async {
    app.main();
    // Allow firebase / async init to settle.
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 1. Should land on auth/login screen when unauthenticated.
    // TODO: wire to actual backend mock — for now we only smoke-test that the
    // app boots and shows *something* clickable.
    expect(find.byType(MaterialApp), findsOneWidget);

    // 2. Enter phone, send OTP, type "0000", verify.
    final phoneField = find.byType(TextField).first;
    if (phoneField.evaluate().isNotEmpty) {
      await tester.enterText(phoneField, '+998901234567');
      await tester.pumpAndSettle();
      // TODO: tap the actual "Send OTP" button (text varies by locale).
      // await tester.tap(find.text('SMS kod olish'));
      // await tester.pumpAndSettle();
      // await tester.enterText(find.byType(TextField).first, '0000');
      // await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // 3. Tap shops tab and pick first shop.
    // TODO: depends on bottom nav being visible. The shell uses GoRouter.
    // final shopsTab = find.byIcon(Icons.storefront_outlined);
    // if (shopsTab.evaluate().isNotEmpty) {
    //   await tester.tap(shopsTab);
    //   await tester.pumpAndSettle();
    //   final firstShop = find.byType(Card).first;
    //   await tester.tap(firstShop);
    //   await tester.pumpAndSettle();
    // }

    // 4. Add product to cart.
    // TODO: tap a "+" on the first ProductCard.
    // final addButton = find.byIcon(Icons.add).first;
    // await tester.tap(addButton);
    // await tester.pumpAndSettle();

    // 5. Open cart, set delivery address, place order.
    // TODO: navigate to /buyer/cart and tap the place-order CTA after picking
    // an address from the address book.
    // await tester.tap(find.text('Buyurtma berish'));
    // await tester.pumpAndSettle(const Duration(seconds: 3));

    // 6. Land on tracking screen.
    // TODO: assert tracking screen is now visible by looking for the route
    // (TrackingScreen widget) or a known string like "Buyurtma yetkazilmoqda".
    // expect(find.byType(TrackingScreen), findsOneWidget);
  });
}
