import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../models/payment_method.dart';
import '../../services/api_client.dart';
import '../../services/payment_method_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Phase 6 — saved payment-method management screen.
///
/// Lists existing methods (Click / Payme / Uzum / cash), supports adding a
/// new card via the dev-mode mock-token form, swipe-to-delete, and
/// long-press to mark default.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  bool _loading = true;
  String? _error;
  List<PaymentMethod> _methods = const [];

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
      final list = await PaymentMethodApi.instance.list();
      if (!mounted) return;
      setState(() {
        _methods = list;
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

  Future<void> _setDefault(PaymentMethod m) async {
    HapticFeedback.selectionClick();
    try {
      await PaymentMethodApi.instance.setDefault(m.id);
      await _load();
      if (mounted) context.showSuccess(t(context, 'payment.set_default'));
    } catch (e) {
      if (mounted) context.showError('$e');
    }
  }

  Future<void> _delete(PaymentMethod m) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t(context, 'payment.delete')),
        content: Text(m.displayLabel),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(t(context, 'common.confirm')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await PaymentMethodApi.instance.delete(m.id);
      await _load();
    } catch (e) {
      if (mounted) context.showError('$e');
    }
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AddCardSheet(),
    );
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final saved = _methods.where((m) => m.provider != 'cash').toList();
    final cash = _methods.where((m) => m.provider == 'cash').toList();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A10), Color(0xFF050507)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _PayHeader(
                onBack: () => Navigator.of(context).maybePop(),
                onAdd: _openAddSheet,
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? ErrorView(message: _error!, onRetry: _load)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 32),
                              children: [
                                if (saved.isNotEmpty)
                                  _PayGroupTitle('Сохранённые карты'),
                                for (final m in saved)
                                  _PayCard(
                                    method: m,
                                    onDelete: () => _delete(m),
                                    onSelect: () => _setDefault(m),
                                  ),
                                const SizedBox(height: 4),
                                _PayGroupTitle('Другие способы'),
                                if (cash.isEmpty)
                                  _PayMethodInline(
                                    label: 'Наличные',
                                    sub: 'Курьеру при доставке',
                                    icon: Icons.payments_outlined,
                                  ),
                                for (final m in cash)
                                  _PayCard(
                                    method: m,
                                    onDelete: () => _delete(m),
                                    onSelect: () => _setDefault(m),
                                  ),
                                const SizedBox(height: 16),
                                _PayAddBtn(
                                  label: 'Добавить новую карту',
                                  onTap: _openAddSheet,
                                ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────
class _PayHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onAdd;
  const _PayHeader({required this.onBack, required this.onAdd});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            _GlassChip(icon: Icons.chevron_left_rounded, onTap: onBack),
            const Spacer(),
            const Text(
              'Способы оплаты',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            _GlassChip(icon: Icons.add_rounded, onTap: onAdd),
          ],
        ),
      );
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassChip({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      );
}

class _PayGroupTitle extends StatelessWidget {
  final String text;
  const _PayGroupTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      );
}

// ─── Pay card ───────────────────────────────────────────────────────────────
class _PayCard extends StatelessWidget {
  final PaymentMethod method;
  final VoidCallback onDelete;
  final VoidCallback onSelect;
  const _PayCard({
    required this.method,
    required this.onDelete,
    required this.onSelect,
  });

  Color _logoColor() {
    switch (method.provider) {
      case 'click':
        return const Color(0xFF2EB1E5);
      case 'payme':
        return const Color(0xFF8C5BFF);
      case 'uzum':
        return const Color(0xFF7841FF);
      case 'apple':
        return Colors.white;
      case 'cash':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  String _logoLabel() {
    switch (method.provider) {
      case 'click':
        return 'Click';
      case 'payme':
        return 'Payme';
      case 'uzum':
        return 'Uzum';
      case 'apple':
        return 'Pay';
      case 'cash':
        return '';
      case 'visa':
        return 'VISA';
      case 'mastercard':
        return 'MC';
      default:
        return method.provider.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) => Dismissible(
        key: ValueKey('pm-${method.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(Icons.delete_outline_rounded, color: AppColors.error),
        ),
        confirmDismiss: (_) async {
          onDelete();
          return false;
        },
        child: GestureDetector(
          onTap: method.isDefault ? null : onSelect,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: method.isDefault
                  ? AppColors.primary.withValues(alpha: 0.06)
                  : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: method.isDefault
                    ? AppColors.primary.withValues(alpha: 0.30)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                // Logo
                Container(
                  width: 56,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _logoColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: _logoColor().withValues(alpha: 0.30)),
                  ),
                  child: method.provider == 'cash'
                      ? Icon(Icons.payments_outlined,
                          size: 18, color: AppColors.warning)
                      : Text(
                          _logoLabel(),
                          style: TextStyle(
                            color: _logoColor(),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method.displayLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        method.expiryMonth != null && method.expiryYear != null
                            ? '${method.providerName} · ${method.expiryMonth!.toString().padLeft(2, '0')}/${method.expiryYear}'
                            : method.providerName,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (method.isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '★ ОСНОВНОЙ',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  )
                else
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 1.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _PayMethodInline extends StatelessWidget {
  final String label;
  final String sub;
  final IconData icon;
  const _PayMethodInline({
    required this.label,
    required this.sub,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.30)),
              ),
              child: Icon(icon, size: 18, color: AppColors.warning),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
            ),
          ],
        ),
      );
}

class _PayAddBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PayAddBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

/// Bottom sheet that walks the user through provider → tokenize → confirm.
class _AddCardSheet extends StatefulWidget {
  const _AddCardSheet();

  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  static const _providers = [
    {'id': 'click', 'name': 'Click', 'emoji': '💳'},
    {'id': 'payme', 'name': 'Payme', 'emoji': '💜'},
    {'id': 'uzum', 'name': 'Uzum Pay', 'emoji': '🟪'},
  ];

  String? _provider;
  bool _busy = false;
  String? _mockToken;
  final _last4 = TextEditingController();
  String _brand = 'visa';

  @override
  void dispose() {
    _last4.dispose();
    super.dispose();
  }

  Future<void> _pickProvider(String provider) async {
    setState(() {
      _provider = provider;
      _busy = true;
      _mockToken = null;
    });
    try {
      final result =
          await PaymentMethodApi.instance.startTokenize(provider);
      if (!mounted) return;
      if (result.mockToken != null && result.mockToken!.isNotEmpty) {
        // Dev mode — backend short-circuits, ask the buyer for last4 + brand
        // so we can finalise locally.
        setState(() => _mockToken = result.mockToken);
      } else if (result.redirectUrl != null &&
          result.redirectUrl!.isNotEmpty) {
        // Production — open the provider's hosted form externally.
        final uri = Uri.parse(result.redirectUrl!);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!mounted) return;
        context.showInfo(t(context, 'payment.use_new_card'));
        Navigator.of(context).pop(false);
        return;
      } else {
        if (mounted) context.showError(t(context, 'common.error'));
      }
    } on ApiException catch (e) {
      if (mounted) context.showError(e.message);
    } catch (e) {
      if (mounted) context.showError('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_provider == null || _mockToken == null) return;
    final last4 = _last4.text.trim();
    if (last4.length != 4 || int.tryParse(last4) == null) {
      context.showError(t(context, 'common.error'));
      return;
    }
    setState(() => _busy = true);
    try {
      await PaymentMethodApi.instance.confirm(
        provider: _provider!,
        mockToken: _mockToken,
        last4: last4,
        brand: _brand,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) context.showError(e.message);
    } catch (e) {
      if (mounted) context.showError('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
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
              Text(t(context, 'payment.add_card'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (_mockToken == null) ...[
                for (final p in _providers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _pickProvider(p['id']!),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        alignment: Alignment.centerLeft,
                      ),
                      child: Row(
                        children: [
                          Text(p['emoji']!,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Text(p['name']!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          const Spacer(),
                          if (_busy && _provider == p['id'])
                            const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                        ],
                      ),
                    ),
                  ),
              ] else ...[
                Text('${t(context, 'payment.use_new_card')} · $_provider',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                TextField(
                  controller: _last4,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Last 4',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['visa', 'mastercard', 'uzcard', 'humo']
                      .map((b) => ChoiceChip(
                            label: Text(b),
                            selected: _brand == b,
                            onSelected: (_) => setState(() => _brand = b),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _busy ? null : _confirm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(t(context, 'common.confirm')),
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
