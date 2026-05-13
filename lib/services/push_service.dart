// Firebase Cloud Messaging client.
//
// Setup:
// 1. Run `flutterfire configure` (creates a real lib/firebase_options.dart).
// 2. Place google-services.json in android/app/.
// 3. Place GoogleService-Info.plist in ios/Runner/.
// 4. Call PushService.instance.init() after a successful login.
// 5. Call PushService.instance.dispose() on logout.
//
// All Firebase calls are wrapped in try/catch — when the app runs without a
// real firebase_options.dart, init() simply logs and returns.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';

/// Top-level entry point required by FirebaseMessaging.onBackgroundMessage.
/// Must be a top-level (or static) function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep this minimal — Flutter binds a fresh isolate just to run this.
  if (kDebugMode) {
    debugPrint('FCM background: ${message.messageId} ${message.data}');
  }
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  String? _token;
  String? get token => _token;

  bool _initialized = false;
  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _ordersChannel =
      AndroidNotificationChannel(
    'orders',
    'Buyurtmalar',
    description: 'Buyurtma holati va kuryer xabarnomalari',
    importance: Importance.high,
  );

  /// Stream of taps on notifications that opened the app.
  /// Listen to this from a router/redirect to deep-link the user.
  final StreamController<RemoteMessage> _tapController =
      StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onTap => _tapController.stream;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  /// Call after successful login.
  Future<void> init() async {
    if (_initialized) return;
    try {
      // ── Permissions ─────────────────────────────────────────────────────
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (kDebugMode) debugPrint('FCM permission denied');
        return;
      }

      // ── Local notifications (foreground display) ────────────────────────
      await _initLocalNotifications();

      // ── Background handler (registered once) ────────────────────────────
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // ── Get & register token ────────────────────────────────────────────
      // TODO: pass a real `vapidKey` for web push (from Firebase console).
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null && _token!.isNotEmpty) {
        await _registerToken(_token!);
      }

      // ── Token refresh ──────────────────────────────────────────────────
      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        _token = newToken;
        await _registerToken(newToken);
      });

      // ── Foreground messages ─────────────────────────────────────────────
      _foregroundSub = FirebaseMessaging.onMessage.listen(_showLocal);

      // ── App opened from a notification (background → foreground) ────────
      _openedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

      // ── App launched from a terminated state via a notification ─────────
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        // Defer so listeners attached after init() still receive it.
        scheduleMicrotask(() => _handleTap(initialMessage));
      }

      _initialized = true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('PushService.init() skipped: $e\n$st');
      }
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifs.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        // When the user taps a foreground-displayed local notification,
        // forward to the same tap stream as background-opened messages.
        final payload = resp.payload;
        if (payload != null) {
          // We don't have a full RemoteMessage here, so synthesize one.
          _tapController.add(RemoteMessage(data: {'payload': payload}));
        }
      },
    );

    // Create the channel once; safe to call repeatedly.
    if (!kIsWeb && Platform.isAndroid) {
      await _localNotifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_ordersChannel);
    }
  }

  Future<void> _showLocal(RemoteMessage msg) async {
    final notif = msg.notification;
    if (notif == null) return;
    final android = AndroidNotificationDetails(
      _ordersChannel.id,
      _ordersChannel.name,
      channelDescription: _ordersChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: notif.android?.smallIcon,
    );
    const ios = DarwinNotificationDetails();
    await _localNotifs.show(
      notif.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(android: android, iOS: ios),
      payload: msg.data.isEmpty ? null : msg.data.toString(),
    );
  }

  void _handleTap(RemoteMessage msg) {
    if (kDebugMode) debugPrint('FCM tap: ${msg.data}');
    // Phase 10.4 — fire-and-forget campaign open tracking. The notification
    // payload carries `campaignId` whenever it originated from a push
    // campaign blast; we hit the analytics endpoint, ignoring failures so a
    // network blip doesn't block the deep-link routing.
    final campaignId = msg.data['campaignId']?.toString();
    if (campaignId != null && campaignId.isNotEmpty) {
      _trackCampaignOpen(campaignId);
    }
    _tapController.add(msg);
  }

  Future<void> _trackCampaignOpen(String campaignId) async {
    try {
      await ApiClient.instance
          .post('/api/push-campaigns/$campaignId/track-open');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Campaign track-open failed (ignored): $e');
      }
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await ApiClient.instance.post('/api/users/fcm-token', {
        'token': token,
        'platform': _platform(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('FCM token register failed: $e');
    }
  }

  String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'web';
  }

  /// Call on logout. Best-effort token unregister + local cleanup.
  Future<void> dispose() async {
    final t = _token;
    if (t != null && t.isNotEmpty) {
      try {
        await ApiClient.instance.delete(
          '/api/users/fcm-token',
          data: {'token': t},
        );
      } catch (e) {
        if (kDebugMode) debugPrint('FCM token unregister failed: $e');
      }
    }
    await _tokenRefreshSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _tokenRefreshSub = null;
    _foregroundSub = null;
    _openedSub = null;
    _token = null;
    _initialized = false;
  }
}
