import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/money.dart';
import '../../services/performance_api.dart';
import '../../theme/app_theme.dart';

/// Phase 8.3 — courier performance dashboard backed by
/// `GET /api/couriers/me/performance`.
///
/// Layout, top to bottom:
///   1. Four KPI cards (acceptance / completion / on-time / avg rating).
///   2. Ratings breakdown — horizontal bars per star tier.
///   3. By-day earnings + orders mini bar chart (CustomPaint).
///   4. Tips total + progress towards a 50k UZS / month "Top performer"
///      badge.
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  Future<PerformanceSummary>? _future;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = PerformanceApi.instance.me(days: _days);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(L10n.instance.t('performance.title')),
        actions: [
          PopupMenuButton<int>(
            initialValue: _days,
            onSelected: (v) {
              setState(() => _days = v);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('7d')),
              PopupMenuItem(value: 30, child: Text('30d')),
              PopupMenuItem(value: 90, child: Text('90d')),
            ],
            icon: const Icon(Icons.calendar_today_outlined),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<PerformanceSummary>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = snap.data ?? PerformanceSummary.empty();
          if (s.isEmpty) {
            return _EmptyState(message: L10n.instance.t('performance.no_data'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _KpiGrid(summary: s),
              const SizedBox(height: 16),
              _RatingsBreakdownCard(breakdown: s.ratingsBreakdown),
              const SizedBox(height: 16),
              _ByDayChartCard(byDay: s.byDay),
              const SizedBox(height: 16),
              _TipsBadgeCard(tipsTotal: s.tipsTotal),
              const SizedBox(height: 60),
            ],
          );
        },
      ),
    );
  }
}

// ── KPI grid (4 cards) ─────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final PerformanceSummary summary;
  const _KpiGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          Expanded(
            child: _KpiCard(
              emoji: '✅',
              value: '${(summary.acceptanceRate * 100).toStringAsFixed(0)}%',
              label: L10n.instance.t('performance.acceptance'),
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _KpiCard(
              emoji: '🏁',
              value: '${(summary.completionRate * 100).toStringAsFixed(0)}%',
              label: L10n.instance.t('performance.completion'),
              color: AppColors.info,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _KpiCard(
              emoji: '⏱',
              value: '${(summary.onTimeRate * 100).toStringAsFixed(0)}%',
              label: L10n.instance.t('performance.on_time'),
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _KpiCard(
              emoji: '⭐',
              value: summary.avgRating.toStringAsFixed(2),
              label: L10n.instance.t('performance.avg_rating'),
              color: AppColors.courier,
            ),
          ),
        ]),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String emoji, value, label;
  final Color color;
  const _KpiCard({
    required this.emoji,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ratings breakdown ──────────────────────────────────────────────────────

class _RatingsBreakdownCard extends StatelessWidget {
  final Map<int, int> breakdown;
  const _RatingsBreakdownCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final total = breakdown.values.fold<int>(0, (s, v) => s + v);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reyting taqsimoti',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final star in const [5, 4, 3, 2, 1])
            _RatingRow(
              star: star,
              count: breakdown[star] ?? 0,
              total: total,
            ),
        ],
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final int star;
  final int count;
  final int total;
  const _RatingRow({
    required this.star,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    final color = star >= 4 ? AppColors.success : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$star ⭐', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: AppColors.bg,
                color: color,
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ── By-day chart ───────────────────────────────────────────────────────────

class _ByDayChartCard extends StatelessWidget {
  final List<DailyPerformance> byDay;
  const _ByDayChartCard({required this.byDay});

  @override
  Widget build(BuildContext context) {
    if (byDay.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Text(
            L10n.instance.t('performance.no_data'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final maxAmount = byDay
        .map((d) => d.earnings)
        .fold<num>(0, (a, b) => b > a ? b : a);
    final maxOrders = byDay
        .map((d) => d.orders)
        .fold<int>(0, (a, b) => b > a ? b : a);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kunlik daromad',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: CustomPaint(
              painter: _ByDayPainter(
                byDay: byDay,
                maxAmount: maxAmount > 0 ? maxAmount : 1,
                maxOrders: maxOrders > 0 ? maxOrders : 1,
              ),
              size: const Size.fromHeight(140),
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              _LegendDot(color: AppColors.courier, label: 'Daromad'),
              SizedBox(width: 16),
              _LegendDot(color: AppColors.info, label: 'Buyurtmalar'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ByDayPainter extends CustomPainter {
  final List<DailyPerformance> byDay;
  final num maxAmount;
  final int maxOrders;
  _ByDayPainter({
    required this.byDay,
    required this.maxAmount,
    required this.maxOrders,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (byDay.isEmpty) return;
    final n = byDay.length;
    const gap = 3.0;
    final totalGap = gap * (n - 1);
    final cellW = ((size.width - totalGap) / n).clamp(2.0, 32.0);
    // Earnings bar fills the lower 70%, orders the top 25% (10% padding).
    final earnH = size.height * 0.7;
    final ordersH = size.height * 0.25;
    final earnPaint = Paint()..color = AppColors.courier;
    final ordersPaint = Paint()..color = AppColors.info;

    for (var i = 0; i < n; i++) {
      final d = byDay[i];
      final x = i * (cellW + gap);
      final ePct =
          maxAmount == 0 ? 0.0 : (d.earnings / maxAmount).clamp(0.0, 1.0);
      final eH = earnH * ePct.toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - eH, cellW, eH),
          const Radius.circular(3),
        ),
        earnPaint,
      );
      final oPct =
          maxOrders == 0 ? 0.0 : (d.orders / maxOrders).clamp(0.0, 1.0);
      final oH = ordersH * oPct;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, cellW, oH),
          const Radius.circular(3),
        ),
        ordersPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ByDayPainter old) =>
      old.byDay != byDay ||
      old.maxAmount != maxAmount ||
      old.maxOrders != maxOrders;
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
}

// ── Tips badge progress ────────────────────────────────────────────────────

class _TipsBadgeCard extends StatelessWidget {
  final num tipsTotal;
  const _TipsBadgeCard({required this.tipsTotal});

  // Phase 8.3 — "Top performer" milestone is 50k UZS/month in tips. The
  // gradient bar fills as the courier approaches the threshold.
  static const _milestone = 50000;

  @override
  Widget build(BuildContext context) {
    final locale = L10n.instance.locale.languageCode;
    final pct = (tipsTotal / _milestone).clamp(0.0, 1.0);
    final reached = tipsTotal >= _milestone;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: reached
              ? [const Color(0xFFFFB300), const Color(0xFFFF6B35)]
              : [AppColors.courier, const Color(0xFFE55A2B)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.instance.t('performance.tips_total'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Money(tipsTotal, 'UZS').format(locale),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (reached)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'TOP',
                    style: TextStyle(
                      color: Color(0xFFFF6B35),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.toDouble(),
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reached
                ? '🎉 ${Money(tipsTotal, 'UZS').format(locale)}'
                : '${Money(tipsTotal, 'UZS').format(locale)} / ${const Money(_milestone, 'UZS').format(locale)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📊', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
}
