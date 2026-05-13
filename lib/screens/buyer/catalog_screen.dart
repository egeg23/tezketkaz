import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/cart_provider.dart';
import '../../services/catalog_api.dart';
import '../../services/favorite_api.dart';
import '../../theme/app_theme.dart';
import 'product_detail_screen.dart';

/// CATALOG — master.html .catalog (lines 6188-6315).
///
/// Header chip-back + title pill + search-icon, Playfair "Mashhur *pitsalar*"
/// hero with subtitle, two glass filter pills (sort / ETA), and a 2-column
/// grid of `.catalog-card` items.
const _categoryLabels = {
  'all': 'Все товары',
  'produce': 'Овощи и фрукты',
  'meat': 'Мясо',
  'dairy': 'Молочные',
  'bakery': 'Выпечка',
  'drinks': 'Напитки',
  'grocery': 'Бакалея',
  'pizza': 'Пицца',
  'sushi': 'Суши',
  'burger': 'Бургеры',
  'uzbek': 'Узбекская кухня',
  'vegan': 'Веган',
  'popular': 'Популярное',
};

class CatalogScreen extends StatefulWidget {
  final String category;
  final String? shopId;
  final String? shopName;
  const CatalogScreen({
    super.key,
    required this.category,
    this.shopId,
    this.shopName,
  });

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _sort = 'popular';
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.shopId != null) {
        context.read<CartProvider>().rememberShop(
              shopId: widget.shopId!,
              name: widget.shopName,
            );
      }
      _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (widget.shopId != null) {
        final res = await CatalogApi.instance.search(
          shopId: widget.shopId,
          categoryId: widget.category == 'all' ? null : widget.category,
          limit: 50,
        );
        if (!mounted) return;
        setState(() {
          _products = res.items;
          _loading = false;
        });
      } else {
        final list = await CatalogApi.instance.list(category: widget.category);
        if (!mounted) return;
        setState(() {
          _products = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Product> get _filtered {
    var list = List<Product>.from(_products);
    if (_sort == 'price_asc') {
      list.sort((a, b) => a.effectivePrice.compareTo(b.effectivePrice));
    }
    if (_sort == 'price_desc') {
      list.sort((a, b) => b.effectivePrice.compareTo(a.effectivePrice));
    }
    return list;
  }

  String get _sortLabel {
    switch (_sort) {
      case 'price_asc':
        return 'Дешевле';
      case 'price_desc':
        return 'Дороже';
      default:
        return 'Популярное';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.shopName ??
        _categoryLabels[widget.category] ??
        widget.category;
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
              _Header(
                title: title,
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filtered.isEmpty
                        ? _Empty()
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                              children: [
                                _Hero(title: title, count: _filtered.length),
                                _FilterBar(
                                  sortLabel: _sortLabel,
                                  onSortTap: _pickSort,
                                ),
                                const SizedBox(height: 20),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 0.72,
                                  ),
                                  itemCount: _filtered.length,
                                  itemBuilder: (_, i) =>
                                      _CatalogCard(product: _filtered[i]),
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

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in {
              'popular': 'Популярное',
              'price_asc': 'Сначала дешёвые',
              'price_desc': 'Сначала дорогие',
            }.entries)
              ListTile(
                title: Text(entry.value,
                    style: const TextStyle(color: Colors.white)),
                trailing: _sort == entry.key
                    ? Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _Header({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            _GlassCircleBtn(icon: Icons.chevron_left_rounded, onTap: onBack),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            _GlassCircleBtn(icon: Icons.search_rounded, onTap: () {}),
          ],
        ),
      );
}

class _GlassCircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassCircleBtn({required this.icon, required this.onTap});
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

// ─── Hero ───────────────────────────────────────────────────────────────────
class _Hero extends StatelessWidget {
  final String title;
  final int count;
  const _Hero({required this.title, required this.count});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: GoogleFonts.playfairDisplay(
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
                children: [
                  const TextSpan(text: 'Популярные '),
                  TextSpan(
                    text: title.toLowerCase(),
                    style: GoogleFonts.playfairDisplay(
                      fontStyle: FontStyle.italic,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$count позиций · по округе',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}

// ─── Filter bar ─────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final String sortLabel;
  final VoidCallback onSortTap;
  const _FilterBar({required this.sortLabel, required this.onSortTap});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _FilterPill(
              icon: Icons.tune_rounded,
              label: 'Сортировка',
              value: sortLabel,
              onTap: onSortTap,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FilterPill(
              icon: Icons.access_time_rounded,
              label: 'Доставка',
              value: '25 мин',
              onTap: () {},
            ),
          ),
        ],
      );
}

class _FilterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _FilterPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textHint),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      );
}

// ─── Catalog card (master .catalog-card) ────────────────────────────────────
class _CatalogCard extends StatefulWidget {
  final Product product;
  const _CatalogCard({required this.product});

  @override
  State<_CatalogCard> createState() => _CatalogCardState();
}

class _CatalogCardState extends State<_CatalogCard> {
  bool? _isFav;
  bool _busy = false;

  Product get p => widget.product;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFav());
  }

  Future<void> _loadFav() async {
    try {
      final v = await FavoriteApi.instance.check(productId: p.id);
      if (!mounted) return;
      setState(() => _isFav = v);
    } catch (_) {}
  }

  Future<void> _toggleFav() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _isFav = !(_isFav ?? false);
    });
    try {
      if (_isFav == true) {
        await FavoriteApi.instance.addProduct(p.id);
      } else {
        await FavoriteApi.instance.removeProduct(p.id);
      }
    } catch (_) {
      if (mounted) setState(() => _isFav = !(_isFav ?? false));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onAdd(BuildContext context) {
    HapticFeedback.lightImpact();
    context.read<CartProvider>().add(p);
  }

  void _openDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
    );
  }

  String _fmtPrice(double v) => v
      .toInt()
      .toString()
      .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openDetail,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0x09FFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─ Image area ────────────────────────────────────────────────
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 1.05,
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
                                    color: AppColors.textHint, size: 28),
                              ),
                            )
                          : Container(color: const Color(0xFF3A2618)),
                    ),
                  ),
                ),
                if (p.hasDiscount)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '−${p.discountPercent.toInt()}%',
                        style: TextStyle(
                          color: AppColors.bg,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: _toggleFav,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        (_isFav ?? false)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 12,
                        color: (_isFav ?? false)
                            ? AppColors.primary
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ─ Name & shop ───────────────────────────────────────────────
            Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: -0.2,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              p.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (p.hasDiscount) ...[
                        Text(
                          _fmtPrice(p.price),
                          style: GoogleFonts.jetBrainsMono(
                            color: AppColors.textHint,
                            decoration: TextDecoration.lineThrough,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          _fmtPrice(p.effectivePrice),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _onAdd(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.30),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(Icons.add_rounded,
                        size: 18, color: AppColors.bg),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔍', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              const Text(
                'Ничего не найдено',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Попробуйте другую категорию',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
}
