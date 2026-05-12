import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import 'shop_shell.dart';

/// Phase 13.2.6 — Shop owner analytics dashboard.
///
/// Reads `GET /api/shops/:id/stats` and renders:
///   * Today / This week / This month KPI cards (orders, revenue, avg ticket).
///   * 30-day daily orders bar chart (rendered via Containers; no `fl_chart`
///     dependency was added — we use raw rectangles).
///   * Top product card over the trailing 30-day window.
///
/// Pull-to-refresh re-fetches the stats endpoint.
class ShopAnalyticsScreen extends StatefulWidget {
  const ShopAnalyticsScreen({super.key});

  @override
  State<ShopAnalyticsScreen> createState() => _ShopAnalyticsScreenState();
}

class _ShopAnalyticsScreenState extends State<ShopAnalyticsScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  _Bucket? _today;
  _Bucket? _week;
  _Bucket? _month;
  List<_DailyPoint> _daily = const [];
  _TopProduct? _top;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final shopId = context.read<AuthProvider>().user?.shopId;
    if (shopId == null || shopId.isEmpty) {
      setState(() {
        _loading = false;
        _error = t(context, 'shop.analytics.no_shop');
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _api.get('/api/shops/$shopId/stats');
      final data = res.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _today = data['today'] == null
            ? null
            : _Bucket.fromJson(data['today'] as Map<String, dynamic>);
        _week = data['week'] == null
            ? null
            : _Bucket.fromJson(data['week'] as Map<String, dynamic>);
        _month = data['month'] == null
            ? null
            : _Bucket.fromJson(data['month'] as Map<String, dynamic>);
        _daily = (data['daily'] as List? ?? const [])
            .map((j) => _DailyPoint.fromJson(j as Map<String, dynamic>))
            .toList();
        _top = data['topProduct'] == null
            ? null
            : _TopProduct.fromJson(data['topProduct'] as Map<String, dynamic>);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        title: Text(t(context, 'shop.analytics.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _KpiCard(
            label: t(context, 'shop.analytics.today'),
            bucket: _today,
            gradient: const [Color(0xFF3B5BDB), Color(0xFF2F4AC0)],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: t(context, 'shop.analytics.week'),
                  bucket: _week,
                  gradient: const [Color(0xFF7048E8), Color(0xFF5F3DC4)],
                  compact: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _KpiCard(
                  label: t(context, 'shop.analytics.month'),
                  bucket: _month,
                  gradient: const [Color(0xFF1098AD), Color(0xFF0C8599)],
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DailyChart(points: _daily),
          const SizedBox(height: 16),
          if (_top != null) _TopProductCard(top: _top!),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final _Bucket? bucket;
  final List<Color> gradient;
  final bool compact;
  const _KpiCard({
    required this.label,
    required this.bucket,
    required this.gradient,
    this.compact = false,
  });

  String _fmtMoney(num n) {
    final s = n.toInt().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final b = bucket;
    final orders = b?.orders ?? 0;
    final net = b?.net ?? 0;
    final avg = b?.avgTicket ?? 0;
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w500,
              )),
          SizedBox(height: compact ? 6 : 8),
          Text(
            '${_fmtMoney(net)} ${t(context, 'common.currency_uzs')}',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 18 : 22,
            ),
          ),
          SizedBox(height: compact ? 4 : 6),
          Row(
            children: [
              _miniStat(
                label: t(context, 'shop.analytics.orders_short'),
                value: '$orders',
              ),
              SizedBox(width: compact ? 10 : 16),
              _miniStat(
                label: t(context, 'shop.analytics.avg_ticket'),
                value: _fmtMoney(avg),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat({required String label, required String value}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
              )),
          Text(value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              )),
        ],
      );
}

class _DailyChart extends StatelessWidget {
  final List<_DailyPoint> points;
  const _DailyChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final maxOrders = points.fold<int>(0, (m, p) => p.orders > m ? p.orders : m);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                t(context, 'shop.analytics.chart_title'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const Spacer(),
              Text(
                t(context, 'shop.analytics.chart_window'),
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: points.isEmpty
                ? Center(
                    child: Text(
                      t(context, 'shop.analytics.chart_empty'),
                      style: const TextStyle(color: AppColors.textHint),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: points.map((p) {
                      final h = maxOrders == 0
                          ? 0.0
                          : (p.orders / maxOrders) * 110.0;
                      return Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Tooltip(
                                message:
                                    '${p.date} • ${p.orders} • ${p.revenue.toInt()}',
                                child: Container(
                                  height: h < 2 && p.orders > 0 ? 2 : h,
                                  decoration: BoxDecoration(
                                    color: p.orders == 0
                                        ? AppColors.border
                                        : kShopColor,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                points.isNotEmpty ? points.first.date : '',
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 10),
              ),
              Text(
                points.isNotEmpty ? points.last.date : '',
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopProductCard extends StatelessWidget {
  final _TopProduct top;
  const _TopProductCard({required this.top});

  @override
  Widget build(BuildContext context) {
    final name = top.name.isNotEmpty ? top.name : top.nameUz;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.shopLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 38)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(context, 'shop.analytics.top_product'),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 2),
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${top.quantity} ${t(context, 'shop.analytics.sold_30d')}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────

class _Bucket {
  final int orders;
  final double gross;
  final double refunded;
  final double net;
  final double avgTicket;
  _Bucket({
    required this.orders,
    required this.gross,
    required this.refunded,
    required this.net,
    required this.avgTicket,
  });
  factory _Bucket.fromJson(Map<String, dynamic> j) => _Bucket(
        orders: (j['orders'] as int?) ?? 0,
        gross: (j['gross'] as num?)?.toDouble() ?? 0.0,
        refunded: (j['refunded'] as num?)?.toDouble() ?? 0.0,
        net: (j['net'] as num?)?.toDouble() ?? 0.0,
        avgTicket: (j['avgTicket'] as num?)?.toDouble() ?? 0.0,
      );
}

class _DailyPoint {
  final String date;
  final int orders;
  final double revenue;
  _DailyPoint({required this.date, required this.orders, required this.revenue});
  factory _DailyPoint.fromJson(Map<String, dynamic> j) => _DailyPoint(
        date: (j['date'] ?? '') as String,
        orders: (j['orders'] as int?) ?? 0,
        revenue: (j['revenue'] as num?)?.toDouble() ?? 0.0,
      );
}

class _TopProduct {
  final String id;
  final String name;
  final String nameUz;
  final int quantity;
  _TopProduct({
    required this.id,
    required this.name,
    required this.nameUz,
    required this.quantity,
  });
  factory _TopProduct.fromJson(Map<String, dynamic> j) => _TopProduct(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        nameUz: (j['nameUz'] ?? '') as String,
        quantity: (j['quantity'] as int?) ?? 0,
      );
}
