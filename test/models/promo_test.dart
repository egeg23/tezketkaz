import 'package:flutter_test/flutter_test.dart';
import 'package:tezketkaz/models/promo.dart';

void main() {
  group('Coupon._normalizeType', () {
    test('normalises uppercase backend types', () {
      expect(
        Coupon.fromJson({'id': 'c1', 'code': 'X', 'type': 'PERCENT', 'value': 10}).type,
        'percent',
      );
      expect(
        Coupon.fromJson({'id': 'c2', 'code': 'X', 'type': 'FIXED', 'value': 5000}).type,
        'fixed',
      );
      expect(
        Coupon.fromJson({'id': 'c3', 'code': 'X', 'type': 'FREE_DELIVERY', 'value': 0}).type,
        'freeDelivery',
      );
    });

    test('accepts "FREEDELIVERY" alias', () {
      final c = Coupon.fromJson({'id': 'c4', 'code': 'X', 'type': 'FREEDELIVERY', 'value': 0});
      expect(c.type, 'freeDelivery');
    });

    test('falls through unknown values', () {
      final c = Coupon.fromJson({'id': 'c5', 'code': 'X', 'type': 'WEIRD', 'value': 1});
      expect(c.type, 'WEIRD');
    });
  });

  group('discountLabel', () {
    test('formats percent', () {
      final c = Coupon.fromJson({'id': '1', 'code': 'X', 'type': 'PERCENT', 'value': 15});
      expect(c.discountLabel, '-15%');
    });

    test('formats fixed amount with thousand separators', () {
      final c = Coupon.fromJson({'id': '1', 'code': 'X', 'type': 'FIXED', 'value': 20000});
      expect(c.discountLabel, "-20 000 so'm");
    });

    test('formats free delivery', () {
      final c = Coupon.fromJson({'id': '1', 'code': 'X', 'type': 'FREE_DELIVERY', 'value': 0});
      expect(c.discountLabel, 'Bepul yetkazib berish');
    });
  });

  group('fromJson legacy fields', () {
    test('reads value from legacy "discount" alias', () {
      final c = Coupon.fromJson({'id': '1', 'code': 'X', 'type': 'PERCENT', 'discount': 25});
      expect(c.value, 25);
    });

    test('reads minSubtotal from legacy "minOrder"', () {
      final c = Coupon.fromJson({
        'id': '1',
        'code': 'X',
        'type': 'PERCENT',
        'value': 10,
        'minOrder': 50000,
      });
      expect(c.minSubtotal, 50000);
    });
  });
}
