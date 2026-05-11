import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../models/catalog.dart';
import '../services/address_api.dart';
import '../services/cart_draft_api.dart';

/// Selected modifier set for a single cart line.
class CartModifierSelection {
  final String groupId;
  final List<String> optionIds;
  const CartModifierSelection({required this.groupId, required this.optionIds});

  Map<String, dynamic> toApiJson() => {
    'groupId': groupId,
    'optionIds': List<String>.from(optionIds),
  };
}

/// One line in the cart. The `key` deduplicates lines so the same product with
/// different modifier sets becomes a separate line.
class CartLine {
  final String key;
  final Product product;
  int quantity;
  final double unitPrice;
  final List<CartModifierSelection> modifiers;
  final List<ModifierSnapshot> snapshot;

  CartLine({
    required this.key,
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.modifiers = const [],
    this.snapshot = const [],
  });

  double get lineTotal => unitPrice * quantity;
}

/// Cached pricing breakdown returned by `POST /api/orders/estimate`. Stored
/// on the cart provider so navigating away and back to the cart screen does
/// not immediately re-fetch.
class CartEstimate {
  final double subtotal;
  final double deliveryFee;
  final double total;
  final double minOrder;
  final bool minOrderMet;
  final double? distanceKm;
  final int? etaMinutes;
  final double surgeFactor;
  final String? surgeReason;
  final String? zoneId;
  final bool outOfZone;
  // Phase 3 — coupon + loyalty deductions surfaced separately so the cart
  // breakdown can render them as individual rows.
  final double couponDiscount;
  final double loyaltyDiscount;
  final DateTime fetchedAt;

  const CartEstimate({
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.minOrder,
    required this.minOrderMet,
    this.distanceKm,
    this.etaMinutes,
    this.surgeFactor = 1.0,
    this.surgeReason,
    this.zoneId,
    this.outOfZone = false,
    this.couponDiscount = 0,
    this.loyaltyDiscount = 0,
    required this.fetchedAt,
  });

  factory CartEstimate.fromJson(Map<String, dynamic> j) => CartEstimate(
    subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0,
    deliveryFee: (j['deliveryFee'] as num?)?.toDouble() ?? 0,
    total: (j['total'] as num?)?.toDouble() ?? 0,
    minOrder: (j['minOrder'] as num?)?.toDouble() ?? 0,
    minOrderMet: j['minOrderMet'] as bool? ?? true,
    distanceKm: (j['distanceKm'] as num?)?.toDouble(),
    etaMinutes: (j['etaMinutes'] as num?)?.toInt(),
    surgeFactor: (j['surgeFactor'] as num?)?.toDouble() ?? 1.0,
    surgeReason: j['surgeReason'] as String?,
    zoneId: j['zoneId'] as String?,
    outOfZone: j['outOfZone'] as bool? ?? false,
    couponDiscount: (j['couponDiscount'] as num?)?.toDouble() ??
        (j['discount'] as num?)?.toDouble() ?? 0,
    loyaltyDiscount: (j['loyaltyDiscount'] as num?)?.toDouble() ?? 0,
    fetchedAt: DateTime.now(),
  );

  CartEstimate copyWith({bool? outOfZone}) => CartEstimate(
    subtotal: subtotal,
    deliveryFee: deliveryFee,
    total: total,
    minOrder: minOrder,
    minOrderMet: minOrderMet,
    distanceKm: distanceKm,
    etaMinutes: etaMinutes,
    surgeFactor: surgeFactor,
    surgeReason: surgeReason,
    zoneId: zoneId,
    outOfZone: outOfZone ?? this.outOfZone,
    couponDiscount: couponDiscount,
    loyaltyDiscount: loyaltyDiscount,
    fetchedAt: fetchedAt,
  );
}

/// Per-shop metadata kept alongside the in-memory draft. Filled either from
/// the listMine() summary on boot, or from the first product the buyer adds.
class _ShopMeta {
  String name;
  String? logoUrl;
  String vertical;
  String currency;
  String? couponCode;
  int loyaltyPoints;
  DateTime? scheduledFor;

  _ShopMeta({
    required this.name,
    required this.vertical,
    required this.currency,
    this.logoUrl,
    this.couponCode,
    this.loyaltyPoints = 0,
    this.scheduledFor,
  });
}

class CartProvider extends ChangeNotifier {
  /// [autoLoad] controls whether the constructor kicks off the
  /// SharedPreferences address restore and the backend draft hydrate.
  /// Tests pass `false` so unit tests can run without mocking the API.
  CartProvider({CartDraftApi? api, bool autoLoad = true})
      : _draftApi = api ?? CartDraftApi.instance {
    if (autoLoad) {
      // Restore the last-used address asynchronously — UI starts up
      // immediately with `null` and refreshes once SharedPreferences resolves.
      _restoreDeliveryAddress();
      // Phase 11 — hydrate drafts in the background. The summary endpoint
      // returns metadata only; we lazily load full payloads when the user
      // actually opens a draft to keep boot fast.
      _hydrateDrafts();
    }
  }

  static const _kPrefAddressId = 'cart.lastAddressId';
  static const _syncDebounce = Duration(milliseconds: 600);

  final CartDraftApi _draftApi;

  /// Lines keyed by `productId|sortedOptionIds` per shopId.
  final Map<String, Map<String, CartLine>> _draftsByShop = {};
  final Map<String, _ShopMeta> _shopMeta = {};
  // Per-shop debounce timer so rapid mutations don't spam the upsert endpoint.
  final Map<String, Timer> _syncTimers = {};
  // Per-shop in-flight tracker. Without this an older upsert()/dropShop() can
  // finish AFTER a newer one and silently revert the latest cart state. We
  // await the previous future before kicking off the next.
  final Map<String, Future<void>> _ongoingSyncs = {};

  /// The shop the cart screen is currently viewing. Mutations route through
  /// this id; `null` when every draft is empty.
  String? _activeShopId;
  String? get activeShopId => _activeShopId;

  CartEstimate? _lastEstimate;
  String? _lastEstimateKey;

  // ── Phase 6 — selected delivery address (saved from address book) ─────────
  UserAddress? _deliveryAddress;
  UserAddress? get deliveryAddress => _deliveryAddress;

  void setDeliveryAddress(UserAddress? address) {
    _deliveryAddress = address;
    // Persist `lastAddressId` so a fresh launch can preselect the same one.
    // Fire-and-forget: SharedPreferences errors are non-fatal here.
    SharedPreferences.getInstance().then((p) {
      if (address?.id != null && address!.id.isNotEmpty) {
        p.setString(_kPrefAddressId, address.id);
      } else {
        p.remove(_kPrefAddressId);
      }
    }).catchError((_) {});
    notifyListeners();
  }

  Future<void> _restoreDeliveryAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kPrefAddressId);
      if (id == null || id.isEmpty) return;
      final list = await AddressApi.instance.list();
      final match = list.where((a) => a.id == id);
      if (match.isNotEmpty) {
        _deliveryAddress = match.first;
        notifyListeners();
      }
    } catch (_) {
      // Silent — address restore is best-effort and shouldn't break the cart.
    }
  }

  /// Phase 11 — pull every persisted draft. We only hydrate the metadata; the
  /// full payload is fetched lazily when the user opens a draft so we don't
  /// download all items up front.
  Future<void> _hydrateDrafts() async {
    try {
      final summaries = await _draftApi.listMine();
      if (summaries.isEmpty) return;
      for (final s in summaries) {
        _shopMeta[s.shopId] = _ShopMeta(
          name: s.shopName,
          vertical: s.shopVertical,
          currency: s.shopCurrency,
          logoUrl: s.shopLogoUrl,
          couponCode: s.couponCode,
          loyaltyPoints: s.loyaltyPoints,
          scheduledFor: s.scheduledFor,
        );
        // Seed an empty map so `drafts` getter surfaces the shop in the
        // switcher even before the payload arrives. We'll fill items in
        // `loadDraftPayload` when the buyer taps the chip.
        _draftsByShop.putIfAbsent(s.shopId, () => {});
      }
      // Auto-select the most recently updated draft so reopening the cart
      // screen lands the user on something useful.
      summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _activeShopId ??= summaries.first.shopId;
      notifyListeners();
      // Fetch full payloads for each draft so the switcher chips show item
      // counts + subtotals. We do this sequentially after the initial notify
      // so the first frame paints with whatever metadata we have.
      for (final s in summaries) {
        await loadDraftPayload(s.shopId);
      }
    } catch (_) {
      // Silent — network errors shouldn't block the app start.
    }
  }

  /// Phase 11 — pull the full payload for [shopId] and rehydrate its draft.
  /// Idempotent; calling repeatedly just refreshes from the server.
  Future<void> loadDraftPayload(String shopId) async {
    try {
      final detail = await _draftApi.getForShop(shopId);
      if (detail == null) return;
      final lines = <String, CartLine>{};
      for (final raw in detail.payload) {
        if (raw is! Map) continue;
        final productId = raw['productId'] as String?;
        final qty = (raw['quantity'] as num?)?.toInt() ?? 0;
        if (productId == null || qty <= 0) continue;
        // The summary doesn't carry the full Product object, so we synthesise
        // a minimal stub. The cart screen renders fine from this; full
        // catalog data is fetched again on checkout via the order POST.
        final productJson = raw['product'] as Map?;
        final stub = Product(
          id: productId,
          name: (productJson?['name'] as String?) ?? productId,
          nameUz: (productJson?['nameUz'] as String?) ??
              (productJson?['name'] as String?) ?? productId,
          price: (productJson?['price'] as num?)?.toDouble() ??
              (raw['unitPrice'] as num?)?.toDouble() ?? 0,
          unit: (productJson?['unit'] as String?) ?? '',
          category: (productJson?['category'] as String?) ?? '',
          imageUrl: (productJson?['imageUrl'] as String?) ?? '',
          shopId: shopId,
        );
        final mods = <CartModifierSelection>[];
        final rawMods = raw['modifiers'] as List? ?? const [];
        for (final m in rawMods) {
          if (m is! Map) continue;
          mods.add(CartModifierSelection(
            groupId: m['groupId'] as String? ?? '',
            optionIds:
                (m['optionIds'] as List? ?? const []).whereType<String>().toList(),
          ));
        }
        final key = _keyFor(productId, mods);
        lines[key] = CartLine(
          key: key,
          product: stub,
          quantity: qty,
          unitPrice: (raw['unitPrice'] as num?)?.toDouble() ?? stub.effectivePrice,
          modifiers: List.unmodifiable(mods),
        );
      }
      _draftsByShop[shopId] = lines;
      _shopMeta[shopId] = _ShopMeta(
        name: detail.shopName,
        vertical: detail.shopVertical,
        currency: detail.shopCurrency,
        logoUrl: detail.shopLogoUrl,
        couponCode: detail.couponCode,
        loyaltyPoints: detail.loyaltyPoints,
        scheduledFor: detail.scheduledFor,
      );
      notifyListeners();
    } catch (_) {
      // Silent — failing to hydrate doesn't break the local cart.
    }
  }

  // ─── Active-shop accessors (back-compat for existing UI) ──────────────────

  Map<String, CartLine> get _activeLines {
    final id = _activeShopId;
    if (id == null) return const <String, CartLine>{};
    return _draftsByShop[id] ?? const <String, CartLine>{};
  }

  _ShopMeta? get _activeMeta =>
      _activeShopId == null ? null : _shopMeta[_activeShopId];

  String? get couponCode => _activeMeta?.couponCode;
  int get loyaltyPoints => _activeMeta?.loyaltyPoints ?? 0;
  DateTime? get scheduledFor => _activeMeta?.scheduledFor;

  void setCouponCode(String? code) {
    final id = _activeShopId;
    if (id == null) return;
    final meta = _shopMeta[id];
    if (meta == null) return;
    meta.couponCode = (code == null || code.isEmpty) ? null : code;
    _scheduleSync(id);
    notifyListeners();
  }

  void setLoyaltyPoints(int points) {
    final id = _activeShopId;
    if (id == null) return;
    final meta = _shopMeta[id];
    if (meta == null) return;
    meta.loyaltyPoints = points < 0 ? 0 : points;
    _scheduleSync(id);
    notifyListeners();
  }

  void setScheduledFor(DateTime? when) {
    final id = _activeShopId;
    if (id == null) return;
    final meta = _shopMeta[id];
    if (meta == null) return;
    meta.scheduledFor = when;
    _scheduleSync(id);
    notifyListeners();
  }

  CartEstimate? get lastEstimate => _lastEstimate;

  /// Build a fingerprint that changes whenever the estimate inputs change so
  /// the cart screen can decide to skip a refetch. `promoCode` defaults to
  /// the cart's persisted coupon and `loyaltyPoints` to the slider value so
  /// callers don't have to thread state through manually.
  String estimateKey({
    required String shopId,
    required String? addressKey,
    String? promoCode,
    int? loyaltyPoints,
  }) {
    final lines = _draftsByShop[shopId]?.values ?? const <CartLine>[];
    // Fingerprint must cover modifier identity + price, not just product+qty,
    // so a modifier change or shop-side price update busts the cache.
    final items = lines
        .map((l) => '${l.key}:${l.quantity}:${l.unitPrice}')
        .toList()
      ..sort();
    final meta = _shopMeta[shopId];
    final pc = promoCode ?? meta?.couponCode ?? '';
    final lp = loyaltyPoints ?? meta?.loyaltyPoints ?? 0;
    return '$shopId|${addressKey ?? ''}|${items.join(',')}|$pc|$lp';
  }

  void setEstimate(CartEstimate? est, {String? key}) {
    _lastEstimate = est;
    _lastEstimateKey = key;
    notifyListeners();
  }

  String? get lastEstimateKey => _lastEstimateKey;

  // ─── Multi-shop API ───────────────────────────────────────────────────────

  /// All non-empty drafts as summaries, sorted by most-recently mutated.
  List<CartDraftSummary> get drafts {
    final out = <CartDraftSummary>[];
    for (final entry in _draftsByShop.entries) {
      final lines = entry.value;
      if (lines.isEmpty) continue;
      final meta = _shopMeta[entry.key];
      final qty = lines.values.fold<int>(0, (a, l) => a + l.quantity);
      final sub =
          lines.values.fold<double>(0, (a, l) => a + l.lineTotal);
      out.add(CartDraftSummary(
        shopId: entry.key,
        shopName: meta?.name ?? '',
        shopVertical: meta?.vertical ?? 'other',
        shopCurrency: meta?.currency ?? 'UZS',
        shopLogoUrl: meta?.logoUrl,
        itemCount: qty,
        subtotal: sub,
        couponCode: meta?.couponCode,
        loyaltyPoints: meta?.loyaltyPoints ?? 0,
        scheduledFor: meta?.scheduledFor,
        updatedAt: DateTime.now(),
        staleItems: 0,
      ));
    }
    return out;
  }

  /// Switch the active shop. Called by the cart-screen switcher chips. The
  /// caller will see `lines`/`subtotal`/etc. point at the new draft after
  /// notify fires.
  void switchShop(String shopId) {
    if (_activeShopId == shopId) return;
    _activeShopId = shopId;
    // Reset the cached estimate — it was for the previous shop.
    _lastEstimate = null;
    _lastEstimateKey = null;
    notifyListeners();
    // Best-effort: ensure full payload is in memory.
    if (_draftsByShop[shopId]?.isEmpty ?? true) {
      unawaited(loadDraftPayload(shopId));
    }
  }

  // ─── Read API (active shop) ───────────────────────────────────────────────

  List<CartLine> get lines => List.unmodifiable(_activeLines.values);

  bool get isEmpty => _activeLines.isEmpty;

  int get itemCount =>
      _activeLines.values.fold(0, (a, l) => a + l.quantity);

  /// Backwards-compat: legacy callers want `Map<productId, qty>`. We sum
  /// quantities across modifier variants of the same product.
  Map<String, int> get items {
    final result = <String, int>{};
    for (final l in _activeLines.values) {
      result.update(l.product.id, (v) => v + l.quantity,
          ifAbsent: () => l.quantity);
    }
    return Map.unmodifiable(result);
  }

  double get subtotal =>
      _activeLines.values.fold(0.0, (sum, l) => sum + l.lineTotal);

  double get deliveryFee {
    if (subtotal >= 100000) return 0;
    return 12000;
  }

  double get total => subtotal + deliveryFee;

  /// Materialise lines into the legacy `OrderItem` shape used by existing UI
  /// (cart screen, order provider).
  List<OrderItem> get orderItems => _activeLines.values
      .map((l) => OrderItem(product: l.product, quantity: l.quantity))
      .toList();

  /// Total quantity across all variants of this product (active shop only).
  int quantityOf(String productId) => _activeLines.values
      .where((l) => l.product.id == productId)
      .fold(0, (a, l) => a + l.quantity);

  /// Backend payload — what `POST /api/orders` expects under `items`. Active
  /// shop only.
  List<Map<String, dynamic>> toApiPayload() => _activeLines.values.map((l) => {
    'productId': l.product.id,
    'quantity': l.quantity,
    'unitPrice': l.unitPrice,
    if (l.modifiers.isNotEmpty)
      'modifiers': l.modifiers.map((m) => m.toApiJson()).toList(),
  }).toList();

  /// Serialise a specific shop's draft (used by the sync layer).
  List<Map<String, dynamic>> _payloadFor(String shopId) {
    final lines = _draftsByShop[shopId]?.values ?? const <CartLine>[];
    return lines.map((l) => {
      'productId': l.product.id,
      'quantity': l.quantity,
      'unitPrice': l.unitPrice,
      'product': {
        'id': l.product.id,
        'name': l.product.name,
        'nameUz': l.product.nameUz,
        'price': l.product.price,
        'unit': l.product.unit,
        'category': l.product.category,
        'imageUrl': l.product.imageUrl,
      },
      if (l.modifiers.isNotEmpty)
        'modifiers': l.modifiers.map((m) => m.toApiJson()).toList(),
    }).toList();
  }

  // ─── Mutations ───────────────────────────────────────────────────────────

  static String _keyFor(String productId, List<CartModifierSelection> mods) {
    if (mods.isEmpty) return productId;
    final allOpts = <String>[];
    for (final m in mods) {
      allOpts.addAll(m.optionIds);
    }
    allOpts.sort();
    return '$productId|${allOpts.join('|')}';
  }

  void _ensureShopBucket(Product product) {
    _draftsByShop.putIfAbsent(product.shopId, () => {});
    _shopMeta.putIfAbsent(
      product.shopId,
      () => _ShopMeta(
        name: '',
        vertical: 'other',
        currency: 'UZS',
      ),
    );
  }

  /// Phase 11 — supply shop metadata once we have it (the catalog screen
  /// passes a [Shop] through here so the cart switcher chip can show the real
  /// name + logo even before backend hydration).
  void rememberShop({
    required String shopId,
    String? name,
    String? logoUrl,
    String? vertical,
    String? currency,
  }) {
    final meta = _shopMeta.putIfAbsent(
      shopId,
      () => _ShopMeta(
        name: name ?? '',
        vertical: vertical ?? 'other',
        currency: currency ?? 'UZS',
      ),
    );
    if (name != null && name.isNotEmpty) meta.name = name;
    if (logoUrl != null) meta.logoUrl = logoUrl;
    if (vertical != null) meta.vertical = vertical;
    if (currency != null) meta.currency = currency;
  }

  /// Legacy add (no modifiers). Returns true — multi-shop drafts mean shop
  /// conflicts are no longer possible; the old false-on-conflict contract is
  /// preserved for callers but now always succeeds.
  bool add(Product product) {
    _ensureShopBucket(product);
    _activeShopId = product.shopId;
    final shopLines = _draftsByShop[product.shopId]!;
    final key = _keyFor(product.id, const []);
    final existing = shopLines[key];
    if (existing != null) {
      existing.quantity += 1;
    } else {
      shopLines[key] = CartLine(
        key: key,
        product: product,
        quantity: 1,
        unitPrice: product.effectivePrice,
      );
    }
    _scheduleSync(product.shopId);
    notifyListeners();
    return true;
  }

  /// Add a product with a specific modifier selection. Same product with
  /// different modifiers occupies a separate line. Always returns true under
  /// the Phase 11 multi-shop contract — kept bool-returning for back-compat.
  bool addWithModifiers(
    Product product,
    int qty,
    List<CartModifierSelection> modifiers,
    double unitPrice, {
    List<ModifierSnapshot> snapshot = const [],
  }) {
    if (qty <= 0) return false;
    _ensureShopBucket(product);
    _activeShopId = product.shopId;
    final shopLines = _draftsByShop[product.shopId]!;
    final key = _keyFor(product.id, modifiers);
    final existing = shopLines[key];
    if (existing != null) {
      existing.quantity += qty;
    } else {
      shopLines[key] = CartLine(
        key: key,
        product: product,
        quantity: qty,
        unitPrice: unitPrice,
        modifiers: List.unmodifiable(modifiers),
        snapshot: List.unmodifiable(snapshot),
      );
    }
    _scheduleSync(product.shopId);
    notifyListeners();
    return true;
  }

  /// Decrement by one. For lines without modifiers we look up by productId so
  /// the existing UI keeps working. Active shop only.
  void remove(String productId) {
    final id = _activeShopId;
    if (id == null) return;
    final shopLines = _draftsByShop[id];
    if (shopLines == null) return;
    CartLine? target;
    final noModKey = _keyFor(productId, const []);
    if (shopLines.containsKey(noModKey)) {
      target = shopLines[noModKey];
    } else {
      for (final l in shopLines.values) {
        if (l.product.id == productId) { target = l; break; }
      }
    }
    if (target == null) return;
    if (target.quantity > 1) {
      target.quantity -= 1;
    } else {
      shopLines.remove(target.key);
    }
    _scheduleSync(id);
    _maybeReassignActive();
    notifyListeners();
  }

  /// Decrement a specific cart line (used when modifier variants exist).
  void removeLine(String key) {
    final id = _activeShopId;
    if (id == null) return;
    final shopLines = _draftsByShop[id];
    if (shopLines == null) return;
    final line = shopLines[key];
    if (line == null) return;
    if (line.quantity > 1) {
      line.quantity -= 1;
    } else {
      shopLines.remove(key);
    }
    _scheduleSync(id);
    _maybeReassignActive();
    notifyListeners();
  }

  /// Drop just the active shop's draft. Used by the cart screen's "delete"
  /// icon and by the order-placed flow.
  void clearForNewShop() {
    final id = _activeShopId;
    if (id == null) return;
    _draftsByShop.remove(id);
    _shopMeta.remove(id);
    _syncTimers.remove(id)?.cancel();
    _activeShopId = null;
    _lastEstimate = null;
    _lastEstimateKey = null;
    // Best-effort: tell the backend to forget this shop's draft. The order
    // POST also clears it server-side, so a 404 here is fine.
    unawaited(_draftApi.dropShop(id));
    _maybeReassignActive();
    notifyListeners();
  }

  /// Phase 11 — drop EVERY draft (used by logout / "clear all carts").
  void clearAll() {
    _draftsByShop.clear();
    _shopMeta.clear();
    for (final t in _syncTimers.values) {
      t.cancel();
    }
    _syncTimers.clear();
    _activeShopId = null;
    _lastEstimate = null;
    _lastEstimateKey = null;
    unawaited(_draftApi.dropAll());
    notifyListeners();
  }

  void clear() => clearForNewShop();

  /// Phase 7.3 — populate the cart from a `POST /api/orders/:id/reorder`
  /// CartDraft payload.
  ///
  /// Wipes the matching shop's draft (NOT every cart) and pushes everything
  /// from `draft.items`, skipping anything flagged `unavailable: true` or
  /// with `availableQty < 1`. Returns the list of skipped product names so
  /// the caller can render a snackbar; an empty list means everything was
  /// added cleanly.
  List<String> replaceFromDraft(CartDraft draft) {
    _draftsByShop[draft.shopId] = {};
    _shopMeta.putIfAbsent(
      draft.shopId,
      () => _ShopMeta(name: '', vertical: 'other', currency: 'UZS'),
    );
    _activeShopId = draft.shopId;
    _lastEstimate = null;
    _lastEstimateKey = null;

    final shopLines = _draftsByShop[draft.shopId]!;
    final skipped = <String>[];
    for (final item in draft.items) {
      if (item.unavailable) {
        skipped.add(item.product.name);
        continue;
      }
      final qty = item.availableQty ?? item.quantity;
      if (qty < 1) {
        skipped.add(item.product.name);
        continue;
      }
      final key = _keyFor(item.product.id, const []);
      shopLines[key] = CartLine(
        key: key,
        product: item.product,
        quantity: qty,
        unitPrice: item.unitPrice,
      );
    }
    _scheduleSync(draft.shopId);
    notifyListeners();
    return skipped;
  }

  // ─── Sync layer ──────────────────────────────────────────────────────────

  void _scheduleSync(String shopId) {
    _syncTimers[shopId]?.cancel();
    _syncTimers[shopId] = Timer(_syncDebounce, () => _flushSync(shopId));
  }

  Future<void> _flushSync(String shopId) async {
    // Serialize per-shop API calls so an older upsert/dropShop can't finish
    // after a newer mutation and overwrite the latest state.
    final prev = _ongoingSyncs[shopId];
    if (prev != null) {
      try { await prev; } catch (_) { /* swallowed — was already best-effort */ }
    }
    final fut = _doFlushSync(shopId);
    _ongoingSyncs[shopId] = fut;
    try {
      await fut;
    } finally {
      // Only clear if this future is still the active one (a newer scheduled
      // run may have replaced us by then).
      if (identical(_ongoingSyncs[shopId], fut)) {
        _ongoingSyncs.remove(shopId);
      }
    }
  }

  Future<void> _doFlushSync(String shopId) async {
    final lines = _draftsByShop[shopId];
    final meta = _shopMeta[shopId];
    try {
      if (lines == null || lines.isEmpty) {
        // Empty shop: drop it server-side and clean up the meta so the
        // switcher no longer surfaces it.
        await _draftApi.dropShop(shopId);
        return;
      }
      await _draftApi.upsert(
        shopId,
        payload: _payloadFor(shopId),
        couponCode: meta?.couponCode,
        loyaltyPoints: meta?.loyaltyPoints,
        scheduledFor: meta?.scheduledFor,
      );
    } catch (e) {
      // Silent — sync is best-effort; the local cart stays authoritative
      // until the next mutation re-triggers a sync.
      if (kDebugMode) debugPrint('CartDraft sync failed for $shopId: $e');
    }
  }

  void _maybeReassignActive() {
    if (_activeShopId != null) {
      final lines = _draftsByShop[_activeShopId];
      if (lines == null || lines.isEmpty) {
        _draftsByShop.remove(_activeShopId);
        _shopMeta.remove(_activeShopId);
        _activeShopId = null;
      } else {
        return;
      }
    }
    // Pick the next non-empty draft so the cart screen has something to show.
    for (final e in _draftsByShop.entries) {
      if (e.value.isNotEmpty) {
        _activeShopId = e.key;
        return;
      }
    }
  }

  @override
  void dispose() {
    for (final t in _syncTimers.values) {
      t.cancel();
    }
    _syncTimers.clear();
    super.dispose();
  }
}

/// Phase 7.3 — payload shape returned by `POST /api/orders/:id/reorder`.
///
/// Each `CartDraftItem` mirrors a previous order line; `unavailable` marks
/// items that can't be re-added (e.g. discontinued, out of zone) so the cart
/// can skip them and inform the buyer.
class CartDraft {
  final String shopId;
  final List<CartDraftItem> items;
  const CartDraft({required this.shopId, required this.items});

  factory CartDraft.fromJson(Map<String, dynamic> j) {
    final shopId = j['shopId'] as String? ?? '';
    final raw = j['items'] as List? ?? const [];
    return CartDraft(
      shopId: shopId,
      items: raw
          .map((i) =>
              CartDraftItem.fromJson(Map<String, dynamic>.from(i as Map), shopId))
          .toList(),
    );
  }
}

class CartDraftItem {
  final Product product;
  final int quantity;
  final double unitPrice;
  final bool unavailable;
  final int? availableQty;
  const CartDraftItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.unavailable = false,
    this.availableQty,
  });

  factory CartDraftItem.fromJson(Map<String, dynamic> j, String fallbackShopId) {
    final p = j['product'] as Map?;
    final productId =
        (p?['id'] ?? j['productId']) as String? ?? '';
    final productName =
        (p?['name'] ?? j['productName']) as String? ?? '';
    return CartDraftItem(
      product: Product(
        id: productId,
        name: productName,
        nameUz: (p?['nameUz'] as String?) ?? productName,
        price: (p?['price'] as num?)?.toDouble() ??
            (j['unitPrice'] as num?)?.toDouble() ??
            0,
        unit: (p?['unit'] as String?) ?? '',
        category: (p?['category'] as String?) ?? '',
        imageUrl: (p?['imageUrl'] as String?) ?? '',
        shopId: (p?['shopId'] as String?) ?? fallbackShopId,
      ),
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (j['unitPrice'] as num?)?.toDouble() ??
          (p?['price'] as num?)?.toDouble() ??
          0,
      // Backend reorder payload uses `available: bool` (true = OK to add).
      // Fall back to legacy `unavailable: bool` for any older callers.
      unavailable: j.containsKey('available')
          ? !(j['available'] as bool? ?? true)
          : (j['unavailable'] as bool? ?? false),
      availableQty: (j['availableQty'] as num?)?.toInt(),
    );
  }
}
