# Firebase Production Setup (Phase 13.1.6)

This runbook activates push notifications and analytics in production. The
repo ships with safe placeholders so debug builds work without Firebase; this
checklist replaces them with real credentials.

Estimated time: 30 minutes (mostly waiting for console UI).

---

## One-time setup (user)

### 1. Create the Firebase project

- Open <https://console.firebase.google.com> → **Add project**
- Name: `tezketkaz-prod`
- Enable Google Analytics: **yes** (for engagement metrics in Phase 13.4)
- Default account: existing or create new

### 2. Add the Android app

- Package name: `uz.tezketkaz.app`
- App nickname: `TezKetKaz Android`
- Debug signing SHA-1 (optional): `cd android && ./gradlew signingReport`
- Download `google-services.json` and replace
  `android/app/google-services.json` (the committed placeholder is
  gitignored, so you just drop the real one in place).

### 3. Add the iOS app

- Bundle ID: `uz.tezketkaz.app`
- App nickname: `TezKetKaz iOS`
- App Store ID: optional, fill after first TestFlight build
- Download `GoogleService-Info.plist` and replace
  `ios/Runner/GoogleService-Info.plist`.

### 4. Configure FlutterFire

`flutterfire configure` rewrites `lib/firebase_options.dart` with the real
project credentials.

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=tezketkaz-prod
# Pick: android, ios (and web if you want PWA push later).
# Confirm overwriting lib/firebase_options.dart.
```

After this step `DefaultFirebaseOptions.currentPlatform` returns a non-stub
`projectId` and the release-mode guard in `lib/firebase_options.dart` is
satisfied.

### 5. Generate the backend service account

- Firebase Console → **Project Settings** → **Service accounts** →
  **Generate new private key**. A JSON file downloads — never commit it.
- Provide it to the backend via **one** of:
  - **Inline** (recommended for Render / Railway / Fly):
    ```bash
    FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account","project_id":"tezketkaz-prod",...}'
    ```
    Most managed platforms accept the raw JSON in single quotes verbatim.
    If your provider doesn't, escape inner quotes with `\"` and join on a
    single line.
  - **Path** (self-hosted):
    ```bash
    FIREBASE_SERVICE_ACCOUNT_PATH=/etc/secrets/firebase-admin.json
    ```
- Set `FCM_ENABLED=true` in the same env.

### 6. Enable required Google Cloud APIs

In the project's Google Cloud Console:
- **Firebase Cloud Messaging API** → Enable
- Analytics is bundled, no separate enable.
- (Phase 13.4 will add **Cloud Messaging API (Legacy)** if we need topic
  broadcasting; skip for now.)

### 7. Verify end-to-end

```bash
# 1. Build a fresh debug APK (or run on device).
flutter run

# 2. Log in. Wait ~10 s. The app calls /api/users/fcm-token automatically.

# 3. Sanity-check the token was registered.
curl -s http://localhost:3000/api/users/me/fcm-tokens \
  -H "Authorization: Bearer <access_token>"

# 4. Trigger a test push:
#    Admin → Push Campaigns → "Send test to my user"
#    Expected: notification on device within 30 s.
```

---

## What's already wired

- `lib/firebase_options.dart` — placeholder that throws in release mode if
  not regenerated.
- `lib/services/firebase_setup.dart` — boots Firebase with try/catch; the
  app keeps working when init fails.
- `lib/providers/auth_provider.dart` — only calls `PushService.init()` when
  Firebase actually initialised.
- `backend/src/services/push.js` — resolves credentials from
  `FIREBASE_SERVICE_ACCOUNT_JSON` → `FIREBASE_SERVICE_ACCOUNT_PATH` →
  legacy `backend/firebase-admin.json`, in that order.
- `android/app/build.gradle` — applies `com.google.gms.google-services` and
  pulls in the Firebase BoM (`firebase-messaging`, `firebase-analytics`).
- `ios/Podfile` — pinned at `platform :ios, '13.0'` (FCM 11+ requirement).
- `ios/Runner/Info.plist` — `FirebaseAppDelegateProxyEnabled = NO` so push
  tap handling routes through our manual delegate.

## Rollback

If something goes wrong with the production push wiring:

1. `FCM_ENABLED=false` in backend env → all pushes become no-op mocks; the
   rest of the stack keeps running.
2. Revert `lib/firebase_options.dart` to placeholders → next mobile build
   boots without Firebase and degrades gracefully.

Out of scope for 13.1.6: Crashlytics (Phase 13.4), Remote Config, A/B test
delivery. Add those after the messaging path is verified in production.
