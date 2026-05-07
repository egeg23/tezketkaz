import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/product_api.dart';
import '../../theme/app_theme.dart';
import 'shop_shell.dart' show kShopColor;
import 'shop_product_editor.dart';
import 'shop_products_import.dart';

class ShopProductsScreen extends StatefulWidget {
  const ShopProductsScreen({super.key});
  @override
  State<ShopProductsScreen> createState() => _ShopProductsScreenState();
}

class _ShopProductsScreenState extends State<ShopProductsScreen> {
  List<ShopProduct> _products = [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final shopId = context.read<AuthProvider>().user?.shopId;
    if (shopId == null) {
      setState(() { _loading = false; _error = "Do'kon ulanmagan"; });
      return;
    }
    try {
      final list = await ProductApi.instance.forShopOwner(shopId);
      if (!mounted) return;
      setState(() { _products = list; _loading = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _openEditor({ShopProduct? product}) async {
    final shopId = context.read<AuthProvider>().user?.shopId;
    if (shopId == null) return;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ShopProductEditor(shopId: shopId, product: product),
    ));
    if (result == true) _load();
  }

  Future<void> _openImport() async {
    final shopId = context.read<AuthProvider>().user?.shopId;
    if (shopId == null) return;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ShopProductsImport(shopId: shopId),
    ));
    if (result == true) _load();
  }

  Future<void> _delete(ShopProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('"${p.name}" o\'chirilsinmi?'),
        content: const Text('Mahsulot katalogdan yashiriladi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Bekor')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text("O'chirish"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ProductApi.instance.delete(p.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Xatolik: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter.isEmpty
        ? _products
        : _products.where((p) =>
            p.name.toLowerCase().contains(_filter.toLowerCase()) ||
            p.nameUz.toLowerCase().contains(_filter.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Mahsulotlar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Excel/CSV import',
            onPressed: _openImport,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kShopColor,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Yangi mahsulot'),
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: "Qidirish...",
                isDense: true,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Xatolik: $_error', textAlign: TextAlign.center),
            )))
          else if (filtered.isEmpty)
            Expanded(child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📦', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 12),
                Text(
                  _filter.isEmpty ? 'Mahsulotlar yo\'q' : 'Topilmadi',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (_filter.isEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Yangi qo\'shing yoki Excel orqali yuklang',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            )))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _Row(
                  product: filtered[i],
                  onTap: () => _openEditor(product: filtered[i]),
                  onDelete: () => _delete(filtered[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final ShopProduct product;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _Row({required this.product, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final hasDiscount = p.discountPrice != null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: p.imageUrl.isNotEmpty
                    ? Image.network(p.imageUrl, width: 56, height: 56, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _ph())
                    : _ph(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(p.name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (!p.isAvailable)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Arxiv',
                                style: TextStyle(fontSize: 10, color: AppColors.textHint)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${(hasDiscount ? p.discountPrice! : p.price).toInt()} so\'m / ${p.unit}',
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${p.price.toInt()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textHint,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${p.stock} dona',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ph() => Container(
        width: 56, height: 56,
        color: AppColors.bg,
        child: const Icon(Icons.image_outlined, color: AppColors.textHint),
      );
}
