# 🚀 TezKetKaz — Launch Checklist

Этот документ — что осталось сделать после получения кода.

## ✅ Уже готово в коде

- [x] Flutter app (3 роли в одном приложении: покупатель / курьер / магазин)
- [x] Backend Node.js + Express + Prisma + Socket.IO + PostgreSQL
- [x] Real-time синхронизация между всеми ролями
- [x] JWT-авторизация по SMS OTP (mock SMS работает из коробки)
- [x] Полный state-machine заказа: покупатель → магазин → курьер
- [x] Валидация номера заказа курьером при заборе из магазина
- [x] Платёжные интеграции (Click + Payme + Uzum Pay) с mock-режимом
- [x] FCM push-нотификации (заглушка готова к подключению)
- [x] Yandex MapKit виджет для трекинга
- [x] Admin-панель (web) для модерации курьеров и аналитики
- [x] Native конфиги Android (AndroidManifest, gradle, Kotlin)
- [x] Native конфиги iOS (Info.plist, permissions)
- [x] Localization (uz/ru/en)
- [x] Loading skeletons, empty states, error widgets
- [x] Pull-to-refresh
- [x] Docker + docker-compose для одной команды
- [x] GitHub Actions CI/CD
- [x] Deep linking (tezketkaz://)
- [x] Persistent сессия (secure storage)

## 🔴 Что нужно сделать вам (внешние шаги)

### 1. Юридическое (Узбекистан) — 1-2 недели

- [ ] **Регистрация ООО** — https://birdarcha.uz (~3 млн сум, 3-5 дней)
- [ ] **СТИР для юрлица** — выдаётся при регистрации
- [ ] **ОКЭД 53.20** (курьерская деятельность) или **47.99** (интернет-торговля)
- [ ] **Расчётный счёт** — Hamkorbank / Trustbank / Asia Alliance
- [ ] **Уведомление о начале электронной коммерции** в Налоговый комитет

### 2. SMS-шлюз (Eskiz.uz) — 5-7 дней

- [ ] Регистрация на https://my.eskiz.uz
- [ ] Подача документов юрлица (KYC)
- [ ] Регистрация sender ID (~500 000 сум разово)
- [ ] В `backend/.env`:
  ```
  USE_MOCK_SMS=false
  ESKIZ_EMAIL=your@email.uz
  ESKIZ_PASSWORD=your_password
  ESKIZ_FROM=4546
  ```

### 3. Платёжные системы — параллельно ~2 недели

#### Click — https://click.uz/business
- [ ] Договор с юрлицом (через email менеджера)
- [ ] `merchant_id`, `service_id`, `secret_key`
- [ ] Указать callback URL: `https://api.tezketkaz.uz/api/payments/click/callback`
- [ ] В `.env`:
  ```
  CLICK_MERCHANT_ID=...
  CLICK_SERVICE_ID=...
  CLICK_SECRET_KEY=...
  ```

#### Payme — https://business.payme.uz
- [ ] Договор + интеграция
- [ ] `merchant_id`, `key`
- [ ] Callback URL: `https://api.tezketkaz.uz/api/payments/payme/callback`

#### Uzum Pay — https://business.uzum.uz
- [ ] Самые низкие комиссии
- [ ] `merchant_id` + webhook URL

После получения ключей: `USE_MOCK_PAYMENTS=false` в `.env`.

### 4. Карты (2GIS / Yandex MapKit) — 1 час

- [ ] Получить ключ на https://developer.tech.yandex.ru
- [ ] Бесплатный тариф: 25 000 запросов/мес
- [ ] Добавить в:
  - `android/gradle.properties`: `YANDEX_MAPKIT_API_KEY=ваш_ключ`
  - `ios/Runner/AppDelegate.swift`: `YandexMapKit.setApiKey("ваш_ключ")` в `didFinishLaunchingWithOptions`

### 5. Push-уведомления (Firebase) — 1 день

- [ ] Создать проект на https://console.firebase.google.com
- [ ] Зарегистрировать Android (com.tezketkaz.app) и iOS bundle ID
- [ ] Скачать:
  - `google-services.json` → `android/app/`
  - `GoogleService-Info.plist` → `ios/Runner/`
  - Service Account JSON → `backend/firebase-admin.json`
- [ ] `flutterfire configure` для генерации `firebase_options.dart`
- [ ] Раскомментировать FCM код в `lib/services/push_service.dart`
- [ ] В `.env`: `FCM_ENABLED=true`

### 6. Apple Developer + Google Play — $124, 1-2 недели

#### iOS App Store
- [ ] Apple Developer Program ($99/год)
- [ ] Bundle ID: `uz.tezketkaz.app`
- [ ] Provisioning Profile + Distribution certificate
- [ ] Скриншоты для всех размеров: 6.7", 6.5", 5.5"
- [ ] Privacy Policy URL (обязательно)
- [ ] Заполнить `App Tracking Transparency` description (если используете аналитику)
- [ ] App Review: 24-48 часов

#### Google Play
- [ ] Google Play Console ($25 разово)
- [ ] Application ID: `uz.tezketkaz.app`
- [ ] Signed App Bundle (`.aab`):
  ```bash
  cd android && ./gradlew bundleRelease
  ```
- [ ] Создать keystore: `keytool -genkey -v -keystore release.jks ...`
- [ ] Заполнить Privacy Policy + Data Safety
- [ ] Возрастной рейтинг: 3+
- [ ] Review: несколько часов до 1-2 дней

### 7. Хостинг production — 1 день

- [ ] **Backend:** Railway / Render / DigitalOcean (~$10-20/мес)
  ```bash
  # Railway:
  railway login && railway init && railway up
  ```
- [ ] **PostgreSQL managed:** Neon / Supabase (free tier до 0.5 GB)
- [ ] **Domain:** `api.tezketkaz.uz` + Let's Encrypt SSL
- [ ] **CDN для фото:** Cloudflare R2 (бесплатно до 10 ГБ)

### 8. Безопасность production — 0.5 дня

- [ ] Сменить `JWT_SECRET` (минимум 64 случайных символа)
  ```bash
  node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
  ```
- [ ] Включить `helmet.js`:
  ```js
  const helmet = require('helmet');
  app.use(helmet());
  ```
- [ ] Rate limiting:
  ```js
  const rateLimit = require('express-rate-limit');
  app.use('/api/auth/send-otp', rateLimit({windowMs: 60000, max: 1}));
  ```
- [ ] Backups БД: Neon делает автоматически

### 9. Мониторинг — 0.5 дня

- [ ] **Sentry** (https://sentry.io) — error tracking, бесплатно до 5k errors/мес
- [ ] **UptimeRobot** — мониторинг доступности, бесплатно
- [ ] **Mixpanel / Amplitude** — продуктовая аналитика, бесплатные тарифы

### 10. Партнёрство с магазинами — 2-4 недели

Это самое долгое. Нужны договоры с физическими магазинами:
- Korzinka
- Makro
- Smart
- Местные продуктовые сети

Каждому магазину:
- Объяснить ценность (новый канал продаж)
- Согласовать комиссию (10-15%)
- Подключить через invite-код в приложении

## 📊 Итого: время до запуска

| Этап | Срок | Стоимость |
|------|------|-----------|
| Юрлицо + СТИР | 5 дней | ~3 млн сум |
| Eskiz.uz договор | 7 дней | 500 тыс сум |
| Click/Payme/Uzum контракты (параллельно) | 14 дней | 0 |
| Apple + Google аккаунты | 1 день | $124 |
| Все интеграции (вы или программист) | 5 дней | — |
| Партнёрство с магазинами | 14-30 дней | — |
| App Review | 1-3 дня | — |
| **Итого минимум** | **~5 недель** | **~$500** |

## 🎯 Когда вы можете тестировать прямо сейчас

С mock-режимом всё работает локально:
```bash
docker-compose up
flutter run
```

Откройте приложение → войдите как `+998901234567` с кодом `123456` → создайте заказ.
Параллельно откройте админку: http://localhost:3000/admin
Войдите через тот же телефон.
Увидите ваш заказ в реальном времени.

Удачи! 🚀
