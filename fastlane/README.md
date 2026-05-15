# Fastlane store metadata

This folder is the source of truth for the Play Store and App Store listing
copy. The layout follows the standard fastlane `supply` (Android) and
`deliver` (iOS) conventions so we can wire `bundle exec fastlane …` later
without rearranging files.

## Layout

```text
fastlane/metadata/
  android/<locale>/
    title.txt              # ≤ 30 chars  (Play store app name)
    short_description.txt  # ≤ 80 chars  (Play listing card)
    full_description.txt   # ≤ 4000 chars (Play listing detail)
  ios/<locale>/
    name.txt               # ≤ 30 chars  (App Store app name)
    subtitle.txt           # ≤ 30 chars  (App Store subtitle)
    keywords.txt           # ≤ 100 chars (comma-separated, ASO)
    description.txt        # ≤ 4000 chars (App Store description)
```

Supported locales: `uz`, `ru`, `en`, `kk`. The localised iOS strings will be
deployed to App Store Connect under `uz`, `ru-RU`, `en-US`, `kk` mapping —
adjust the locale codes in `deliver`'s `Deliverfile` when wiring CI.

Screenshots, app icon, and the marketing app icon (the 1024×1024 listing
icon for iOS) are NOT stored here yet — see `assets/launcher/README.md`
for the icon spec. Each platform expects a different default location, so
drop screenshots into the right tree and `supply`/`deliver` will pick them
up automatically:

- iOS (`deliver`): `fastlane/screenshots/<language-locale>/` — flat per
  locale, no platform subdirectory. See the
  [deliver docs](https://docs.fastlane.tools/getting-started/ios/screenshots/).
- Android (`supply`): `fastlane/metadata/android/<locale>/images/<device>Screenshots/`
  where `<device>` is one of `phone`, `sevenInch`, `tenInch`, `tv`, `wear`.
  See the [supply docs](https://docs.fastlane.tools/actions/supply/).

## Common edits

— Change the tagline → edit each locale's `subtitle.txt` /
  `short_description.txt`. Keep the character budgets in mind, especially
  Russian and Kazakh which are noticeably longer than Uzbek/English.
— Add a new locale → create the four files under each platform folder, then
  add the locale code to the supported list in `pubspec.yaml` /
  `lib/l10n/l10n.dart`.
— Change app name → update `title.txt` (Android) and `name.txt` (iOS) in
  every locale. The Android manifest `android:label` must match.

## Deploy (when fastlane is wired into CI)

```bash
# Android — uploads listing copy + APK to Play Store internal track.
bundle exec fastlane android deploy

# iOS — uploads localised metadata + screenshots; build is uploaded by Xcode
# cloud / `gym` step before this.
bundle exec fastlane ios deploy
```

Until the `Fastfile` and signing keys are checked in, the .txt files in this
tree can still be copy-pasted into Play Console and App Store Connect by
hand for the initial release.

## Deploying

The Phase 13.1.4 work wired a real `Fastfile`, `Appfile`, and
`.github/workflows/release.yml` to the metadata in this folder. The lanes
below assume `bundle install` has been run once at the repo root.

```bash
# Local (after bundle install + signing setup):
bundle exec fastlane android internal        # APK to Play Internal Testing
bundle exec fastlane android beta            # Promote → Beta
bundle exec fastlane android production      # Promote → Production
bundle exec fastlane ios beta                # IPA to TestFlight
bundle exec fastlane ios release             # Metadata + screenshots → App Store

# CI (push a semver tag, e.g. v1.0.1):
git tag v1.0.1 && git push origin v1.0.1     # Triggers release.yml
```

### 1-time signing setup

The release workflow expects a set of GitHub Secrets — see the inline
`# Required:` comments in `.github/workflows/release.yml`. In short:

- **Android** — generate a keystore once with
  `keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias tezketkaz`,
  then `base64 release.jks | pbcopy` and paste into `ANDROID_KEYSTORE_BASE64`.
  Create a Play Console service account
  ([guide](https://docs.fastlane.tools/getting-started/android/setup/)),
  download the JSON key, base64-encode it, and paste into `PLAY_STORE_JSON_KEY`.
- **iOS** — provision a separate private repo for `match` to store the
  encrypted distribution certificate, then locally:
  `bundle exec fastlane match init` followed by `bundle exec fastlane match appstore`.
  Generate an App Store Connect API key with the App Manager role in
  Users and Access → Keys, base64-encode the `.p8`, and store the key id,
  issuer id, and key blob in CI secrets.

The iOS lane self-skips with a friendly warning until `MATCH_GIT_URL` is set,
so Android-only releases stay green on CI.
