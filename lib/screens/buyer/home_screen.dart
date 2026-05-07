import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../models/models.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final list = await CatalogApi.instance.featured();
      if (!mounted) return;
      setState(() { _featured = list; _loading = false; });
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
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          _Header(user: user),

          if (activeOrder != null)
            SliverToBoxAdapter(child: _ActiveOrderBanner(order: activeOrder)),

          // Search
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: GestureDetector(
                onTap: () => context.go('/buyer/catalog/all'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    boxShadow: AppShadows.card,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: AppColors.textHint, size: 22),
                      const SizedBox(width: 12),
                      Text("Mahsulot, do'kon yoki kategoriya...",
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textHint)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Hero
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: const _HeroBanner(),
            ),
          ),

          // Categories
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Kategoriyalar', style: Theme.of(context).textTheme.headlineMedium),
                  TextButton(
                    onPressed: () => context.go('/buyer/catalog/all'),
                    child: const Text('Barchasi'),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final c = _categories[i];
                  return _CategoryTile(
                    emoji: c['emoji'] as String,
                    name: c['name'] as String,
                    bg: c['bg'] as Color,
                    fg: c['fg'] as Color,
                    onTap: () => context.go('/buyer/catalog/${c['id']}'),
                  );
                },
                childCount: _categories.length,
              ),
            ),
          ),

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
      backgroundColor: AppColors.bg,
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
                icon: Icons.swap_horiz_rounded,
                onTap: () => context.push('/switch-role'),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.go('/buyer/profile'),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
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
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        boxShadow: AppShadows.card,
      ),
      child: Icon(icon, size: 22, color: AppColors.textPrimary),
    ),
  );
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
    height: 156,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF14A44D), Color(0xFF0E8B40)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(AppRadii.xl),
      boxShadow: AppShadows.button,
    ),
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          right: -40, bottom: -40,
          child: Container(
            width: 180, height: 180,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          right: 24, top: 18,
          child: Text('🛍️', style: const TextStyle(fontSize: 80)),
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
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded, color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                    Text('15 daqiqa',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text("Birinchi buyurtmaga\n20% chegirma",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800, height: 1.2,
                  )),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                ),
                child: Text('BIRINCHI20',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white, letterSpacing: 1.2, fontWeight: FontWeight.w700,
                    )),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CategoryTile extends StatelessWidget {
  final String emoji, name;
  final Color bg, fg;
  final VoidCallback onTap;
  const _CategoryTile({
    required this.emoji,
    required this.name,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: bg,
    borderRadius: BorderRadius.circular(AppRadii.lg),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 6),
            Text(name,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg,
                ),
                textAlign: TextAlign.center,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ),
  );
}
