/// Promo / coupon model. Maps the backend response shape from
/// `GET /api/coupons/me/eligible` and `POST /api/coupons/validate`.
class Coupon {
  final String id;
  final String code;
  /// One of: `percent`, `fixed`, `freeDelivery`.
  final String type;
  /// Numeric value of the discount (percent if type == 'percent', otherwise UZS).
  final num value;
  final num? minSubtotal;
  final num? maxDiscount;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String? shopId;
  final String? vertical;
  final String? title;
  final String? description;
  final List<String>? conditions;
  final int? maxUses;
  final int? usesLeft;

  const Coupon({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    this.minSubtotal,
    this.maxDiscount,
    this.validFrom,
    this.validUntil,
    this.shopId,
    this.vertical,
    this.title,
    this.description,
    this.conditions,
    this.maxUses,
    this.usesLeft,
  });

  factory Coupon.fromJson(Map<String, dynamic> j) => Coupon(
        id: (j['id'] ?? j['_id'] ?? j['code'] ?? '').toString(),
        code: (j['code'] ?? '').toString(),
        // Backend stores type as PERCENT/FIXED/FREE_DELIVERY (uppercase).
        // Normalize to the lowercase camelCase the UI helpers expect.
        type: _normalizeType(j['type']),
        value: (j['value'] as num?) ?? (j['discount'] as num?) ?? 0,
        minSubtotal: (j['minSubtotal'] as num?) ?? (j['minOrder'] as num?),
        maxDiscount: j['maxDiscount'] as num?,
        validFrom: j['validFrom'] != null
            ? DateTime.tryParse(j['validFrom'].toString())
            : null,
        validUntil: j['validUntil'] != null
            ? DateTime.tryParse(j['validUntil'].toString())
            : null,
        shopId: j['shopId'] as String?,
        vertical: j['vertical'] as String?,
        title: j['title'] as String?,
        description: j['description'] as String?,
        conditions: (j['conditions'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        maxUses: (j['maxUses'] as num?)?.toInt(),
        usesLeft: (j['usesLeft'] as num?)?.toInt(),
      );

  static String _normalizeType(dynamic raw) {
    final s = (raw ?? '').toString();
    switch (s.toUpperCase()) {
      case 'PERCENT':
        return 'percent';
      case 'FIXED':
        return 'fixed';
      case 'FREE_DELIVERY':
      case 'FREEDELIVERY':
        return 'freeDelivery';
      default:
        return s.isEmpty ? 'percent' : s;
    }
  }

  /// Human-friendly discount string ("-15%", "-20 000 so'm", "Bepul yetkazib").
  String get discountLabel {
    switch (type) {
      case 'percent':
        return '-${value.toString()}%';
      case 'fixed':
        final v = value.toInt();
        final formatted = v.toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
        return "-$formatted so'm";
      case 'freeDelivery':
        return 'Bepul yetkazib berish';
      default:
        return value.toString();
    }
  }

  String get typeIcon {
    switch (type) {
      case 'percent':
        return '%';
      case 'fixed':
        return '₸';
      case 'freeDelivery':
        return '🛵';
      default:
        return '🎁';
    }
  }
}
