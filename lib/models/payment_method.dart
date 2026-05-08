/// Phase 6 — saved payment method (Click / Payme / Uzum / cash).
///
/// Mirrors the backend `PaymentMethod` row exposed via
/// `GET /api/payment-methods/me`. Brand (visa / mastercard / uzcard / humo)
/// drives which icon is rendered, and `last4` + `expiry*` live independently
/// because cash entries don't have either.
class PaymentMethod {
  final String id;
  final String provider; // click | payme | uzum | cash
  final String? brand;   // visa | mastercard | uzcard | humo
  final String? last4;
  final int? expiryMonth;
  final int? expiryYear;
  final bool isDefault;

  const PaymentMethod({
    required this.id,
    required this.provider,
    this.brand,
    this.last4,
    this.expiryMonth,
    this.expiryYear,
    this.isDefault = false,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> j) => PaymentMethod(
        id: j['id'] as String,
        provider: (j['provider'] as String?) ?? 'click',
        brand: j['brand'] as String?,
        last4: j['last4'] as String?,
        expiryMonth: (j['expiryMonth'] as num?)?.toInt(),
        expiryYear: (j['expiryYear'] as num?)?.toInt(),
        isDefault: j['isDefault'] as bool? ?? false,
      );

  /// Pretty masked card label e.g. "•••• 1234" or "Naqd pul" for cash.
  String get displayLabel {
    if (provider == 'cash') return 'Naqd pul';
    if (last4 != null && last4!.isNotEmpty) return '•••• $last4';
    return provider;
  }

  /// Best-effort brand → emoji fallback. Real assets land in Phase 7.
  String get brandEmoji {
    switch ((brand ?? provider).toLowerCase()) {
      case 'visa':
        return '💳';
      case 'mastercard':
        return '💳';
      case 'uzcard':
        return '🟦';
      case 'humo':
        return '🟩';
      case 'click':
        return '💳';
      case 'payme':
        return '💜';
      case 'uzum':
        return '🟪';
      case 'cash':
        return '💵';
      default:
        return '💳';
    }
  }

  String get providerName {
    switch (provider) {
      case 'click':
        return 'Click';
      case 'payme':
        return 'Payme';
      case 'uzum':
        return 'Uzum Pay';
      case 'cash':
        return 'Naqd pul';
      default:
        return provider;
    }
  }
}
