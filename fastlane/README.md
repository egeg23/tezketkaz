# Fastlane store metadata

This folder is the source of truth for the Play Store and App Store listing
copy. The layout follows the standard fastlane `supply` (Android) and
`deliver` (iOS) conventions so we can wire `bundle exec fastlane …` later
without rearranging files.

## Layout

```
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
for the icon spec. Drop screenshots into
`fastlane/screenshots/<platform>/<locale>/` when the design team produces
them; both `supply` and `deliver` will pick them up automatically.

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
