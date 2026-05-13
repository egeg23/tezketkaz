import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n.dart';
import '../models/models.dart';
import '../providers/cart_provider.dart';
import '../screens/buyer/product_detail_screen.dart';
import '../services/favorite_api.dart';
import '../theme/app_theme.dart';

String _formatPrice(double price) {
  final formatted = price.toInt().toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]} ',
  );
  return "$formatted so'm";
}

class ProductCard extends StatefulWidget {
  final Product product;
  const ProductCard({super.key, required this.product});

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool? _isFavorite;
  bool _favBusy = false;

  Product get product => widget.product;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFavorite());
  }

  Future<void> _loadFavorite() async {
    try {
      final fav = await FavoriteApi.instance.check(productId: product.id);
      if (!mounted) return;
      setState(() => _isFavorite = fav);
    } catch (_) {/* silent */}
  }

  Future<void> _toggleFavorite() async {
    if (_favBusy) return;
    HapticFeedback.lightImpact();
    setState(() {
      _favBusy = true;
      _isFavorite = !(_isFavorite ?? false);
    });
    try {
      if (_isFavorite == true) {
        await FavoriteApi.instance.addProduct(product.id);
      } else {
        await FavoriteApi.instance.removeProduct(product.id);
      }
    } catch (_) {
      // Roll back on failure so the heart matches the server state.
      if (mounted) {
        setState(() => _isFavorite = !(_isFavorite ?? false));
      }
    } finally {
      if (mounted) setState(() => _favBusy = false);
    }
  }

  void _onAdd(BuildContext context) {
    HapticFeedback.lightImpact();
    final cart = context.read<CartProvider>();
    final wasDifferentShop =
        cart.activeShopId != null && cart.activeShopId != product.shopId;
    cart.add(product);
    if (wasDifferentShop) {
      // Phase 11 — multi-shop drafts: just confirm where the item landed.
      final tpl = t(context, 'cart.added_to_shop');
      final shopName = cart.drafts
          .where((d) => d.shopId == product.shopId)
          .map((d) => d.shopName)
          .firstWhere((n) => n.isNotEmpty, orElse: () => '');
      final msg = tpl.replaceAll('{shopName}',
          shopName.isEmpty ? t(context, 'shops.title') : shopName);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final qty = cart.quantityOf(product.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? null : AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: InkWell(
          onTap: () => _openDetail(context),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with overlay controls
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: AppColors.surfaceMuted),
                  Hero(
                    tag: 'product-${product.id}',
                    child: CachedNetworkImage(
                      imageUrl: product.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const _Shimmer(),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surfaceMuted,
                        child: const Icon(Icons.image_outlined, color: AppColors.textHint, size: 32),
                      ),
                    ),
                  ),
                  // Discount badge — UberEats prints the % saved in lime, not red.
                  if (product.hasDiscount)
                    Positioned(
                      top: 10, left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          boxShadow: AppShadows.card,
                        ),
                        child: Text(
                          '−${product.discountPercent.toInt()}%',
                          style: const TextStyle(
                            color: AppColors.neutralInk, fontSize: 11,
                            fontWeight: FontWeight.w800, letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  // Floating add/counter — top right
                  Positioned(
                    top: 8, right: 8,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: qty == 0
                          ? _AddButton(key: const ValueKey('add'), onTap: () => _onAdd(context))
                          : _Counter(key: const ValueKey('cnt'), qty: qty, product: product),
                    ),
                  ),
                  // Phase 7.3 — favourite heart, sits bottom-right of the
                  // image so it doesn't fight the add button or discount
                  // badge. Optimistically toggles, rolls back on API error.
                  Positioned(
                    bottom: 8, right: 8,
                    child: _FavoriteHeart(
                      isFavorite: _isFavorite ?? false,
                      onTap: _toggleFavorite,
                    ),
                  ),
                ],
              ),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatPrice(product.effectivePrice),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (product.hasDiscount) ...[
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            _formatPrice(product.price),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textHint,
                              decoration: TextDecoration.lineThrough,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '1 ${product.unit}',
                    style: const TextStyle(
                      fontSize: 11, color: AppColors.textHint, fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: const CircleBorder(),
    elevation: 0,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36, height: 36,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          boxShadow: AppShadows.cardHover,
        ),
        child: const Icon(Icons.add_rounded, color: AppColors.textPrimary, size: 22),
      ),
    ),
  );
}

class _Counter extends StatelessWidget {
  final int qty;
  final Product product;
  const _Counter({super.key, required this.qty, required this.product});

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartProvider>();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        boxShadow: AppShadows.button,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepIcon(
            icon: Icons.remove_rounded,
            onTap: () { HapticFeedback.lightImpact(); cart.remove(product.id); },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '$qty',
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14,
              ),
            ),
          ),
          _StepIcon(
            icon: Icons.add_rounded,
            onTap: () { HapticFeedback.lightImpact(); cart.add(product); },
          ),
        ],
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 32, height: 36,
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    ),
  );
}

/// Phase 7.3 — small circular heart overlay used by [ProductCard] and
/// `_ShopCard` (via the public copy in `shops_screen.dart`).
class _FavoriteHeart extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onTap;
  const _FavoriteHeart({required this.isFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? AppColors.error : AppColors.textSecondary,
              size: 18,
            ),
          ),
        ),
      );
}

class _Shimmer extends StatelessWidget {
  const _Shimmer();
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.surfaceMuted, AppColors.borderLight, AppColors.surfaceMuted],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
  );
}
