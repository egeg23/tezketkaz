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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(t(context, 'payment.cards_list'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add_card_rounded),
        label: Text(t(context, 'payment.add_card')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _methods.isEmpty
                  ? EmptyState(
                      emoji: '💳',
                      title: t(context, 'payment.no_cards'),
                      description: t(context, 'payment.add_card'),
                      ctaLabel: t(context, 'payment.add_card'),
                      onCta: _openAddSheet,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _methods.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final m = _methods[i];
                          return Dismissible(
                            key: ValueKey('pm-${m.id}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: AppColors.errorLight,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.lg),
                              ),
                              child: const Icon(Icons.delete_outline_rounded,
                                  color: AppColors.error),
                            ),
                            confirmDismiss: (_) async {
                              await _delete(m);
                              // Always return false so we can re-render the
                              // tile if delete failed; `_load()` rebuilds.
                              return false;
                            },
                            child: GestureDetector(
                              onLongPress:
                                  m.isDefault ? null : () => _setDefault(m),
                              child: _MethodTile(
                                method: m,
                                onDelete: () => _delete(m),
                                onSetDefault: m.isDefault
                                    ? null
                                    : () => _setDefault(m),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final PaymentMethod method;
  final VoidCallback onDelete;
  final VoidCallback? onSetDefault;
  const _MethodTile({
    required this.method,
    required this.onDelete,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
            color: method.isDefault ? AppColors.primary : AppColors.border,
            width: method.isDefault ? 1.4 : 1),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Text(method.brandEmoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(method.displayLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(width: 8),
                    if (method.isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius:
                              BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(t(context, 'address.default_badge'),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            )),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  method.expiryMonth != null && method.expiryYear != null
                      ? '${method.providerName} · ${method.expiryMonth!.toString().padLeft(2, '0')}/${method.expiryYear}'
                      : method.providerName,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onSetDefault != null)
            IconButton(
              tooltip: t(context, 'payment.set_default'),
              onPressed: onSetDefault,
              icon: const Icon(Icons.star_outline_rounded,
                  color: AppColors.textSecondary),
            ),
          IconButton(
            tooltip: t(context, 'payment.delete'),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.error),
          ),
        ],
      ),
    );
  }
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
