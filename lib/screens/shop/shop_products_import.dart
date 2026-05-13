import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/product_api.dart';
import '../../theme/app_theme.dart';
import 'shop_shell.dart' show kShopColor;

class ShopProductsImport extends StatefulWidget {
  final String shopId;
  const ShopProductsImport({super.key, required this.shopId});

  @override
  State<ShopProductsImport> createState() => _ShopProductsImportState();
}

class _ShopProductsImportState extends State<ShopProductsImport> {
  bool _busy = false;
  ImportResult? _result;
  String? _filename;
  String? _error;

  Future<void> _downloadTemplate(bool xlsx) async {
    final url = Uri.parse(ProductApi.instance.templateUrl(xlsx: xlsx));
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yuklab olish: $url')));
    }
  }

  Future<void> _pickAndImport({required bool dryRun}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    if (f.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Faylni o'qib bo'lmadi")));
      return;
    }
    setState(() {
      _busy = true;
      _filename = f.name;
      _error = null;
      _result = null;
    });
    try {
      final res = await ProductApi.instance.importFromFile(
        shopId: widget.shopId,
        bytes: f.bytes!,
        filename: f.name,
        dryRun: dryRun,
      );
      if (!mounted) return;
      setState(() { _result = res; _busy = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final imported = _result != null && _result!.created > 0 && _result!.errors.isEmpty;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Excel/CSV import'),
        actions: [
          if (imported)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Tayyor'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Step 1: template
          _Card(
            step: '1',
            title: "Shablonni yuklab oling",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Sarlavhalar: name, nameUz, description, ingredients, "
                  "price, discountPrice, unit, category, imageUrl, stock",
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _downloadTemplate(true),
                        icon: const Icon(Icons.table_chart_outlined, size: 18),
                        label: const Text('XLSX'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _downloadTemplate(false),
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text('CSV'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Step 2: import
          _Card(
            step: '2',
            title: "Faylni yuklang",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_filename != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_filename!, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pickAndImport(dryRun: true),
                        icon: const Icon(Icons.preview_outlined, size: 18),
                        label: const Text('Tekshirish'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : () => _pickAndImport(dryRun: false),
                        style: ElevatedButton.styleFrom(backgroundColor: kShopColor),
                        icon: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: const Text('Yuklash', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Result
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error))),
              ]),
            )
          else if (_result != null) ...[
            _ResultBanner(result: _result!),
            if (_result!.errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Xatoliklar', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const Divider(height: 1),
                    ..._result!.errors.map((e) => ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${e.row}', style: const TextStyle(fontSize: 12)),
                      ),
                      title: Text(e.error, style: const TextStyle(fontSize: 13)),
                    )),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String step;
  final String title;
  final Widget child;
  const _Card({required this.step, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 24, height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: kShopColor,
                shape: BoxShape.circle,
              ),
              child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  final ImportResult result;
  const _ResultBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final isSuccess = result.errors.isEmpty;
    final color = isSuccess ? AppColors.success : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(isSuccess ? Icons.check_circle : Icons.warning_amber, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.created > 0
                      ? '${result.created} ta mahsulot qo\'shildi'
                      : 'Hech nima qo\'shilmadi',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
                Text(
                  '${result.total} qator, ${result.errors.length} xato',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
