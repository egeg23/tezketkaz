import 'package:flutter_test/flutter_test.dart';
import 'package:tezketkaz/models/loyalty.dart';

void main() {
  group('LoyaltyTier thresholds', () {
    test('are monotonically increasing', () {
      const tiers = LoyaltyTier.values;
      for (var i = 1; i < tiers.length; i++) {
        expect(
          tiers[i].threshold,
          greaterThan(tiers[i - 1].threshold),
          reason: '${tiers[i].name} threshold should exceed ${tiers[i - 1].name}',
        );
      }
    });

    test('exact bronze/silver/gold/platinum values', () {
      expect(LoyaltyTier.bronze.threshold, 0);
      expect(LoyaltyTier.silver.threshold, 500000);
      expect(LoyaltyTier.gold.threshold, 2000000);
      expect(LoyaltyTier.platinum.threshold, 10000000);
    });
  });

  group('LoyaltyTier.next', () {
    test('progresses through the chain', () {
      expect(LoyaltyTier.bronze.next, LoyaltyTier.silver);
      expect(LoyaltyTier.silver.next, LoyaltyTier.gold);
      expect(LoyaltyTier.gold.next, LoyaltyTier.platinum);
      expect(LoyaltyTier.platinum.next, isNull);
    });
  });

  group('loyaltyTierFromString', () {
    test('maps known strings', () {
      expect(loyaltyTierFromString('silver'), LoyaltyTier.silver);
      expect(loyaltyTierFromString('gold'), LoyaltyTier.gold);
      expect(loyaltyTierFromString('platinum'), LoyaltyTier.platinum);
      expect(loyaltyTierFromString('bronze'), LoyaltyTier.bronze);
    });

    test('falls back to bronze on null/unknown', () {
      expect(loyaltyTierFromString(null), LoyaltyTier.bronze);
      expect(loyaltyTierFromString('weird'), LoyaltyTier.bronze);
    });
  });

  group('LoyaltyAccount.fromJson', () {
    test('parses with defaults when fields are missing', () {
      final a = LoyaltyAccount.fromJson(<String, dynamic>{});
      expect(a.tier, LoyaltyTier.bronze);
      expect(a.points, 0);
      expect(a.cashback, 0);
      expect(a.lifetimeSpent, 0);
      expect(a.transactions, isEmpty);
    });

    test('parses transactions array', () {
      final a = LoyaltyAccount.fromJson({
        'tier': 'gold',
        'points': 1200,
        'cashback': 5000,
        'lifetimeSpent': 2500000,
        'transactions': [
          {'id': 't1', 'reason': 'order', 'delta': 100, 'type': 'earn'}
        ],
      });
      expect(a.tier, LoyaltyTier.gold);
      expect(a.transactions, hasLength(1));
      expect(a.transactions.first.delta, 100);
    });
  });
}
