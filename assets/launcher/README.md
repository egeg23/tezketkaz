# TezKetKaz App Icon + Splash

Все ассеты сгенерированы из `design/logo-concepts/concept-3-pin-bolt.svg` (выбран 11 мая 2026 пользователем как production-логотип).

## Файлы

| Файл | Назначение |
|------|------------|
| `icon-1024.png` | Master для `flutter_launcher_icons`; App Store marketing icon (1024×1024, без альфы) |
| `icon-512.png` | Play Store listing icon (512×512) |
| `icon-256/192/144/96/72/48.png` | Прочие fallback размеры |
| `icon-fg-1024.png` | Adaptive icon foreground (Android 8+, прозрачный фон, контент в центральных 66%) |
| `icon-bg-1024.png` | Solid navy `#1A237E` background для adaptive icon (если не хотим использовать color literal) |
| `splash-logo.png` | Логотип на splash-экране (512×512, центрированный на навигационном фоне) |

## Брендовая палитра

| Цвет | Hex | Где |
|------|-----|-----|
| Navy | `#1A237E` | Splash фон, adaptive icon фон, iOS icon background |
| Indigo | `#3F51B5` | Градиент конец |
| Gold | `#FFD600` | Lightning bolt акцент |
| Amber | `#FFA000` | Bolt градиент конец |

## Применить иконки в Flutter

```bash
# Один раз — установить dev-зависимости
flutter pub get

# Сгенерировать все размеры под Android + iOS + web (читает секцию flutter_launcher_icons в pubspec.yaml)
dart run flutter_launcher_icons

# Сгенерировать splash экраны
dart run flutter_native_splash:create
```

После этого:
- Android: `android/app/src/main/res/mipmap-*/ic_launcher.png` обновятся; для Android 8+ дополнительно появится `mipmap-anydpi-v26/ic_launcher.xml` (adaptive icon).
- iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` обновится со всеми размерами (включая 1024 marketing для App Store).
- Splash: `flutter_native_splash` модифицирует `LaunchScreen.storyboard` (iOS), `drawable/launch_background.xml` (Android), `drawable-v21/launch_background.xml`.

## Проверить визуально

```bash
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
# На устройстве home screen должен показать pin+lightning иконку на navy фоне.
```

iOS: `flutter build ios --debug` + установка через Xcode на физическое устройство (симулятор тоже работает).

## Re-export если правишь SVG

```bash
cd design/logo-concepts && python3 ../../scripts/export-icons.py
```

(скрипт `scripts/export-icons.py` — TODO; пока генерация делается inline через `cairosvg.svg2png` — см. историю коммитов).

## Source

- `design/logo-concepts/concept-3-pin-bolt.svg` — единственный source of truth. Все PNG генерируются из него. Если меняешь логотип — правь SVG, перегенерируй PNG, коммить и то и другое.
