import '../models/money.dart';
import 'api_client.dart';

/// Phase 6 — courier earnings API client. Backed by `GET /api/couriers/me/earnings`.
///
/// The backend response is expected to look like:
/// ```
/// {
///   daily: [{date, amount, orders, tips}, ...],   // last 30 days
///   weekly:  {total, orders},
///   monthly: {total, orders},
///   total:    <num>,    // lifetime
///   tipsTotal: <num>
/// }
/// ```
/// However different shapes may come back during the rollout — we tolerate
/// flat keys (`weeklyTotal`, `weeklyOrders`, ...) and missing fields so the UI
/// degrades gracefully instead of crashing.
class EarningsApi {
  EarningsApi._();
  static final EarningsApi instance = EarningsApi._();

  final _api = ApiClient.instance;

  Future<EarningsSummary> me() async {
    final res = await _api.get('/api/couriers/me/earnings');
    final raw = res.data;
    if (raw is! Map) return EarningsSummary.empty();
    return EarningsSummary.fromJson(Map<String, dynamic>.from(raw));
  }
}

class EarningsSummary {
  final List<DailyEarning> daily;   // last 30 days
  final num weeklyTotal;
  final num weeklyOrders;
  final num monthlyTotal;
  final num monthlyOrders;
  final num lifetimeTotal;
  final num tipsTotal;
  final String currency;

  const EarningsSummary({
    required this.daily,
    required this.weeklyTotal,
    required this.weeklyOrders,
    required this.monthlyTotal,
    required this.monthlyOrders,
    required this.lifetimeTotal,
    required this.tipsTotal,
    this.currency = 'UZS',
  });

  factory EarningsSummary.empty() => const EarningsSummary(
        daily: [],
        weeklyTotal: 0,
        weeklyOrders: 0,
        monthlyTotal: 0,
        monthlyOrders: 0,
        lifetimeTotal: 0,
        tipsTotal: 0,
      );

  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    // daily can come as List<Map> or be missing.
    final dailyRaw = json['daily'] ?? json['days'] ?? const [];
    final daily = (dailyRaw is List ? dailyRaw : const [])
        .map((d) => DailyEarning.fromJson(
              d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{},
            ))
        .toList();

    // weekly/monthly may be nested objects or flat fields.
    final weekly = _readBucket(json, 'weekly', 'weeklyTotal', 'weeklyOrders');
    final monthly =
        _readBucket(json, 'monthly', 'monthlyTotal', 'monthlyOrders');

    return EarningsSummary(
      daily: daily,
      weeklyTotal: weekly.$1,
      weeklyOrders: weekly.$2,
      monthlyTotal: monthly.$1,
      monthlyOrders: monthly.$2,
      lifetimeTotal: _toNum(json['total'] ?? json['lifetimeTotal']),
      tipsTotal: _toNum(json['tipsTotal'] ?? json['tips']),
      currency: (json['currency'] as String?) ?? 'UZS',
    );
  }

  num get todayTotal => daily.isEmpty ? 0 : daily.last.amount;
  num get todayOrders => daily.isEmpty ? 0 : daily.last.orders;

  Money get weeklyMoney => Money(weeklyTotal, currency);
  Money get monthlyMoney => Money(monthlyTotal, currency);
  Money get lifetimeMoney => Money(lifetimeTotal, currency);
  Money get tipsMoney => Money(tipsTotal, currency);
  Money get todayMoney => Money(todayTotal, currency);

  static (num, num) _readBucket(
    Map<String, dynamic> json,
    String nestedKey,
    String flatTotal,
    String flatOrders,
  ) {
    final nested = json[nestedKey];
    if (nested is Map) {
      return (
        _toNum(nested['total'] ?? nested['amount']),
        _toNum(nested['orders'] ?? nested['count']),
      );
    }
    return (_toNum(json[flatTotal]), _toNum(json[flatOrders]));
  }
}

class DailyEarning {
  final DateTime date;
  final num amount;
  final int orders;
  final num tips;

  const DailyEarning({
    required this.date,
    required this.amount,
    required this.orders,
    required this.tips,
  });

  factory DailyEarning.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'] ?? json['day'];
    DateTime parsed;
    if (rawDate is String) {
      parsed = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else if (rawDate is DateTime) {
      parsed = rawDate;
    } else {
      parsed = DateTime.now();
    }
    return DailyEarning(
      date: parsed,
      amount: _toNum(json['amount'] ?? json['total'] ?? json['earnings']),
      orders: _toNum(json['orders'] ?? json['count']).toInt(),
      tips: _toNum(json['tips']),
    );
  }
}

num _toNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse(v.toString()) ?? 0;
}
