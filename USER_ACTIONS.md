# TezKetKaz — Действия пользователя (накопленный чек-лист Phase 13)

Здесь собран список всех ручных шагов которые **должен сделать ты** параллельно с моей разработкой Phase 13. Помечаю срочность:

- 🔴 **NOW** — нужно сделать в течение недели, иначе блокирует pilot launch
- 🟠 **SOON** — нужно сделать в течение Phase 13 (4-6 недель), иначе блокирует определённые фичи
- 🟢 **BEFORE PILOT** — нужно сделать до первого магазина, можно отложить на конец Phase 13

---

## 🔴 NOW (срочно — на этой неделе)

### A. Подать заявки на merchant accounts (5-15 рабочих дней wall-time)

Это самое долгое. **Начинай прямо сейчас**, пока я продолжаю код:

- [ ] **Click** (UZ): https://click.uz/business/ → "Подключить онлайн-оплату" → заявка с реквизитами юр.лица
- [ ] **Payme** (UZ): https://merchant.payme.uz/ → регистрация мерчанта
- [ ] **Uzum Pay** (UZ): https://uzum.uz/merchant/ → заявка
- [ ] **Kaspi.kz** (KZ, только если запускаешься в Казахстане): https://kaspi.kz/merchant/ → заявка
- [ ] **Click KG** (KG, опционально): https://my.click.kg/business/

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

### E. Apple Developer + App Store Connect (~30 минут)

- [ ] **Apple Developer account** ($99/год): https://developer.apple.com/programs/enroll/
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

## Запланировано на следующие волны (ничего не нужно делать сейчас)

- **Wave 3** (в работе): Soliq integration, marketing landing, payment creds runbook
- **Wave 4**: hardcoded l10n → ru/uz/en/kk; role selection screen; KYC re-upload; delivery photo proof
- **Wave 5**: Shop mobile refund/promo/analytics; vendor 403 fixes; heatmap UI; cookie banner; Privacy Nutrition Labels
- **Wave 6**: Smoke tests; DR runbooks; receipts PDF; pull-to-refresh; onboarding playbooks

После Wave 6 → пилот в Ташкенте → сбор фидбека → Phase 14.
