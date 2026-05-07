import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../services/api_client.dart';
import '../../services/dispatch_api.dart';
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

  Timer? _estimateDebounce;
  bool _estimateLoading = false;
  String? _estimateError;
  String? _lastRequestedKey;

  // Stub coordinates — buyer flow Phase 1 chooses a saved address; if a
  // selected location is later piped through this screen, plug it in here.
  // Falls back to Tashkent centre so the estimate API still receives valid
  // floats.
  double get _lat => 41.2995;
  double get _lng => 69.2401;

  static const _payments = [
    {'id': 'click',   'name': 'Click',     'emoji': '💳', 'hint': 'To\'lov kartasi'},
    {'id': 'payme',   'name': 'Payme',     'emoji': '💜', 'hint': '10M+ foydalanuvchi'},
    {'id': 'uzumpay', 'name': 'Uzum Pay',  'emoji': '🟪', 'hint': '0% komissiya'},
    {'id': 'cash',    'name': 'Naqd pul',  'emoji': '💵', 'hint': 'Yetkazib berishda'},
  ];

  CartProvider? _cartListening;

  @override
  void initState() {
    super.initState();
    _addressCtrl.addListener(_onInputsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cartListening = context.read<CartProvider>();
      _cartListening!.addListener(_onInputsChanged);
      _refreshEstimate(immediate: true);
    });
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    _addressCtrl.removeListener(_onInputsChanged);
    _cartListening?.removeListener(_onInputsChanged);
    _addressCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _onInputsChanged() {
    // Listener fires for every cart mutation including our own
    // `setEstimate(...)`. The fingerprint check inside `_refreshEstimate`
    // dedupes redundant work, so a no-op refetch is just a fast string
    // compare here.
    _refreshEstimate();
  }

  String _fmt(double v) => '${v.toInt()
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  /// Debounced (500ms) call to `dispatchApi.estimate`. Caches the result on
  /// `CartProvider.lastEstimate` so navigating away and back doesn't refetch
  /// when the inputs haven't changed.
  void _refreshEstimate({bool immediate = false}) {
    _estimateDebounce?.cancel();
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) return;
    final shopId = cart.orderItems.first.product.shopId;
    final key = cart.estimateKey(
      shopId: shopId,
      addressKey: '${_addressCtrl.text.trim()}|$_lat,$_lng',
    );
    // Skip when the cached estimate matches and is fresh.
    if (cart.lastEstimateKey == key &&
        cart.lastEstimate != null &&
        DateTime.now().difference(cart.lastEstimate!.fetchedAt) <
            const Duration(seconds: 30) &&
        !immediate) {
      return;
    }
    Future<void> run() async {
      if (!mounted) return;
      setState(() {
        _estimateLoading = true;
        _estimateError = null;
        _lastRequestedKey = key;
      });
      try {
        final res = await DispatchApi.instance.estimate(
          shopId: shopId,
          address: {
            'lat': _lat,
            'lng': _lng,
            'fullAddress': _addressCtrl.text.trim(),
          },
          items: cart.toApiPayload(),
        );
        if (!mounted || _lastRequestedKey != key) return;
        final est = CartEstimate.fromJson(res);
        cart.setEstimate(est, key: key);
        setState(() => _estimateLoading = false);
      } on ApiException catch (e) {
        if (!mounted || _lastRequestedKey != key) return;
        // 400 + out_of_zone body → flag the cached estimate as out-of-zone.
        final msg = e.message.toLowerCase();
        if (e.statusCode == 400 && msg.contains('out_of_zone')) {
          final stub = CartEstimate(
            subtotal: cart.subtotal,
            deliveryFee: 0,
            total: cart.subtotal,
            minOrder: 0,
            minOrderMet: true,
            outOfZone: true,
            fetchedAt: DateTime.now(),
          );
          cart.setEstimate(stub, key: key);
          setState(() {
            _estimateLoading = false;
            _estimateError = null;
          });
        } else {
          setState(() {
            _estimateLoading = false;
            _estimateError = e.message;
          });
        }
      } catch (e) {
        if (!mounted || _lastRequestedKey != key) return;
        setState(() {
          _estimateLoading = false;
          _estimateError = e.toString();
        });
      }
    }

    if (immediate) {
      run();
    } else {
      _estimateDebounce =
          Timer(const Duration(milliseconds: 500), run);
    }
  }

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
          _PricingBreakdown(
            cart: cart,
            estimate: cart.lastEstimate,
            isLoading: _estimateLoading,
            error: _estimateError,
            fmtMoney: _fmt,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Builder(builder: (_) {
          final est = cart.lastEstimate;
          final canCheckout = !_isPlacing &&
              !(est?.outOfZone ?? false) &&
              (est?.minOrderMet ?? true);
          final total = est?.total ?? cart.total;
          return Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            decoration: BoxDecoration(
              color: canCheckout ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(AppRadii.md),
              boxShadow: canCheckout ? AppShadows.button : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: canCheckout ? _placeOrder : null,
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Row(
                    children: [
                      if (_isPlacing) ...[
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          _isPlacing
                              ? 'Yuborilmoqda...'
                              : 'Buyurtma berish · ${_fmt(total)}',
                          style: TextStyle(
                            color: canCheckout
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      if (!_isPlacing && canCheckout)
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius:
                                BorderRadius.circular(AppRadii.pill),
                          ),
                          child: const Icon(Icons.arrow_forward_rounded,
                              color: Colors.white, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
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

/// Pricing breakdown — wraps subtotal/delivery/total/ETA/distance plus the
/// out-of-zone & min-order banners. Driven by the latest `CartEstimate`
/// cached on `CartProvider`.
class _PricingBreakdown extends StatelessWidget {
  final CartProvider cart;
  final CartEstimate? estimate;
  final bool isLoading;
  final String? error;
  final String Function(double) fmtMoney;

  const _PricingBreakdown({
    required this.cart,
    required this.estimate,
    required this.isLoading,
    required this.error,
    required this.fmtMoney,
  });

  @override
  Widget build(BuildContext context) {
    final est = estimate;

    final subtotal = est?.subtotal ?? cart.subtotal;
    final deliveryFee = est?.deliveryFee ?? cart.deliveryFee;
    final total = est?.total ?? cart.total;

    final children = <Widget>[];

    if (est?.outOfZone == true) {
      children.add(_Banner(
        emoji: '⚠️',
        bg: AppColors.errorLight,
        fg: AppColors.error,
        title: "Adresga yetkazib bo'lmaydi",
        subtitle: 'Доставка не доступна',
      ));
    }

    if (est != null && !est.minOrderMet) {
      final missing = est.minOrder - est.subtotal;
      children.add(_Banner(
        emoji: '🛒',
        bg: AppColors.warningLight,
        fg: AppColors.warning,
        title:
            "Yana ${fmtMoney(missing < 0 ? 0 : missing)} qo'shing",
        subtitle: "Minimal buyurtma ${fmtMoney(est.minOrder)}",
      ));
    }

    children.add(_Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: _SumRow('Mahsulotlar (${cart.itemCount})',
                        fmtMoney(subtotal))),
                if (isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SumRow(
                    'Yetkazib berish',
                    deliveryFee == 0 ? 'Bepul' : fmtMoney(deliveryFee),
                    accent: deliveryFee == 0,
                    sub: est?.surgeReason,
                  ),
                ),
                if ((est?.surgeFactor ?? 1.0) > 1.0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(
                        '×${est!.surgeFactor.toStringAsFixed(1)} surge',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            if (est?.etaMinutes != null || est?.distanceKm != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (est?.etaMinutes != null) ...[
                    const Icon(Icons.timer_outlined,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text('Доставка через ~${est!.etaMinutes} мин',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                  if (est?.distanceKm != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.place_outlined,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text('${est!.distanceKm!.toStringAsFixed(1)} км',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.borderLight),
            const SizedBox(height: 14),
            _SumRow('Jami', fmtMoney(total), bold: true),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String emoji, title, subtitle;
  final Color bg, fg;
  const _Banner({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: fg.withValues(alpha: 0.4))),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
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
