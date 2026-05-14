import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/money.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

/// Phase 13.2.6 — shop analytics dashboard (today / week / month KPI cards +
/// 30-day bar chart + top-selling product card).
///
/// Pulls everything from `GET /api/shops/:id/stats`. The chart is plain
/// `Container` bars rather than `fl_chart` to keep the dep footprint flat
/// (as required by Phase 13.2.6 spec).
class ShopAnalyticsScreen extends StatefulWidget {
  const ShopAnalyticsScreen({super.key});

  @override
  State<ShopAnalyticsScreen> createState() => _ShopAnalyticsScreenState();
}

class _ShopAnalyticsScreenState extends State<ShopAnalyticsScreen> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _stats;

  String? get _shopId => context.read<AuthProvider>().user?.shopId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final shopId = _shopId;
    if (shopId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.get('/api/shops/$shopId/stats');
      final raw = res.data;
      _stats = raw is Map ? Map<String, dynamic>.from(raw) : null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopId = _shopId;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(t(context, 'shop.analytics.title')),
      ),
      body: shopId == null
          ? Center(
              child: Text(
                t(context, 'shop.analytics.no_shop'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    t(context, 'shop.analytics.subtitle'),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_loading && _stats == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null && _stats == null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(color: AppColors.error)),
                    )
                  else if (_stats != null) ...[
                    _BucketCards(stats: _stats!),
                    const SizedBox(height: 20),
                    _DailyChart(daily: _stats!['daily'] as List? ?? const []),
                    const SizedBox(height: 20),
                    if (_stats!['topProduct'] is Map)
                      _TopProductCard(
                        product: Map<String, dynamic>.from(
                          _stats!['topProduct'] as Map,
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _BucketCards extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _BucketCards({required this.stats});

  Map<String, dynamic> _b(String key) {
    final raw = stats[key];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final today = _b('today');
    final week = _b('week');
    final month = _b('month');
    return Column(
      children: [
        _BucketCard(
          label: t(context, 'shop.analytics.today'),
          data: today,
          accent: AppColors.primary,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _BucketCard(
                label: t(context, 'shop.analytics.week'),
                data: week,
                compact: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BucketCard(
                label: t(context, 'shop.analytics.month'),
                data: month,
                compact: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BucketCard extends StatelessWidget {
  final String label;
  final Map<String, dynamic> data;
  final Color? accent;
  final bool compact;
  const _BucketCard({
    required this.label,
    required this.data,
    this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final lang = L10n.instance.locale.languageCode;
    final orders = (data['orders'] as num?)?.toInt() ?? 0;
    final net = (data['net'] as num?)?.toDouble() ?? 0;
    final avg = (data['avgTicket'] as num?)?.toDouble() ?? 0;
    final accentColor = accent ?? AppColors.primary;

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Money(net).format(lang),
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white,
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  value: '$orders',
                  label: t(context, 'shop.analytics.orders_short'),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  value: Money(avg).format(lang),
                  label: t(context, 'shop.analytics.avg_ticket'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  const _MiniStat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textHint,
              fontSize: 10,
              letterSpacing: 0.4,
            ),
          ),
        ],
      );
}

class _DailyChart extends StatelessWidget {
  final List<dynamic> daily;
  const _DailyChart({required this.daily});

  @override
  Widget build(BuildContext context) {
    final rows = daily
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Text(
            t(context, 'shop.analytics.chart_empty'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final max = rows
        .map((r) => (r['orders'] as num?)?.toInt() ?? 0)
        .fold<int>(1, (a, b) => b > a ? b : a);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t(context, 'shop.analytics.chart_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                t(context, 'shop.analytics.chart_window'),
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final r in rows) ...[
                  Expanded(
                    child: _Bar(
                      ratio: ((r['orders'] as num?)?.toInt() ?? 0) / max,
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double ratio;
  const _Bar({required this.ratio});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: ratio.clamp(0.04, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.85),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ),
        ),
      );
}

class _TopProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const _TopProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final name =
        (product['nameUz'] as String? ?? product['name'] as String? ?? '—');
    final quantity = (product['quantity'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.local_fire_department_rounded,
                color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(context, 'shop.analytics.top_product').toUpperCase(),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$quantity ${t(context, 'shop.analytics.sold_30d')}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
