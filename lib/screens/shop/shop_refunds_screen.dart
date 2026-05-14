import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/money.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

/// Phase 13.2.6 — shop owner refund / dispute resolution screen.
///
/// Lists every dispute attached to the shop's orders. Open disputes appear
/// first; resolved / rejected drop into separate filters. Tapping a row
/// opens [_ShopRefundDetailScreen] which lets the owner approve, reject or
/// issue a partial refund through the shared `/api/shops/:id/disputes/:id/
/// resolve` endpoint.
class ShopRefundsScreen extends StatefulWidget {
  const ShopRefundsScreen({super.key});

  @override
  State<ShopRefundsScreen> createState() => _ShopRefundsScreenState();
}

enum _RefundFilter { open, resolved, rejected, all }

class _ShopRefundsScreenState extends State<ShopRefundsScreen> {
  _RefundFilter _filter = _RefundFilter.open;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _disputes = const [];

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
      final res = await ApiClient.instance
          .get('/api/shops/$shopId/disputes', query: {
        'limit': 100,
      });
      final raw = res.data;
      final list = raw is Map && raw['disputes'] is List
          ? (raw['disputes'] as List)
          : const [];
      _disputes = list
          .map((d) => d is Map
              ? Map<String, dynamic>.from(d)
              : <String, dynamic>{})
          .toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    switch (_filter) {
      case _RefundFilter.open:
        return _disputes
            .where((d) =>
                (d['status'] as String?)?.toLowerCase() == 'open' ||
                (d['status'] as String?)?.toLowerCase() == 'under_review')
            .toList();
      case _RefundFilter.resolved:
        return _disputes
            .where((d) => (d['status'] as String?)?.toLowerCase() == 'resolved')
            .toList();
      case _RefundFilter.rejected:
        return _disputes
            .where((d) => (d['status'] as String?)?.toLowerCase() == 'rejected')
            .toList();
      case _RefundFilter.all:
        return _disputes;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopId = _shopId;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(t(context, 'shop.refunds.title')),
      ),
      body: shopId == null
          ? _NoShopEmpty(label: t(context, 'shop.refunds.no_shop'))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    t(context, 'shop.refunds.subtitle'),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _FilterBar(
                    active: _filter,
                    onTap: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    _ErrorBlock(message: _error!)
                  else if (_filtered.isEmpty)
                    _EmptyBlock(message: t(context, 'shop.refunds.empty'))
                  else
                    ..._filtered.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DisputeRow(
                            dispute: d,
                            onTap: () => _openDetail(d),
                          ),
                        )),
                ],
              ),
            ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> dispute) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ShopRefundDetailScreen(
          shopId: _shopId!,
          dispute: dispute,
        ),
      ),
    );
    if (result == true) await _load();
  }
}

class _FilterBar extends StatelessWidget {
  final _RefundFilter active;
  final ValueChanged<_RefundFilter> onTap;

  const _FilterBar({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final entries = <(_RefundFilter, String)>[
      (_RefundFilter.open, t(context, 'shop.refunds.filter_open')),
      (_RefundFilter.resolved, t(context, 'shop.refunds.filter_resolved')),
      (_RefundFilter.rejected, t(context, 'shop.refunds.filter_rejected')),
      (_RefundFilter.all, t(context, 'shop.refunds.filter_all')),
    ];
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final e in entries) ...[
            _Chip(
              label: e.$2,
              active: active == e.$1,
              onTap: () => onTap(e.$1),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.bg : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
}

class _DisputeRow extends StatelessWidget {
  final Map<String, dynamic> dispute;
  final VoidCallback onTap;
  const _DisputeRow({required this.dispute, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final order = (dispute['order'] is Map)
        ? Map<String, dynamic>.from(dispute['order'] as Map)
        : const <String, dynamic>{};
    final status = (dispute['status'] as String? ?? 'open').toLowerCase();
    final reason = (dispute['reason'] as String? ?? '').toLowerCase();
    final amount = (order['total'] as num?)?.toDouble() ?? 0;
    final rawId = order['id'] as String? ?? '';
    final orderNumber = order['orderNumber'] as String? ??
        (rawId.length >= 8 ? rawId.substring(0, 8) : rawId);
    final customer = order['customerName'] as String? ?? '—';
    final lang = L10n.instance.locale.languageCode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '#$orderNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusPill(status: status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                customer,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _reasonLabel(context, reason),
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    Money(amount).format(lang),
                    style: GoogleFonts.jetBrainsMono(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _reasonLabel(BuildContext context, String key) {
    switch (key) {
      case 'missing_items':
      case 'missing':
        return t(context, 'shop.refunds.reason_missing_items');
      case 'wrong_items':
      case 'wrong':
        return t(context, 'shop.refunds.reason_wrong_items');
      case 'late':
        return t(context, 'shop.refunds.reason_late');
      case 'damaged':
        return t(context, 'shop.refunds.reason_damaged');
      default:
        return t(context, 'shop.refunds.reason_other');
    }
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'open' => (t(context, 'shop.refunds.status_open'), AppColors.warning),
      'under_review' =>
        (t(context, 'shop.refunds.status_under_review'), AppColors.info),
      'resolved' =>
        (t(context, 'shop.refunds.status_resolved'), AppColors.success),
      'rejected' =>
        (t(context, 'shop.refunds.status_rejected'), AppColors.error),
      _ => (status, AppColors.textHint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  final String message;
  const _EmptyBlock({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.inbox_rounded,
                  size: 48, color: AppColors.textHint),
              const SizedBox(height: 8),
              Text(
                message,
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  const _ErrorBlock({required this.message});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: AppColors.errorLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message,
          style: const TextStyle(color: AppColors.error, fontSize: 13),
        ),
      );
}

class _NoShopEmpty extends StatelessWidget {
  final String label;
  const _NoShopEmpty({required this.label});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront_rounded,
                  size: 48, color: AppColors.textHint),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
}

// ─── Detail screen ────────────────────────────────────────────────────────

enum _Resolution { approve, reject, partial }

class _ShopRefundDetailScreen extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic> dispute;
  const _ShopRefundDetailScreen({
    required this.shopId,
    required this.dispute,
  });

  @override
  State<_ShopRefundDetailScreen> createState() =>
      _ShopRefundDetailScreenState();
}

class _ShopRefundDetailScreenState extends State<_ShopRefundDetailScreen> {
  _Resolution _resolution = _Resolution.approve;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  Map<String, dynamic> get _order =>
      widget.dispute['order'] is Map
          ? Map<String, dynamic>.from(widget.dispute['order'] as Map)
          : <String, dynamic>{};

  double get _orderTotal =>
      (_order['total'] as num?)?.toDouble() ?? 0;

  bool get _isTerminal {
    final s = (widget.dispute['status'] as String? ?? '').toLowerCase();
    return s == 'resolved' || s == 'rejected';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Map UI choice → backend resolution code.
      final String code;
      double? refundAmount;
      switch (_resolution) {
        case _Resolution.approve:
          code = 'refund';
          refundAmount = _orderTotal;
          break;
        case _Resolution.partial:
          code = 'partial_refund';
          final raw = double.tryParse(_amountCtrl.text.trim()
              .replaceAll(',', '.')
              .replaceAll(' ', ''));
          if (raw == null || raw <= 0 || raw > _orderTotal) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t(context, 'shop.refunds.amount_invalid')),
            ));
            setState(() => _saving = false);
            return;
          }
          refundAmount = raw;
          break;
        case _Resolution.reject:
          code = 'rejected';
          break;
      }

      await ApiClient.instance.post(
        '/api/shops/${widget.shopId}/disputes/${widget.dispute['id']}/resolve',
        {
          'resolution': code,
          if (refundAmount != null) 'refundAmount': refundAmount,
          if (_noteCtrl.text.trim().isNotEmpty)
            'note': _noteCtrl.text.trim(),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(context, 'shop.refunds.success')),
      ));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${t(context, 'tracking.error_prefix')}: $e'),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final lang = L10n.instance.locale.languageCode;
    final orderNumber = order['orderNumber'] as String? ??
        (order['id'] as String? ?? '');
    final customer = order['customerName'] as String? ?? '—';
    final status = (widget.dispute['status'] as String? ?? '').toLowerCase();
    final refunded = (order['refundedAmount'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(t(context, 'shop.refunds.detail_title')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Section(
            title: t(context, 'shop.refunds.order_section'),
            children: [
              _Row(
                label: t(context, 'shop.refunds.order_id'),
                value: '#$orderNumber',
              ),
              _Row(
                label: t(context, 'shop.refunds.customer'),
                value: customer,
              ),
              _Row(
                label: t(context, 'shop.refunds.amount'),
                value: Money(_orderTotal).format(lang),
              ),
              if (refunded > 0)
                _Row(
                  label: t(context, 'shop.refunds.already_refunded'),
                  value: Money(refunded).format(lang),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: t(context, 'shop.refunds.reason_section'),
            children: [
              _Row(
                label: t(context, 'shop.refunds.reason'),
                value: (widget.dispute['reason'] as String? ?? '—'),
              ),
              if ((widget.dispute['description'] as String?)?.isNotEmpty ==
                  true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.dispute['description'] as String,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: t(context, 'shop.refunds.status'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _StatusPill(status: status),
              ),
            ],
          ),
          if (!_isTerminal) ...[
            const SizedBox(height: 16),
            _Section(
              title: t(context, 'shop.refunds.action_section'),
              children: [
                _ResolutionChips(
                  active: _resolution,
                  onChange: (r) => setState(() => _resolution = r),
                ),
                if (_resolution == _Resolution.partial) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: t(context, 'shop.refunds.refund_amount'),
                      helperText: t(context, 'shop.refunds.partial_help'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _noteCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: t(context, 'shop.refunds.note'),
                    hintText: t(context, 'shop.refunds.note_hint'),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: AppColors.bg,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _resolution == _Resolution.reject
                              ? t(context, 'shop.refunds.reject')
                              : t(context, 'shop.refunds.approve'),
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _ResolutionChips extends StatelessWidget {
  final _Resolution active;
  final ValueChanged<_Resolution> onChange;
  const _ResolutionChips({required this.active, required this.onChange});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _build(context, _Resolution.approve,
              t(context, 'shop.refunds.resolution_refund')),
          _build(context, _Resolution.partial,
              t(context, 'shop.refunds.partial')),
          _build(context, _Resolution.reject, t(context, 'shop.refunds.reject')),
        ],
      );

  Widget _build(BuildContext context, _Resolution r, String label) {
    final isActive = r == active;
    return GestureDetector(
      onTap: () => onChange(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.bg : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
