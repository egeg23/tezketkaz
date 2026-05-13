import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/product_api.dart';
import '../../theme/app_theme.dart';
import 'shop_shell.dart' show kShopColor;

const _categories = [
  {'id': 'produce', 'label': 'Sabzavot/meva'},
  {'id': 'meat', 'label': "Go'sht"},
  {'id': 'dairy', 'label': 'Sut mahsulotlari'},
  {'id': 'bakery', 'label': 'Non/non-mahsulot'},
  {'id': 'drinks', 'label': 'Ichimliklar'},
  {'id': 'grocery', 'label': 'Bakaleya'},
];
const _units = ['кг', 'шт', 'л', 'пачка'];

class ShopProductEditor extends StatefulWidget {
  final String shopId;
  final ShopProduct? product;
  const ShopProductEditor({super.key, required this.shopId, this.product});

  @override
  State<ShopProductEditor> createState() => _ShopProductEditorState();
}

class _ShopProductEditorState extends State<ShopProductEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _nameUz = TextEditingController();
  final _description = TextEditingController();
  final _ingredients = TextEditingController();
  final _price = TextEditingController();
  final _discountPrice = TextEditingController();
  final _stock = TextEditingController(text: '100');
  String _category = 'produce';
  String _unit = 'кг';
  String _imageUrl = '';
  bool _isAvailable = true;
  bool _saving = false;
  bool _uploading = false;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _name.text = p.name;
      _nameUz.text = p.nameUz;
      _description.text = p.description ?? '';
      _ingredients.text = p.ingredients ?? '';
      _price.text = p.price.toInt().toString();
      _discountPrice.text = p.discountPrice?.toInt().toString() ?? '';
      _stock.text = p.stock.toString();
      _category = p.category;
      _unit = p.unit;
      _imageUrl = p.imageUrl;
      _isAvailable = p.isAvailable;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _nameUz.dispose();
    _description.dispose();
    _ingredients.dispose();
    _price.dispose();
    _discountPrice.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final Uint8List bytes = await file.readAsBytes();
      final url = await ProductApi.instance.uploadImage(bytes: bytes, filename: file.name);
      if (!mounted) return;
      setState(() { _imageUrl = url; _uploading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Yuklashda xatolik: $e')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rasm kerak')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await ProductApi.instance.update(widget.product!.id, {
          'name': _name.text.trim(),
          'nameUz': _nameUz.text.trim(),
          'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
          'ingredients': _ingredients.text.trim().isEmpty ? null : _ingredients.text.trim(),
          'price': double.parse(_price.text),
          'discountPrice': _discountPrice.text.isEmpty ? null : double.parse(_discountPrice.text),
          'unit': _unit,
          'category': _category,
          'imageUrl': _imageUrl,
          'stock': int.tryParse(_stock.text.trim()) ?? 100,
          'isAvailable': _isAvailable,
        });
      } else {
        await ProductApi.instance.create(
          shopId: widget.shopId,
          name: _name.text.trim(),
          nameUz: _nameUz.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          ingredients: _ingredients.text.trim().isEmpty ? null : _ingredients.text.trim(),
          price: double.parse(_price.text),
          discountPrice: _discountPrice.text.isEmpty ? null : double.parse(_discountPrice.text),
          unit: _unit,
          category: _category,
          imageUrl: _imageUrl,
          stock: int.tryParse(_stock.text) ?? 100,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Xatolik: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_isEdit ? 'Tahrirlash' : 'Yangi mahsulot'),
        actions: [
          if (!_saving)
            TextButton(
              onPressed: _save,
              child: const Text('Saqlash', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          else
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Image
            GestureDetector(
              onTap: _uploading ? null : _pickImage,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: _uploading
                    ? const Center(child: CircularProgressIndicator())
                    : _imageUrl.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_a_photo_outlined, size: 40, color: AppColors.textHint),
                                SizedBox(height: 8),
                                Text('Rasm qo\'shish', style: TextStyle(color: AppColors.textHint)),
                              ],
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(_imageUrl, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined))),
                          ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Rasmni o'zgartirish uchun bosing",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
            const SizedBox(height: 16),

            _field(_name, 'Nomi (RU/EN)', validator: _required),
            const SizedBox(height: 12),
            _field(_nameUz, "Nomi (O'zbek)", validator: _required),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field(_price, 'Narx (so\'m)', kb: TextInputType.number, validator: _requiredNumber)),
                const SizedBox(width: 10),
                Expanded(child: _field(_discountPrice, 'Chegirma narx', kb: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: _decoration('Birlik'),
                    items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                    onChanged: (v) => setState(() => _unit = v ?? 'кг'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _field(_stock, 'Zaxira', kb: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: _decoration('Kategoriya'),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c['id'], child: Text(c['label']!)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'produce'),
            ),
            const SizedBox(height: 12),
            _field(_description, 'Tavsif', maxLines: 3),
            const SizedBox(height: 12),
            _field(_ingredients, 'Tarkibi / sostav', maxLines: 2),
            const SizedBox(height: 16),
            SwitchListTile(
              tileColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              title: const Text('Sotuvda'),
              subtitle: Text(
                _isAvailable ? 'Mahsulot katalogda ko\'rinadi' : 'Yashirilgan',
                style: const TextStyle(fontSize: 12),
              ),
              value: _isAvailable,
              activeThumbColor: kShopColor,
              onChanged: (v) => setState(() => _isAvailable = v),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    TextInputType? kb,
    int? maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: kb,
      maxLines: maxLines,
      decoration: _decoration(label),
      validator: validator,
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kShopColor, width: 2),
        ),
      );

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Majburiy' : null;
  String? _requiredNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Majburiy';
    final n = double.tryParse(v);
    if (n == null || n < 0) return 'Raqam';
    return null;
  }
}
