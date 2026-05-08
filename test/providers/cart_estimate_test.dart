import 'package:flutter_test/flutter_test.dart';
import 'package:tezketkaz/providers/cart_provider.dart';

void main() {
  group('CartEstimate.fromJson', () {
    test('parses full Phase 3 payload with discounts', () {
      final est = CartEstimate.fromJson({
        'subtotal': 100000,
        'deliveryFee': 12000,
        'total': 95000,
        'minOrder': 50000,
        'minOrderMet': true,
        'distanceKm': 2.5,
        'etaMinutes': 35,
        'surgeFactor': 1.2,
        'surgeReason': 'rain',
        'zoneId': 'z1',
        'outOfZone': false,
        'couponDiscount': 10000,
        'loyaltyDiscount': 7000,
      });
      expect(est.subtotal, 100000);
      expect(est.couponDiscount, 10000);
      expect(est.loyaltyDiscount, 7000);
      expect(est.surgeReason, 'rain');
      expect(est.outOfZone, false);
    });

    test('legacy "discount" field maps onto couponDiscount when no couponDiscount', () {
      final est = CartEstimate.fromJson({
        'subtotal': 50000,
        'deliveryFee': 0,
        'total': 45000,
        'minOrder': 0,
        'minOrderMet': true,
        'discount': 5000,
      });
      expect(est.couponDiscount, 5000);
      expect(est.loyaltyDiscount, 0);
    });

    test('uses sensible defaults when fields missing', () {
      final est = CartEstimate.fromJson(<String, dynamic>{});
      expect(est.subtotal, 0);
      expect(est.minOrderMet, true);
      expect(est.surgeFactor, 1.0);
      expect(est.outOfZone, false);
    });
  });

  group('CartEstimate.copyWith', () {
    test('toggles outOfZone without changing other fields', () {
      final est = CartEstimate.fromJson({
        'subtotal': 100,
        'deliveryFee': 10,
        'total': 110,
        'minOrder': 0,
        'minOrderMet': true,
      });
      final flipped = est.copyWith(outOfZone: true);
      expect(flipped.outOfZone, true);
      expect(flipped.subtotal, est.subtotal);
      expect(flipped.deliveryFee, est.deliveryFee);
    });
  });
}
