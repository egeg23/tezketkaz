import '../models/money.dart';
import 'api_client.dart';

/// Phase 7.2 — buyer subscription tiers.
///
/// Mirrors the backend `Membership` row exposed by `/api/membership/*`.
/// Tier values: `'plus'` | `'pro'`.
/// Billing periods: `'monthly'` | `'yearly'`.
/// Status values: `'active'` | `'cancelled'` | `'expired'` | `'pending'`.
class Membership {
  final String tier;            // plus | pro
  final String status;          // active | cancelled | expired | pending
  final String billingPeriod;   // monthly | yearly
  final String currency;        // UZS | KZT | KGS | RUB
  final num periodAmount;
  final DateTime? currentPeriodEnd;
  final bool autoRenew;
  final String? paymentMethodId;

  const Membership({
    required this.tier,
    required this.status,
    required this.billingPeriod,
    required this.currency,
    required this.periodAmount,
    this.currentPeriodEnd,
    this.autoRenew = true,
    this.paymentMethodId,
  });

  bool get isActive => status == 'active';
  bool get isCancelledButValid =>
      status == 'cancelled' &&
      currentPeriodEnd != null &&
      currentPeriodEnd!.isAfter(DateTime.now());

  Money get periodMoney => Money(periodAmount, currency);

  factory Membership.fromJson(Map<String, dynamic> j) {
    final period = j['periodAmount'];
    final num amount = period is num
        ? period
        : (period is Map ? (period['amount'] as num? ?? 0) : 0);
    final String currency = j['currency'] as String? ??
        (period is Map ? (period['currency'] as String? ?? 'UZS') : 'UZS');
    return Membership(
      tier: (j['tier'] as String?) ?? 'plus',
      status: (j['status'] as String?) ?? 'active',
      billingPeriod: (j['billingPeriod'] as String?) ?? 'monthly',
      currency: currency,
      periodAmount: amount,
      currentPeriodEnd: j['currentPeriodEnd'] != null
          ? DateTime.tryParse(j['currentPeriodEnd'] as String)
          : null,
      autoRenew: j['autoRenew'] as bool? ?? true,
      paymentMethodId: j['paymentMethod'] is Map
          ? (j['paymentMethod'] as Map)['id'] as String?
          : j['paymentMethodId'] as String?,
    );
  }
}

/// Pricing payload returned from `/api/membership/pricing`.
///
/// Layout: `{plus: {monthly: Money, yearly: Money}, pro: {monthly, yearly}}`
class MembershipPricing {
  final Map<String, Map<String, Money>> tiers;
  const MembershipPricing(this.tiers);

  Money? priceFor(String tier, String period) =>
      tiers[tier]?[period];

  factory MembershipPricing.fromJson(Map<String, dynamic> j) {
    final out = <String, Map<String, Money>>{};
    for (final tier in const ['plus', 'pro']) {
      final tierJson = j[tier];
      if (tierJson is Map) {
        final inner = <String, Money>{};
        for (final period in const ['monthly', 'yearly']) {
          final p = tierJson[period];
          if (p != null) {
            inner[period] = Money.fromJson(p);
          }
        }
        if (inner.isNotEmpty) out[tier] = inner;
      }
    }
    return MembershipPricing(out);
  }
}

class MembershipApi {
  MembershipApi._();
  static final MembershipApi instance = MembershipApi._();

  final _api = ApiClient.instance;

  /// Returns `null` when buyer has no membership row at all.
  Future<Membership?> me() async {
    final res = await _api.get('/api/membership/me');
    final data = res.data;
    if (data == null) return null;
    if (data is Map && data.isEmpty) return null;
    // Backend wraps as `{membership: null|{...}, isActive, benefits, nextChargeAt}`.
    // Explicitly check the `membership` key — when null we have no row, even
    // though the wrapper itself is non-empty.
    if (data is Map && data.containsKey('membership')) {
      final inner = data['membership'];
      if (inner == null) return null;
      return Membership.fromJson(Map<String, dynamic>.from(inner as Map));
    }
    return Membership.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<MembershipPricing> pricing() async {
    final res = await _api.get('/api/membership/pricing');
    final raw = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    // Backend shape: `{country, pricing: {plus: {monthly, yearly}, pro: {...}}, benefits, available}`.
    // Unwrap the `pricing` envelope; fall back to bare body for older/test shapes.
    final inner = raw['pricing'] is Map
        ? Map<String, dynamic>.from(raw['pricing'] as Map)
        : raw;
    return MembershipPricing.fromJson(inner);
  }

  Future<Membership> subscribe({
    required String tier,
    required String billingPeriod,
    required String paymentMethodId,
  }) async {
    final res = await _api.post('/api/membership/subscribe', {
      'tier': tier,
      'billingPeriod': billingPeriod,
      'paymentMethodId': paymentMethodId,
    });
    final payload = res.data is Map && res.data['membership'] != null
        ? res.data['membership']
        : res.data;
    return Membership.fromJson(Map<String, dynamic>.from(payload as Map));
  }

  Future<Membership> cancel({String? reason}) async {
    final res = await _api.post('/api/membership/cancel', {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    final payload = res.data is Map && res.data['membership'] != null
        ? res.data['membership']
        : res.data;
    return Membership.fromJson(Map<String, dynamic>.from(payload as Map));
  }

  Future<Membership> reactivate() async {
    final res = await _api.post('/api/membership/reactivate');
    final payload = res.data is Map && res.data['membership'] != null
        ? res.data['membership']
        : res.data;
    return Membership.fromJson(Map<String, dynamic>.from(payload as Map));
  }
}
