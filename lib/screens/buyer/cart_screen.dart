import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String _paymentMethod = 'click';
  bool _isPlacing = false;
  final _addressCtrl = TextEditingController(
    text: 'Toshkent, Yunusobod, 13-mavze, 28-uy',
  );
  final _commentCtrl = TextEditingController();

  static const _payments = [
    {'id': 'click',   'name': 'Click',     'emoji': '💳', 'hint': 'To\'lov kartasi'},
    {'id': 'payme',   'name': 'Payme',     'emoji': '💜', 'hint': '10M+ foydalanuvchi'},
    {'id': 'uzumpay', 'name': 'Uzum Pay',  'emoji': '🟪', 'hint': '0% komissiya'},
    {'id': 'cash',    'name': 'Naqd pul',  'emoji': '💵', 'hint': 'Yetkazib berishda'},
  ];

  String _fmt(double v) => '${v.toInt()
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  Future<void> _placeOrder() async {
    final cart = context.read<CartProvider>();
    final orders = context.read<OrderProvider>();
    if (cart.isEmpty) return;
    final shopId = cart.orderItems.first.product.shopId;
    setState(() => _isPlacing = true);
    HapticFeedback.mediumImpact();

    try {
      final order = await orders.placeOrder(
        shopId: shopId,
        items: cart.orderItems,
        itemsPayload: cart.toApiPayload(),
        deliveryAddress: _addressCtrl.text.trim(),
        customerComment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
        paymentMethod: _paymentMethod,
      );
      cart.clear();
      if (mounted) {
        setState(() => _isPlacing = false);
        context.go('/buyer/tracking/${order.id}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPlacing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Xatolik: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    if (cart.isEmpty) return _EmptyState(onShop: () => context.go('/buyer'));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Savat · ${cart.itemCount}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
                title: const Text("Savatni tozalash?"),
                content: const Text('Hammasi olib tashlanadi.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Yo'q")),
                  TextButton(
                    onPressed: () { cart.clear(); Navigator.pop(context); },
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Ha'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 220),
        children: [
          // Items card
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              children: [
                for (var i = 0; i < cart.lines.length; i++) ...[
                  _ItemRow(line: cart.lines[i]),
                  if (i < cart.lines.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Divider(height: 1),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          _SectionLabel('Yetkazib berish manzili'),
          const SizedBox(height: 8),
          _Card(
            child: Column(
              children: [
                _AddressField(
                  controller: _addressCtrl,
                  icon: Icons.location_on_rounded,
                  iconColor: AppColors.primary,
                  hint: "Ko'cha, uy, xonadon",
                  maxLines: 2,
                ),
                const Divider(height: 1, indent: 50),
                _AddressField(
                  controller: _commentCtrl,
                  icon: Icons.note_alt_outlined,
                  iconColor: AppColors.textHint,
                  hint: 'Kuryer uchun izoh',
                  maxLines: 1,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _SectionLabel("To'lov usuli"),
          const SizedBox(height: 8),
          _Card(
            child: Column(
              children: [
                for (var i = 0; i < _payments.length; i++) ...[
                  _PaymentRow(
                    name: _payments[i]['name']!,
                    emoji: _payments[i]['emoji']!,
                    hint: _payments[i]['hint']!,
                    selected: _paymentMethod == _payments[i]['id'],
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _paymentMethod = _payments[i]['id']!);
                    },
                  ),
                  if (i < _payments.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(left: 60),
                      child: Divider(height: 1),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          _SectionLabel('Hisob'),
          const SizedBox(height: 8),
          _Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _SumRow('Mahsulotlar (${cart.itemCount})', _fmt(cart.subtotal)),
                  const SizedBox(height: 10),
                  _SumRow(
                    'Yetkazib berish',
                    cart.deliveryFee == 0 ? 'Bepul' : _fmt(cart.deliveryFee),
                    accent: cart.deliveryFee == 0,
                    sub: cart.deliveryFee > 0 ? "100 000 so'mdan bepul" : null,
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: AppColors.borderLight),
                  const SizedBox(height: 14),
                  _SumRow('Jami', _fmt(cart.total), bold: true),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadii.md),
            boxShadow: AppShadows.button,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isPlacing ? null : _placeOrder,
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Row(
                  children: [
                    if (_isPlacing) ...[
                      const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        _isPlacing
                            ? 'Yuborilmoqda...'
                            : 'Buyurtma berish · ${_fmt(cart.total)}',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w800, letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    if (!_isPlacing)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onShop;
  const _EmptyState({required this.onShop});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Savat')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppRadii.xl),
              ),
              alignment: Alignment.center,
              child: const Text('🛒', style: TextStyle(fontSize: 48)),
            ),
            const SizedBox(height: 20),
            Text("Savat bo'sh", style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text(
              "Mahsulot qo'shing va biz tezda yetkazib beramiz",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 240,
              child: ElevatedButton.icon(
                onPressed: onShop,
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('Xarid qilishni boshlash'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ItemRow extends StatelessWidget {
  final CartLine line;
  const _ItemRow({required this.line});

  String _fmt(double v) => '${v.toInt()
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartProvider>();
    final modifierText = line.snapshot.isEmpty
        ? null
        : line.snapshot
            .expand((s) => s.options.map((o) => o.name))
            .join(' · ');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: SizedBox(
              width: 64, height: 64,
              child: line.product.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: line.product.imageUrl, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppColors.surfaceMuted),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surfaceMuted,
                        child: const Icon(Icons.image_outlined, color: AppColors.textHint),
                      ),
                    )
                  : Container(
                      color: AppColors.surfaceMuted,
                      child: const Icon(Icons.image_outlined, color: AppColors.textHint),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                if (modifierText != null) ...[
                  const SizedBox(height: 2),
                  Text(modifierText,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
                const SizedBox(height: 4),
                Text(_fmt(line.unitPrice),
                    style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
              ],
            ),
          ),
          // Counter
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CartStep(
                  icon: Icons.remove_rounded,
                  onTap: () => cart.removeLine(line.key),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('${line.quantity}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                _CartStep(
                  icon: Icons.add_rounded,
                  // Re-add with the same modifier set so quantity grows on
                  // the existing line rather than spawning a new one.
                  onTap: () {
                    if (line.modifiers.isEmpty) {
                      cart.add(line.product);
                    } else {
                      cart.addWithModifiers(
                        line.product,
                        1,
                        line.modifiers,
                        line.unitPrice,
                        snapshot: line.snapshot,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartStep extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CartStep({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: const CircleBorder(),
    child: InkWell(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      customBorder: const CircleBorder(),
      child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 16)),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(text,
        style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.4,
        )),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      boxShadow: AppShadows.card,
    ),
    child: child,
  );
}

class _AddressField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final Color iconColor;
  final String hint;
  final int maxLines;
  const _AddressField({
    required this.controller, required this.icon, required this.iconColor,
    required this.hint, required this.maxLines,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

class _PaymentRow extends StatelessWidget {
  final String name, emoji, hint;
  final bool selected;
  final VoidCallback onTap;
  const _PaymentRow({
    required this.name, required this.emoji, required this.hint,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(hint, style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SumRow extends StatelessWidget {
  final String label, value;
  final bool bold, accent;
  final String? sub;
  const _SumRow(this.label, this.value, {this.bold = false, this.accent = false, this.sub});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: bold ? 16 : 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                color: bold ? AppColors.textPrimary : AppColors.textSecondary,
              )),
          Text(value,
              style: TextStyle(
                fontSize: bold ? 18 : 14,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                color: accent ? AppColors.success : AppColors.textPrimary,
                letterSpacing: bold ? -0.3 : 0,
              )),
        ],
      ),
      if (sub != null) ...[
        const SizedBox(height: 2),
        Text(sub!, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
      ],
    ],
  );
}
