import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import 'shop_shell.dart';

/// Phase 13.2.6 — Shop owner promo / coupon screen.
///
/// Lists coupons scoped to the current shop (Coupon.shopId == shopId) and lets
/// the owner create, edit and toggle them. Hard-delete is only allowed when
/// the coupon has zero redemptions; otherwise the owner deactivates it.
class ShopPromoScreen extends StatefulWidget {
  const ShopPromoScreen({super.key});

  @override
  State<ShopPromoScreen> createState() => _ShopPromoScreenState();
}

class _ShopPromoScreenState extends State<ShopPromoScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  List<_Coupon> _coupons = [];

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
        _error = t(context, 'shop.promo.no_shop');
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _api.get('/api/shops/$shopId/coupons');
      final list = (res.data['coupons'] as List? ?? const [])
          .map((j) => _Coupon.fromJson(j as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() { _coupons = list; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _create() async {
    final shopId = _shopId();
    if (shopId == null) return;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _CouponEditor(shopId: shopId, coupon: null),
    ));
    if (result == true) _load();
  }

  Future<void> _edit(_Coupon c) async {
    final shopId = _shopId();
    if (shopId == null) return;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _CouponEditor(shopId: shopId, coupon: c),
    ));
    if (result == true) _load();
  }

  Future<void> _toggleActive(_Coupon c) async {
    final shopId = _shopId();
    if (shopId == null) return;
    try {
      await _api.patch(
        '/api/shops/$shopId/coupons/${c.code}',
        {'isActive': !c.isActive},
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${t(context, 'common.error')}: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _delete(_Coupon c) async {
    final shopId = _shopId();
    if (shopId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t(context, 'shop.promo.delete_confirm_title')),
        content: Text(t(context, 'shop.promo.delete_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(t(context, 'common.delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.delete('/api/shops/$shopId/coupons/${c.code}');
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${t(context, 'common.error')}: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        title: Text(t(context, 'shop.promo.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(t(context, 'shop.promo.create')),
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
    if (_coupons.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏷️', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(t(context, 'shop.promo.empty'),
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(t(context, 'shop.promo.empty_hint'),
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 12)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: _coupons.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _CouponRow(
          coupon: _coupons[i],
          onEdit: () => _edit(_coupons[i]),
          onToggle: () => _toggleActive(_coupons[i]),
          onDelete: () => _delete(_coupons[i]),
        ),
      ),
    );
  }
}

class _CouponRow extends StatelessWidget {
  final _Coupon coupon;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  const _CouponRow({
    required this.coupon,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  String _valueLabel(BuildContext context) {
    switch (coupon.type) {
      case 'PERCENT':
        return '-${coupon.value.toInt()}%';
      case 'FIXED':
        return '-${coupon.value.toInt()} ${t(context, 'common.currency_uzs')}';
      case 'FREE_DELIVERY':
      default:
        return t(context, 'shop.promo.type_free_delivery');
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = coupon.validUntil.isBefore(DateTime.now());
    final used = coupon.usedCount;
    final limit = coupon.usageLimit;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onEdit,
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
                      coupon.code,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: kShopColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: coupon.isActive && !expired
                          ? AppColors.successLight
                          : AppColors.errorLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      coupon.isActive && !expired
                          ? t(context, 'shop.promo.active')
                          : (expired
                              ? t(context, 'shop.promo.expired')
                              : t(context, 'shop.promo.inactive')),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: coupon.isActive && !expired
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_valueLabel(context),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.event,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '${_d(coupon.validFrom)} → ${_d(coupon.validUntil)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  Text(
                    limit == null
                        ? '$used ${t(context, 'shop.promo.uses')}'
                        : '$used / $limit',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textHint),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onToggle,
                    icon: Icon(
                      coupon.isActive
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      size: 18,
                    ),
                    label: Text(coupon.isActive
                        ? t(context, 'shop.promo.deactivate')
                        : t(context, 'shop.promo.activate')),
                    style: TextButton.styleFrom(foregroundColor: kShopColor),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: AppColors.error),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _d(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}

// ─── Editor ──────────────────────────────────────────────────────────────────

class _CouponEditor extends StatefulWidget {
  final String shopId;
  final _Coupon? coupon;
  const _CouponEditor({required this.shopId, required this.coupon});

  @override
  State<_CouponEditor> createState() => _CouponEditorState();
}

class _CouponEditorState extends State<_CouponEditor> {
  final _api = ApiClient.instance;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _codeCtrl;
  late TextEditingController _valueCtrl;
  late TextEditingController _minOrderCtrl;
  late TextEditingController _maxDiscountCtrl;
  late TextEditingController _usageLimitCtrl;
  String _type = 'PERCENT';
  DateTime _validFrom = DateTime.now();
  DateTime _validUntil = DateTime.now().add(const Duration(days: 30));
  bool _isActive = true;
  bool _submitting = false;

  bool get _isEdit => widget.coupon != null;

  @override
  void initState() {
    super.initState();
    final c = widget.coupon;
    _codeCtrl = TextEditingController(text: c?.code ?? _randomCode());
    _valueCtrl = TextEditingController(text: c?.value.toString() ?? '10');
    _minOrderCtrl =
        TextEditingController(text: c?.minOrder?.toInt().toString() ?? '');
    _maxDiscountCtrl =
        TextEditingController(text: c?.maxDiscount?.toInt().toString() ?? '');
    _usageLimitCtrl =
        TextEditingController(text: c?.usageLimit?.toString() ?? '');
    _type = c?.type ?? 'PERCENT';
    _validFrom = c?.validFrom ?? DateTime.now();
    _validUntil =
        c?.validUntil ?? DateTime.now().add(const Duration(days: 30));
    _isActive = c?.isActive ?? true;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _minOrderCtrl.dispose();
    _maxDiscountCtrl.dispose();
    _usageLimitCtrl.dispose();
    super.dispose();
  }

  static String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(7, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _validFrom : _validUntil;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (isStart) {
        _validFrom = d;
      } else {
        _validUntil = d;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_validUntil.isBefore(_validFrom) ||
        _validUntil.isAtSameMomentAs(_validFrom)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(context, 'shop.promo.error_dates')),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _submitting = true);
    final body = <String, dynamic>{
      'code': _codeCtrl.text.trim().toUpperCase(),
      'type': _type,
      'value': _type == 'FREE_DELIVERY'
          ? 0
          : double.tryParse(_valueCtrl.text.replaceAll(',', '.')) ?? 0,
      'validFrom': _validFrom.toIso8601String(),
      'validUntil': _validUntil.toIso8601String(),
      'isActive': _isActive,
    };
    final minOrder = double.tryParse(_minOrderCtrl.text.replaceAll(',', '.'));
    if (minOrder != null) body['minOrder'] = minOrder;
    final maxDiscount =
        double.tryParse(_maxDiscountCtrl.text.replaceAll(',', '.'));
    if (maxDiscount != null) body['maxDiscount'] = maxDiscount;
    final usageLimit = int.tryParse(_usageLimitCtrl.text);
    if (usageLimit != null) body['usageLimit'] = usageLimit;

    try {
      if (_isEdit) {
        // Code is immutable on edit — server-side primary key.
        body.remove('code');
        await _api.patch(
          '/api/shops/${widget.shopId}/coupons/${widget.coupon!.code}',
          body,
        );
      } else {
        await _api.post('/api/shops/${widget.shopId}/coupons', body);
      }
      if (!mounted) return;
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        title: Text(_isEdit
            ? t(context, 'shop.promo.edit_title')
            : t(context, 'shop.promo.create_title')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Code
            TextFormField(
              controller: _codeCtrl,
              enabled: !_isEdit,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(24),
              ],
              decoration: InputDecoration(
                labelText: t(context, 'shop.promo.code'),
                hintText: 'WELCOME10',
                border: const OutlineInputBorder(),
                suffixIcon: _isEdit
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.casino),
                        tooltip: t(context, 'shop.promo.generate'),
                        onPressed: () =>
                            setState(() => _codeCtrl.text = _randomCode()),
                      ),
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? t(context, 'shop.promo.error_code')
                  : null,
            ),
            const SizedBox(height: 14),

            // Type
            DropdownButtonFormField<String>(
              value: _type,
              decoration: InputDecoration(
                labelText: t(context, 'shop.promo.type'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'PERCENT',
                  child: Text(t(context, 'shop.promo.type_percent')),
                ),
                DropdownMenuItem(
                  value: 'FIXED',
                  child: Text(t(context, 'shop.promo.type_fixed')),
                ),
                DropdownMenuItem(
                  value: 'FREE_DELIVERY',
                  child: Text(t(context, 'shop.promo.type_free_delivery')),
                ),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'PERCENT'),
            ),
            const SizedBox(height: 14),

            // Value (skip for FREE_DELIVERY)
            if (_type != 'FREE_DELIVERY')
              TextFormField(
                controller: _valueCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: InputDecoration(
                  labelText: _type == 'PERCENT'
                      ? t(context, 'shop.promo.value_percent')
                      : t(context, 'shop.promo.value_fixed'),
                  suffixText: _type == 'PERCENT'
                      ? '%'
                      : t(context, 'common.currency_uzs'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                  if (n == null || n <= 0) {
                    return t(context, 'shop.promo.error_value');
                  }
                  if (_type == 'PERCENT' && n > 100) {
                    return t(context, 'shop.promo.error_percent_range');
                  }
                  return null;
                },
              ),
            if (_type != 'FREE_DELIVERY') const SizedBox(height: 14),

            // Min order
            TextFormField(
              controller: _minOrderCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t(context, 'shop.promo.min_order'),
                helperText: t(context, 'shop.promo.min_order_help'),
                suffixText: t(context, 'common.currency_uzs'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),

            // Max discount (only meaningful for PERCENT)
            if (_type == 'PERCENT')
              TextFormField(
                controller: _maxDiscountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t(context, 'shop.promo.max_discount'),
                  helperText: t(context, 'shop.promo.max_discount_help'),
                  suffixText: t(context, 'common.currency_uzs'),
                  border: const OutlineInputBorder(),
                ),
              ),
            if (_type == 'PERCENT') const SizedBox(height: 14),

            // Usage limit
            TextFormField(
              controller: _usageLimitCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t(context, 'shop.promo.usage_limit'),
                helperText: t(context, 'shop.promo.usage_limit_help'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),

            // Dates
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: t(context, 'shop.promo.valid_from'),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(_fmt(_validFrom)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: t(context, 'shop.promo.valid_until'),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(_fmt(_validUntil)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t(context, 'shop.promo.is_active')),
              value: _isActive,
              activeColor: kShopColor,
              onChanged: (v) => setState(() => _isActive = v),
            ),
            const SizedBox(height: 18),

            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: kShopColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(_isEdit
                      ? t(context, 'shop.promo.save')
                      : t(context, 'shop.promo.create')),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}

// ─── Model ───────────────────────────────────────────────────────────────────

class _Coupon {
  final String code;
  final String type;
  final double value;
  final double? minOrder;
  final double? maxDiscount;
  final DateTime validFrom;
  final DateTime validUntil;
  final int? usageLimit;
  final int usagePerUser;
  final int usedCount;
  final bool firstOrderOnly;
  final bool isActive;

  _Coupon({
    required this.code,
    required this.type,
    required this.value,
    required this.minOrder,
    required this.maxDiscount,
    required this.validFrom,
    required this.validUntil,
    required this.usageLimit,
    required this.usagePerUser,
    required this.usedCount,
    required this.firstOrderOnly,
    required this.isActive,
  });

  factory _Coupon.fromJson(Map<String, dynamic> j) => _Coupon(
        code: j['code'] as String,
        type: (j['type'] ?? 'PERCENT') as String,
        value: (j['value'] as num?)?.toDouble() ?? 0.0,
        minOrder: (j['minOrder'] as num?)?.toDouble(),
        maxDiscount: (j['maxDiscount'] as num?)?.toDouble(),
        validFrom: DateTime.tryParse(j['validFrom'] as String? ?? '') ??
            DateTime.now(),
        validUntil: DateTime.tryParse(j['validUntil'] as String? ?? '') ??
            DateTime.now().add(const Duration(days: 30)),
        usageLimit: j['usageLimit'] as int?,
        usagePerUser: (j['usagePerUser'] as int?) ?? 1,
        usedCount: (j['usedCount'] as int?) ?? 0,
        firstOrderOnly: (j['firstOrderOnly'] as bool?) ?? false,
        isActive: (j['isActive'] as bool?) ?? true,
      );
}
