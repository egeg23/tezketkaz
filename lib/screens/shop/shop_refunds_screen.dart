import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import 'shop_shell.dart';

/// Phase 13.2.6 — Shop owner refunds / disputes screen.
///
/// Lists buyer-opened disputes for orders belonging to the current shop,
/// scoped via ShopMember. The shop owner can approve (full refund), partial-
/// refund, or reject. The actual refund is processed by the backend via
/// `disputesSvc.resolveDispute` → `refunds.refundOrder`.
class ShopRefundsScreen extends StatefulWidget {
  const ShopRefundsScreen({super.key});

  @override
  State<ShopRefundsScreen> createState() => _ShopRefundsScreenState();
}

class _ShopRefundsScreenState extends State<ShopRefundsScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  List<_Dispute> _disputes = [];
  String _filter = 'open'; // open | resolved | rejected | all

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? _shopId() => context.read<AuthProvider>().user?.shopId;

  Future<void> _load() async {
    final shopId = _shopId();
    if (shopId == null || shopId.isEmpty) {
      setState(() {
        _loading = false;
        _error = t(context, 'shop.refunds.no_shop');
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final query = <String, dynamic>{};
      if (_filter != 'all') query['status'] = _filter;
      final res = await _api.get('/api/shops/$shopId/disputes', query: query);
      final list = (res.data['disputes'] as List? ?? const [])
          .map((j) => _Dispute.fromJson(j as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() { _disputes = list; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _openDetail(_Dispute d) async {
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _RefundDetailScreen(dispute: d, shopId: _shopId()!),
    ));
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        title: Text(t(context, 'shop.refunds.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: t(context, 'common.refresh'),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            value: _filter,
            onChanged: (v) {
              setState(() => _filter = v);
              _load();
            },
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error)),
        ),
      );
    }
    if (_disputes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📭', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(t(context, 'shop.refunds.empty'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 15)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _disputes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _RefundRow(
          dispute: _disputes[i],
          onTap: () => _openDetail(_disputes[i]),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _FilterBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('open', t(context, 'shop.refunds.filter_open')),
      ('resolved', t(context, 'shop.refunds.filter_resolved')),
      ('rejected', t(context, 'shop.refunds.filter_rejected')),
      ('all', t(context, 'shop.refunds.filter_all')),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final selected = f.$1 == value;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.$2),
                selected: selected,
                onSelected: (_) => onChanged(f.$1),
                selectedColor: kShopColor.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: selected ? kShopColor : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _RefundRow extends StatelessWidget {
  final _Dispute dispute;
  final VoidCallback onTap;
  const _RefundRow({required this.dispute, required this.onTap});

  Color _statusColor() {
    switch (dispute.status) {
      case 'open':
      case 'under_review':
        return AppColors.warning;
      case 'resolved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.textHint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = dispute.order?.total ?? 0;
    final refunded = dispute.order?.refundedAmount ?? 0;
    final orderNum = dispute.order?.orderNumber ?? dispute.order?.id ?? '';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '#$orderNum',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: kShopColor,
                          fontSize: 14),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor().withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      t(context, 'shop.refunds.status_${dispute.status}'),
                      style: TextStyle(
                        color: _statusColor(),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      dispute.order?.customerName ?? '—',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${amount.toInt()} ${t(context, 'common.currency_uzs')}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${t(context, 'shop.refunds.reason_${dispute.reason}')}'
                '${(dispute.description ?? '').isNotEmpty ? ' — ${dispute.description}' : ''}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (refunded > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${t(context, 'shop.refunds.already_refunded')}: '
                  '${refunded.toInt()} ${t(context, 'common.currency_uzs')}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.success),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Detail screen ───────────────────────────────────────────────────────────

class _RefundDetailScreen extends StatefulWidget {
  final _Dispute dispute;
  final String shopId;
  const _RefundDetailScreen({required this.dispute, required this.shopId});

  @override
  State<_RefundDetailScreen> createState() => _RefundDetailScreenState();
}

class _RefundDetailScreenState extends State<_RefundDetailScreen> {
  final _api = ApiClient.instance;
  final _noteCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _submitting = false;
  bool _partial = false;

  @override
  void initState() {
    super.initState();
    final remaining = (widget.dispute.order?.total ?? 0)
        - (widget.dispute.order?.refundedAmount ?? 0);
    if (remaining > 0) {
      _amountCtrl.text = remaining.toInt().toString();
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolve(String resolution) async {
    if (_submitting) return;
    final body = <String, dynamic>{
      'resolution': resolution,
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    };
    if (resolution == 'refund' || resolution == 'partial_refund') {
      final amt = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
      if (amt == null || amt <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(context, 'shop.refunds.amount_invalid')),
          backgroundColor: AppColors.error,
        ));
        return;
      }
      body['refundAmount'] = amt;
    }

    setState(() => _submitting = true);
    try {
      await _api.post(
        '/api/shops/${widget.shopId}/disputes/${widget.dispute.id}/resolve',
        body,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(context, 'shop.refunds.success')),
        backgroundColor: AppColors.success,
      ));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${t(context, 'common.error')}: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dispute;
    final closed = d.status == 'resolved' || d.status == 'rejected';
    final total = (d.order?.total ?? 0).toInt();
    final refunded = (d.order?.refundedAmount ?? 0).toInt();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        title: Text(t(context, 'shop.refunds.detail_title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: t(context, 'shop.refunds.order_section'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(t(context, 'shop.refunds.order_id'),
                    '#${d.order?.orderNumber ?? d.order?.id ?? "—"}'),
                _kv(t(context, 'shop.refunds.customer'),
                    d.order?.customerName ?? '—'),
                _kv(t(context, 'shop.refunds.amount'),
                    '$total ${t(context, 'common.currency_uzs')}'),
                if (refunded > 0)
                  _kv(t(context, 'shop.refunds.already_refunded'),
                      '$refunded ${t(context, 'common.currency_uzs')}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: t(context, 'shop.refunds.reason_section'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(t(context, 'shop.refunds.reason'),
                    t(context, 'shop.refunds.reason_${d.reason}')),
                if ((d.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(d.description!,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textPrimary)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (closed)
            _Section(
              title: t(context, 'shop.refunds.resolution_section'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv(t(context, 'shop.refunds.status'),
                      t(context, 'shop.refunds.status_${d.status}')),
                  if (d.resolution != null)
                    _kv(t(context, 'shop.refunds.action'),
                        t(context, 'shop.refunds.resolution_${d.resolution}')),
                  if ((d.resolutionNote ?? '').isNotEmpty)
                    _kv(t(context, 'shop.refunds.note'), d.resolutionNote!),
                ],
              ),
            )
          else
            _Section(
              title: t(context, 'shop.refunds.action_section'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t(context, 'shop.refunds.partial')),
                    subtitle:
                        Text(t(context, 'shop.refunds.partial_help')),
                    value: _partial,
                    activeColor: kShopColor,
                    onChanged: (v) => setState(() => _partial = v),
                  ),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: t(context, 'shop.refunds.refund_amount'),
                      suffixText: t(context, 'common.currency_uzs'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _noteCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: t(context, 'shop.refunds.note'),
                      hintText: t(context, 'shop.refunds.note_hint'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => _resolve('rejected'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(t(context, 'shop.refunds.reject')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submitting
                              ? null
                              : () => _resolve(
                                  _partial ? 'partial_refund' : 'refund'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kShopColor,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                          Colors.white)),
                                )
                              : Text(t(context, 'shop.refunds.approve')),
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

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(k,
                  style:
                      const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
            Expanded(
              flex: 6,
              child: Text(v,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    fontSize: 13)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

// ─── Models ───────────────────────────────────────────────────────────────────

class _Dispute {
  final String id;
  final String reason;
  final String? description;
  final String status;
  final String? resolution;
  final double refundAmount;
  final String? resolutionNote;
  final DateTime createdAt;
  final _DisputeOrder? order;

  _Dispute({
    required this.id,
    required this.reason,
    required this.description,
    required this.status,
    required this.resolution,
    required this.refundAmount,
    required this.resolutionNote,
    required this.createdAt,
    required this.order,
  });

  factory _Dispute.fromJson(Map<String, dynamic> j) => _Dispute(
        id: j['id'] as String,
        reason: (j['reason'] ?? 'other') as String,
        description: j['description'] as String?,
        status: (j['status'] ?? 'open') as String,
        resolution: j['resolution'] as String?,
        refundAmount: (j['refundAmount'] as num?)?.toDouble() ?? 0.0,
        resolutionNote: j['resolutionNote'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        order: j['order'] == null
            ? null
            : _DisputeOrder.fromJson(j['order'] as Map<String, dynamic>),
      );
}

class _DisputeOrder {
  final String id;
  final String? orderNumber;
  final double total;
  final double refundedAmount;
  final String? customerName;
  final String? status;

  _DisputeOrder({
    required this.id,
    required this.orderNumber,
    required this.total,
    required this.refundedAmount,
    required this.customerName,
    required this.status,
  });

  factory _DisputeOrder.fromJson(Map<String, dynamic> j) => _DisputeOrder(
        id: j['id'] as String,
        orderNumber: j['orderNumber'] as String?,
        total: (j['total'] as num?)?.toDouble() ?? 0.0,
        refundedAmount: (j['refundedAmount'] as num?)?.toDouble() ?? 0.0,
        customerName: j['customerName'] as String?,
        status: j['status'] as String?,
      );
}
