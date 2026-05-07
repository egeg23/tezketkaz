/// Loyalty / cashback models matching `GET /api/loyalty/me`.
enum LoyaltyTier { bronze, silver, gold, platinum }

LoyaltyTier loyaltyTierFromString(String? raw) {
  switch (raw) {
    case 'silver':
      return LoyaltyTier.silver;
    case 'gold':
      return LoyaltyTier.gold;
    case 'platinum':
      return LoyaltyTier.platinum;
    case 'bronze':
    default:
      return LoyaltyTier.bronze;
  }
}

extension LoyaltyTierUi on LoyaltyTier {
  String get label {
    switch (this) {
      case LoyaltyTier.bronze:
        return 'Bronze';
      case LoyaltyTier.silver:
        return 'Silver';
      case LoyaltyTier.gold:
        return 'Gold';
      case LoyaltyTier.platinum:
        return 'Platinum';
    }
  }

  String get emoji {
    switch (this) {
      case LoyaltyTier.bronze:
        return '🥉';
      case LoyaltyTier.silver:
        return '🥈';
      case LoyaltyTier.gold:
        return '🥇';
      case LoyaltyTier.platinum:
        return '💎';
    }
  }

  /// Threshold (lifetime UZS spent) needed to enter this tier.
  num get threshold {
    switch (this) {
      case LoyaltyTier.bronze:
        return 0;
      case LoyaltyTier.silver:
        return 500000;
      case LoyaltyTier.gold:
        return 2000000;
      case LoyaltyTier.platinum:
        return 10000000;
    }
  }

  LoyaltyTier? get next {
    switch (this) {
      case LoyaltyTier.bronze:
        return LoyaltyTier.silver;
      case LoyaltyTier.silver:
        return LoyaltyTier.gold;
      case LoyaltyTier.gold:
        return LoyaltyTier.platinum;
      case LoyaltyTier.platinum:
        return null;
    }
  }
}

class LoyaltyTransaction {
  final String id;
  final String reason;
  final num delta;
  final String? type; // 'earn' / 'spend' / 'cashback' / 'referral'
  final DateTime createdAt;

  const LoyaltyTransaction({
    required this.id,
    required this.reason,
    required this.delta,
    this.type,
    required this.createdAt,
  });

  factory LoyaltyTransaction.fromJson(Map<String, dynamic> j) =>
      LoyaltyTransaction(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        reason: (j['reason'] ?? j['description'] ?? '').toString(),
        delta: (j['delta'] as num?) ?? (j['amount'] as num?) ?? 0,
        type: j['type'] as String?,
        createdAt: DateTime.tryParse(
                (j['createdAt'] ?? j['date'] ?? '').toString()) ??
            DateTime.now(),
      );
}

class LoyaltyAccount {
  final LoyaltyTier tier;
  final num points;
  final num cashback;
  final num lifetimeSpent;
  final List<LoyaltyTransaction> transactions;

  const LoyaltyAccount({
    required this.tier,
    required this.points,
    required this.cashback,
    required this.lifetimeSpent,
    this.transactions = const [],
  });

  factory LoyaltyAccount.fromJson(Map<String, dynamic> j) => LoyaltyAccount(
        tier: loyaltyTierFromString(j['tier']?.toString()),
        points: (j['points'] as num?) ?? 0,
        cashback: (j['cashback'] as num?) ?? 0,
        lifetimeSpent: (j['lifetimeSpent'] as num?) ?? 0,
        transactions: (j['transactions'] as List? ?? const [])
            .map((t) => LoyaltyTransaction.fromJson(
                Map<String, dynamic>.from(t as Map)))
            .toList(),
      );
}
