# TezKetKaz — Действия пользователя (накопленный чек-лист Phase 13)

Здесь собран список всех ручных шагов которые **должен сделать ты** параллельно с моей разработкой Phase 13. Помечаю срочность:

- 🔴 **NOW** — нужно сделать в течение недели, иначе блокирует pilot launch
- 🟠 **SOON** — нужно сделать в течение Phase 13 (4-6 недель), иначе блокирует определённые фичи
- 🟢 **BEFORE PILOT** — нужно сделать до первого магазина, можно отложить на конец Phase 13

## Граф зависимостей (что блокирует что)

```
A. Merchant credentials  ──► payments-go-live (block D в payments-go-live.md)
                         ──► поставить USE_MOCK_PAYMENTS=false
B. Firebase project      ──► FCM push-уведомления
                         ──► flutterfire configure → lib/firebase_options.dart
C. Android signing       ──► (нужно перед D) GitHub release CI tag v1.0.x
D. Play Console          ──► требует C (keystore) и B (google-services.json)
E. Apple Developer       ──► требует D-U-N-S (1-5 дней) — старт ВМЕСТЕ с A!
                         ──► требует B (GoogleService-Info.plist)
F. iOS match (signing)   ──► требует E (developer account)
G. Домен + Cloudflare    ──► требует .uz регистратора (часы-сутки)
                         ──► блокирует marketing-deploy + production URLs
H. Soliq.uz fiscal       ──► требует EDS USB key (1-3 дня)
                         ──► блокирует cashless > 100k UZS в проде
I. Hosting/Deploy        ──► требует G (домен) + H2 (env vars) + B (FCM creds)
                         ──► блокирует smoke tests против прода
J. Контракты магазинов   ──► требует I (api.tezketkaz.uz онлайн) и vendor-next deploy
K. Курьеры               ──► требует D+E (приложения в сторах) или TestFlight build
```

**Главное:** `A. Merchant credentials` и `E. Apple Developer` оба занимают
1-2 недели wall-time. Если не подал заявки в первый день — сдвинется ВСЁ.

---

## 🔴 NOW (срочно — на этой неделе)

### A. Подать заявки на merchant accounts (5-15 рабочих дней wall-time)

Это самое долгое. **Начинай прямо сейчас**, пока я продолжаю код:

- [ ] **Click** (UZ): https://click.uz/business/ → "Подключить онлайн-оплату" → заявка с реквизитами юр.лица
- [ ] **Payme** (UZ): https://merchant.payme.uz/ → регистрация мерчанта
- [ ] **Uzum Pay** (UZ): https://uzum.uz/merchant/ → заявка
- [ ] **Kaspi.kz** (KZ, только если запускаешься в Казахстане): https://kaspi.kz/merchant/ → заявка
- [ ] **Click KG** (KG, опционально): https://my.click.kg/business/

**После получения credentials каждого провайдера:**
1. Запусти `node backend/scripts/payment-diagnose.js <provider>` локально — он валидирует формат и пингует endpoint
2. Установи env переменные в prod хостинге (см. `docs/runbooks/payments-go-live.md`)
3. Сделай тестовую транзакцию 1000 UZS реальной картой → проверь в личном кабинете провайдера
4. Сделай рефанд → проверь что статус Order.refundedAt обновился
5. Только после прохождения этих 4 шагов — поставь `USE_MOCK_PAYMENTS=false`

После получения merchant credentials — присылай мне (или сам подставь в env):
```env
CLICK_MERCHANT_ID=...
CLICK_SERVICE_ID=...
CLICK_SECRET_KEY=...
PAYME_MERCHANT_ID=...
PAYME_KEY=...
UZUM_MERCHANT_ID=...
UZUM_SECRET_KEY=...
KASPI_MERCHANT_ID=...     # если запускаешься в KZ
KASPI_SECRET=...
USE_MOCK_PAYMENTS=false
```

### B. Firebase production project (~30 минут)

Полный runbook: `docs/runbooks/firebase-prod-setup.md`. Кратко:

- [ ] https://console.firebase.google.com → "Add project" → название `tezketkaz-prod`
- [ ] Включить Google Analytics
- [ ] Добавить Android app: package `uz.tezketkaz.app` → скачать `google-services.json` → положить в `android/app/google-services.json`
- [ ] Добавить iOS app: bundle id `uz.tezketkaz.app` → скачать `GoogleService-Info.plist` → положить в `ios/Runner/GoogleService-Info.plist`
- [ ] Локально установить flutterfire CLI: `dart pub global activate flutterfire_cli`
- [ ] Запустить: `flutterfire configure --project=tezketkaz-prod` (перепишет `lib/firebase_options.dart`)
- [ ] Project Settings → Service Accounts → "Generate new private key" → скачать JSON
- [ ] В backend env (Render/Railway/local `.env`):
  ```env
  FCM_ENABLED=true
  FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account","project_id":"tezketkaz-prod",...}'
  ```
- [ ] Google Cloud Console → Firebase Cloud Messaging API → Enable

### C. Android signing keystore (~10 минут)

```bash
keytool -genkey -v \
  -keystore release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias tezketkaz \
  -storepass "<сильный_пароль>" \
  -keypass "<сильный_пароль>" \
  -dname "CN=TezKetKaz, OU=Mobile, O=TezKetKaz LLC, L=Tashkent, ST=Tashkent, C=UZ"

# Закодировать base64 для GitHub secret
base64 release.jks > release.jks.base64

# Скопировать содержимое release.jks.base64 в GitHub repo secret ANDROID_KEYSTORE_BASE64
```

После этого в GitHub repo → Settings → Secrets and variables → Actions → New repository secret:

- [ ] `ANDROID_KEYSTORE_BASE64` = содержимое `release.jks.base64`
- [ ] `ANDROID_KEYSTORE_PASSWORD` = тот пароль что использовал выше
- [ ] `ANDROID_KEY_ALIAS` = `tezketkaz`
- [ ] `ANDROID_KEY_PASSWORD` = тот же пароль (или другой если разделял)
- [ ] **Сохрани `release.jks` в надёжном месте** — если потеряешь, не сможешь обновлять прод-приложение, придётся публиковать новый пакет.

---

## 🟠 SOON (в течение Phase 13)

### D. Google Play Console (~15 минут после Android signing)

- [ ] https://play.google.com/console/ → "Create app" → название `TezKetKaz`, локаль `Russian / Russia`, free, app
- [ ] Заполнить store listing — можно вручную или через `fastlane supply init` (стянет содержимое `fastlane/metadata/android/*`)
- [ ] Setup → API access → Create new service account → "Release manager" role
  - Service account JSON → скачать → base64 encode → GitHub secret `PLAY_STORE_JSON_KEY`
- [ ] Internal Testing track → добавить себя как tester
- [ ] Загрузить первый APK вручную (через UI) или дождаться когда я докручу CI и просто запушить `git tag v1.0.1`

### E. Apple Developer + App Store Connect (1–2 недели wall-time, ~30 минут активной работы)

> **Внимание:** Apple Developer enrollment для юр.лица — это **1–2 недели**
> wall-time (Apple вручную верифицирует D-U-N-S номер компании, иногда требует
> повторных документов). Individual enrollment быстрее (часы–день). **Начинай
> в одно время с merchant accounts**, не позже.

- [ ] **Apple Developer account** ($99/год): https://developer.apple.com/programs/enroll/
  - Для юр.лица: D-U-N-S Number обязателен (можно получить бесплатно через
    https://www.dnb.com/duns-number.html — 1–5 рабочих дней).
  - Apple ID, привязанный к корпоративной почте (`ops@tezketkaz.uz`), а не к
    личной — если человек уйдёт, доступ останется.
- [ ] **App ID**: developer.apple.com → Certificates, IDs & Profiles → Identifiers → "+" → App IDs → Bundle ID `uz.tezketkaz.app`
- [ ] **App Store Connect**: https://appstoreconnect.apple.com → "+" → New App → Bundle ID = `uz.tezketkaz.app`
- [ ] **App Store Connect API Key** (для CI):
  - Users and Access → Keys → Generate API Key → "App Manager" role
  - Скачать `.p8` файл (можно скачать ТОЛЬКО ОДИН РАЗ)
  - Запомнить Key ID + Issuer ID
  - base64 encode `.p8` → GitHub secret `APP_STORE_CONNECT_API_KEY_BASE64`
  - GitHub secrets: `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`
- [ ] GitHub secrets: `FASTLANE_APPLE_ID` (твой Apple ID email), `FASTLANE_TEAM_ID` (developer portal Team ID), `FASTLANE_ITC_TEAM_ID` (App Store Connect numeric Team ID — найти через `bundle exec fastlane produce` once)

### F. iOS signing via match (~20 минут)

- [ ] Создать новый **private** репо `tezketkaz/ios-certs` (только секреты!). НЕ публичный.
- [ ] GitHub PAT (Personal Access Token) с `repo:write` на этот репо
- [ ] Build base64: `echo -n "username:token" | base64`
- [ ] GitHub secrets:
  - `MATCH_GIT_URL` = `https://github.com/tezketkaz/ios-certs.git`
  - `MATCH_PASSWORD` = strong passphrase (запиши в password manager — без него сертификаты не дешифруются)
  - `MATCH_GIT_BASIC_AUTHORIZATION` = base64 от `username:token`
- [ ] Локально на Mac (один раз чтобы засеять certs):
  ```bash
  cd /path/to/tezketkaz
  bundle install
  bundle exec fastlane match init    # интерактивно выбрать "git" + URL
  bundle exec fastlane match appstore   # сгенерит и закоммитит сертификат + provisioning profile
  ```

### G. Домен tezketkaz.uz + Cloudflare (~30 минут)

- [ ] Купить домен `tezketkaz.uz` через узбекского регистратора (UZINFOCOM, Hosting.uz, etc) — ~50,000 UZS/год
- [ ] Создать Cloudflare account: https://dash.cloudflare.com/sign-up
- [ ] В Cloudflare → "Add a site" → `tezketkaz.uz` → Free plan
- [ ] У регистратора домена сменить nameservers на те что покажет Cloudflare (обычно 2 штуки `*.ns.cloudflare.com`)
- [ ] DNS records в Cloudflare (как только я задеплою marketing landing):
  - `tezketkaz.uz` → A → IP лендинга (Cloudflare Pages автоматически)
  - `app.tezketkaz.uz` → backend (Render/Railway URL)
  - `admin.tezketkaz.uz` → admin-next Vercel deployment
  - `vendor.tezketkaz.uz` → vendor-next Vercel deployment
  - `api.tezketkaz.uz` → backend (то же что app)

---

## 🟢 BEFORE PILOT (до первого магазина)

### H. Soliq.uz fiscal API доступ

После того как я допишу Soliq integration (Wave 3):
- [ ] Регистрация в Soliq.uz Personal Cabinet как юр.лицо
- [ ] Получить API key для fiscal receipts (через ТСИ/ТП интерфейс)
- [ ] От **каждого магазина-партнёра** при онбординге собрать:
  - STIR/ИНН (9 или 14 цифр)
  - VAT number (если плательщик НДС)
  - Класс активности (ОКЭД код)

### H2. Дополнительные env-переменные production-бэкенда

Кроме платёжных и Firebase кредов (выше) бэкенду в проде нужны ещё несколько
переменных. Полный шаблон — `backend/.env.example`. Кратко то, что часто
забывают:

```env
# Auth — обязательно сгенерировать УНИКАЛЬНЫЕ secrets (≥32 символа)
JWT_SECRET=<pwgen -s 48 1>
REFRESH_SECRET=<pwgen -s 48 1>

# Storage (после R2 setup — block I ниже)
STORAGE_PROVIDER=r2
S3_BUCKET=tezketkaz-prod
S3_ENDPOINT=https://<accountid>.r2.cloudflarestorage.com
S3_REGION=auto
S3_ACCESS_KEY=<R2 API token access key>
S3_SECRET_KEY=<R2 API token secret>
S3_PUBLIC_BASE=https://cdn.tezketkaz.uz   # или прямая R2 ссылка
PUBLIC_URL=https://api.tezketkaz.uz

# SMS — Eskiz прод-режим (после получения корпоративного аккаунта)
USE_MOCK_SMS=false
ESKIZ_EMAIL=<регистрация на https://my.eskiz.uz>
ESKIZ_PASSWORD=<пароль из кабинета Eskiz>
ESKIZ_FROM=4546   # одобренный sender ID

# Maps (опционально, для road-aware ETA)
YANDEX_ROUTING_KEY=<https://developer.tech.yandex.ru>
DGIS_API_KEY=<https://dev.2gis.ru>

# Транзакционный email (опционально, для KYC / invoices)
RESEND_API_KEY=<https://resend.com>

# Soliq (Wave 3 / block H выше)
USE_MOCK_SOLIQ=false
SOLIQ_API_KEY=<из кабинета Soliq.uz, см. soliq-fiscal-setup.md>

# Observability
SENTRY_DSN=<из https://sentry.io/settings/ → Projects → tezketkaz-backend>
LOG_LEVEL=info

# Smoke-тестовый телефон (нужен и на бэке, и в GitHub secrets)
TEST_PHONES_ACCEPT_123456=+998900000001
```

В GitHub repo secrets дополнительно:
- `SMOKE_BASE_URL` = `https://api.tezketkaz.uz`
- `SMOKE_TEST_PHONE` = `+998900000001` (тот же что в `TEST_PHONES_ACCEPT_123456`)
- `SENTRY_AUTH_TOKEN` + `SENTRY_ORG` — для тегов релизов из CI (опционально)

### I. Hosting / Deploy

Я задеплою через CI на:
- [ ] Backend → Render Pro $19/мес или Railway $5/мес (выбери что больше нравится; Render проще)
- [ ] Postgres → Neon Pro $19/мес (point-in-time recovery + branching)
- [ ] Redis → Upstash free tier для начала; перейти на $10-30/мес после 1k DAU
- [ ] Storage (R2) → Cloudflare R2 free tier (10 GB) для иконок и KYC; после ~5k юзеров перейти на Pro
- [ ] admin-next → Vercel free / Pro $20/мес
- [ ] vendor-next → Vercel free / Pro $20/мес
- [ ] Marketing landing → Cloudflare Pages free
- [ ] Sentry → free tier 5k events/мес для начала

**Стартовый бюджет:** $25-40/мес (Neon Pro + Render + остальное free).
**После 1k DAU:** ~$80-150/мес.

### J. Контракты с магазинами (5-10 штук для пилота)

После того как я допишу onboarding playbooks (Wave 5):
- [ ] Связаться с 10-15 потенциальными партнёрами (рестораны, аптеки, магазинчики возле дома)
- [ ] Подписать рамочный договор (юрист / шаблон)
- [ ] Обучить владельца / менеджера vendor-портал
- [ ] Залить первый продукт-каталог через XLSX импорт

### K. Курьеры (10-20 штук для пилота)

- [ ] Реклама в Telegram-каналах "Работа в Ташкенте"
- [ ] Собеседование (телефон + офис) с проверкой STIR/паспорта
- [ ] Выдать униформу + сумку
- [ ] Первая смена с supervisor

---

## Phase 13 — статус волн (все код-работы завершены)

- ✅ **Wave 1**: Postgres миграция + R2/S3 storage + T&C enforcement
- ✅ **Wave 2**: App icons (Pin+Lightning) + Fastfile + Firebase prep
- ✅ **Wave 3**: Soliq.uz fiscal integration + Marketing landing + Payment audit + diagnose CLI
- ✅ **Wave 4**: l10n hardcoded → keys + Kazakh translation + role selection + KYC re-upload + delivery photo proof
- ✅ **Wave 5**: Shop mobile refund/promo/analytics + vendor-next 403 fixes + heatmap UI + cookie banner + Privacy labels
- ✅ **Wave 6**: Smoke test CLI + DR runbooks + receipts PDF + pull-to-refresh/skeleton states + onboarding playbooks

**Тестовая база:** 560/560 backend тестов зелёные на Postgres.

## После Wave 6 → запуск пилота

Чек-лист сжатый — раскрытие в runbook'ах:

1. **Реги­стра­ции и креды** (см. блоки 🔴 NOW и 🟠 SOON выше)
2. **Деплой инфраструктуры** (см. `docs/runbooks/marketing-deploy.md`, hosting в блоке I выше)
3. **Smoke test после каждого деплоя** — `node backend/scripts/smoke-test.js` (`docs/runbooks/smoke-tests.md`)
4. **DR подготовка** — изучить `docs/runbooks/disaster-recovery.md` ДО запуска, чтобы при сбое не паниковать
5. **Онбординг магазинов** — `docs/runbooks/shop-onboarding.md` (5-10 партнёров для пилота)
6. **Онбординг курьеров** — `docs/runbooks/courier-onboarding.md` (10-20 курьеров)
7. **Запуск пилота** — `docs/runbooks/pilot-launch-checklist.md` (2 недели → 1 неделя → запуск → 1-я неделя → 1-й месяц)

После пилота → сбор фидбека → Phase 14 (улучшения по результатам пилота).

## Все runbook'и (в `docs/runbooks/`)

| Файл | Что описывает |
|------|---------------|
| `firebase-prod-setup.md` | Создание Firebase проекта, FCM, service account |
| `soliq-fiscal-setup.md` | Регистрация в Soliq.uz, fiscal API, per-shop onboarding |
| `marketing-deploy.md` | Cloudflare Pages, домен, DNS |
| `payments-go-live.md` | Активация Click/Payme/Uzum/Kaspi из mock-mode |
| `smoke-tests.md` | Post-deploy smoke verification |
| `disaster-recovery.md` | 9 сценариев отказа + recovery procedures |
| `shop-onboarding.md` | Подключение первых магазинов-партнёров |
| `courier-onboarding.md` | Найм и обучение курьеров |
| `pilot-launch-checklist.md` | Тайминг запуска пилота |
| `fastlane/README.md` | iOS/Android signing setup |
| `docs/privacy/ios-privacy-labels.md` | App Store Privacy Labels |
| `docs/privacy/android-data-safety.md` | Play Store Data Safety |
