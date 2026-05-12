import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/cart_provider.dart';
import '../../services/catalog_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_shimmer.dart';
import '../../widgets/product_card.dart';

const _categoryLabels = {
  'all': 'Barcha mahsulotlar',
  'produce': 'Sabzavot va meva',
  'meat': "Go'sht mahsulotlari",
  'dairy': 'Sut mahsulotlari',
  'bakery': 'Non va non mahsulotlari',
  'drinks': 'Ichimliklar',
  'grocery': 'Bakaleya',
};

class CatalogScreen extends StatefulWidget {
  final String category;
  final String? shopId;
  final String? shopName;
  const CatalogScreen({super.key, required this.category, this.shopId, this.shopName});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _search = '';
  String _sort = 'popular';
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Phase 11 — seed the cart provider with the shop name so the
      // multi-shop switcher chip can label the draft before the backend
      // hydrates a summary row.
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
      // When a shopId is supplied (Phase 1 — coming from ShopsScreen) use the
      // paginated search endpoint scoped to that shop. Otherwise keep the
      // legacy category list.
      if (widget.shopId != null) {
        final res = await CatalogApi.instance.search(
          shopId: widget.shopId,
          categoryId: widget.category == 'all' ? null : widget.category,
          limit: 50,
        );
        if (!mounted) return;
        setState(() { _products = res.items; _loading = false; });
      } else {
        final list = await CatalogApi.instance.list(category: widget.category);
        if (!mounted) return;
        setState(() { _products = list; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Product> get _filtered {
    var list = List<Product>.from(_products);
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((p) =>
        p.name.toLowerCase().contains(q) || p.nameUz.toLowerCase().contains(q)
      ).toList();
    }
    if (_sort == 'price_asc') list.sort((a, b) => a.effectivePrice.compareTo(b.effectivePrice));
    if (_sort == 'price_desc') list.sort((a, b) => b.effectivePrice.compareTo(a.effectivePrice));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.shopName ?? _categoryLabels[widget.category] ?? widget.category),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        hintText: 'Qidirish...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textHint),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    boxShadow: AppShadows.card,
                  ),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.tune_rounded),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'popular', child: Text('Ommabop')),
                      PopupMenuItem(value: 'price_asc', child: Text('Avval arzon')),
                      PopupMenuItem(value: 'price_desc', child: Text('Avval qimmat')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          // Phase 13.3.4 — shimmer grid keeps the UI shape consistent during load.
          ? const LoadingShimmerGrid(itemCount: 6, aspectRatio: 0.74)
          : RefreshIndicator(
              onRefresh: _load,
              child: _filtered.isEmpty
                  // Wrap empty state in a scrollable so pull-to-refresh still works.
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 80),
                        Center(child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🔍', style: TextStyle(fontSize: 56)),
                              const SizedBox(height: 12),
                              Text('Topilmadi',
                                  style: Theme.of(context).textTheme.headlineMedium),
                              const SizedBox(height: 4),
                              const Text(
                                "Boshqa kategoriya yoki so'rovni sinab ko'ring",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        )),
                      ],
                    )
                  : GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, crossAxisSpacing: 14,
                        mainAxisSpacing: 14, childAspectRatio: 0.74,
                      ),
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) => ProductCard(product: _filtered[i]),
                    ),
            ),
    );
  }
}
