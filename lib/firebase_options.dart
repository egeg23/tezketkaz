// TODO: Run `flutterfire configure` to replace this file with real config.
// GENERATED PLACEHOLDER — this file exists so the app compiles before Firebase
// is set up. All values are stubs and will not authenticate against any
// real Firebase project. PushService.init() catches the resulting failure and
// silently degrades.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return _web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _android;
      case TargetPlatform.iOS:
        return _ios;
      default:
        throw UnsupportedError(
          'Firebase not configured for this platform — run flutterfire configure',
        );
    }
  }

  static const _web = FirebaseOptions(
    apiKey: 'STUB',
    appId: '1:000000000000:web:stub',
    messagingSenderId: '000000000000',
    projectId: 'tezketkaz-stub',
    authDomain: 'tezketkaz-stub.firebaseapp.com',
  );

  static const _android = FirebaseOptions(
    apiKey: 'STUB',
    appId: '1:000000000000:android:stub',
    messagingSenderId: '000000000000',
    projectId: 'tezketkaz-stub',
  );

  static const _ios = FirebaseOptions(
    apiKey: 'STUB',
    appId: '1:000000000000:ios:stub',
    messagingSenderId: '000000000000',
    projectId: 'tezketkaz-stub',
    iosBundleId: 'uz.tezketkaz.app',
  );
}
