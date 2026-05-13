import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/money.dart';
import '../../services/earnings_api.dart';
import '../../services/order_api.dart';
import '../../services/payout_api.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

/// Phase 6 — courier earnings screen, backed by `GET /api/couriers/me/earnings`.
///
/// Tabs: today / week / month / lifetime. Each tab shows KPI cards and a
/// simple bar chart drawn with [CustomPaint] (no fl_chart dependency).
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Future<EarningsSummary>? _summaryFuture;
  Future<List<AppOrder>>? _historyFuture;
  // Phase 8.5 — instant payout balance shared across all tabs.
  Future<PayoutBalance>? _balanceFuture;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  void _load() {
    setState(() {
      _summaryFuture = EarningsApi.instance.me();
      _historyFuture = _loadHistory();
      _balanceFuture = _loadBalance();
    });
  }

  Future<PayoutBalance> _loadBalance() async {
    try {
      return await PayoutApi.instance.myBalance();
    } catch (_) {
      return PayoutBalance.empty();
    }
  }

  /// Phase 8.5 — fire the payout request. Re-fetches the balance so the UI
  /// flips to the "pending" state immediately on success.
  Future<void> _requestPayout(PayoutBalance balance) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L10n.instance.t('payout.cashout_now')),
        content: Text(
          '${L10n.instance.t('payout.balance')}: '
          '${Money(balance.availableBalance, balance.currency).format(_locale())}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.instance.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.instance.t('common.confirm')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await PayoutApi.instance.request();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(L10n.instance.t('payout.requested_success')),
        behavior: SnackBarBehavior.floating,
      ));
      setState(() {
        _balanceFuture = _loadBalance();
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.error,
      ));
    }
  }

  /// Best-effort: pull recent delivered orders for this courier. The Phase 6
  /// backend may not yet expose a courier-history endpoint, so we just
  /// degrade gracefully to an empty list when the call fails.
  Future<List<AppOrder>> _loadHistory() async {
    try {
      // Phase 6: try the buyer-style /mine endpoint with role auth — backend
      // is expected to filter by courierId when the caller is a courier.
      final mine = await OrderApi.instance.myOrders();
      return mine
          .where((o) => o.status == AppOrderStatus.delivered ||
              o.status == AppOrderStatus.confirmedByBuyer)
          .take(50)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Daromad'),
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            labelColor: AppColors.courier,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.courier,
            tabs: const [
              Tab(text: 'Bugun'),
              Tab(text: 'Hafta'),
              Tab(text: 'Oy'),
              Tab(text: 'Hammasi'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Yangilash',
              onPressed: _load,
            ),
          ],
        ),
        body: FutureBuilder<EarningsSummary>(
          future: _summaryFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorView(error: snap.error.toString(), onRetry: _load);
            }
            final s = snap.data ?? EarningsSummary.empty();
            // Phase 8.5 — payout card pinned above the tab content. The card
            // is shown across all tabs so the courier can cash out from any
            // period view.
            return Column(
              children: [
                FutureBuilder<PayoutBalance>(
                  future: _balanceFuture,
                  builder: (_, balSnap) {
                    final bal = balSnap.data;
                    if (bal == null) return const SizedBox.shrink();
                    return _InstantPayoutCard(
                      balance: bal,
                      onCashOut: () => _requestPayout(bal),
                    );
                  },
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _TodayTab(summary: s, historyFuture: _historyFuture),
                      _PeriodTab(
                        total: s.weeklyMoney,
                        orders: s.weeklyOrders.toInt(),
                        tips: s.tipsMoney,
                        daily: _daysSlice(s.daily, 7),
                        label: 'Bu hafta',
                      ),
                      _PeriodTab(
                        total: s.monthlyMoney,
                        orders: s.monthlyOrders.toInt(),
                        tips: s.tipsMoney,
                        daily: _daysSlice(s.daily, 30),
                        label: 'Bu oy',
                      ),
                      _LifetimeTab(summary: s),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<DailyEarning> _daysSlice(List<DailyEarning> all, int n) {
    if (all.length <= n) return all;
    return all.sublist(all.length - n);
  }
}

// ─── Today tab ───────────────────────────────────────────────────────────────

class _TodayTab extends StatelessWidget {
  final EarningsSummary summary;
  final Future<List<AppOrder>>? historyFuture;
  const _TodayTab({required this.summary, required this.historyFuture});

  @override
  Widget build(BuildContext context) {
    final today = summary.todayMoney;
    final orders = summary.todayOrders.toInt();
    final tips = summary.tipsMoney;
    final avg = orders > 0
        ? Money(today.amount / orders, today.currency)
        : Money(0, today.currency);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroBalanceCard(
          title: 'Bugungi daromad',
          money: today,
          tipsMoney: tips,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _KpiCard(label: 'Buyurtmalar', value: '$orders ta', emoji: '📦')),
          const SizedBox(width: 10),
          Expanded(child: _KpiCard(
            label: "O'rtacha",
            value: avg.format(_locale()),
            emoji: '📊',
          )),
        ]),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'Yetkazib berilgan buyurtmalar',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        FutureBuilder<List<AppOrder>>(
          future: historyFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final list = snap.data ?? const <AppOrder>[];
            if (list.isEmpty) {
              return const _EmptyHint(text: 'Hozircha tarix yo\'q');
            }
            return Column(
              children: [
                for (final o in list) _OrderHistoryTile(order: o),
              ],
            );
          },
        ),
        const SizedBox(height: 60),
      ],
    );
  }
}

// ─── Period tab (week / month) ───────────────────────────────────────────────

class _PeriodTab extends StatelessWidget {
  final Money total;
  final int orders;
  final Money tips;
  final List<DailyEarning> daily;
  final String label;
  const _PeriodTab({
    required this.total,
    required this.orders,
    required this.tips,
    required this.daily,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final avg = orders > 0
        ? Money(total.amount / orders, total.currency)
        : Money(0, total.currency);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroBalanceCard(title: label, money: total, tipsMoney: tips),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _KpiCard(label: 'Buyurtmalar', value: '$orders ta', emoji: '📦')),
          const SizedBox(width: 10),
          Expanded(child: _KpiCard(
            label: "O'rtacha",
            value: avg.format(_locale()),
            emoji: '📊',
          )),
        ]),
        const SizedBox(height: 18),
        if (daily.isEmpty)
          const _EmptyHint(text: 'Diagramma uchun ma\'lumot yo\'q')
        else
          _BarChartCard(daily: daily, currency: total.currency),
        const SizedBox(height: 60),
      ],
    );
  }
}

// ─── Lifetime tab ────────────────────────────────────────────────────────────

class _LifetimeTab extends StatelessWidget {
  final EarningsSummary summary;
  const _LifetimeTab({required this.summary});

  @override
  Widget build(BuildContext context) {
    final allOrders = summary.daily.fold<int>(0, (s, d) => s + d.orders);
    final avg = allOrders > 0
        ? Money(summary.lifetimeTotal / allOrders, summary.currency)
        : Money(0, summary.currency);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroBalanceCard(
          title: 'Umumiy daromad',
          money: summary.lifetimeMoney,
          tipsMoney: summary.tipsMoney,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _KpiCard(
            label: 'Jami buyurtmalar',
            value: '$allOrders ta',
            emoji: '📦',
          )),
          const SizedBox(width: 10),
          Expanded(child: _KpiCard(
            label: "O'rtacha",
            value: avg.format(_locale()),
            emoji: '📊',
          )),
        ]),
        const SizedBox(height: 16),
        if (summary.daily.isNotEmpty)
          _BarChartCard(daily: summary.daily, currency: summary.currency),
        const SizedBox(height: 60),
      ],
    );
  }
}

// ─── Reusable widgets ────────────────────────────────────────────────────────

String _locale() => L10n.instance.locale.languageCode;

class _HeroBalanceCard extends StatelessWidget {
  final String title;
  final Money money;
  final Money tipsMoney;
  const _HeroBalanceCard({
    required this.title,
    required this.money,
    required this.tipsMoney,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B35), Color(0xFFE55A2B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.courier.withValues(alpha: 0.3),
            blurRadius: 20, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            money.format(_locale()),
            style: const TextStyle(
              color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900,
            ),
          ),
          if (!tipsMoney.isZero) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('💝 Chayryak: ',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                  Text(
                    tipsMoney.format(_locale()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12, fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label, value, emoji;
  const _KpiCard({required this.label, required this.value, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarChartCard extends StatelessWidget {
  final List<DailyEarning> daily;
  final String currency;
  const _BarChartCard({required this.daily, required this.currency});

  @override
  Widget build(BuildContext context) {
    final maxAmount =
        daily.map((d) => d.amount).fold<num>(0, (a, b) => b > a ? b : a);
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
          Text('Diagramma',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            child: CustomPaint(
              painter: _BarChartPainter(
                daily: daily,
                maxAmount: maxAmount > 0 ? maxAmount : 1,
              ),
              size: const Size.fromHeight(140),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<DailyEarning> daily;
  final num maxAmount;
  _BarChartPainter({required this.daily, required this.maxAmount});

  @override
  void paint(Canvas canvas, Size size) {
    if (daily.isEmpty) return;
    final n = daily.length;
    const gap = 4.0;
    final totalGap = gap * (n - 1);
    final barW = ((size.width - totalGap) / n).clamp(2.0, 32.0);
    final paint = Paint()..color = AppColors.courier;
    final paintMuted = Paint()..color = AppColors.courier.withValues(alpha: 0.25);

    for (var i = 0; i < n; i++) {
      final d = daily[i];
      final pct = maxAmount == 0 ? 0.0 : (d.amount / maxAmount).clamp(0.0, 1.0);
      final h = size.height * pct.toDouble();
      final x = i * (barW + gap);
      final y = size.height - h;
      final isLast = i == n - 1;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, h),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, isLast ? paint : paintMuted);
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.daily != daily || old.maxAmount != maxAmount;
}

class _OrderHistoryTile extends StatelessWidget {
  final AppOrder order;
  const _OrderHistoryTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final money = Money(order.reward, 'UZS');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.courierLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('📦', style: TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.shopName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(order.deliveryAddress,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('+ ${money.format(_locale())}',
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w800, fontSize: 13,
              )),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(text,
              style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13,
              )),
        ),
      );
}

/// Phase 8.5 — instant payout card. Disabled when balance < min payout, or
/// when there is already a pending request.
class _InstantPayoutCard extends StatelessWidget {
  final PayoutBalance balance;
  final VoidCallback onCashOut;
  const _InstantPayoutCard({required this.balance, required this.onCashOut});

  @override
  Widget build(BuildContext context) {
    final locale = _locale();
    final money = Money(balance.availableBalance, balance.currency);
    final min = Money(balance.minPayout, balance.currency);
    final canCashOut = balance.canRequest;
    final showBelowMin =
        !balance.hasPending && balance.availableBalance < balance.minPayout;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💸', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.instance.t('payout.balance'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      money.format(locale),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: canCashOut ? onCashOut : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.courier,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(L10n.instance.t('payout.cashout_now')),
              ),
            ],
          ),
          if (balance.hasPending) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top,
                      color: AppColors.warning, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      L10n.instance.t('payout.pending'),
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (showBelowMin) ...[
            const SizedBox(height: 8),
            Text(
              L10n.instance
                  .t('payout.below_min')
                  .replaceAll('{amount}', min.format(locale)),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text(
                'Daromadni yuklab bo\'lmadi',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12,
                  )),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
}
