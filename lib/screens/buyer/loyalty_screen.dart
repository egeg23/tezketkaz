import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n.dart';
import '../../models/loyalty.dart';
import '../../services/api_client.dart';
import '../../services/promo_api.dart';
import '../../theme/app_theme.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});
  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  bool _loading = true;
  String? _error;
  LoyaltyAccount? _account;
  String? _referralCode;
  bool _redeeming = false;
  final _referralCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _referralCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = LoyaltyApi.instance;
      final account = await api.me();
      String code = '';
      try {
        code = await api.myReferralCode();
      } catch (_) {/* referral code is best-effort */}
      if (!mounted) return;
      setState(() {
        _account = account;
        _referralCode = code;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _useReferral() async {
    final code = _referralCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _redeeming = true);
    try {
      await LoyaltyApi.instance.useReferral(code);
      if (!mounted) return;
      _referralCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'loyalty.referral_applied'))),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  String _fmtMoney(num v) {
    final s = v.toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
    return "$s so'm";
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(t(context, 'loyalty.title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            style: const TextStyle(color: AppColors.error)),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _load,
                          child: Text(t(context, 'common.retry')),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _buildBody(),
                ),
    );
  }

  Widget _buildBody() {
    final acc = _account!;
    final tier = acc.tier;
    final next = tier.next;
    final progress = next == null
        ? 1.0
        : ((acc.lifetimeSpent - tier.threshold) /
                (next.threshold - tier.threshold))
            .clamp(0.0, 1.0)
            .toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // ── Header card ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.button,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Text(tier.emoji,
                        style: const TextStyle(fontSize: 32)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t(context, 'loyalty.tier'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            )),
                        const SizedBox(height: 2),
                        Text(tier.label,
                            style: const TextStyle(
                              fontSize: 22,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: t(context, 'loyalty.points'),
                      value: '${acc.points.toInt()}',
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: Colors.white24,
                  ),
                  Expanded(
                    child: _Stat(
                      label: t(context, 'loyalty.cashback'),
                      value: _fmtMoney(acc.cashback),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (next != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${t(context, 'loyalty.to_next')} ${next.label} · ${_fmtMoney(next.threshold - acc.lifetimeSpent)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ] else
                Text(
                  t(context, 'loyalty.max_tier'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Referral ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t(context, 'loyalty.your_referral'),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Text(
                        _referralCode?.isNotEmpty == true
                            ? _referralCode!
                            : '—',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: 1.2,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded,
                        color: AppColors.primary),
                    onPressed: _referralCode?.isNotEmpty == true
                        ? () {
                            Clipboard.setData(
                                ClipboardData(text: _referralCode!));
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    t(context, 'loyalty.copied')),
                              ),
                            );
                          }
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Text(t(context, 'loyalty.have_friend_code'),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _referralCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: t(context, 'loyalty.enter_friend_code'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _redeeming ? null : _useReferral,
                    child: _redeeming
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(t(context, 'loyalty.apply')),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Recent activity ──────────────────────────────────────────────
        Text(t(context, 'loyalty.recent_activity'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            children: [
              if (acc.transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      t(context, 'loyalty.no_activity'),
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 13),
                    ),
                  ),
                ),
              for (var i = 0; i < acc.transactions.length; i++) ...[
                _ActivityRow(
                  tx: acc.transactions[i],
                  fmtDate: _fmtDate,
                ),
                if (i < acc.transactions.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
                letterSpacing: 0.4,
              )),
        ],
      );
}

class _ActivityRow extends StatelessWidget {
  final LoyaltyTransaction tx;
  final String Function(DateTime) fmtDate;
  const _ActivityRow({required this.tx, required this.fmtDate});
  @override
  Widget build(BuildContext context) {
    final positive = tx.delta >= 0;
    final sign = positive ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: positive
                  ? AppColors.successLight
                  : AppColors.errorLight,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              positive
                  ? Icons.add_circle_outline
                  : Icons.remove_circle_outline,
              color: positive ? AppColors.success : AppColors.error,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.reason,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(fmtDate(tx.createdAt),
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 12)),
              ],
            ),
          ),
          Text(
            '$sign${tx.delta}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: positive ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}
