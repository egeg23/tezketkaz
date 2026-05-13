import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/catalog.dart' show Shop;
import '../../models/models.dart';
import '../../services/catalog_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/product_card.dart';

/// Wolt/UberEats-style merchant page:
///   - large hero cover with parallax behaviour via SliverAppBar
///   - meta row (rating · distance · ETA · working hours)
///   - product grid scoped to this shop
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        CatalogApi.instance.nearbyShops(limit: 50),
        CatalogApi.instance.search(shopId: widget.shopId, limit: 50),
      ]);
      final shops = results[0] as List<Shop>;
      final items = (results[1] as ({List<Product> items, String? nextCursor})).items;
      if (!mounted) return;
      setState(() {
        _shop = shops.where((s) => s.id == widget.shopId).cast<Shop?>().firstOrNull;
        _products = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.shopName ?? '')),
        body: Center(child: Text(_error!)),
      );
    }
    final shop = _shop;
    final name = shop?.name ?? widget.shopName ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: AppColors.neutralInk,
            foregroundColor: Colors.white,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: _CircleChip(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: shop?.logoUrl != null && shop!.logoUrl!.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: shop.logoUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: AppColors.surfaceMuted),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.35),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.55),
                              ],
                              stops: const [0.0, 0.4, 1.0],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: AppColors.neutralInk,
                      alignment: Alignment.center,
                      child: const Text('🏪', style: TextStyle(fontSize: 80)),
                    ),
            ),
          ),

          // Header card with meta
          SliverToBoxAdapter(
            child: Container(
              transform: Matrix4.translationValues(0, -24, 0),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900,
                        letterSpacing: -0.5, color: AppColors.textPrimary,
                      )),
                  if (shop?.address != null) ...[
                    const SizedBox(height: 6),
                    Text(shop!.address!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13, fontWeight: FontWeight.w500,
                        )),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      if (shop?.rating != null)
                        _Chip(icon: Icons.star_rounded,
                            text: '${shop!.rating!.toStringAsFixed(1)}'
                                '${shop.reviewsCount != null ? ' · ${shop.reviewsCount}' : ''}'),
                      if (shop?.distanceKm != null)
                        _Chip(icon: Icons.place_outlined,
                            text: '${shop!.distanceKm!.toStringAsFixed(1)} km'),
                      const _Chip(icon: Icons.bolt_rounded, text: '15-25 daqiqa', lime: true),
                      if (shop?.workingHours != null && shop!.workingHours!.isNotEmpty)
                        _Chip(icon: Icons.schedule_rounded, text: shop.workingHours!),
                      if (shop?.isOpen == false)
                        const _Chip(icon: Icons.lock_clock_rounded, text: 'Yopiq', danger: true),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Products
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text("Mahsulotlar",
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
          ),
          if (_products.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text("Hozircha mahsulot yo'q",
                    style: TextStyle(color: AppColors.textSecondary))),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 0.74,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => ProductCard(product: _products[i]),
                  childCount: _products.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool lime;
  final bool danger;
  const _Chip({required this.icon, required this.text, this.lime = false, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? AppColors.errorLight
        : lime
            ? AppColors.primaryLight
            : AppColors.surfaceMuted;
    final fg = danger
        ? AppColors.error
        : lime
            ? AppColors.primaryDark
            : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: fg,
          )),
        ],
      ),
    );
  }
}

class _CircleChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleChip({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    elevation: 0,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.neutralInk, size: 22),
      ),
    ),
  );
}
