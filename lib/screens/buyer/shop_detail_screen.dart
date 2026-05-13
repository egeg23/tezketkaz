import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/catalog.dart' show Shop;
import '../../models/models.dart';
import '../../providers/cart_provider.dart';
import '../../services/catalog_api.dart';
import '../../theme/app_theme.dart';
import 'product_detail_screen.dart';

/// SHOP DETAIL — master.html .shop-detail (lines 6094-6182).
///
/// 320-px hero sliver (radial warm gradient + gradient fall-off), three float
/// chips (back / bookmark / share), glass info card with editorial badge,
/// Playfair shop name + subtitle + 4-stat grid, horizontal `.cat-tabs`,
/// 2-column `.product-grid`, sticky lime CTA bottom for the active cart.
class ShopDetailScreen extends StatefulWidget {
  final String shopId;
  final String? shopName;
  const ShopDetailScreen({super.key, required this.shopId, this.shopName});

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  Shop? _shop;
  List<Product> _products = const [];
  bool _loading = true;
  String? _error;
  int _tab = 0;
  static const _tabs = [
    'Популярное',
    'Основное',
    'Салаты',
    'Напитки',
    'Десерты',
  ];

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
      final results = await Future.wait([
        CatalogApi.instance.nearbyShops(limit: 50),
        CatalogApi.instance.search(shopId: widget.shopId, limit: 50),
      ]);
      final shops = results[0] as List<Shop>;
      final items =
          (results[1] as ({List<Product> items, String? nextCursor})).items;
      if (!mounted) return;
      setState(() {
        _shop = shops
            .where((s) => s.id == widget.shopId)
            .cast<Shop?>()
            .firstOrNull;
        _products = items;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final shop = _shop;
    final name = shop?.name ?? widget.shopName ?? '';
    final cart = context.watch<CartProvider>();
    final activeForShop = cart.activeShopId == widget.shopId
        ? cart.itemCount
        : cart.drafts
                .where((d) => d.shopId == widget.shopId)
                .map((d) => d.itemCount)
                .firstOrNull ??
            0;
    final num totalForShop = cart.activeShopId == widget.shopId
        ? cart.subtotal
        : cart.drafts
                .where((d) => d.shopId == widget.shopId)
                .map((d) => d.subtotal)
                .firstOrNull ??
            0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ─ Hero sliver ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _HeroSliver(
                  logoUrl: shop?.logoUrl,
                  onBack: () => Navigator.of(context).maybePop(),
                  onBookmark: () {},
                  onShare: () {},
                ),
              ),
              // ─ Info card (overlapping hero) ───────────────────────────
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -60),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoCard(shop: shop, name: name),
                        const SizedBox(height: 24),
                        _CatTabs(
                          tabs: _tabs,
                          active: _tab,
                          onTap: (i) => setState(() => _tab = i),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ─ Product grid ───────────────────────────────────────────
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: TextStyle(color: AppColors.error)),
                  ),
                )
              else if (_products.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Пока нет позиций',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      20, 0, 20, activeForShop > 0 ? 110 : 24),
                  // Negative top from translate(-60): keep margin compact.
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.66,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _ProductCard(product: _products[i]),
                      childCount: _products.length,
                    ),
                  ),
                ),
            ],
          ),

          // ─ Sticky lime CTA ──────────────────────────────────────────────
          if (activeForShop > 0)
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/cart'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
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
                          'В корзину · $activeForShop поз.',
                          style: TextStyle(
                            color: AppColors.bg,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          "${_fmt(totalForShop.toDouble())} сум",
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
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Hero sliver ────────────────────────────────────────────────────────────
class _HeroSliver extends StatelessWidget {
  final String? logoUrl;
  final VoidCallback onBack;
  final VoidCallback onBookmark;
  final VoidCallback onShare;
  const _HeroSliver({
    required this.logoUrl,
    required this.onBack,
    required this.onBookmark,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          // Background (image if present, else warm radial)
          SizedBox(
            height: 320,
            width: double.infinity,
            child: logoUrl != null && logoUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: logoUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _WarmGradient(),
                  )
                : _WarmGradient(),
          ),
          // Fall-off gradient to ink at bottom
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppColors.bg],
                ),
              ),
            ),
          ),
          // Float chips
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _FloatChip(icon: Icons.chevron_left_rounded, onTap: onBack),
                Row(
                  children: [
                    _FloatChip(
                        icon: Icons.bookmark_border_rounded, onTap: onBookmark),
                    const SizedBox(width: 8),
                    _FloatChip(icon: Icons.share_outlined, onTap: onShare),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
}

class _WarmGradient extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A1F10), Color(0xFF0A0A0E)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.2),
                    radius: 0.7,
                    colors: [
                      const Color(0xFFFF8C50).withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.5, 0.4),
                    radius: 0.6,
                    colors: [
                      const Color(0xFFF56446).withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _FloatChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _FloatChip({required this.icon, required this.onTap});
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
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      );
}

// ─── Info card ──────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final Shop? shop;
  final String name;
  const _InfoCard({required this.shop, required this.name});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xD90F0F16),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '★ ВЫБОР РЕДАКЦИИ',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              shop?.address ?? 'Узбекская кухня · Premium',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(
                  value: shop?.rating?.toStringAsFixed(1) ?? '4.9',
                  label: 'Рейтинг',
                  lime: true,
                ),
                const SizedBox(width: 12),
                _Stat(
                  value: shop?.distanceKm != null
                      ? '${shop!.distanceKm!.toStringAsFixed(1)} км'
                      : '1.2 км',
                  label: 'Дистанция',
                ),
                const SizedBox(width: 12),
                _Stat(value: '25 мин', label: 'Доставка'),
                const SizedBox(width: 12),
                _Stat(value: shop?.workingHours ?? '10–23', label: 'Часы'),
              ],
            ),
          ],
        ),
      );
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final bool lime;
  const _Stat({required this.value, required this.label, this.lime = false});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x08FFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x0DFFFFFF)),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: lime ? AppColors.primary : Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}

// ─── Cat tabs ───────────────────────────────────────────────────────────────
class _CatTabs extends StatelessWidget {
  final List<String> tabs;
  final int active;
  final ValueChanged<int> onTap;
  const _CatTabs({required this.tabs, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: tabs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final isActive = i == active;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onTap(i);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: isActive ? AppColors.primary : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 13,
                    color: isActive ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      );
}

// ─── Product card (master .product-card) ────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({required this.product});

  String _fmt(double v) => v
      .toInt()
      .toString()
      .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: product)),
        ),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0x09FFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x0FFFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 1.4,
                      child: product.imageUrl.isNotEmpty
                          ? Hero(
                              tag: 'product-${product.id}',
                              child: CachedNetworkImage(
                                imageUrl: product.imageUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    _WarmThumbnailBg(),
                              ),
                            )
                          : _WarmThumbnailBg(),
                    ),
                  ),
                  if (product.hasDiscount)
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
                          '−${product.discountPercent.toInt()}%',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.bg,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 28,
                child: Text(
                  product.nameUz.isNotEmpty ? product.nameUz : product.category,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmt(product.effectivePrice),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.read<CartProvider>().add(product);
                    },
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

class _WarmThumbnailBg extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 0.75,
            colors: [const Color(0xFFF5B95C), const Color(0xFF6B3A0E)],
            stops: const [0.0, 0.75],
          ),
        ),
      );
}
