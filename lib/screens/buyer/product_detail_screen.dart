import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../models/catalog.dart';
import '../../providers/cart_provider.dart';
import '../../services/catalog_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// PRODUCT DETAIL — master.html .pd (lines 6320-6418).
///
/// 360-px hero image with 32-px bottom radius + chips, optional floating
/// discount badge, then a `pd-body` overlapping the hero by 32 px. Shop row
/// (lime shop name), Playfair title, rating + count, description, big price
/// row, size options (.pd-options), modifiers (.pd-mod-row), qty stepper,
/// sticky lime CTA pinned at the bottom.
class ProductDetailScreen extends StatefulWidget {
  final Product product;
  final String? description;
  const ProductDetailScreen({
    super.key,
    required this.product,
    this.description,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _loading = true;
  String? _error;
  List<ModifierGroup> _groups = const [];
  final Map<String, Set<String>> _selected = {};
  int _qty = 1;

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
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmt(double v) => v
      .toInt()
      .toString()
      .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');

  String _fmtDelta(double v) {
    if (v == 0) return 'Бесплатно';
    final abs = _fmt(v.abs());
    return v > 0 ? '+$abs' : '−$abs';
  }

  double get _modifierDelta {
    double sum = 0;
    for (final g in _groups) {
      final ids = _selected[g.id] ?? const <String>{};
      for (final o in g.options) {
        if (ids.contains(o.id)) sum += o.priceDelta;
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
    context.read<CartProvider>().addWithModifiers(
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

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.only(bottom: 110),
                  children: [
                    _Hero(
                      imageUrl: p.imageUrl,
                      hasDiscount: p.hasDiscount,
                      onBack: () => Navigator.of(context).maybePop(),
                      onFav: () {},
                      onShare: () {},
                    ),
                    Transform.translate(
                      offset: const Offset(0, -32),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ShopRow(p: p),
                            const SizedBox(height: 8),
                            _Title(name: p.name),
                            const SizedBox(height: 12),
                            _Rating(p: p),
                            const SizedBox(height: 12),
                            _Desc(text: widget.description),
                            const SizedBox(height: 12),
                            _PriceRow(p: p, fmt: _fmt),
                            const SizedBox(height: 24),
                            // Reviews entry
                            _ReviewsTile(
                              onTap: () => context.push(
                                  '/reviews/product/${p.id}',
                                  extra: p.name),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              ErrorView(message: _error!, onRetry: _load),
                            ],
                            if (_groups.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              for (final g in _groups) ...[
                                _ModifierGroup(
                                  group: g,
                                  selected: _selected[g.id] ?? const <String>{},
                                  onToggle: (o) => _toggle(g, o),
                                  fmtDelta: _fmtDelta,
                                ),
                                const SizedBox(height: 16),
                              ],
                            ],
                            const SizedBox(height: 8),
                            _QtyBar(
                              qty: _qty,
                              onMinus: () {
                                if (_qty > 1) {
                                  HapticFeedback.lightImpact();
                                  setState(() => _qty -= 1);
                                }
                              },
                              onPlus: () {
                                HapticFeedback.lightImpact();
                                setState(() => _qty += 1);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // ─ Sticky lime CTA ───────────────────────────────────────
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 16,
                  child: SafeArea(
                    top: false,
                    child: _LimeCta(
                      label: 'Добавить в корзину',
                      total: _fmt(_total),
                      onTap: disabled ? null : _addToCart,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Hero ───────────────────────────────────────────────────────────────────
class _Hero extends StatelessWidget {
  final String imageUrl;
  final bool hasDiscount;
  final VoidCallback onBack;
  final VoidCallback onFav;
  final VoidCallback onShare;
  const _Hero({
    required this.imageUrl,
    required this.hasDiscount,
    required this.onBack,
    required this.onFav,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(32),
            ),
            child: SizedBox(
              height: 360,
              width: double.infinity,
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _Placeholder(),
                    )
                  : _Placeholder(),
            ),
          ),
          // Gradient overlay
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(32),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                    stops: const [0.0, 0.3, 0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Top chips
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _PdChip(icon: Icons.chevron_left_rounded, onTap: onBack),
                Row(
                  children: [
                    _PdChip(icon: Icons.favorite_border_rounded, onTap: onFav),
                    const SizedBox(width: 8),
                    _PdChip(icon: Icons.share_outlined, onTap: onShare),
                  ],
                ),
              ],
            ),
          ),
          // Floating discount
          if (hasDiscount)
            Positioned(
              bottom: 24 + 32,
              left: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '−20% НОЧЬЮ',
                  style: TextStyle(
                    color: AppColors.bg,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      );
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF3A1F10),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined,
            size: 64, color: Colors.white24),
      );
}

class _PdChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _PdChip({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      );
}

// ─── Body widgets ───────────────────────────────────────────────────────────
class _ShopRow extends StatelessWidget {
  final Product p;
  const _ShopRow({required this.p});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            'Ресторан:',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Text(
            p.shopId,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text('·',
              style: TextStyle(
                  color: AppColors.textHint, fontSize: 12)),
          const SizedBox(width: 8),
          Text('20 мин',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      );
}

class _Title extends StatelessWidget {
  final String name;
  const _Title({required this.name});
  @override
  Widget build(BuildContext context) => Text(
        name,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.7,
          height: 1.1,
        ),
      );
}

class _Rating extends StatelessWidget {
  final Product p;
  const _Rating({required this.p});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            '★ 4.9',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '(124 отзыва)',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
}

class _Desc extends StatelessWidget {
  final String? text;
  const _Desc({this.text});
  @override
  Widget build(BuildContext context) => Text(
        (text != null && text!.trim().isNotEmpty)
            ? text!
            : 'Свежие ингредиенты, готовится по заказу. Подробное описание скоро появится.',
        style: TextStyle(
          fontSize: 13.5,
          color: AppColors.textSecondary,
          height: 1.55,
        ),
      );
}

class _PriceRow extends StatelessWidget {
  final Product p;
  final String Function(double) fmt;
  const _PriceRow({required this.p, required this.fmt});
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            fmt(p.effectivePrice),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "сум",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          if (p.hasDiscount) ...[
            const SizedBox(width: 12),
            Text(
              fmt(p.price),
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textHint,
                decoration: TextDecoration.lineThrough,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      );
}

class _ReviewsTile extends StatelessWidget {
  final VoidCallback onTap;
  const _ReviewsTile({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.star_rounded, color: AppColors.warning, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Отзывы',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
            ],
          ),
        ),
      );
}

// ─── Modifier group ─────────────────────────────────────────────────────────
class _ModifierGroup extends StatelessWidget {
  final ModifierGroup group;
  final Set<String> selected;
  final ValueChanged<ModifierOption> onToggle;
  final String Function(double) fmtDelta;
  const _ModifierGroup({
    required this.group,
    required this.selected,
    required this.onToggle,
    required this.fmtDelta,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.name.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          if (group.isSingleSelect)
            Row(
              children: [
                for (var i = 0; i < group.options.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _PdOption(
                      name: group.options[i].name,
                      extra: group.options[i].priceDelta == 0
                          ? 'Стандарт'
                          : fmtDelta(group.options[i].priceDelta),
                      active: selected.contains(group.options[i].id),
                      onTap: () => onToggle(group.options[i]),
                    ),
                  ),
                ],
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < group.options.length; i++)
                  Container(
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(
                              top: BorderSide(color: AppColors.border)),
                    ),
                    child: _PdModRow(
                      name: group.options[i].name,
                      delta: fmtDelta(group.options[i].priceDelta),
                      isLime: group.options[i].priceDelta == 0,
                      checked: selected.contains(group.options[i].id),
                      onTap: () => onToggle(group.options[i]),
                    ),
                  ),
              ],
            ),
        ],
      );
}

class _PdOption extends StatelessWidget {
  final String name;
  final String extra;
  final bool active;
  final VoidCallback onTap;
  const _PdOption({
    required this.name,
    required this.extra,
    required this.active,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withValues(alpha: 0.10)
                : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                extra,
                style: TextStyle(
                  fontSize: 11,
                  color: active
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}

class _PdModRow extends StatelessWidget {
  final String name;
  final String delta;
  final bool isLime;
  final bool checked;
  final VoidCallback onTap;
  const _PdModRow({
    required this.name,
    required this.delta,
    required this.isLime,
    required this.checked,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: checked ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: checked ? AppColors.primary : AppColors.border,
                    width: 1.5,
                  ),
                ),
                child: checked
                    ? Icon(Icons.check_rounded,
                        size: 14, color: AppColors.bg)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                delta,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isLime ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}

// ─── Qty bar ────────────────────────────────────────────────────────────────
class _QtyBar extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _QtyBar({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
  });
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            'КОЛИЧЕСТВО',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _QtyBtn(icon: Icons.remove_rounded, lime: false, onTap: onMinus),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '$qty',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                _QtyBtn(icon: Icons.add_rounded, lime: true, onTap: onPlus),
              ],
            ),
          ),
        ],
      );
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final bool lime;
  final VoidCallback onTap;
  const _QtyBtn({
    required this.icon,
    required this.lime,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: lime ? AppColors.primary : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 16,
            color: lime ? AppColors.bg : Colors.white,
          ),
        ),
      );
}

// ─── Sticky lime CTA ────────────────────────────────────────────────────────
class _LimeCta extends StatelessWidget {
  final String label;
  final String total;
  final VoidCallback? onTap;
  const _LimeCta({
    required this.label,
    required this.total,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(100),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.bg,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  "$total сум",
                  style: GoogleFonts.jetBrainsMono(
                    color: AppColors.bg,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
