// Firebase Cloud Messaging client.
//
// Setup checklist:
// 1. flutter pub add firebase_core firebase_messaging
// 2. Run flutterfire configure (creates firebase_options.dart)
// 3. Place google-services.json in android/app/
// 4. Place GoogleService-Info.plist in ios/Runner/
// 5. Call PushService.instance.init() after login

import 'package:flutter/foundation.dart';
import 'api_client.dart';

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  String? _token;
  String? get token => _token;

  Future<void> init() async {
    // Stub for prototype.
    // Real implementation:
    //
    // import 'package:firebase_core/firebase_core.dart';
    // import 'package:firebase_messaging/firebase_messaging.dart';
    //
    // await Firebase.initializeApp();
    // final settings = await FirebaseMessaging.instance.requestPermission();
    // if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    //   _token = await FirebaseMessaging.instance.getToken();
    //   await ApiClient.instance.post('/api/users/fcm-token', {'token': _token});
    //   FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    //   FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
    // }

    if (kDebugMode) {
      print('📲 PushService.init() — заглушка. Подключите Firebase.');
    }
  }

  Future<void> updateToken() async {
    if (_token == null) return;
    try {
      await ApiClient.instance.post('/api/users/fcm-token', {'token': _token});
    } catch (_) {}
  }

}
