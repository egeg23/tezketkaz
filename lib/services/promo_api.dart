import '../models/promo.dart';
import '../models/loyalty.dart';
import 'api_client.dart';

/// Promo / coupon endpoints (Phase 3, Agent A backend).
class PromoApi {
  PromoApi._();
  static final PromoApi instance = PromoApi._();

  final _api = ApiClient.instance;

  /// `POST /api/coupons/validate`
  ///
  /// Returns a record `(valid, discount, reason?)`. When `valid` is false,
  /// `reason` carries the backend message ("expired", "min_subtotal", ...).
  Future<({bool valid, num discount, String? reason})> validate({
    required String code,
    String? shopId,
    String? vertical,
    required num subtotal,
  }) async {
    try {
      final res = await _api.post('/api/coupons/validate', {
        'code': code,
        if (shopId != null) 'shopId': shopId,
        if (vertical != null) 'vertical': vertical,
        'subtotal': subtotal,
      });
      final data = res.data is Map ? res.data as Map : const {};
      return (
        valid: (data['valid'] as bool?) ?? false,
        discount: (data['discount'] as num?) ?? 0,
        reason: data['reason'] as String?,
      );
    } on ApiException catch (e) {
      return (valid: false, discount: 0, reason: e.message);
    }
  }

  /// `GET /api/coupons/me/eligible?shopId=&subtotal=`
  Future<List<Coupon>> myEligible({String? shopId, num? subtotal}) async {
    final res = await _api.get('/api/coupons/me/eligible', query: {
      if (shopId != null) 'shopId': shopId,
      if (subtotal != null) 'subtotal': subtotal,
    });
    final data = res.data;
    final list = (data is List)
        ? data
        : (data is Map && data['coupons'] is List
            ? data['coupons'] as List
            : const []);
    return list
        .map((c) => Coupon.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
  }
}

/// Loyalty endpoints (Phase 3, Agent A backend).
class LoyaltyApi {
  LoyaltyApi._();
  static final LoyaltyApi instance = LoyaltyApi._();

  final _api = ApiClient.instance;

  /// `GET /api/loyalty/me`
  Future<LoyaltyAccount> me() async {
    final res = await _api.get('/api/loyalty/me');
    final data = res.data;
    final m = (data is Map && data['account'] is Map)
        ? Map<String, dynamic>.from(data['account'] as Map)
        : Map<String, dynamic>.from(data as Map);
    return LoyaltyAccount.fromJson(m);
  }

  /// `GET /api/loyalty/me/referral-code`
  Future<String> myReferralCode() async {
    final res = await _api.get('/api/loyalty/me/referral-code');
    final data = res.data;
    if (data is Map) {
      final code = data['referralCode'] ?? data['code'];
      if (code != null) return code.toString();
    }
    return '';
  }

  /// `POST /api/loyalty/me/use-referral`
  Future<void> useReferral(String code) async {
    await _api.post('/api/loyalty/me/use-referral', {'code': code});
  }
}
