import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../models/catalog.dart';
import '../../models/money.dart';
import '../../models/payment_method.dart';
import '../../providers/cart_provider.dart';
import '../../providers/order_provider.dart';
import '../../services/api_client.dart';
import '../../services/dispatch_api.dart';
import '../../services/payment_method_api.dart';
import '../../services/promo_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/time_slot_picker.dart';
import 'address_book_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  /// Phase 6 — saved-method id; falls back to legacy [_paymentMethod] string
  /// when buyer chooses "new card / cash" without a saved entry.
  String _paymentMethod = 'click';
  PaymentMethod? _selectedSavedMethod;
  List<PaymentMethod> _savedMethods = const [];
  bool _savedMethodsLoaded = false;

  bool _isPlacing = false;
  final _commentCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();

  Timer? _estimateDebounce;
  bool _estimateLoading = false;
  String? _estimateError;
  String? _lastRequestedKey;
  bool _promoValidating = false;
  String? _promoError;
  bool _isScheduled = false;
  num _userLoyaltyPoints = 0;
  bool _loyaltyLoaded = false;

  // Coordinates come from the selected `cart.deliveryAddress`. When the
  // buyer hasn't picked one yet we surface a CTA at the top of the screen
  // and disable checkout instead of silently using a Tashkent fallback.
  double? get _lat => _cartListening?.deliveryAddress?.lat;
  double? get _lng => _cartListening?.deliveryAddress?.lng;
  String get _addressLine =>
      _cartListening?.deliveryAddress?.fullAddress ?? '';

  // Legacy provider catalogue — kept as a fallback for the order payload's
  // `paymentMethod` string when the buyer hasn't saved a card yet.
  // ignore: unused_field
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cartListening = context.read<CartProvider>();
      _cartListening!.addListener(_onInputsChanged);
      _promoCtrl.text = _cartListening!.couponCode ?? '';
      _isScheduled = _cartListening!.scheduledFor != null;
      _refreshEstimate(immediate: true);
      _loadLoyalty();
      _loadSavedMethods();
    });
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    _cartListening?.removeListener(_onInputsChanged);
    _commentCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedMethods() async {
    try {
      final list = await PaymentMethodApi.instance.list();
      if (!mounted) return;
      setState(() {
        _savedMethods = list;
        _savedMethodsLoaded = true;
        // Pre-select default if backend marked one — saves the buyer a tap.
        final defaults = list.where((m) => m.isDefault);
        _selectedSavedMethod =
            defaults.isNotEmpty ? defaults.first : (list.isNotEmpty ? list.first : null);
        if (_selectedSavedMethod != null) {
          _paymentMethod = _selectedSavedMethod!.provider;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _savedMethodsLoaded = true);
    }
  }

  Future<void> _pickAddress() async {
    final cart = context.read<CartProvider>();
    final picked = await Navigator.of(context).push<UserAddress>(
      MaterialPageRoute(
        builder: (_) => const AddressBookScreen(picker: true),
      ),
    );
    if (picked != null) {
      cart.setDeliveryAddress(picked);
    }
  }

  Future<void> _pickPaymentMethod() async {
    final picked = await showModalBottomSheet<PaymentMethod>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PaymentMethodSheet(
        methods: _savedMethods,
        selected: _selectedSavedMethod,
      ),
    );
    if (!mounted) return;
    if (picked == null) {
      // Sheet was dismissed without picking — leave selection alone.
      return;
    }
    if (picked.id == '__new__') {
      // Buyer asked to add a card — push the management screen and reload
      // when they come back.
      await context.push('/buyer/payment-methods');
      await _loadSavedMethods();
      return;
    }
    setState(() {
      _selectedSavedMethod = picked;
      _paymentMethod = picked.provider;
    });
  }

  Future<void> _loadLoyalty() async {
    try {
      final acc = await LoyaltyApi.instance.me();
      if (!mounted) return;
      setState(() {
        _userLoyaltyPoints = acc.points;
        _loyaltyLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loyaltyLoaded = true);
    }
  }

  void _onInputsChanged() {
    // Listener fires for every cart mutation including our own
    // `setEstimate(...)`. The fingerprint check inside `_refreshEstimate`
    // dedupes redundant work, so a no-op refetch is just a fast string
    // compare here.
    _refreshEstimate();
  }

  /// Debounced (500ms) call to `dispatchApi.estimate`. Caches the result on
  /// `CartProvider.lastEstimate` so navigating away and back doesn't refetch
  /// when the inputs haven't changed.
  void _refreshEstimate({bool immediate = false}) {
    _estimateDebounce?.cancel();
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) return;
    // Phase 6 — without a chosen address we can't build a meaningful
    // estimate, so just bail. The screen forces an address pick before
    // checkout becomes enabled.
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return;
    final shopId = cart.orderItems.first.product.shopId;
    final addrLine = _addressLine;
    final key = cart.estimateKey(
      shopId: shopId,
      addressKey: '$addrLine|$lat,$lng',
      promoCode: cart.couponCode,
      loyaltyPoints: cart.loyaltyPoints,
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
            'lat': lat,
            'lng': lng,
            'fullAddress': addrLine,
          },
          items: cart.toApiPayload(),
          couponCode: cart.couponCode,
          loyaltyPoints: cart.loyaltyPoints > 0 ? cart.loyaltyPoints : null,
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

  Future<void> _applyPromo() async {
    final cart = context.read<CartProvider>();
    if (cart.couponCode != null) {
      // Tap acts as cancel when a code is already applied.
      cart.setCouponCode(null);
      _promoCtrl.clear();
      setState(() => _promoError = null);
      return;
    }
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    if (cart.isEmpty) return;
    final shopId = cart.orderItems.first.product.shopId;
    final subtotal = cart.lastEstimate?.subtotal ?? cart.subtotal;
    setState(() {
      _promoValidating = true;
      _promoError = null;
    });
    try {
      final result = await PromoApi.instance.validate(
        code: code,
        shopId: shopId,
        subtotal: subtotal,
      );
      if (!mounted) return;
      if (result.valid) {
        cart.setCouponCode(code);
        setState(() => _promoError = null);
        HapticFeedback.lightImpact();
      } else {
        setState(() => _promoError = result.reason ?? 'Promo kod yaroqsiz');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _promoError = e.toString());
    } finally {
      if (mounted) setState(() => _promoValidating = false);
    }
  }

  Future<void> _openPromoList() async {
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) return;
    final shopId = cart.orderItems.first.product.shopId;
    final subtotal = cart.lastEstimate?.subtotal ?? cart.subtotal;
    final code = await context.push<String>(
      '/buyer/promo',
      extra: {'shopId': shopId, 'subtotal': subtotal},
    );
    if (!mounted || code == null || code.isEmpty) return;
    _promoCtrl.text = code;
    await _applyPromo();
  }

  String _fmtSlot(DateTime dt) {
    final today = DateTime.now();
    final isTomorrow = dt.day != today.day;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return isTomorrow ? 'Ertaga $hh:$mm' : 'Bugun $hh:$mm';
  }

  Future<void> _placeOrder() async {
    final cart = context.read<CartProvider>();
    final orders = context.read<OrderProvider>();
    if (cart.isEmpty) return;
    final addr = cart.deliveryAddress;
    if (addr == null) {
      // Defensive guard — UI hides the CTA but a stale frame could still
      // route here if the user clears the address mid-place.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(context, 'cart.no_address_warning')),
      ));
      return;
    }
    final shopId = cart.orderItems.first.product.shopId;
    setState(() => _isPlacing = true);
    HapticFeedback.mediumImpact();

    try {
      final order = await orders.placeOrder(
        shopId: shopId,
        items: cart.orderItems,
        itemsPayload: cart.toApiPayload(),
        deliveryAddress: addr.fullAddress,
        lat: addr.lat,
        lng: addr.lng,
        customerComment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
        paymentMethod: _paymentMethod,
        paymentMethodId: _selectedSavedMethod?.id,
        couponCode: cart.couponCode,
        loyaltyPoints: cart.loyaltyPoints > 0 ? cart.loyaltyPoints : null,
        scheduledFor: cart.scheduledFor,
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

  String _localeCode() => L10n.instance.locale.languageCode;
  String _money(double v) => Money(v).format(_localeCode());

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
          _SectionLabel(t(context, 'cart.address_tile_title')),
          const SizedBox(height: 8),
          _Card(
            child: Column(
              children: [
                _AddressTileButton(
                  address: cart.deliveryAddress,
                  onTap: _pickAddress,
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
          _SectionLabel(t(context, 'buyer.payment_method')),
          const SizedBox(height: 8),
          _Card(
            child: _PaymentMethodTile(
              loaded: _savedMethodsLoaded,
              method: _selectedSavedMethod,
              fallbackMethodId: _paymentMethod,
              onTap: _pickPaymentMethod,
            ),
          ),

          const SizedBox(height: 16),
          _SectionLabel(t(context, 'cart.promo_code')),
          const SizedBox(height: 8),
          _Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.local_offer_outlined,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _promoCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            hintText: t(context, 'cart.promo_hint'),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _promoValidating ? null : _applyPromo,
                        child: _promoValidating
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(cart.couponCode == null
                                ? t(context, 'promo.apply')
                                : t(context, 'common.cancel')),
                      ),
                      IconButton(
                        icon: const Icon(Icons.list_rounded,
                            color: AppColors.textSecondary),
                        tooltip: t(context, 'promo.title'),
                        onPressed: _openPromoList,
                      ),
                    ],
                  ),
                ),
                if (_promoError != null)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Text(_promoError!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12)),
                  )
                else if (cart.couponCode != null)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Text(
                      '${t(context, 'cart.promo_applied')}: ${cart.couponCode}',
                      style: const TextStyle(
                          color: AppColors.success, fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),

          if (_loyaltyLoaded && _userLoyaltyPoints > 0) ...[
            const SizedBox(height: 16),
            _SectionLabel(t(context, 'cart.loyalty_points')),
            const SizedBox(height: 8),
            _LoyaltyPointsCard(
              available: _userLoyaltyPoints.toInt(),
              currentSubtotal:
                  cart.lastEstimate?.subtotal ?? cart.subtotal,
              selected: cart.loyaltyPoints,
              onChanged: (v) {
                cart.setLoyaltyPoints(v);
              },
            ),
          ],

          const SizedBox(height: 16),
          _SectionLabel(t(context, 'cart.plan_delivery')),
          const SizedBox(height: 8),
          _Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PlanToggleButton(
                          label: t(context, 'cart.plan_asap'),
                          icon: Icons.flash_on_rounded,
                          selected: !_isScheduled,
                          onTap: () {
                            setState(() => _isScheduled = false);
                            cart.setScheduledFor(null);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PlanToggleButton(
                          label: t(context, 'cart.plan_schedule'),
                          icon: Icons.schedule_rounded,
                          selected: _isScheduled,
                          onTap: () =>
                              setState(() => _isScheduled = true),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isScheduled) ...[
                  const Divider(height: 16),
                  TimeSlotPicker(
                    selected: cart.scheduledFor,
                    onSelected: (when) {
                      cart.setScheduledFor(when);
                    },
                  ),
                  if (cart.scheduledFor != null)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(14, 4, 14, 12),
                      child: Text(
                        '${t(context, 'cart.scheduled_for')}: '
                        '${_fmtSlot(cart.scheduledFor!)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
            fmtMoney: _money,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Builder(builder: (_) {
          final est = cart.lastEstimate;
          final hasAddress = cart.deliveryAddress != null;
          final canCheckout = !_isPlacing &&
              hasAddress &&
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
                              : !hasAddress
                                  ? t(context, 'cart.no_address_warning')
                                  : 'Buyurtma berish · ${_money(total)}',
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
            if ((est?.couponDiscount ?? 0) > 0) ...[
              const SizedBox(height: 10),
              _SumRow('Promo',
                  '−${fmtMoney(est!.couponDiscount)}',
                  accent: true),
            ],
            if ((est?.loyaltyDiscount ?? 0) > 0) ...[
              const SizedBox(height: 10),
              _SumRow('Bonuslar',
                  '−${fmtMoney(est!.loyaltyDiscount)}',
                  accent: true),
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

/// Phase 3 — slider for spending loyalty points.
///
/// Cap at min(available points, floor(subtotal / 100)) so we never let the
/// buyer drop below 0 — backend re-validates anyway.
class _LoyaltyPointsCard extends StatelessWidget {
  final int available;
  final double currentSubtotal;
  final int selected;
  final ValueChanged<int> onChanged;

  const _LoyaltyPointsCard({
    required this.available,
    required this.currentSubtotal,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cap = (currentSubtotal / 100).floor();
    final maxPts = cap < available ? cap : available;
    final clamped = selected > maxPts ? maxPts : selected;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${t(context, 'cart.points_available')}: $available',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Text('-$clamped',
                  style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
            ],
          ),
          if (maxPts == 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t(context, 'cart.points_too_small'),
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 12),
              ),
            )
          else
            Slider(
              value: clamped.toDouble(),
              min: 0,
              max: maxPts.toDouble(),
              divisions: maxPts > 0 ? maxPts : 1,
              label: '$clamped',
              onChanged: (v) => onChanged(v.round()),
            ),
        ],
      ),
    );
  }
}

/// Tab-style toggle for ASAP vs Schedule planning.
class _PlanToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _PlanToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phase 6 — replaces the legacy free-text address input with a tile that
/// pushes the address book picker.
class _AddressTileButton extends StatelessWidget {
  final UserAddress? address;
  final VoidCallback onTap;
  const _AddressTileButton({required this.address, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.location_on_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: address == null
                  ? Text(
                      t(context, 'cart.address_choose'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(address!.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          address!.fullAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

/// Phase 6 — single-row tile that opens a sheet to choose between saved
/// payment methods (or "pay with new card" as a fallback).
class _PaymentMethodTile extends StatelessWidget {
  final bool loaded;
  final PaymentMethod? method;
  final String fallbackMethodId;
  final VoidCallback onTap;
  const _PaymentMethodTile({
    required this.loaded,
    required this.method,
    required this.fallbackMethodId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = method;
    final emoji = m?.brandEmoji ??
        (fallbackMethodId == 'cash'
            ? '💵'
            : fallbackMethodId == 'payme'
                ? '💜'
                : fallbackMethodId == 'uzumpay'
                    ? '🟪'
                    : '💳');
    final title = m?.displayLabel ??
        (fallbackMethodId == 'cash'
            ? 'Naqd pul'
            : t(context, 'payment.use_new_card'));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    !loaded
                        ? t(context, 'common.loading')
                        : (m?.providerName ?? t(context, 'buyer.payment_method')),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet listing saved payment methods + a "pay with new card"
/// fallback. Returns the chosen [PaymentMethod] (or a sentinel with
/// `id == '__new__'` when buyer wants to manage their cards).
class _PaymentMethodSheet extends StatelessWidget {
  final List<PaymentMethod> methods;
  final PaymentMethod? selected;
  const _PaymentMethodSheet({required this.methods, required this.selected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(t(context, 'buyer.payment_method'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final m in methods)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    side: BorderSide(
                      color: m.id == selected?.id
                          ? AppColors.primary
                          : AppColors.border,
                    ),
                  ),
                  leading: Text(m.brandEmoji,
                      style: const TextStyle(fontSize: 22)),
                  title: Text(m.displayLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(m.providerName),
                  trailing: m.id == selected?.id
                      ? const Icon(Icons.check_circle,
                          color: AppColors.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(m),
                ),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(
                const PaymentMethod(id: '__new__', provider: 'click'),
              ),
              icon: const Icon(Icons.add_card_rounded),
              label: Text(t(context, 'payment.use_new_card')),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
