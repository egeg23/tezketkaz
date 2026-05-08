import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../services/dispatch_api.dart';
import '../services/socket_service.dart';

/// Snapshot of the courier's active shift, parsed from the dispatch API.
/// All fields are optional because the backend payload may evolve; callers
/// should defensively check for nulls.
class Shift {
  final String id;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<String> zoneIds;
  final double earnings;
  final int ordersCount;

  const Shift({
    required this.id,
    this.startedAt,
    this.endedAt,
    this.zoneIds = const [],
    this.earnings = 0,
    this.ordersCount = 0,
  });

  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
    id: (j['id'] ?? j['shiftId'] ?? '').toString(),
    startedAt: _date(j['startedAt'] ?? j['startAt'] ?? j['startTime']),
    endedAt: _date(j['endedAt'] ?? j['endAt'] ?? j['endTime']),
    zoneIds: ((j['zoneIds'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    earnings: (j['earnings'] as num?)?.toDouble() ??
        (j['totalEarnings'] as num?)?.toDouble() ??
        0,
    ordersCount: (j['ordersCount'] as num?)?.toInt() ??
        (j['ordersDelivered'] as num?)?.toInt() ??
        0,
  );

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  /// Wall-clock duration since the shift opened. `Duration.zero` when there
  /// is no `startedAt`.
  Duration get duration {
    if (startedAt == null) return Duration.zero;
    return DateTime.now().difference(startedAt!);
  }
}

/// A single dispatch offer pushed by the backend on the courier socket.
class DispatchOffer {
  final String orderId;
  final DateTime expiresAt;
  final double? distanceKm;
  final double? payout;
  final int? etaMinutes;
  final String? shopName;
  final String? customerAddress;

  const DispatchOffer({
    required this.orderId,
    required this.expiresAt,
    this.distanceKm,
    this.payout,
    this.etaMinutes,
    this.shopName,
    this.customerAddress,
  });

  factory DispatchOffer.fromJson(Map<String, dynamic> j) {
    final expiresRaw = j['expiresAt'];
    DateTime expires;
    if (expiresRaw is DateTime) {
      expires = expiresRaw;
    } else if (expiresRaw != null) {
      expires = DateTime.tryParse(expiresRaw.toString()) ??
          DateTime.now().add(const Duration(seconds: 60));
    } else {
      expires = DateTime.now().add(const Duration(seconds: 60));
    }
    return DispatchOffer(
      orderId: (j['orderId'] ?? j['id'] ?? '').toString(),
      expiresAt: expires,
      distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      payout: (j['payout'] as num?)?.toDouble() ??
          (j['reward'] as num?)?.toDouble(),
      etaMinutes: (j['etaMinutes'] as num?)?.toInt(),
      shopName: j['shopName'] as String?,
      customerAddress: j['customerAddress'] as String?,
    );
  }

  /// Seconds until the offer expires, clamped at 0.
  int secondsRemaining(DateTime now) {
    final s = expiresAt.difference(now).inSeconds;
    return s < 0 ? 0 : s;
  }
}

/// Holds the courier's online state, current shift, latest known location, and
/// any pending dispatch offer. Driven by the dispatch API and the courier
/// socket (`dispatch:offer`, `order:assigned`).
class CourierStateProvider extends ChangeNotifier {
  CourierStateProvider({DispatchApi? api, SocketService? socket})
      : _api = api ?? DispatchApi.instance,
        _socket = socket ?? SocketService.instance;

  final DispatchApi _api;
  final SocketService _socket;

  bool _isOnline = false;
  Shift? _currentShift;
  LatLng? _lastLocation;
  DispatchOffer? _pendingOffer;
  bool _busy = false;
  String? _error;

  Timer? _tick;
  bool _socketBound = false;

  bool get isOnline => _isOnline;
  Shift? get currentShift => _currentShift;
  LatLng? get lastLocation => _lastLocation;
  DispatchOffer? get pendingOffer => _pendingOffer;
  bool get busy => _busy;
  String? get error => _error;

  /// Seconds left on the current pending offer, or `0` if none / expired.
  int get offerSecondsLeft {
    final p = _pendingOffer;
    if (p == null) return 0;
    return p.secondsRemaining(DateTime.now());
  }

  /// Wire socket listeners, fetch the existing shift (if any) and start the
  /// 1-second tick that drives countdown UIs. Safe to call multiple times.
  Future<void> bootstrap() async {
    _bindSocket();
    _ensureTick();
    try {
      final shift = await _api.currentShift();
      if (shift != null) {
        _currentShift = Shift.fromJson(shift);
        _isOnline = true;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CourierStateProvider.bootstrap: $e');
    }
  }

  /// Start a shift and flip the courier to online.
  Future<void> goOnline({List<String>? zoneIds}) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final shift = await _api.startShift(zoneIds: zoneIds);
      _currentShift = Shift.fromJson(shift);
      _isOnline = true;
      try {
        await _api.setOnline(true);
      } catch (_) {}
      _bindSocket();
      _ensureTick();
    } catch (e) {
      _error = e.toString();
    }
    _busy = false;
    notifyListeners();
  }

  /// Close the shift and flip offline.
  Future<void> goOffline() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      try {
        await _api.setOnline(false);
      } catch (_) {}
      await _api.endShift();
      _currentShift = null;
      _isOnline = false;
      _pendingOffer = null;
    } catch (e) {
      _error = e.toString();
    }
    _busy = false;
    notifyListeners();
  }

  /// Accept the currently pending offer.
  Future<bool> acceptOffer() async {
    final offer = _pendingOffer;
    if (offer == null) return false;
    try {
      await _api.acceptOffer(offer.orderId);
      _pendingOffer = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Decline the currently pending offer.
  Future<bool> declineOffer([String? reason]) async {
    final offer = _pendingOffer;
    if (offer == null) return false;
    try {
      await _api.declineOffer(offer.orderId, reason: reason);
      _pendingOffer = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update the courier's last-known location (used to draw the courier pin
  /// on the map). Does not hit the network — callers should report to the
  /// backend separately if needed.
  void updateLocation(LatLng next) {
    _lastLocation = next;
    notifyListeners();
  }

  /// Push a fresh offer in from outside (e.g. push notification fan-out).
  void injectOffer(DispatchOffer offer) {
    _pendingOffer = offer;
    notifyListeners();
  }

  /// Clear any pending offer (e.g. when navigating to active order screen).
  void clearOffer() {
    if (_pendingOffer == null) return;
    _pendingOffer = null;
    notifyListeners();
  }

  void _bindSocket() {
    if (_socketBound) return;
    // Socket may not be connected yet (auth provider connects on login). The
    // listener still binds; socket.io will buffer the registration.
    _socket.on('dispatch:offer', _onDispatchOffer);
    _socket.on('order:assigned', _onOrderAssigned);
    _socketBound = true;
  }

  void _unbindSocket() {
    if (!_socketBound) return;
    _socket.off('dispatch:offer', _onDispatchOffer);
    _socket.off('order:assigned', _onOrderAssigned);
    _socketBound = false;
  }

  void _onDispatchOffer(dynamic data) {
    if (data is! Map) return;
    try {
      _pendingOffer = DispatchOffer.fromJson(Map<String, dynamic>.from(data));
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('dispatch:offer parse error: $e');
    }
  }

  void _onOrderAssigned(dynamic data) {
    // Either we got the offer (clear pending) or somebody else did
    // (still clear). The active order screen subscribes separately.
    _pendingOffer = null;
    notifyListeners();
  }

  void _ensureTick() {
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      // Drive countdown UI even when nothing else changes.
      if (_pendingOffer != null) {
        if (_pendingOffer!.secondsRemaining(DateTime.now()) <= 0) {
          _pendingOffer = null;
        }
        notifyListeners();
        return;
      }
      if (_currentShift != null) {
        // Repaint shift duration label.
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _unbindSocket();
    super.dispose();
  }
}
