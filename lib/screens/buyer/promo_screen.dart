import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n.dart';
import '../../models/promo.dart';
import '../../services/api_client.dart';
import '../../services/promo_api.dart';
import '../../theme/app_theme.dart';

/// Lists eligible coupons for the current buyer.
///
/// Tapping the code copies it. Tapping "Apply" pops with the code so the
/// caller (cart screen) can run validation + apply.
class PromoScreen extends StatefulWidget {
  final String? shopId;
  final num? subtotal;
  const PromoScreen({super.key, this.shopId, this.subtotal});

  @override
  State<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends State<PromoScreen> {
  bool _loading = true;
  String? _error;
  List<Coupon> _coupons = const [];

  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await PromoApi.instance
          .myEligible(shopId: widget.shopId, subtotal: widget.subtotal);
      if (!mounted) return;
      setState(() {
        _coupons = res;
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

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${t(context, 'promo.copied')}: $code'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _applyManual() {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(t(context, 'promo.title'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Manual code entry
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: t(context, 'promo.enter_code'),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _applyManual,
                    child: Text(t(context, 'promo.apply')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
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
              )
            else if (_coupons.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    const Text('🎟️', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(t(context, 'promo.empty'),
                        style: const TextStyle(
                            color: AppColors.textSecondary)),
                  ],
                ),
              )
            else
              for (final c in _coupons) ...[
                _CouponCard(
                  coupon: c,
                  onCopy: () => _copy(c.code),
                  onApply: () => Navigator.of(context).pop(c.code),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  final Coupon coupon;
  final VoidCallback onCopy;
  final VoidCallback onApply;
  const _CouponCard({
    required this.coupon,
    required this.onCopy,
    required this.onApply,
  });

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: type icon + discount + dashed perforation
          Container(
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppRadii.lg)),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  alignment: Alignment.center,
                  child: Text(coupon.typeIcon,
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      )),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        coupon.title ?? coupon.discountLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        coupon.discountLabel,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (coupon.description != null) ...[
                  Text(
                    coupon.description!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (coupon.conditions != null &&
                    coupon.conditions!.isNotEmpty) ...[
                  for (final c in coupon.conditions!) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Icon(Icons.check_rounded,
                              size: 14, color: AppColors.success),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(c,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  const SizedBox(height: 4),
                ],
                if (coupon.validUntil != null)
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 14, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text(
                        '${t(context, 'promo.until')} ${_fmtDate(coupon.validUntil)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textHint),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCopy,
                        child: Text('${coupon.code}  📋'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onApply,
                        child: Text(t(context, 'promo.apply')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
