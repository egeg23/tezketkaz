import 'package:flutter_test/flutter_test.dart';
import 'package:tezketkaz/models/models.dart';
import 'package:tezketkaz/providers/cart_provider.dart';

Product _product({
  String id = 'p1',
  String shopId = 's1',
  double price = 10000,
}) =>
    Product(
      id: id,
      name: 'Pizza',
      nameUz: 'Pitsa',
      price: price,
      unit: 'pcs',
      category: 'food',
      imageUrl: '',
      shopId: shopId,
    );

void main() {
  group('CartProvider basic add/remove', () {
    test('add increments quantity for the same product', () {
      final cart = CartProvider(autoLoad: false);
      expect(cart.add(_product()), true);
      expect(cart.add(_product()), true);
      expect(cart.itemCount, 2);
      expect(cart.lines, hasLength(1));
    });

    test('remove decrements then deletes the line', () {
      final cart = CartProvider(autoLoad: false);
      cart.add(_product());
      cart.add(_product());
      cart.remove('p1');
      expect(cart.itemCount, 1);
      cart.remove('p1');
      expect(cart.isEmpty, true);
    });

    test('multi-shop drafts keep each shop in its own bucket (Phase 11)', () {
      final cart = CartProvider(autoLoad: false);
      expect(cart.add(_product(shopId: 's1')), true);
      // Mixing shops no longer fails — the second shop opens its own draft
      // and becomes the active one.
      expect(cart.add(_product(id: 'p2', shopId: 's2')), true);
      expect(cart.activeShopId, 's2');
      expect(cart.drafts, hasLength(2));
    });
  });

  group('CartLine keying with modifiers', () {
    test('same product with different modifier sets makes two lines', () {
      final cart = CartProvider(autoLoad: false);
      final p = _product();

      cart.addWithModifiers(
        p,
        1,
        const [
          CartModifierSelection(groupId: 'g1', optionIds: ['o1']),
        ],
        12000,
      );
      cart.addWithModifiers(
        p,
        1,
        const [
          CartModifierSelection(groupId: 'g1', optionIds: ['o2']),
        ],
        15000,
      );

      expect(cart.lines, hasLength(2));
      expect(cart.itemCount, 2);
    });

    test('same product with same modifiers merges into one line', () {
      final cart = CartProvider(autoLoad: false);
      final p = _product();

      cart.addWithModifiers(p, 1, const [
        CartModifierSelection(groupId: 'g1', optionIds: ['o1', 'o2']),
      ], 10000);
      cart.addWithModifiers(p, 2, const [
        // Different ordering, same option set — should merge.
        CartModifierSelection(groupId: 'g1', optionIds: ['o2', 'o1']),
      ], 10000);

      expect(cart.lines, hasLength(1));
      expect(cart.lines.first.quantity, 3);
    });

    test('quantityOf sums across modifier variants', () {
      final cart = CartProvider(autoLoad: false);
      final p = _product();
      cart.addWithModifiers(p, 2, const [
        CartModifierSelection(groupId: 'g1', optionIds: ['o1']),
      ], 1000);
      cart.addWithModifiers(p, 1, const [
        CartModifierSelection(groupId: 'g1', optionIds: ['o2']),
      ], 1000);
      expect(cart.quantityOf('p1'), 3);
    });
  });

  group('CartProvider scheduling + promo', () {
    test('setCouponCode treats empty string as null', () {
      final cart = CartProvider(autoLoad: false);
      // Phase 11 — couponCode lives on per-shop meta, so the cart needs at
      // least one active shop before the setter has anywhere to write to.
      cart.add(_product());
      cart.setCouponCode('PROMO');
      expect(cart.couponCode, 'PROMO');
      cart.setCouponCode('');
      expect(cart.couponCode, isNull);
    });

    test('setLoyaltyPoints clamps negative input to 0', () {
      final cart = CartProvider(autoLoad: false);
      cart.add(_product());
      cart.setLoyaltyPoints(-10);
      expect(cart.loyaltyPoints, 0);
      cart.setLoyaltyPoints(50);
      expect(cart.loyaltyPoints, 50);
    });
  });
}
