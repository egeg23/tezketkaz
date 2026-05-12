import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/l10n.dart';
import '../../models/catalog.dart';
import '../../services/analytics_service.dart';
import '../../services/catalog_api.dart';
import '../../services/favorite_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/banner_carousel.dart';
import '../../widgets/common.dart';
import '../../widgets/loading_shimmer.dart';
import '../../widgets/search_bar.dart';

/// Shops catalogue with 4 vertical tabs (grocery / restaurant / pharmacy /
/// electronics).
class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key});

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen>
    with SingleTickerProviderStateMixin {
  // TODO(buyer-loc): wire to real "last known location" once geolocator
  // wrapper exists. For now we centre on Tashkent which keeps backend happy.
  static const _defaultLat = 41.2995;
  static const _defaultLng = 69.2401;
  static const _radiusKm = 10.0;

  static const _verticals = [
    _Tab('grocery',     '🛒', 'vertical_grocery'),
    _Tab('restaurant',  '🍔', 'vertical_restaurant'),
    _Tab('pharmacy',    '💊', 'vertical_pharmacy'),
    _Tab('electronics', '📱', 'vertical_electronics'),
  ];

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _verticals.length, vsync: this);
    // Phase 7.4 — log a screen view per vertical so analytics can attribute
    // engagement by storefront type, not just by route.
    _tab.addListener(() {
      if (_tab.indexIsChanging) return;
      final v = _verticals[_tab.index];
      AnalyticsService.instance.logScreen('shops_${v.code}');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AnalyticsService.instance.logScreen('shops_${_verticals.first.code}');
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Phase 11 — rely on ThemeData.scaffoldBackgroundColor (dark mode).
      appBar: AppBar(
        title: Text(t(context, 'shops.title')),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: _verticals
              .map((v) => Tab(
                    text: '${v.emoji}  ${t(context, v.l10nKey)}',
                  ))
              .toList(),
        ),
      ),
      body: Column(
        children: [
          // Phase 7.3 — promotional banner carousel sits above the tab
          // contents so it stays visible across vertical switches.
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 12, 0, 4),
            child: BannerCarousel(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: _verticals
                  .map((v) => _ShopsTabView(
                        vertical: v.code,
                        lat: _defaultLat,
                        lng: _defaultLng,
                        radiusKm: _radiusKm,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab {
  final String code;
  final String emoji;
  final String l10nKey;
  const _Tab(this.code, this.emoji, this.l10nKey);
}

class _ShopsTabView extends StatefulWidget {
  final String vertical;
  final double lat;
  final double lng;
  final double radiusKm;
  const _ShopsTabView({
    required this.vertical,
    required this.lat,
    required this.lng,
    required this.radiusKm,
  });

  @override
  State<_ShopsTabView> createState() => _ShopsTabViewState();
}

class _ShopsTabViewState extends State<_ShopsTabView>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Shop> _shops = const [];
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final shops = await CatalogApi.instance.nearbyShops(
        vertical: widget.vertical,
        lat: widget.lat,
        lng: widget.lng,
        radiusKm: widget.radiusKm,
        q: _query.isEmpty ? null : _query,
        limit: 30,
      );
      if (!mounted) return;
      setState(() { _shops = shops; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onSearchChanged(String q) {
    if (q == _query) return;
    setState(() => _query = q);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
        children: [
          AppSearchBar(
            hint: t(context, 'shops.search_hint'),
            onChanged: _onSearchChanged,
            onSubmitted: _onSearchChanged,
          ),
          const SizedBox(height: 16),
          if (_loading)
            // Phase 13.3.4 — Wolt-style skeleton replaces the spinner so the
            // page has the same shape during load as after data lands.
            const SizedBox(
              height: 420,
              child: LoadingShimmer(itemCount: 4, itemHeight: 110),
            )
          else if (_error != null)
            ErrorView(message: _error!, onRetry: _load)
          else if (_shops.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: EmptyState(
                emoji: '🏪',
                title: t(context, 'shops.empty_title'),
                description: t(context, 'shops.empty_desc'),
              ),
            )
          else
            for (final s in _shops) ...[
              _ShopCard(shop: s),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _ShopCard extends StatefulWidget {
  final Shop shop;
  const _ShopCard({required this.shop});

  @override
  State<_ShopCard> createState() => _ShopCardState();
}

class _ShopCardState extends State<_ShopCard> {
  bool? _isFavorite;
  bool _favBusy = false;

  Shop get shop => widget.shop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFavorite());
  }

  Future<void> _loadFavorite() async {
    try {
      final fav = await FavoriteApi.instance.check(shopId: shop.id);
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
        await FavoriteApi.instance.addShop(shop.id);
      } else {
        await FavoriteApi.instance.removeShop(shop.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isFavorite = !(_isFavorite ?? false));
      }
    } finally {
      if (mounted) setState(() => _favBusy = false);
    }
  }

  String _verticalLabel(BuildContext context) {
    switch (shop.vertical) {
      case ShopVertical.grocery:     return t(context, 'vertical_grocery');
      case ShopVertical.restaurant:  return t(context, 'vertical_restaurant');
      case ShopVertical.pharmacy:    return t(context, 'vertical_pharmacy');
      case ShopVertical.electronics: return t(context, 'vertical_electronics');
      case ShopVertical.other:       return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      // Phase 11 — theme-aware so dark mode picks the right surface tone.
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: () {
          // Send shopId/shopName via `extra` so CatalogScreen can scope its
          // search. Keeps the route shape unchanged.
          context.push(
            '/buyer/catalog/all',
            extra: {'shopId': shop.id, 'shopName': shop.name},
          );
        },
        onLongPress: () =>
            context.push('/reviews/shop/${shop.id}', extra: shop.name),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: SizedBox(
                  width: 64, height: 64,
                  child: shop.logoUrl != null && shop.logoUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: shop.logoUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.surfaceMuted,
                            child: const Icon(Icons.storefront_rounded,
                                color: AppColors.textHint),
                          ),
                        )
                      : Container(
                          color: AppColors.surfaceMuted,
                          alignment: Alignment.center,
                          child: const Icon(Icons.storefront_rounded,
                              color: AppColors.textHint, size: 28),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shop.name,
                        style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8, runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (shop.distanceKm != null)
                          _MetaChip(
                            icon: Icons.place_rounded,
                            label: '${shop.distanceKm!.toStringAsFixed(1)} km',
                          ),
                        if (shop.rating != null)
                          _MetaChip(
                            icon: Icons.star_rounded,
                            label: shop.rating!.toStringAsFixed(1),
                            color: AppColors.warning,
                          ),
                        if (_verticalLabel(context).isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(AppRadii.pill),
                            ),
                            child: Text(
                              _verticalLabel(context),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (shop.workingHours != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        shop.workingHours!,
                        style: const TextStyle(
                          fontSize: 12, color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _isFavorite == true
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: _isFavorite == true
                      ? AppColors.error
                      : AppColors.textHint,
                ),
                onPressed: _toggleFavorite,
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MetaChip({required this.icon, required this.label, this.color});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color ?? AppColors.textSecondary),
      const SizedBox(width: 3),
      Text(label,
          style: TextStyle(
            fontSize: 12, color: color ?? AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          )),
    ],
  );
}
