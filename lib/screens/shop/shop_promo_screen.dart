import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/money.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

/// Phase 13.2.6 — shop coupon / promo code management.
///
/// Lists every coupon attached to the current shop (active first, then
/// inactive / expired). A FAB opens the create sheet; tapping a row opens
/// edit mode. All writes go through `/api/shops/:id/coupons` so the backend
/// validates uniqueness, dates and discount-type combinations centrally.
class ShopPromoScreen extends StatefulWidget {
  const ShopPromoScreen({super.key});

  @override
  State<ShopPromoScreen> createState() => _ShopPromoScreenState();
}

class _ShopPromoScreenState extends State<ShopPromoScreen> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _coupons = const [];

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
      final res = await ApiClient.instance.get('/api/shops/$shopId/coupons');
      final raw = res.data;
      final list = raw is Map && raw['coupons'] is List
          ? (raw['coupons'] as List)
          : const [];
      _coupons = list
          .map((c) => c is Map
              ? Map<String, dynamic>.from(c)
              : <String, dynamic>{})
          .toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final shopId = _shopId;
    if (shopId == null) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CouponEditorSheet(
        shopId: shopId,
        existing: existing,
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final shopId = _shopId;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(t(context, 'shop.promo.title'))),
      floatingActionButton: shopId == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.bg,
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                t(context, 'shop.promo.create'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
      body: shopId == null
          ? Center(
              child: Text(
                t(context, 'shop.promo.no_shop'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  Text(
                    t(context, 'shop.promo.subtitle'),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(color: AppColors.error)),
                    )
                  else if (_coupons.isEmpty)
                    _Empty(
                      title: t(context, 'shop.promo.empty'),
                      hint: t(context, 'shop.promo.empty_hint'),
                    )
                  else
                    ..._coupons.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CouponRow(
                          coupon: c,
                          onTap: () => _openEditor(existing: c),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String title;
  final String hint;
  const _Empty({required this.title, required this.hint});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const Icon(Icons.local_offer_outlined,
                size: 48, color: AppColors.textHint),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
      );
}

class _CouponRow extends StatelessWidget {
  final Map<String, dynamic> coupon;
  final VoidCallback onTap;
  const _CouponRow({required this.coupon, required this.onTap});

  bool get _expired {
    final raw = coupon['validUntil'];
    if (raw is! String) return false;
    final dt = DateTime.tryParse(raw);
    return dt != null && dt.isBefore(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final code = (coupon['code'] as String? ?? '').toUpperCase();
    final type = (coupon['type'] as String? ?? '').toLowerCase();
    final value = (coupon['value'] as num?)?.toDouble() ?? 0;
    final usageCount = (coupon['usageCount'] as num?)?.toInt() ?? 0;
    final usageLimit = (coupon['usageLimit'] as num?)?.toInt();
    final isActive = coupon['isActive'] == true;
    final lang = L10n.instance.locale.languageCode;

    String discount;
    if (type == 'percent') {
      discount = '-${value.toStringAsFixed(0)}%';
    } else if (type == 'fixed') {
      discount = '-${Money(value).format(lang)}';
    } else {
      discount = t(context, 'shop.promo.type_free_delivery');
    }

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
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.local_offer_rounded,
                  color: isActive ? AppColors.primary : AppColors.textHint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          code,
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(
                          label: _expired
                              ? t(context, 'shop.promo.expired')
                              : isActive
                                  ? t(context, 'shop.promo.active')
                                  : t(context, 'shop.promo.inactive'),
                          color: _expired
                              ? AppColors.error
                              : isActive
                                  ? AppColors.success
                                  : AppColors.textHint,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$discount · ${usageCount}${usageLimit != null ? '/$usageLimit' : ''} ${t(context, 'shop.promo.uses')}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

// ─── Editor sheet ─────────────────────────────────────────────────────────

class _CouponEditorSheet extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic>? existing;
  const _CouponEditorSheet({required this.shopId, this.existing});

  @override
  State<_CouponEditorSheet> createState() => _CouponEditorSheetState();
}

class _CouponEditorSheetState extends State<_CouponEditorSheet> {
  final _codeCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _minOrderCtrl = TextEditingController();
  final _maxDiscountCtrl = TextEditingController();
  final _usageLimitCtrl = TextEditingController();

  String _type = 'percent';
  DateTime _validFrom = DateTime.now();
  DateTime _validUntil =
      DateTime.now().add(const Duration(days: 30));
  bool _isActive = true;
  bool _saving = false;
  String? _formError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _codeCtrl.text = (e['code'] as String? ?? '').toUpperCase();
      _type = (e['type'] as String? ?? 'percent').toLowerCase();
      _valueCtrl.text =
          (e['value'] as num?)?.toString() ?? '';
      _minOrderCtrl.text = e['minOrder']?.toString() ?? '';
      _maxDiscountCtrl.text = e['maxDiscount']?.toString() ?? '';
      _usageLimitCtrl.text = e['usageLimit']?.toString() ?? '';
      _isActive = e['isActive'] == true;
      final from = e['validFrom'];
      if (from is String) {
        _validFrom = DateTime.tryParse(from) ?? _validFrom;
      }
      final until = e['validUntil'];
      if (until is String) {
        _validUntil = DateTime.tryParse(until) ?? _validUntil;
      }
    }
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

  void _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    final code = List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
    _codeCtrl.text = code;
    HapticFeedback.selectionClick();
    setState(() {});
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final initial = isFrom ? _validFrom : _validUntil;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _validFrom = picked;
      } else {
        _validUntil = picked;
      }
    });
  }

  String? _validate() {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 3) return t(context, 'shop.promo.error_code');
    final value =
        double.tryParse(_valueCtrl.text.trim().replaceAll(',', '.'));
    if (_type != 'free_delivery') {
      if (value == null || value <= 0) {
        return t(context, 'shop.promo.error_value');
      }
      if (_type == 'percent' && (value < 1 || value > 100)) {
        return t(context, 'shop.promo.error_percent_range');
      }
    }
    if (!_validUntil.isAfter(_validFrom)) {
      return t(context, 'shop.promo.error_dates');
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final err = _validate();
    if (err != null) {
      setState(() => _formError = err);
      return;
    }
    setState(() {
      _formError = null;
      _saving = true;
    });
    try {
      final body = <String, dynamic>{
        'code': _codeCtrl.text.trim().toUpperCase(),
        'type': _type,
        'value': _type == 'free_delivery'
            ? 0
            : double.parse(
                _valueCtrl.text.trim().replaceAll(',', '.')),
        'validFrom': _validFrom.toIso8601String(),
        'validUntil': _validUntil.toIso8601String(),
        'isActive': _isActive,
        if (_minOrderCtrl.text.trim().isNotEmpty)
          'minOrder': double.tryParse(
              _minOrderCtrl.text.trim().replaceAll(',', '.')),
        if (_maxDiscountCtrl.text.trim().isNotEmpty)
          'maxDiscount': double.tryParse(
              _maxDiscountCtrl.text.trim().replaceAll(',', '.')),
        if (_usageLimitCtrl.text.trim().isNotEmpty)
          'usageLimit': int.tryParse(_usageLimitCtrl.text.trim()),
      };
      if (_isEdit) {
        final code = (widget.existing!['code'] as String).toUpperCase();
        await ApiClient.instance
            .patch('/api/shops/${widget.shopId}/coupons/$code', body);
      } else {
        await ApiClient.instance
            .post('/api/shops/${widget.shopId}/coupons', body);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _formError = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t(context, 'shop.promo.delete_confirm_title')),
        content: Text(t(context, 'shop.promo.delete_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, 'common.cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, 'common.delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final code = (widget.existing!['code'] as String).toUpperCase();
      await ApiClient.instance
          .delete('/api/shops/${widget.shopId}/coupons/$code');
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // 409 = has redemptions → deactivate instead.
      try {
        final code = (widget.existing!['code'] as String).toUpperCase();
        await ApiClient.instance.patch(
          '/api/shops/${widget.shopId}/coupons/$code',
          {'isActive': false},
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } catch (_) {
        setState(() => _formError = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                _isEdit
                    ? t(context, 'shop.promo.edit_title')
                    : t(context, 'shop.promo.create_title'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              // Code + generate
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      enabled: !_isEdit, // backend uses code as PK
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 16, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: t(context, 'shop.promo.code'),
                      ),
                    ),
                  ),
                  if (!_isEdit) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _generateCode,
                      icon: const Icon(Icons.casino_rounded, size: 16),
                      label: Text(t(context, 'shop.promo.generate')),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Type
              Text(
                t(context, 'shop.promo.type'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  _typeChip(
                    'percent',
                    t(context, 'shop.promo.type_percent'),
                  ),
                  _typeChip('fixed', t(context, 'shop.promo.type_fixed')),
                  _typeChip(
                    'free_delivery',
                    t(context, 'shop.promo.type_free_delivery'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_type != 'free_delivery')
                TextField(
                  controller: _valueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: _type == 'percent'
                        ? t(context, 'shop.promo.value_percent')
                        : t(context, 'shop.promo.value_fixed'),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _minOrderCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: InputDecoration(
                  labelText: t(context, 'shop.promo.min_order'),
                  helperText: t(context, 'shop.promo.min_order_help'),
                ),
              ),
              const SizedBox(height: 12),
              if (_type == 'percent')
                TextField(
                  controller: _maxDiscountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: t(context, 'shop.promo.max_discount'),
                    helperText: t(context, 'shop.promo.max_discount_help'),
                  ),
                ),
              if (_type == 'percent') const SizedBox(height: 12),
              TextField(
                controller: _usageLimitCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t(context, 'shop.promo.usage_limit'),
                  helperText: t(context, 'shop.promo.usage_limit_help'),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: t(context, 'shop.promo.valid_from'),
                      value: _validFrom,
                      onTap: () => _pickDate(true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: t(context, 'shop.promo.valid_until'),
                      value: _validUntil,
                      onTap: () => _pickDate(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                title: Text(t(context, 'shop.promo.is_active')),
                activeColor: AppColors.primary,
              ),
              if (_formError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formError!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (_isEdit)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _delete,
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.error),
                        label: Text(
                          t(context, 'common.delete'),
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    ),
                  if (_isEdit) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: AppColors.bg,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(t(context, 'shop.promo.save')),
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

  Widget _typeChip(String value, String label) {
    final active = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$y-$m-$d',
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.calendar_today_rounded,
                      color: AppColors.textHint, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
