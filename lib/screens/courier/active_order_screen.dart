import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/l10n.dart';
import '../../providers/order_provider.dart';
import '../../services/order_api.dart';
import '../../theme/app_theme.dart';

// Шаги со стороны курьера — теперь с подтверждением номера у магазина
enum DeliveryStep { goToShop, confirmPickup, goToCustomer, atCustomer, done }

class ActiveOrderScreen extends StatefulWidget {
  final String orderId;
  const ActiveOrderScreen({super.key, required this.orderId});
  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen>
    with TickerProviderStateMixin {
  DeliveryStep _step = DeliveryStep.goToShop;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  final _numberCtrl = TextEditingController();
  bool _numberError = false;

  // Phase 8.1 — sibling orders in the same batch as `widget.orderId`. Loaded
  // lazily once we know the active order's `batchId`.
  List<AppOrder> _batchOrders = const [];
  String? _loadedBatchId;

  // Simulated path: shop → customer (Tashkent Yunusobod area)
  static const _shopPoint = (lat: 41.3617, lng: 69.2877);
  static const _customerPoint = (lat: 41.3700, lng: 69.2890);
  Timer? _locTimer;
  double _progress = 0.0; // 0..1 along the route

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  /// Phase 8.1 — pull all sibling orders for the current batch so we can
  /// preview the next pickup and render the batch overview sheet.
  Future<void> _ensureBatchLoaded(String batchId) async {
    if (_loadedBatchId == batchId) return;
    _loadedBatchId = batchId;
    try {
      final list = await OrderApi.instance.courierBatch(batchId);
      if (!mounted) return;
      setState(() => _batchOrders = list);
    } catch (_) {
      // Silent — batch overview is opt-in eye-candy, not load-bearing.
    }
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    _pulseCtrl.dispose();
    _numberCtrl.dispose();
    super.dispose();
  }

  void _startLocationStream() {
    _locTimer?.cancel();
    _locTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      // Linear interp from shop → customer over ~30s after pickup
      _progress = (_progress + 0.07).clamp(0.0, 1.0);
      final lat = _shopPoint.lat + (_customerPoint.lat - _shopPoint.lat) * _progress;
      final lng = _shopPoint.lng + (_customerPoint.lng - _shopPoint.lng) * _progress;
      try {
        await OrderApi.instance.reportCourierLocation(
          lat: lat, lng: lng, orderId: widget.orderId,
        );
      } catch (_) {}
    });
  }

  Future<void> _advance() async {
    HapticFeedback.mediumImpact();
    final orders = context.read<OrderProvider>();

    switch (_step) {
      case DeliveryStep.goToShop:
        setState(() => _step = DeliveryStep.confirmPickup);
        break;

      case DeliveryStep.confirmPickup:
        final ok = await orders.courierPickup(widget.orderId, _numberCtrl.text.trim());
        if (!mounted) return;
        if (ok) {
          if (!mounted) return;
          setState(() { _step = DeliveryStep.goToCustomer; _numberError = false; });
          _startLocationStream();
        } else {
          setState(() => _numberError = true);
          HapticFeedback.heavyImpact();
        }
        break;

      case DeliveryStep.goToCustomer:
        // "Yetib keldim" → arrived at customer's door
        await orders.courierArrived(widget.orderId);
        _locTimer?.cancel();
        if (!mounted) return;
        setState(() => _step = DeliveryStep.atCustomer);
        break;

      case DeliveryStep.atCustomer:
        // Phase 13.2.5 — "Topshirildi" requires a fresh delivery proof
        // photo. We open the rear camera, show a confirm preview, then
        // call the multipart `/courier/delivered` endpoint. On any failure
        // we keep the user on the same step so they can retry.
        final completed = await _captureAndSubmitDeliveryPhoto();
        if (!mounted || !completed) return;
        setState(() => _step = DeliveryStep.done);
        break;

      case DeliveryStep.done:
        // The done screen has a primary CTA which routes through
        // `_finishAndAdvance`; this `case` only fires on the rare path where
        // `_advance` is called while in the done step (e.g. quick double-tap).
        final order = orders.findById(widget.orderId);
        await _finishAndAdvance(order?.batchId);
        break;
    }
  }

  /// Phase 8.1 — when finishing a batch leg, jump to the courier's next
  /// active order automatically. Falls back to the home screen otherwise.
  Future<void> _finishAndAdvance(String? batchId) async {
    if (batchId != null) {
      try {
        final next = await OrderApi.instance.courierActive();
        if (!mounted) return;
        if (next != null && next.id != widget.orderId) {
          context.go('/courier/order/${next.id}');
          return;
        }
      } catch (_) {
        // Fall through to home on error.
      }
    }
    if (!mounted) return;
    context.go('/courier');
  }

  /// Phase 13.2.5 — capture a rear-camera photo, show preview with
  /// Retry / Submit, then POST it as multipart proof. Returns true when the
  /// backend acks `delivered`, false on cancel / failure (so the caller
  /// keeps the courier on the at-door step for retry).
  Future<bool> _captureAndSubmitDeliveryPhoto() async {
    final picker = ImagePicker();
    XFile? picked;
    try {
      picked = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 78,
        maxWidth: 1920,
      );
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(context, 'delivery_photo.camera_unavailable')),
      ));
      return false;
    }
    if (picked == null) return false;

    // Loop: show preview → Retry retakes, Submit uploads.
    File current = File(picked.path);
    while (mounted) {
      final action = await Navigator.of(context).push<_PhotoPreviewAction>(
        MaterialPageRoute(
          builder: (_) => _DeliveryPhotoPreview(photo: current),
          fullscreenDialog: true,
        ),
      );
      if (action == null) return false;
      if (action == _PhotoPreviewAction.retry) {
        final retake = await picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          imageQuality: 78,
          maxWidth: 1920,
        );
        if (retake == null) return false;
        current = File(retake.path);
        continue;
      }
      // Submit
      try {
        await context
            .read<OrderProvider>()
            .courierCompleteWithPhoto(widget.orderId, current);
        return true;
      } catch (_) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(context, 'delivery_photo.upload_failed')),
        ));
        // Stay in the loop so the courier can retake / re-submit.
        continue;
      }
    }
    return false;
  }

  Future<void> _openMap(String address) async {
    final enc = Uri.encodeComponent(address);
    final dgis = Uri.parse('dgis://2gis.uz/routeto?q=$enc');
    final web = Uri.parse('https://2gis.uz/search/$enc');
    if (await canLaunchUrl(dgis)) { await launchUrl(dgis); }
    else { await launchUrl(web, mode: LaunchMode.externalApplication); }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll(' ', '')}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final order = context.watch<OrderProvider>().findById(widget.orderId);
    if (order == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    // Phase 8.1 — kick off batch fetch the first time we render an order in
    // a batch. Safe to call repeatedly; `_ensureBatchLoaded` is idempotent.
    if (order.batchId != null) {
      _ensureBatchLoaded(order.batchId!);
    }
    if (_step == DeliveryStep.done) {
      return _DoneScreen(
        reward: order.reward,
        onFinish: () => _finishAndAdvance(order.batchId),
      );
    }

    final isBatch = order.batchId != null;
    final upcoming = isBatch
        ? _batchOrders
            .where((o) =>
                o.id != order.id &&
                o.status != AppOrderStatus.delivered &&
                o.status != AppOrderStatus.confirmedByBuyer &&
                o.status != AppOrderStatus.cancelled)
            .toList()
        : const <AppOrder>[];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              step: _step,
              onCancel: () => _showCancelSheet(context, order),
              onChat: () => context.push('/order/${order.id}/chat'),
              batchSequence: order.batchSequence,
              batchTotal: order.batchTotal,
            ),
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  _MapView(step: _step),
                  Positioned(
                    bottom: 80, left: 60,
                    child: ScaleTransition(
                      scale: _pulse,
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.courier, shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppColors.courier.withValues(alpha: 0.4), blurRadius: 14, spreadRadius: 4)],
                        ),
                        child: const Center(child: Text('🛵', style: TextStyle(fontSize: 22))),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16, left: 16, right: 16,
                    child: _EtaBubble(step: _step, distanceKm: 1.8),
                  ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Color(0x10000000), blurRadius: 20, offset: Offset(0, -4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  _StepBody(
                    step: _step,
                    order: order,
                    numberCtrl: _numberCtrl,
                    numberError: _numberError,
                    onCall: _callPhone,
                    onMap: _openMap,
                    onNumberChanged: () => setState(() => _numberError = false),
                  ),
                  // Phase 8.1 — upcoming batch orders preview + overview CTA.
                  if (isBatch && upcoming.isNotEmpty)
                    _BatchUpcomingList(
                      upcoming: upcoming,
                      onOverview: () => _showBatchOverview(context, order),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    child: _CtaButton(step: _step, onTap: _advance, canProceed: _canProceed()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBatchOverview(BuildContext context, AppOrder current) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BatchOverviewSheet(
        current: current,
        all: _batchOrders.isEmpty ? [current] : _batchOrders,
      ),
    );
  }

  bool _canProceed() {
    if (_step == DeliveryStep.confirmPickup) return _numberCtrl.text.trim().isNotEmpty;
    return true;
  }

  void _showCancelSheet(BuildContext context, AppOrder order) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Buyurtmani tark etish?', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text('Tez-tez tark etish reytingingizni pasaytiradi.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 20),
            ...[
              'Yo\'lda muammo yuz berdi',
              'Do\'kon yopiq',
              'Boshqa favqulodda holat',
            ].map((r) => ListTile(
              leading: const Icon(Icons.radio_button_unchecked, color: AppColors.textHint),
              title: Text(r),
              contentPadding: EdgeInsets.zero,
              onTap: () { Navigator.pop(context); context.go('/courier'); },
            )),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Ortga')),
          ],
        ),
      ),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final DeliveryStep step;
  final VoidCallback onCancel;
  final VoidCallback? onChat;
  final int? batchSequence;
  final int? batchTotal;
  const _TopBar({
    required this.step,
    required this.onCancel,
    this.onChat,
    this.batchSequence,
    this.batchTotal,
  });

  @override
  Widget build(BuildContext context) {
    final labels = {
      DeliveryStep.goToShop: 'Do\'konga boring',
      DeliveryStep.confirmPickup: 'Buyurtmani oling',
      DeliveryStep.goToCustomer: 'Xaridorga boring',
      DeliveryStep.atCustomer: 'Mahsulot topshiring',
      DeliveryStep.done: 'Bajarildi',
    };
    final steps = DeliveryStep.values.where((s) => s != DeliveryStep.done).toList();
    final curIdx = steps.indexOf(step);
    final isBatch = (batchTotal ?? 0) > 1;

    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(16, isBatch ? 8 : 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBatch) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.courierLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                L10n.instance
                    .t('dispatch.batch_progress')
                    .replaceAll('{index}', '${batchSequence ?? 1}')
                    .replaceAll('{total}', '${batchTotal ?? 2}'),
                style: const TextStyle(
                  color: AppColors.courier,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Row(
                children: steps
                    .asMap()
                    .entries
                    .map((e) => Container(
                          width: e.key == curIdx ? 20 : 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: e.key <= curIdx
                                ? AppColors.courier
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  labels[step] ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              if (onChat != null)
                IconButton(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      color: AppColors.courier),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.courierLight,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onCancel,
                icon: const Icon(Icons.close,
                    color: AppColors.textSecondary),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Phase 8.1 — list of upcoming sibling orders in the same batch with a
/// "view batch overview" button that opens a bottom sheet.
class _BatchUpcomingList extends StatelessWidget {
  final List<AppOrder> upcoming;
  final VoidCallback onOverview;
  const _BatchUpcomingList({
    required this.upcoming,
    required this.onOverview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📦', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  L10n.instance.t('batch.upcoming_pickup'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onOverview,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 28),
                  foregroundColor: AppColors.courier,
                ),
                child: Text(
                  L10n.instance.t('batch.view_overview'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final o in upcoming.take(2))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: AppColors.textHint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      o.deliveryAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (o.batchSequence != null)
                    Text(
                      '#${o.batchSequence}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Phase 8.1 — bottom sheet that lists every order in the batch. The map
/// preview is intentionally minimal (a placeholder card with addresses) so
/// we don't depend on the live Yandex map widget here.
class _BatchOverviewSheet extends StatelessWidget {
  final AppOrder current;
  final List<AppOrder> all;
  const _BatchOverviewSheet({required this.current, required this.all});

  @override
  Widget build(BuildContext context) {
    final sorted = [...all]..sort((a, b) =>
        (a.batchSequence ?? 0).compareTo(b.batchSequence ?? 0));
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📦', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                L10n.instance.t('batch.view_overview'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Map placeholder — production version would render the full route.
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('🗺️', style: TextStyle(fontSize: 40)),
            ),
          ),
          const SizedBox(height: 14),
          for (final o in sorted)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: o.id == current.id
                    ? AppColors.courierLight
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: o.id == current.id
                      ? AppColors.courier
                      : AppColors.border,
                  width: o.id == current.id ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.courier,
                    child: Text(
                      '${o.batchSequence ?? '?'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.shopName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          o.deliveryAddress,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L10n.instance.t('common.back')),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Map ─────────────────────────────────────────────────────────────────────

class _MapView extends StatelessWidget {
  final DeliveryStep step;
  const _MapView({required this.step});
  @override
  Widget build(BuildContext context) {
    final toShop = step == DeliveryStep.goToShop || step == DeliveryStep.confirmPickup;
    return Container(
      color: toShop ? const Color(0xFFE3F2FD) : const Color(0xFFE8F5E9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(toShop ? '🏪' : '🏠', style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 8),
            Text('2GIS Navigator\n(production versiyada)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _EtaBubble extends StatelessWidget {
  final DeliveryStep step;
  final double distanceKm;
  const _EtaBubble({required this.step, required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    final mins = step == DeliveryStep.goToShop || step == DeliveryStep.confirmPickup ? 8 : 12;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(50),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_outlined, size: 16, color: AppColors.courier),
            const SizedBox(width: 6),
            Text('~$mins daqiqa', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(width: 8),
            Container(width: 1, height: 14, color: AppColors.border),
            const SizedBox(width: 8),
            Text('$distanceKm km', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ─── Step body ────────────────────────────────────────────────────────────────

class _StepBody extends StatelessWidget {
  final DeliveryStep step;
  final AppOrder order;
  final TextEditingController numberCtrl;
  final bool numberError;
  final Function(String) onCall;
  final Function(String) onMap;
  final VoidCallback onNumberChanged;

  const _StepBody({
    required this.step, required this.order,
    required this.numberCtrl, required this.numberError,
    required this.onCall, required this.onMap,
    required this.onNumberChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (step) {
      case DeliveryStep.goToShop:
        return _GoToShop(order: order, onMap: onMap);
      case DeliveryStep.confirmPickup:
        return _ConfirmPickup(order: order, ctrl: numberCtrl, hasError: numberError, onChanged: onNumberChanged);
      case DeliveryStep.goToCustomer:
      case DeliveryStep.atCustomer:
        return _GoToCustomer(order: order, isAtDoor: step == DeliveryStep.atCustomer, onCall: onCall, onMap: onMap);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _GoToShop extends StatelessWidget {
  final AppOrder order;
  final Function(String) onMap;
  const _GoToShop({required this.order, required this.onMap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(14)),
              child: const Center(child: Text('🏪', style: TextStyle(fontSize: 24)))),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.shopName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(order.shopAddress, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            )),
            _IconBtn(icon: Icons.navigation_outlined, color: AppColors.info, onTap: () => onMap(order.shopAddress)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Column(
            children: [
              const Row(children: [
                Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Text('Mahsulotlar ro\'yxati', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
              const SizedBox(height: 8),
              ...order.items.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.circle, size: 5, color: AppColors.textHint),
                  const SizedBox(width: 8),
                  Expanded(child: Text(i.product.name, style: const TextStyle(fontSize: 13))),
                  Text('${i.quantity} ${i.product.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              )),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ConfirmPickup extends StatelessWidget {
  final AppOrder order;
  final TextEditingController ctrl;
  final bool hasError;
  final VoidCallback onChanged;
  const _ConfirmPickup({required this.order, required this.ctrl, required this.hasError, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Big instruction
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Text('🏷️', style: TextStyle(fontSize: 32)),
              SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Do\'kondan buyurtma raqamini so\'rang', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.primary)),
                  SizedBox(height: 4),
                  Text('Sticker yoki chekdagi raqamni kiriting', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Number input
        TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4),
          decoration: InputDecoration(
            hintText: 'K-247',
            hintStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: AppColors.textHint, letterSpacing: 4),
            errorText: hasError ? 'Noto\'g\'ri raqam. Qayta urinib ko\'ring' : null,
            filled: true,
            fillColor: hasError ? const Color(0xFFFFEEEE) : AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: hasError ? AppColors.error : AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: hasError ? AppColors.error : AppColors.courier, width: 2),
            ),
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Do\'kon panelida buyurtma raqami ko\'rsatilgan',
            style: TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _GoToCustomer extends StatelessWidget {
  final AppOrder order;
  final bool isAtDoor;
  final Function(String) onCall;
  final Function(String) onMap;
  const _GoToCustomer({required this.order, required this.isAtDoor, required this.onCall, required this.onMap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.courierLight,
              child: Text(order.customerName[0],
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.courier)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(order.deliveryAddress,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            )),
            _IconBtn(icon: Icons.phone_outlined, color: AppColors.success, onTap: () => onCall(order.customerPhone)),
            const SizedBox(width: 8),
            _IconBtn(icon: Icons.navigation_outlined, color: AppColors.info, onTap: () => onMap(order.deliveryAddress)),
          ],
        ),
        if (order.customerComment != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFE082))),
            child: Row(
              children: [
                const Text('💬', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(child: Text(order.customerComment!, style: const TextStyle(fontSize: 13, color: Color(0xFF795548), fontWeight: FontWeight.w500))),
              ],
            ),
          ),
        ],
        if (isAtDoor) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Text('💳', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('To\'lov: ${order.paymentMethod}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(order.isPaid ? 'To\'langan ✓' : 'Naqd pul oling',
                        style: TextStyle(color: order.isPaid ? AppColors.success : AppColors.courier, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                )),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 42, height: 42,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: color, size: 20),
    ),
  );
}

class _CtaButton extends StatelessWidget {
  final DeliveryStep step;
  final VoidCallback onTap;
  final bool canProceed;
  const _CtaButton({required this.step, required this.onTap, required this.canProceed});

  @override
  Widget build(BuildContext context) {
    final labels = {
      DeliveryStep.goToShop: '🏪  Do\'konga yetib keldim',
      DeliveryStep.confirmPickup: '✓  Buyurtmani oldim',
      DeliveryStep.goToCustomer: '🏠  Xaridor eshigiga yetdim',
      DeliveryStep.atCustomer: '🎉  Mahsulot topshirildi',
      DeliveryStep.done: 'Yangi buyurtmalar',
    };
    return AnimatedOpacity(
      opacity: canProceed ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: ElevatedButton(
        onPressed: canProceed ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: step == DeliveryStep.atCustomer ? AppColors.success : AppColors.courier,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(labels[step] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

// ─── Done screen ─────────────────────────────────────────────────────────────

class _DoneScreen extends StatefulWidget {
  final double reward;
  final VoidCallback onFinish;
  const _DoneScreen({required this.reward, required this.onFinish});
  @override
  State<_DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends State<_DoneScreen> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _scale, _fade;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
    _scale = Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.elasticOut));
    _fade = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _c, curve: const Interval(0, 0.4)));
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  String _fmt(double v) => '${v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} so\'m';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.success,
    body: SafeArea(
      child: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 30, offset: const Offset(0, 10))]),
                    child: const Center(child: Text('🎉', style: TextStyle(fontSize: 56))),
                  ),
                ),
                const SizedBox(height: 28),
                const Text('Buyurtma yetkazildi!',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Text('Daromadingiz', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text('+ ${_fmt(widget.reward)}',
                          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('⭐ Xaridor sizni baholashini kuting',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: widget.onFinish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.success,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Yangi buyurtma qabul qilish', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ─── Phase 13.2.5 — Delivery photo preview ─────────────────────────────────

enum _PhotoPreviewAction { retry, submit }

class _DeliveryPhotoPreview extends StatelessWidget {
  final File photo;
  const _DeliveryPhotoPreview({required this.photo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(t(context, 'delivery_photo.preview_title')),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: Image.file(
                    photo,
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context)
                          .pop(_PhotoPreviewAction.retry),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(t(context, 'delivery_photo.retry')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context)
                          .pop(_PhotoPreviewAction.submit),
                      icon: const Icon(Icons.check_circle_rounded,
                          size: 18, color: AppColors.bg),
                      label: Text(t(context, 'delivery_photo.submit')),
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
}
