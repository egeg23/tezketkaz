import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../services/favorite_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Phase 7.3 — buyer's favourites with two tabs (Products / Shops).
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _loading = true;
  String? _error;
  List<Favorite> _all = const [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await FavoriteApi.instance.list();
      if (!mounted) return;
      setState(() {
        _all = list;
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

  @override
  Widget build(BuildContext context) {
    final products = _all.where((f) => f.isProduct).toList();
    final shops = _all.where((f) => f.isShop).toList();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(t(context, 'favorites.title')),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: t(context, 'favorites.tab_products')),
            Tab(text: t(context, 'favorites.tab_shops')),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tab,
                  children: [
                    _buildProductList(products),
                    _buildShopList(shops),
                  ],
                ),
    );
  }

  Widget _buildProductList(List<Favorite> items) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            EmptyState(
              emoji: '❤️',
              title: t(context, 'favorites.empty_products_title'),
              description: t(context, 'favorites.empty_products_desc'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final f = items[i];
          final p = f.product;
          return Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: InkWell(
              onTap: () {
                if (p == null) return;
                context.go('/buyer/catalog/all',
                    extra: {'shopId': p.shopId});
              },
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: (p?.imageUrl ?? '').isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: p!.imageUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: AppColors.surfaceMuted,
                                  child: const Icon(Icons.image_outlined,
                                      color: AppColors.textHint),
                                ),
                              )
                            : Container(
                                color: AppColors.surfaceMuted,
                                child: const Icon(Icons.image_outlined,
                                    color: AppColors.textHint),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p?.name ?? f.productId ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.favorite,
                          color: AppColors.error),
                      onPressed: () async {
                        final id = f.productId;
                        if (id == null) return;
                        await FavoriteApi.instance.removeProduct(id);
                        if (!mounted) return;
                        setState(() {
                          _all = _all
                              .where((x) => x.id != f.id)
                              .toList(growable: false);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShopList(List<Favorite> items) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            EmptyState(
              emoji: '🏪',
              title: t(context, 'favorites.empty_shops_title'),
              description: t(context, 'favorites.empty_shops_desc'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final f = items[i];
          final s = f.shop;
          return Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: InkWell(
              onTap: () {
                if (s == null) return;
                context.push(
                  '/buyer/catalog/all',
                  extra: {'shopId': s.id, 'shopName': s.name},
                );
              },
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: (s?.logoUrl ?? '').isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: s!.logoUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: AppColors.surfaceMuted,
                                  child: const Icon(
                                      Icons.storefront_rounded,
                                      color: AppColors.textHint),
                                ),
                              )
                            : Container(
                                color: AppColors.surfaceMuted,
                                child: const Icon(Icons.storefront_rounded,
                                    color: AppColors.textHint),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s?.name ?? f.shopId ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.favorite,
                          color: AppColors.error),
                      onPressed: () async {
                        final id = f.shopId;
                        if (id == null) return;
                        await FavoriteApi.instance.removeShop(id);
                        if (!mounted) return;
                        setState(() {
                          _all = _all
                              .where((x) => x.id != f.id)
                              .toList(growable: false);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
