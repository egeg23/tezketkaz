import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../models/models.dart';
import '../../models/catalog.dart' show Shop;
import '../../services/catalog_api.dart';
import '../../theme/app_theme.dart';

/// HOME — exact port of Master Design v1 (screen 01).
///
/// Layout in master.html (lines 5953-6087):
///   home-header  → location-pill + glass bell
///   greeting     → "Xush kelibsiz, {Asal}" in Playfair italic with lime accent
///   greeting-sub → "Bugun nima buyurtma qilamiz?"
///   search       → glass pill: lupe · text · divider · mic
///   chips        → horizontal scroll: Hammasi (active), Mashhur, Sushi, ...
///   hero-card    → featured shop with radial-gradient cover + bottom overlay
///   shop-row     → vertical list of nearby shops (small 68x68 thumb + name + meta)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _chips = [
    'Все', 'Популярное', 'Суши', 'Пицца', 'Бургер', 'Узбекская', 'Веган',
  ];

  List<Shop> _shops = const [];
  String _activeChip = 'Все';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final shops = await CatalogApi.instance.nearbyShops(limit: 12);
      if (!mounted) return;
      setState(() { _shops = shops; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final orders = context.watch<OrderProvider>();
    final user = auth.user;
    final firstName = (user?.name ?? '').split(' ').first;
    final activeOrder = orders.activeOrderForBuyer(user?.id ?? '');

    final heroShop = _shops.isNotEmpty ? _shops.first : null;
    final restShops = _shops.length > 1 ? _shops.sublist(1) : const <Shop>[];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        // Body ambient — same radial spotlights as master.html body.
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.8, -0.95),
            radius: 0.9,
            colors: [Color(0x1A06C167), Color(0x00000000)],
            stops: [0, 1],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              _Header(user: user),
              const SizedBox(height: 24),
              _Greeting(name: firstName.isEmpty ? null : firstName),
              const SizedBox(height: 20),
              _SearchPill(onTap: () => context.go('/buyer/catalog/all')),
              const SizedBox(height: 22),
              if (activeOrder != null) ...[
                _ActiveOrderBanner(order: activeOrder),
                const SizedBox(height: 22),
              ],
              _Chips(
                items: _chips,
                active: _activeChip,
                onPick: (c) {
                  setState(() => _activeChip = c);
                  HapticFeedback.selectionClick();
                },
              ),
              const SizedBox(height: 24),
              if (heroShop != null)
                _HeroCard(shop: heroShop, onTap: () => context.push(
                  '/buyer/shop/${heroShop.id}',
                  extra: <String, dynamic>{'shopName': heroShop.name},
                ))
              else if (_loading)
                const _HeroPlaceholder(),
              const SizedBox(height: 28),
              _SectionRow(
                title: 'Рядом с вами',
                onMore: () => context.go('/buyer/shops'),
              ),
              const SizedBox(height: 14),
              if (_loading && restShops.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                for (final s in restShops) ...[
                  _ShopRow(
                    shop: s,
                    onTap: () => context.push(
                      '/buyer/shop/${s.id}',
                      extra: <String, dynamic>{'shopName': s.name},
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              if (!_loading && _shops.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text(
                    "Пока нет ресторанов",
                    style: TextStyle(color: AppColors.textHint),
                  )),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final User? user;
  const _Header({this.user});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // Location pill — glass + backdrop blur in master; static here.
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(100),
            border: const Border.fromBorderSide(BorderSide(color: AppColors.border)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PulsingDot(),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Ташкент, Чиланзар',
                  style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '▾',
                style: TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ),
      const Spacer(),
      _BellChip(onTap: () => context.push('/buyer/notifications')),
    ],
  );
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.5, end: 1.0).animate(_c),
    child: Container(
      width: 7, height: 7,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.7),
          blurRadius: 12, spreadRadius: 1,
        )],
      ),
    ),
  );
}

class _BellChip extends StatelessWidget {
  final VoidCallback onTap;
  const _BellChip({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Center(
            child: Icon(Icons.notifications_none_rounded,
                size: 20, color: AppColors.textPrimary),
          ),
          Positioned(
            top: 8, right: 8,
            child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Greeting (Playfair italic) ─────────────────────────────────────────────

class _Greeting extends StatelessWidget {
  final String? name;
  const _Greeting({this.name});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RichText(
        text: TextSpan(
          style: GoogleFonts.playfairDisplay(
            fontSize: 34, fontWeight: FontWeight.w500,
            letterSpacing: -0.7, height: 1.1, color: Colors.white,
          ),
          children: [
            const TextSpan(text: 'Добро пожаловать,\n'),
            TextSpan(
              text: name ?? 'Асаль',
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
        "Что закажем сегодня?",
        style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
      ),
    ],
  );
}

// ── Search pill ───────────────────────────────────────────────────────────

class _SearchPill extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchPill({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18,
              color: AppColors.textSecondary.withValues(alpha: 0.85)),
          const SizedBox(width: 12),
          Expanded(child: Text(
            'Ресторан или блюдо',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          )),
          Container(
            width: 1, height: 20,
            color: AppColors.border,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          Icon(Icons.mic_rounded, size: 18,
              color: AppColors.textSecondary.withValues(alpha: 0.85)),
        ],
      ),
    ),
  );
}

// ── Chips ─────────────────────────────────────────────────────────────────

class _Chips extends StatelessWidget {
  final List<String> items;
  final String active;
  final ValueChanged<String> onPick;
  const _Chips({required this.items, required this.active, required this.onPick});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      padding: const EdgeInsets.symmetric(horizontal: 0),
      itemBuilder: (_, i) {
        final c = items[i];
        final isActive = c == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : const Color(0x08FFFFFF),
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(100),
            boxShadow: isActive
                ? [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 16, offset: const Offset(0, 4),
                  )]
                : null,
          ),
          child: InkWell(
            onTap: () => onPick(c),
            child: Text(
              c,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? const Color(0xFF003A1F) : Colors.white,
              ),
            ),
          ),
        );
      },
    ),
  );
}

// ── Hero card ─────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final Shop shop;
  final VoidCallback onTap;
  const _HeroCard({required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cover image fallback — dark amber radial gradient.
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.5, -0.3),
                radius: 1.2,
                colors: [Color(0xFF3A2618), Color(0xFF1A0E08)],
              ),
            ),
          ),
          if (shop.logoUrl != null && shop.logoUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: shop.logoUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          // Bottom dark overlay
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xA6000000)],
                stops: [0.45, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),

          // Top badge
          Positioned(
            top: 20, left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Text(
                '★ ВЫБОР РЕДАКЦИИ',
                style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w600,
                  letterSpacing: 0.8, color: AppColors.primary,
                ),
              ),
            ),
          ),

          // Bottom info row
          Positioned(
            left: 20, right: 20, bottom: 18,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        shop.name,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 24, fontWeight: FontWeight.w600,
                          letterSpacing: -0.3, color: Colors.white,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _HeroMetaRow(shop: shop),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: const Text(
                    '25 min',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _HeroMetaRow extends StatelessWidget {
  final Shop shop;
  const _HeroMetaRow({required this.shop});
  @override
  Widget build(BuildContext context) {
    final rating = shop.rating?.toStringAsFixed(1) ?? '4.8';
    final addr = (shop.address ?? "O'zbek oshxonasi").split(',').first;
    return Row(
      children: [
        Text('★ $rating',
            style: const TextStyle(
              fontSize: 12, color: Colors.white,
              fontWeight: FontWeight.w600,
            )),
        Text(' · ', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
        Flexible(
          child: Text(addr,
              style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.8),
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    height: 200,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      color: AppColors.surfaceMuted,
      border: Border.all(color: AppColors.border),
    ),
    alignment: Alignment.center,
    child: const CircularProgressIndicator(),
  );
}

// ── Section row ───────────────────────────────────────────────────────────

class _SectionRow extends StatelessWidget {
  final String title;
  final VoidCallback onMore;
  const _SectionRow({required this.title, required this.onMore});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 20, fontWeight: FontWeight.w500,
            letterSpacing: -0.3, color: Colors.white,
          )),
      const Spacer(),
      GestureDetector(
        onTap: onMore,
        child: Text(
          'Hammasi →',
          style: TextStyle(
            fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

// ── Shop row (small list item) ────────────────────────────────────────────

class _ShopRow extends StatelessWidget {
  final Shop shop;
  final VoidCallback onTap;
  const _ShopRow({required this.shop, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final rating = shop.rating?.toStringAsFixed(1) ?? '4.7';
    final dist = shop.distanceKm != null
        ? '${shop.distanceKm!.toStringAsFixed(1)} km'
        : '20 min';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x09FFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 68, height: 68,
                child: shop.logoUrl != null && shop.logoUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: shop.logoUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _ShopThumbFallback(),
                      )
                    : _ShopThumbFallback(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shop.name,
                    style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      letterSpacing: -0.2, color: Colors.white,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('★ $rating',
                          style: TextStyle(
                            color: AppColors.primary, fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                      Text(' · ', style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4), fontSize: 12,
                      )),
                      Flexible(
                        child: Text(
                          shop.address ?? '',
                          style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(' · ', style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4), fontSize: 12,
                      )),
                      Text(dist,
                          style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12,
                          )),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopThumbFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(-0.4, -0.4),
        colors: [Color(0xFFE8B06C), Color(0xFF3A1A08)],
        stops: [0, 1],
      ),
    ),
    child: const Center(child: Text('🍽️', style: TextStyle(fontSize: 32))),
  );
}

// ── Active order banner (kept from prior design, now glass-styled) ────────

class _ActiveOrderBanner extends StatelessWidget {
  final AppOrder order;
  const _ActiveOrderBanner({required this.order});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.go('/buyer/tracking/${order.id}'),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(order.statusEmoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.statusLabel,
                    style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14,
                    )),
                const SizedBox(height: 2),
                Text(order.shopName,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.primary),
        ],
      ),
    ),
  );
}
