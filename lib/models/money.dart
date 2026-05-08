/// Phase 6 — multi-currency framework on the Flutter side. Mirrors
/// `backend/src/lib/money.js`. UZS is the only active currency at launch;
/// KZT/KGS activate in Phase 7.
class Money {
  final num amount;
  final String currency;

  const Money(this.amount, [this.currency = 'UZS']);

  /// Parse from any of:
  /// - `{amount, currency, formatted?}` (Phase 6 backend canonical shape)
  /// - bare number (legacy — assumes UZS)
  factory Money.fromJson(dynamic raw, {String fallbackCurrency = 'UZS'}) {
    if (raw == null) return Money(0, fallbackCurrency);
    if (raw is num) return Money(raw, fallbackCurrency);
    if (raw is Map) {
      final a = raw['amount'];
      final c = (raw['currency'] ?? fallbackCurrency).toString();
      return Money(a is num ? a : num.tryParse(a?.toString() ?? '0') ?? 0, c);
    }
    return Money(num.tryParse(raw.toString()) ?? 0, fallbackCurrency);
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'currency': currency,
      };

  static const _meta = <String, _CurrencyMeta>{
    'UZS': _CurrencyMeta("so'm", 0),
    'KZT': _CurrencyMeta('₸', 0),
    'KGS': _CurrencyMeta('сом', 0),
    'RUB': _CurrencyMeta('₽', 2),
    'USD': _CurrencyMeta(r'$', 2),
  };

  /// Locale-aware string. `locale` is one of 'uz' | 'ru' | 'en' | 'kk'.
  /// Returns e.g. "45 000 so'm" / "45,000 \$" / "1 234.56 ₽".
  String format([String locale = 'ru']) {
    final meta = _meta[currency] ?? _meta['UZS']!;
    final fixed = amount.toStringAsFixed(meta.decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final frac = parts.length > 1 ? parts[1] : null;
    final sep = locale.startsWith('en') ? ',' : ' ';
    final grouped = intPart.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => sep,
    );
    final numStr = frac != null ? '$grouped.$frac' : grouped;
    return '$numStr ${meta.symbol}';
  }

  Money operator +(Money other) {
    if (other.currency != currency) {
      throw StateError('Cannot add $currency and ${other.currency}');
    }
    return Money(amount + other.amount, currency);
  }

  Money operator -(Money other) {
    if (other.currency != currency) {
      throw StateError('Cannot subtract $currency and ${other.currency}');
    }
    return Money(amount - other.amount, currency);
  }

  bool get isZero => amount == 0;
}

class _CurrencyMeta {
  final String symbol;
  final int decimals;
  const _CurrencyMeta(this.symbol, this.decimals);
}
