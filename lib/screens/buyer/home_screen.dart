import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../models/models.dart';
import '../../models/catalog.dart' show Shop, shopVerticalToString;
import '../../services/catalog_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/product_card.dart';

const _categories = [
  {'id': 'produce', 'name': 'Sabzavot', 'emoji': '🥦', 'bg': AppColors.catProduce, 'fg': AppColors.catProduceFg},
  {'id': 'meat',    'name': "Go'sht",   'emoji': '🥩', 'bg': AppColors.catMeat,    'fg': AppColors.catMeatFg},
  {'id': 'dairy',   'name': 'Sut',      'emoji': '🥛', 'bg': AppColors.catDairy,   'fg': AppColors.catDairyFg},
  {'id': 'bakery',  'name': 'Non',      'emoji': '🍞', 'bg': AppColors.catBakery,  'fg': AppColors.catBakeryFg},
  {'id': 'drinks',  'name': 'Ichimlik', 'emoji': '🥤', 'bg': AppColors.catDrinks,  'fg': AppColors.catDrinksFg},
  {'id': 'grocery', 'name': 'Bakaleya', 'emoji': '🛒', 'bg': AppColors.catGrocery, 'fg': AppColors.catGroceryFg},
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> _featured = [];
  List<Shop> _shops = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        CatalogApi.instance.featured(),
        CatalogApi.instance.nearbyShops(limit: 12),
      ]);
      if (!mounted) return;
      setState(() {
        _featured = results[0] as List<Product>;
        _shops = results[1] as List<Shop>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final orders = context.watch<OrderProvider>();
    final user = auth.user;
    final activeOrder = orders.activeOrderForBuyer(user?.id ?? '');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          _Header(user: user),

          if (activeOrder != null)
            SliverToBoxAdapter(child: _ActiveOrderBanner(order: activeOrder)),

          // Search — UberEats-style pill with mic on the right
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: GestureDetector(
                onTap: () => context.go('/buyer/catalog/all'),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    boxShadow: Theme.of(context).brightness == Brightness.dark
                        ? null : AppShadows.card,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: AppColors.textHint, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text("Mahsulot, do'kon yoki kategoriya...",
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textHint)),
                      ),
                      Container(
                        width: 1, height: 22, color: AppColors.borderLight,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.mic_rounded, color: AppColors.neutralInk, size: 22),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ovozli qidiruv tez orada'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Hero
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _HeroBanner(),
            ),
          ),

          // Categories — UberEats horizontal scrolling pills
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text("Kategoriya bo'yicha buyurtma",
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemCount: _categories.length,
                itemBuilder: (_, i) {
                  final c = _categories[i];
                  return _CategoryPill(
                    emoji: c['emoji'] as String,
                    name: c['name'] as String,
                    onTap: () => context.go('/buyer/catalog/${c['id']}'),
                  );
                },
              ),
            ),
          ),

          // Shops carousel (UberEats — large image cards horizontal scroll)
          if (_shops.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Yaqin atrofdagi do'konlar",
                        style: Theme.of(context).textTheme.headlineMedium),
                    TextButton(
                      onPressed: () => context.go('/buyer/shops'),
                      child: const Text('Barchasi'),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 230,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemCount: _shops.length,
                  itemBuilder: (_, i) => _ShopCard(
                    shop: _shops[i],
                    onTap: () => context.push(
                      '/buyer/shop/${_shops[i].id}',
                      extra: <String, dynamic>{'shopName': _shops[i].name},
                    ),
                  ),
                ),
              ),
            ),
          ],

          // Featured
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Ommabop tovarlar', style: Theme.of(context).textTheme.headlineMedium),
                  TextButton(
                    onPressed: () => context.go('/buyer/catalog/all'),
                    child: const Text('Barchasi'),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_featured.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    "Hozircha mahsulot yo'q",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.74,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => ProductCard(product: _featured[i]),
                  childCount: _featured.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final User? user;
  const _Header({this.user});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 72,
      automaticallyImplyLeading: false,
      flexibleSpace: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {},
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Text('Yetkazib berish',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textHint, fontWeight: FontWeight.w500,
                              )),
                          const SizedBox(width: 4),
                          const Icon(Icons.bolt_rounded, size: 12, color: AppColors.warning),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              "Yunusobod, 13-mavze",
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _IconPill(
                icon: Icons.notifications_none_rounded,
                onTap: () => context.push('/buyer/notifications'),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.push('/switch-role'),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.neutralInk,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    boxShadow: AppShadows.button,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    user?.name?.isNotEmpty == true ? user!.name![0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16,
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

class _IconPill extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconPill({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: isDark ? null : AppShadows.card,
        ),
        child: Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }
}

class _ActiveOrderBanner extends StatelessWidget {
  final AppOrder order;
  const _ActiveOrderBanner({required this.order});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
    child: GestureDetector(
      onTap: () => context.go('/buyer/tracking/${order.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow: AppShadows.button,
        ),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              alignment: Alignment.center,
              child: Text(order.statusEmoji, style: const TextStyle(fontSize: 28)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.statusLabel,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(order.shopName,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) => Container(
    height: 168,
    decoration: BoxDecoration(
      // UberEats Eats Pass-style — near-black card with a lime spark.
      color: AppColors.neutralInk,
      borderRadius: BorderRadius.circular(AppRadii.xl),
      boxShadow: AppShadows.elevated,
    ),
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Lime glow corner
        Positioned(
          right: -60, bottom: -60,
          child: Container(
            width: 220, height: 220,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const Positioned(
          right: 28, top: 22,
          child: Text('🛍️', style: TextStyle(fontSize: 84)),
        ),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, color: AppColors.neutralInk, size: 13),
                    SizedBox(width: 4),
                    Text('15 daqiqa',
                        style: TextStyle(
                          color: AppColors.neutralInk,
                          fontWeight: FontWeight.w800, fontSize: 11,
                          letterSpacing: 0.2,
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text("Birinchi buyurtmaga\n20% chegirma",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19, fontWeight: FontWeight.w800, height: 1.2,
                    letterSpacing: -0.2,
                  )),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                ),
                child: const Text('BIRINCHI20',
                    style: TextStyle(
                      color: Colors.white, letterSpacing: 1.4,
                      fontWeight: FontWeight.w800, fontSize: 12,
                    )),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// UberEats-style horizontal category pill — soft-grey circle for the emoji,
/// label centered below. Tap navigates into the catalog filter.
class _CategoryPill extends StatelessWidget {
  final String emoji, name;
  final VoidCallback onTap;
  const _CategoryPill({required this.emoji, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadii.lg),
    child: SizedBox(
      width: 84,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 34)),
          ),
          const SizedBox(height: 8),
          Text(name,
              style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );
}

/// UberEats-style large shop card with cover image, name, badges row.
class _ShopCard extends StatelessWidget {
  final Shop shop;
  final VoidCallback onTap;
  const _ShopCard({required this.shop, required this.onTap});

  String get _emoji {
    switch (shopVerticalToString(shop.vertical)) {
      case 'restaurant': return '🍽️';
      case 'pharmacy':   return '💊';
      case 'electronics': return '📱';
      case 'grocery':    return '🛒';
      default:           return '🏪';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: SizedBox(
                height: 140, width: 260,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: AppColors.surfaceMuted),
                    if (shop.logoUrl != null && shop.logoUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: shop.logoUrl!, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Center(
                          child: Text(_emoji, style: const TextStyle(fontSize: 56)),
                        ),
                      )
                    else
                      Center(child: Text(_emoji, style: const TextStyle(fontSize: 56))),
                    if (!shop.isOpen)
                      Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.neutralInk,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: const Text("Yopiq",
                              style: TextStyle(
                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700,
                              )),
                        ),
                      ),
                    // ETA chip
                    Positioned(
                      bottom: 10, left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.neutralInk,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded, color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              shop.distanceKm != null
                                  ? '${shop.distanceKm!.toStringAsFixed(1)} km'
                                  : '15-25 daqiqa',
                              style: const TextStyle(
                                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    shop.name,
                    style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary, letterSpacing: -0.2,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (shop.rating != null) ...[
                  const Icon(Icons.star_rounded, size: 16, color: AppColors.textPrimary),
                  const SizedBox(width: 2),
                  Text(
                    shop.rating!.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
            if (shop.address != null) ...[
              const SizedBox(height: 2),
              Text(
                shop.address!,
                style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
