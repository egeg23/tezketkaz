import 'api_client.dart';

/// Phase 8.3 — courier performance API client.
///
/// Backed by `GET /api/couriers/me/performance?days=N`. The backend returns
/// the shape:
/// ```
/// {
///   acceptanceRate, completionRate, onTimeRate, avgRating,
///   ratingsBreakdown: { '5': N, '4': N, ... },
///   totalEarnings, totalOrders, tipsTotal,
///   byDay: [{date, earnings, orders, tips}, ...]
/// }
/// ```
/// All fields tolerate missing values so the UI degrades gracefully when the
/// backend is still rolling the endpoint out.
class PerformanceApi {
  PerformanceApi._();
  static final PerformanceApi instance = PerformanceApi._();

  final _api = ApiClient.instance;

  Future<PerformanceSummary> me({int days = 30}) async {
    final res = await _api.get(
      '/api/couriers/me/performance',
      query: {'days': days},
    );
    final raw = res.data;
    if (raw is! Map) return PerformanceSummary.empty();
    return PerformanceSummary.fromJson(Map<String, dynamic>.from(raw));
  }
}

class PerformanceSummary {
  final double acceptanceRate;
  final double completionRate;
  final double onTimeRate;
  final double avgRating;
  final Map<int, int> ratingsBreakdown;
  final num totalEarnings;
  final num totalOrders;
  final num tipsTotal;
  final List<DailyPerformance> byDay;

  const PerformanceSummary({
    required this.acceptanceRate,
    required this.completionRate,
    required this.onTimeRate,
    required this.avgRating,
    required this.ratingsBreakdown,
    required this.totalEarnings,
    required this.totalOrders,
    required this.tipsTotal,
    required this.byDay,
  });

  factory PerformanceSummary.empty() => const PerformanceSummary(
        acceptanceRate: 0,
        completionRate: 0,
        onTimeRate: 0,
        avgRating: 0,
        ratingsBreakdown: {},
        totalEarnings: 0,
        totalOrders: 0,
        tipsTotal: 0,
        byDay: [],
      );

  bool get isEmpty =>
      totalOrders == 0 && byDay.isEmpty && ratingsBreakdown.isEmpty;

  factory PerformanceSummary.fromJson(Map<String, dynamic> j) {
    final breakdownRaw = j['ratingsBreakdown'];
    final breakdown = <int, int>{};
    if (breakdownRaw is Map) {
      breakdownRaw.forEach((k, v) {
        final star = int.tryParse(k.toString());
        final count = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        if (star != null) breakdown[star] = count;
      });
    }

    final byDayRaw = j['byDay'] ?? j['daily'] ?? const [];
    final byDay = (byDayRaw is List ? byDayRaw : const [])
        .map((d) => DailyPerformance.fromJson(
              d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{},
            ))
        .toList();

    return PerformanceSummary(
      acceptanceRate: _toDouble(j['acceptanceRate']),
      completionRate: _toDouble(j['completionRate']),
      onTimeRate: _toDouble(j['onTimeRate']),
      avgRating: _toDouble(j['avgRating']),
      ratingsBreakdown: breakdown,
      totalEarnings: _toNum(j['totalEarnings']),
      totalOrders: _toNum(j['totalOrders']),
      tipsTotal: _toNum(j['tipsTotal']),
      byDay: byDay,
    );
  }
}

class DailyPerformance {
  final DateTime date;
  final num earnings;
  final int orders;
  final num tips;

  const DailyPerformance({
    required this.date,
    required this.earnings,
    required this.orders,
    required this.tips,
  });

  factory DailyPerformance.fromJson(Map<String, dynamic> j) {
    final raw = j['date'] ?? j['day'];
    DateTime parsed;
    if (raw is DateTime) {
      parsed = raw;
    } else if (raw is String) {
      parsed = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      parsed = DateTime.now();
    }
    return DailyPerformance(
      date: parsed,
      earnings: _toNum(j['earnings'] ?? j['amount'] ?? j['total']),
      orders: _toNum(j['orders'] ?? j['count']).toInt(),
      tips: _toNum(j['tips']),
    );
  }
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

num _toNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse(v.toString()) ?? 0;
}
