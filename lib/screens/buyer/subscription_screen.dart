import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../models/money.dart';
import '../../models/payment_method.dart';
import '../../providers/auth_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/api_client.dart';
import '../../services/membership_api.dart';
import '../../services/payment_method_api.dart';
import '../../theme/app_theme.dart';

/// Phase 7.2 — buyer subscription screen.
///
/// Shows a tier comparison + billing toggle for non-members, or current tier
/// + cancel/reactivate controls when subscribed.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _loading = true;
  String? _error;
  Membership? _current;
  MembershipPricing? _pricing;
  String _selectedTier = 'plus';
  String _selectedPeriod = 'monthly';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await MembershipApi.instance.me();
      final p = await MembershipApi.instance.pricing();
      if (!mounted) return;
      setState(() {
        _current = m;
        _pricing = p;
        if (m != null) {
          _selectedTier = m.tier;
          _selectedPeriod = m.billingPeriod;
        }
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

  Future<PaymentMethod?> _pickPaymentMethod() async {
    final methods = await PaymentMethodApi.instance.list();
    if (!mounted) return null;
    if (methods.isEmpty) {
      // No saved methods — push the management screen and bail.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'subscription.add_card_first'))),
      );
      await context.push('/buyer/payment-methods');
      return null;
    }
    return showModalBottomSheet<PaymentMethod>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(t(context, 'buyer.payment_method'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              for (final m in methods)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  leading: Text(m.brandEmoji,
                      style: const TextStyle(fontSize: 22)),
                  title: Text(m.displayLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(m.providerName),
                  onTap: () => Navigator.of(context).pop(m),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSubscribe() async {
    final method = await _pickPaymentMethod();
    if (method == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final m = await MembershipApi.instance.subscribe(
        tier: _selectedTier,
        billingPeriod: _selectedPeriod,
        paymentMethodId: method.id,
      );
      AnalyticsService.instance.logEvent('subscription_started', {
        'tier': _selectedTier,
        'billingPeriod': _selectedPeriod,
      });
      // Refresh provider-side cache so the rest of the app picks up the new
      // tier (e.g. cart screen's "free delivery" line).
      try {
        // ignore: use_build_context_synchronously
        await AuthProvider.refreshMembershipFromAnywhere(context);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _current = m;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'subscription.activated'))),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _onCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t(context, 'subscription.cancel_title')),
        content: Text(t(context, 'subscription.cancel_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(t(context, 'subscription.cancel_cta')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final m = await MembershipApi.instance.cancel();
      if (!mounted) return;
      setState(() {
        _current = m;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _onReactivate() async {
    setState(() => _busy = true);
    try {
      final m = await MembershipApi.instance.reactivate();
      if (!mounted) return;
      setState(() {
        _current = m;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  String _money(Money? m) =>
      m?.format(L10n.instance.locale.languageCode) ?? '—';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(t(context, 'subscription.title'))),
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
    final cur = _current;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (cur != null && (cur.isActive || cur.isCancelledButValid))
          _buildCurrentCard(cur)
        else
          _buildBecomeCta(),
        const SizedBox(height: 16),
        _buildBillingToggle(),
        const SizedBox(height: 16),
        _buildTierCard(
          tier: 'plus',
          emoji: '⭐',
          color: AppColors.primary,
          features: [
            t(context, 'subscription.feat_free_delivery_50'),
            t(context, 'subscription.feat_cashback_2x'),
            t(context, 'subscription.feat_priority_support'),
          ],
        ),
        const SizedBox(height: 12),
        _buildTierCard(
          tier: 'pro',
          emoji: '👑',
          color: AppColors.warning,
          features: [
            t(context, 'subscription.feat_free_delivery'),
            t(context, 'subscription.feat_cashback_5x'),
            t(context, 'subscription.feat_priority_support'),
            t(context, 'subscription.feat_exclusive_promo'),
          ],
        ),
        const SizedBox(height: 24),
        if (cur == null || !cur.isActive)
          ElevatedButton(
            onPressed: _busy ? null : _onSubscribe,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.primary,
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : Text(
                    t(context, 'subscription.subscribe_cta'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
          ),
      ],
    );
  }

  Widget _buildCurrentCard(Membership cur) {
    final isPlus = cur.tier == 'plus';
    final emoji = isPlus ? '⭐' : '👑';
    final tierLabel = isPlus
        ? t(context, 'subscription.tier_plus')
        : t(context, 'subscription.tier_pro');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            isPlus ? AppColors.primary : AppColors.warning,
            isPlus ? AppColors.primaryDark : AppColors.warning,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.button,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tierLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    Text(
                      _money(cur.periodMoney) +
                          ' / ' +
                          (cur.billingPeriod == 'yearly'
                              ? t(context, 'subscription.period_yearly')
                              : t(context, 'subscription.period_monthly')),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (cur.currentPeriodEnd != null) ...[
            const SizedBox(height: 14),
            Text(
              cur.isCancelledButValid
                  ? '${t(context, 'subscription.expires_on')} ${_fmtDate(cur.currentPeriodEnd!)}'
                  : '${t(context, 'subscription.renews_on')} ${_fmtDate(cur.currentPeriodEnd!)}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          if (cur.isActive)
            OutlinedButton(
              onPressed: _busy ? null : _onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              child: Text(t(context, 'subscription.cancel_cta')),
            )
          else if (cur.isCancelledButValid)
            ElevatedButton(
              onPressed: _busy ? null : _onReactivate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
              child: Text(t(context, 'subscription.reactivate_cta')),
            ),
        ],
      ),
    );
  }

  Widget _buildBecomeCta() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.button,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⭐', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 10),
          Text(
            t(context, 'subscription.become_plus'),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            t(context, 'subscription.become_subtitle'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PeriodChoice(
              label: t(context, 'subscription.period_monthly'),
              selected: _selectedPeriod == 'monthly',
              onTap: () => setState(() => _selectedPeriod = 'monthly'),
            ),
          ),
          Expanded(
            child: _PeriodChoice(
              label: t(context, 'subscription.period_yearly'),
              selected: _selectedPeriod == 'yearly',
              badge: t(context, 'subscription.save_17'),
              onTap: () => setState(() => _selectedPeriod = 'yearly'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCard({
    required String tier,
    required String emoji,
    required Color color,
    required List<String> features,
  }) {
    final price = _pricing?.priceFor(tier, _selectedPeriod);
    final selected = _selectedTier == tier;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: () => setState(() => _selectedTier = tier),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: selected ? color : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 8),
                  Text(
                    tier == 'plus'
                        ? t(context, 'subscription.tier_plus')
                        : t(context, 'subscription.tier_pro'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _money(price),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final f in features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: color, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodChoice extends StatelessWidget {
  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      elevation: selected ? 2 : 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
