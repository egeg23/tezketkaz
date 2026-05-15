import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
      setState(() { _loading = false; _error = "Магазин не подключён — выберите его через Сменить роль"; });
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
        backgroundColor: AppColors.surface,
        title: Text('Удалить «${p.name}»?',
            style: const TextStyle(color: Colors.white)),
        content: Text('Товар будет скрыт из каталога.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text("Удалить"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ProductApi.instance.delete(p.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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
        backgroundColor: AppColors.bg,
        title: const Text('Меню', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.cloud_sync_outlined, color: AppColors.primary),
            tooltip: 'API и интеграции',
            onPressed: () => context.push('/shop/integration'),
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Импорт Excel/CSV',
            onPressed: _openImport,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.bg,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Новый товар',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded,
                    size: 20, color: AppColors.textSecondary),
                hintText: "Поиск по товарам…",
                hintStyle: TextStyle(color: AppColors.textHint),
                isDense: true,
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
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
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
            )))
          else if (filtered.isEmpty)
            Expanded(child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📦', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 12),
                Text(
                  _filter.isEmpty ? 'Товаров пока нет' : 'Не найдено',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                if (_filter.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Добавьте товар вручную, загрузите Excel или\nподключите интеграцию по API',
                    textAlign: TextAlign.center,
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
