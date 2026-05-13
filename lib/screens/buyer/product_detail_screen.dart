import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../models/catalog.dart';
import '../../providers/cart_provider.dart';
import '../../services/catalog_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Shows a product's image / description and lets the buyer pick modifier
/// options before adding to cart.
class ProductDetailScreen extends StatefulWidget {
  final Product product;
  final String? description;
  const ProductDetailScreen({super.key, required this.product, this.description});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _loading = true;
  String? _error;
  List<ModifierGroup> _groups = const [];
  /// groupId → set of selected option ids
  final Map<String, Set<String>> _selected = {};
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final groups =
          await CatalogApi.instance.productModifiers(widget.product.id);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _selected
          ..clear()
          ..addEntries(groups.map((g) => MapEntry(g.id, <String>{})));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _fmtPrice(double v) =>
      "${v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so'm";

  double get _modifierDelta {
    double sum = 0;
    for (final g in _groups) {
      final selectedIds = _selected[g.id] ?? const <String>{};
      for (final o in g.options) {
        if (selectedIds.contains(o.id)) sum += o.priceDelta;
      }
    }
    return sum;
  }

  double get _unitPrice => widget.product.effectivePrice + _modifierDelta;
  double get _total => _unitPrice * _qty;

  String? _validationError(BuildContext context) {
    for (final g in _groups) {
      final count = _selected[g.id]?.length ?? 0;
      if (count < g.minSelect) {
        return '${t(context, 'min_select_violation')}: ${g.name} (${g.minSelect})';
      }
    }
    return null;
  }

  void _toggle(ModifierGroup g, ModifierOption o) {
    HapticFeedback.selectionClick();
    final set = _selected[g.id] ??= <String>{};
    setState(() {
      if (g.isSingleSelect) {
        set
          ..clear()
          ..add(o.id);
      } else {
        if (set.contains(o.id)) {
          set.remove(o.id);
        } else if (set.length < g.maxSelect) {
          set.add(o.id);
        }
      }
    });
  }

  Future<void> _addToCart() async {
    final err = _validationError(context);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    HapticFeedback.mediumImpact();

    final selections = <CartModifierSelection>[];
    final snapshot = <ModifierSnapshot>[];
    for (final g in _groups) {
      final ids = (_selected[g.id] ?? const <String>{}).toList();
      if (ids.isEmpty) continue;
      selections.add(CartModifierSelection(groupId: g.id, optionIds: ids));
      snapshot.add(ModifierSnapshot(
        groupId: g.id,
        groupName: g.name,
        options: g.options.where((o) => ids.contains(o.id)).toList(),
      ));
    }

    final cart = context.read<CartProvider>();
    // Phase 11 — multi-shop drafts: addWithModifiers always succeeds now.
    // Different-shop additions land in a separate draft instead of replacing
    // the active one. Confirmation snackbar uses the shop's name when we know
    // it (cached when the buyer entered via the shop card).
    cart.addWithModifiers(
      widget.product,
      _qty,
      selections,
      _unitPrice,
      snapshot: snapshot,
    );
    if (!mounted) return;
    context.showSuccess(t(context, 'product.added_to_cart'));
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final disabled = _validationError(context) != null;

    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBodyBehindAppBar: true,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 140),
              children: [
                // UberEats/abuanwar-style hero: full-bleed image, soft rounded
                // bottom corners, floating back/favourite chips overlaid.
                Stack(
                  children: [
                    SizedBox(
                      height: mq.size.height * 0.42,
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(AppRadii.xl),
                        ),
                        child: Hero(
                          tag: 'product-${p.id}',
                          child: p.imageUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: p.imageUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    color: AppColors.surfaceMuted,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.image_outlined,
                                        size: 48, color: AppColors.textHint),
                                  ),
                                )
                              : Container(
                                  color: AppColors.surfaceMuted,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.image_outlined,
                                      size: 48, color: AppColors.textHint),
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: mq.padding.top + 12, left: 16,
                      child: _HeroChip(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    if (p.hasDiscount)
                      Positioned(
                        top: mq.padding.top + 12, right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            boxShadow: AppShadows.card,
                          ),
                          child: Text(
                            '−${p.discountPercent.toInt()}%',
                            style: const TextStyle(
                              color: AppColors.neutralInk,
                              fontWeight: FontWeight.w800,
                              fontSize: 12, letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                            height: 1.15,
                          )),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_fmtPrice(p.effectivePrice),
                              style: const TextStyle(
                                fontSize: 22,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              )),
                          if (p.hasDiscount) ...[
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(_fmtPrice(p.price),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textHint,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.lineThrough,
                                  )),
                            ),
                          ],
                        ],
                      ),
                      if (widget.description != null &&
                          widget.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(widget.description!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            )),
                      ],
                    ],
                  ),
                ),
                // Reviews tile — opens the public reviews screen for this
                // product. Phase 3 wiring; the screen handles its own load.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: InkWell(
                    onTap: () => context
                        .push('/reviews/product/${p.id}', extra: p.name),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.star_rounded,
                              color: AppColors.warning, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text('Sharhlar',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: AppColors.textHint),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: ErrorView(message: _error!, onRetry: _load),
                  )
                else if (_groups.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      t(context, 'select_modifiers'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final g in _groups)
                    _ModifierGroupCard(
                      group: g,
                      selected: _selected[g.id] ?? const <String>{},
                      onToggle: (o) => _toggle(g, o),
                    ),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.elevated,
          ),
          child: Row(
            children: [
              _Stepper(
                qty: _qty,
                onMinus: () {
                  if (_qty > 1) setState(() => _qty -= 1);
                },
                onPlus: () => setState(() => _qty += 1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: disabled ? null : _addToCart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      '${t(context, 'product.add_to_cart')} · ${_fmtPrice(_total)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
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

class _ModifierGroupCard extends StatelessWidget {
  final ModifierGroup group;
  final Set<String> selected;
  final ValueChanged<ModifierOption> onToggle;
  const _ModifierGroupCard({
    required this.group,
    required this.selected,
    required this.onToggle,
  });

  String _fmtDelta(double v) {
    if (v == 0) return '';
    final abs = v.abs().toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
    final sign = v > 0 ? '+' : '−';
    return "  $sign$abs so'm";
  }

  @override
  Widget build(BuildContext context) {
    final atMax = !group.isSingleSelect && selected.length >= group.maxSelect;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  '(min: ${group.minSelect}, max: ${group.maxSelect})',
                  style: const TextStyle(
                    fontSize: 12, color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < group.options.length; i++) ...[
            _OptionTile(
              option: group.options[i],
              isChecked: selected.contains(group.options[i].id),
              isSingle: group.isSingleSelect,
              disabled: !group.isSingleSelect &&
                  atMax &&
                  !selected.contains(group.options[i].id),
              priceLabel: _fmtDelta(group.options[i].priceDelta),
              onTap: () => onToggle(group.options[i]),
            ),
            if (i < group.options.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Divider(height: 1),
              ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final ModifierOption option;
  final bool isChecked;
  final bool isSingle;
  final bool disabled;
  final String priceLabel;
  final VoidCallback onTap;
  const _OptionTile({
    required this.option,
    required this.isChecked,
    required this.isSingle,
    required this.disabled,
    required this.priceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled || !option.isAvailable ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              if (isSingle)
                Radio<bool>(
                  value: true,
                  groupValue: isChecked ? true : null,
                  onChanged: disabled ? null : (_) => onTap(),
                  activeColor: AppColors.primary,
                )
              else
                Checkbox(
                  value: isChecked,
                  onChanged: disabled ? null : (_) => onTap(),
                  activeColor: AppColors.primary,
                ),
              Expanded(
                child: Text(
                  option.name,
                  style: TextStyle(
                    fontSize: 14,
                    color: disabled || !option.isAvailable
                        ? AppColors.textHint
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (priceLabel.isNotEmpty)
                Text(priceLabel,
                    style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    )),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _Stepper({required this.qty, required this.onMinus, required this.onPlus});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_rounded, size: 18),
          onPressed: onMinus,
          splashRadius: 18,
        ),
        SizedBox(
          width: 22,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_rounded, size: 18),
          onPressed: onPlus,
          splashRadius: 18,
        ),
      ],
    ),
  );
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeroChip({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    elevation: 0,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44, height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: AppShadows.card,
        ),
        child: Icon(icon, color: AppColors.neutralInk, size: 22),
      ),
    ),
  );
}
