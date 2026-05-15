# TezKetKaz

> **Marketplace доставки еды и продуктов для Узбекистана.**
> Один Flutter-app, три роли (покупатель / курьер / ресторан), Node-backend
> с real-time, B2B-интеграции с POS-системами (iiko / Poster / Custom REST),
> Telegram-вход, тёмный дизайн с лимонным акцентом.

[![Build](https://github.com/egeg23/tezketkaz/actions/workflows/build-web.yml/badge.svg)](https://github.com/egeg23/tezketkaz/actions)
![License](https://img.shields.io/badge/License-Proprietary-red)
![Stack](https://img.shields.io/badge/stack-Flutter%20%2B%20Node%20%2B%20Postgres-06C167)

---

## 📸 В двух словах

**Один-роль-на-все-три**: пользователь регистрируется через Telegram (без SMS, без паролей), потом сам выбирает в каком режиме открыть приложение — покупатель / курьер / ресторан-менеджер.

**Каждая роль — отдельный мир** под мастер-дизайном [tezketkaz_master_design.html](_design/master.html): home / catalog / cart / tracking для покупателя, dashboard / order-queue для ресторана, available / active / earnings для курьера.

**B2B-уровень для сетей**: ресторан подключает свой iiko/Poster/1С через UI, и меню синхронизируется автоматически. Заказы возвращаются партнёру по HTTP webhook'у с HMAC-подписью. Готово для подключения 100+ точек одной сети.

---

## 🚀 Быстрый старт

### А. Развернуть staging на своём VPS (рекомендуется)

См. полный гайд: **[DEPLOY.md](DEPLOY.md)**. 10-15 минут на чистом Ubuntu 24+ сервере, итог — рабочий стэк по HTTPS:

```bash
# на сервере:
git clone https://github.com/egeg23/tezketkaz /opt/tezketkaz
cd /opt/tezketkaz
./infra/deploy.sh       # генерит секреты, поднимает 4 контейнера
nano infra/.env         # вписать DOMAIN + ADMIN_EMAIL
./infra/deploy.sh       # реальный запуск
```

→ через ~10 мин: `https://<твой-домен>/` с auto-SSL, Postgres, Redis, BullMQ-воркерами, Telegram-логином.

### Б. Локальная разработка

```bash
# Backend
cd backend
cp .env.example .env
npm install
npx prisma db push       # создаёт SQLite-базу
node prisma/seed.js
npm run dev              # порт 3000

# Flutter web (новый терминал)
cd ..
flutter pub get
flutter run -d chrome    # порт авто
```

### В. B2B-интеграция для партнёра-ресторана

```bash
# Получи свой tz_live_… через UI: /shop/integration
curl -X POST https://<домен>/api/v1/products/upsert \
  -H "Authorization: Bearer tz_live_..." \
  -H "Content-Type: application/json" \
  -d '{"items":[{"externalId":"sku-1","name":"Маргарита","price":60000,"unit":"шт","category":"pizza"}]}'
```

Полная документация — в UI на `/shop/integration` с cURL-примерами и live-логом.

---

## 🎯 Готовность

| Уровень | Готовность | Что нужно для финального чека |
|---|---|---|
| **Закрытый бета** (5 ресторанов + 50 покупателей, cash-only) | **80%** | Развернуть staging + домен |
| **Публичный запуск** (real money, AppStore, реальные SMS) | **48%** | + Click/Payme контракты, AppStore аккаунт, юрист, прод-сервер |

Подробный аудит по слоям — в [DEPLOY.md → Sanity checks](DEPLOY.md).

---

## 🏗 Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                  Flutter app (Web + iOS + Android)          │
│  ──────────────────────────────────────────────────────────┤
│  Master Design v1 — dark / lime / Playfair italic           │
│  Buyer / Courier / Shop — три полных surface-области        │
│  Provider state, go_router, flutter_map, socket.io          │
└─────────────────────────────────────────────────────────────┘
                              │ HTTPS / WS
                              ▼
┌─────────────────────────────────────────────────────────────┐
│         Caddy reverse proxy (auto Let's Encrypt)            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Node 20 — Express + Prisma + Socket.IO + BullMQ           │
│  ──────────────────────────────────────────────────────────┤
│  /api/auth/telegram   /api/orders   /api/shops              │
│  /api/v1/*  (B2B)     /api/geocode  /api/payments           │
│  /api/shops/me/integration  (POS connectors)                │
└─────────────────────────────────────────────────────────────┘
       │              │              │              │
       ▼              ▼              ▼              ▼
  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
  │ Postgres │    │  Redis  │    │ Yandex  │    │Telegram │
  │   16     │    │   7     │    │Geocoder │    │   Bot   │
  └─────────┘    └─────────┘    └─────────┘    └─────────┘
```

---

## 📂 Структура репо

```
tezketkaz/
├── lib/                          # Flutter app (~14 000 строк)
│   ├── screens/
│   │   ├── auth/                 # splash, login (Telegram), name
│   │   ├── buyer/                # home, catalog, cart, tracking, profile…
│   │   ├── courier/              # available, active, earnings, profile…
│   │   ├── shop/                 # dashboard, products, integrations, settings…
│   │   └── shared/               # role-switcher, courier-verification
│   ├── providers/                # AuthProvider, CartProvider, OrderProvider…
│   ├── services/                 # api_client, socket, push, catalog_api…
│   ├── widgets/                  # map_tile_layer (Yandex), product_card…
│   ├── theme/app_theme.dart      # AppColors, AppShadows, AppRadii
│   └── config/                   # api_config, maps_config
│
├── backend/                      # Node 20 + Express
│   ├── prisma/
│   │   ├── schema.prisma         # 30+ моделей (User, Order, Shop, Product…)
│   │   ├── seed.js               # demo-данные (Korzinka, товары, зона)
│   │   └── dev.db                # SQLite для локали (gitignored)
│   ├── src/
│   │   ├── routes/               # auth, orders, shops, products, payments,
│   │   │                         # integration, geocode, telegram-auth…
│   │   ├── integrations/         # registry, custom-rest, iiko, poster
│   │   ├── jobs/                 # dispatch, scheduled, integration (BullMQ)
│   │   ├── services/             # pricing, dispatcher, notifications, sms
│   │   └── middleware/           # auth (JWT), rate-limit
│   ├── tests/                    # jest e2e + integration smoke
│   └── test_e2e_full.js          # 41-шаговый прогон сценария
│
├── infra/                        # Production-ready deploy stack
│   ├── docker-compose.yml        # Caddy + Node + Postgres + Redis
│   ├── Dockerfile.backend        # multi-stage Node 20 image
│   ├── Caddyfile                 # HTTPS auto, WebSocket, security headers
│   ├── .env.production.example   # все переменные с пояснениями
│   └── deploy.sh                 # idempotent bootstrap script
│
├── _design/
│   ├── master.html               # дизайн-исходник (35 экранов)
│   └── map_dark.json             # CartoDB Dark Matter (legacy)
│
├── admin-next/                   # Next.js админ-панель (WIP)
│
├── DEPLOY.md                     # пошаговая инструкция деплоя
├── E2E_REPORT.md                 # отчёт прогона тестов (41/41)
└── README.md                     # вы здесь
```

---

## ✅ Что уже работает

### 🔐 Аутентификация
- **Telegram login** через deep-link (`t.me/<bot>?start=<challenge>`) — primary метод. JWT access + refresh tokens, HMAC-проверка webhook'ов.
- **SMS OTP** как fallback для dev (`123456`) и тестинга, готов к подключению Eskiz.uz.
- **Multi-role**: один аккаунт может быть покупателем + курьером + менеджером ресторана. Переключение через role-switcher pill в нижнем доке.

### 🛒 Покупатель
- Splash → login → имя → home
- Home: lime-greeting, search-pill, чипы категорий, hero-card «★ Выбор редакции», лента ресторанов
- Catalog: 2-колонн grid с .catalog-card (lime add-button, fav heart, discount badge)
- Shop detail: 320-px warm hero sliver, glass info-card с 4-stat сеткой, cat-tabs, product-grid
- Product detail: 360-px hero + Playfair title + modifiers + qty-stepper + sticky lime CTA
- Cart → Order success (3 lime rings) → Tracking (Yandex dark map, courier socket pings, 4-step timeline) → Orders list
- Profile, addresses, payment methods, notifications

### 🚚 Курьер
- Telegram login → courier verification → /courier/home
- Available offers, accept-order with atomic claim (защита от гонки)
- Pickup → start → arrived → complete (FSM с 8 переходами)
- Earnings, instant payout (min 50k UZS), rating

### 🏪 Ресторан (B2B-grade)
- Master-design Shop Dashboard: revenue 2.4M, 42 заказа, средний чек, рейтинг
- Order queue с новыми / в работе / готовыми
- Product CRUD + Excel/CSV импорт
- **POS integrations** на `/shop/integration`:
  - **Custom REST** — stable, любой партнёр пишет 5 URL'ов в форму
  - **iiko Cloud** — beta, scaffold (отключается `MOCK_IIKO=0` после получения sandbox-ключей)
  - **Poster POS** — beta, scaffold
- AES-256-GCM шифрование credentials в БД
- Auto-sync меню каждые 15 минут (BullMQ scheduler)
- Webhook delivery с HMAC-подписью + exponential backoff retry (5×) + dead-letter

### 🛠 Backend
- Express + Prisma + Socket.IO + BullMQ + Redis
- Yandex Geocoder backend proxy (forward / reverse / suggest) с 24h LRU cache
- Real-time order updates через сокеты
- Loyalty points, tips, promo codes, referrals
- Multi-shop cart drafts (Phase 11)
- Delivery zones with polygon-in-point
- Order numbering (K-247 формат, sequential per shop)
- Atomic courier claim, dispatch batching

### 🚀 DevOps
- `infra/docker-compose.yml` — Caddy + Node + Postgres + Redis
- Auto-SSL через Let's Encrypt
- Multi-stage Dockerfile с non-root user + tini для graceful shutdown
- `deploy.sh` — idempotent bootstrap, генерит prod-secrets, перепривязывает Telegram webhook
- GitHub Actions: `flutter build web` + автокоммит обновлённого bundle

---

## 🔧 Stack

### Frontend (Flutter)
- **flutter** ^3.24, Dart 3.5
- **go_router** ^14 — навигация
- **provider** ^6.1 — state
- **flutter_map** ^7 + **latlong2** — карты (Yandex tiles)
- **dio** ^5 — HTTP
- **socket_io_client** ^2 — real-time
- **google_fonts** — Playfair Display + JetBrains Mono
- **cached_network_image** — кэш картинок товаров
- **flutter_secure_storage** — токены
- **image_picker**, **file_picker** — загрузка фото товаров
- **firebase_messaging** — push (готов к FCM ключу)

### Backend (Node 20)
- **express** + **express-rate-limit** + **helmet**
- **prisma** ^5 — ORM (SQLite в dev, Postgres в prod)
- **socket.io** ^4 — real-time
- **bullmq** ^5 — фоновые задачи
- **ioredis** — Redis клиент
- **jsonwebtoken** + **bcryptjs** — auth
- **multer** + **xlsx** — file upload + Excel import
- **pino** + **@sentry/node** — логирование + error tracking
- **dotenv** + **zod** — env validation

### Infra
- **Caddy 2.8** — reverse proxy + auto Let's Encrypt
- **Postgres 16-alpine** — main DB
- **Redis 7-alpine** — BullMQ + sockets + rate limits
- **Docker Compose** — оркестрация

---

## 🤝 Внешние сервисы

| Сервис | Статус | Назначение |
|---|---|---|
| **Telegram Bot** (`@Maximov_ai_bot`) | ✅ Работает | Аутентификация по deep-link |
| **Yandex Geocoder API** | ⏳ Ключ есть, ждёт активации сервиса | Адреса, autocomplete, reverse |
| **Yandex JS API** | ✅ Ключ есть | Карты в браузере (если понадобится) |
| **Yandex MapKit SDK** | ✅ Ключ есть | Native iOS/Android карты (будущее) |
| **Click / Payme / Uzum Pay** | ❌ Не подключено | Платежи (cash работает) |
| **Eskiz.uz** | ❌ Не подключено | SMS (Telegram заменяет) |
| **Firebase FCM** | ❌ Не подключено | Push-уведомления |
| **Sentry** | ❌ Не подключено | Error tracking |

---

## 🧪 Тестирование

```bash
# Backend e2e (полный сценарий 41 шаг)
node backend/test_e2e_full.js
# → buyer signup → address → catalog → order →
#   shop accept → ready → courier accept → pickup →
#   start → arrived → complete → buyer confirm →
#   loyalty → review → cancel-flow → dashboard

# Backend integration adapters smoke (15 шагов)
node backend/test_integration_adapters.js
# → custom REST + iiko mock + Poster mock — все три провайдера

# Jest (имеются падения после Phase 14 — см. issue tracker)
cd backend && npm test
```

См. [E2E_REPORT.md](backend/E2E_REPORT.md) для полного отчёта.

---

## 🗺 Roadmap

### 🟢 Закрытый beta (Сценарий A) — ~2-3 недели

- [ ] Развернуть staging на TimeWeb Cloud по `DEPLOY.md`
- [ ] Telegram bot webhook привязан к prod-домену
- [ ] Yandex Geocoder активирован (ждём на стороне Яндекса)
- [ ] Cart screen rewrite под master design (1643 строки)
- [ ] Courier screens × 5 под master
- [ ] Promo / Loyalty / Subscription / Support screens под master
- [ ] FCM push после получения Firebase ключей
- [ ] Sentry DSN после регистрации проекта
- [ ] 200+ jest-тестов на критическую логику
- [ ] Real iiko/Poster интеграция (`MOCK_IIKO=0`) после sandbox-доступа

### 🟡 Публичный запуск (Сценарий B) — ~3-5 месяцев

- [ ] Click / Payme / Uzum Pay контракты + интеграция реальных платежей
- [ ] Eskiz.uz SMS-провайдер контракт
- [ ] Юр.лицо в Узбекистане + ОФД фискализация
- [ ] Юрист: ToS, Privacy Policy, договоры с ресторанами/курьерами
- [ ] Apple Developer + Google Play аккаунты
- [ ] iOS / Android сборки + Store metadata + иконки
- [ ] Admin panel в `admin-next/` завершить
- [ ] Load testing + security audit
- [ ] Production-grade deployment (отдельно от staging)
- [ ] R-Keeper, 1С:Общепит POS-адаптеры

### 🔵 После запуска

- [ ] Чат покупатель ↔ курьер
- [ ] Расписание ежедневных доставок
- [ ] Программа лояльности с tier'ами (Бронза → Серебро → Золото → Платина)
- [ ] Open beta тестирование с 100 ресторанами
- [ ] Маркетинг + customer support

---

## 📊 Phase log

Хронология крупных вех проекта:

| Phase | Что |
|---|---|
| 1 — Foundation | Auth, базовые модели, JWT |
| 2 — Real-time | Socket.IO, dispatch worker, courier flow |
| 3 — Reviews | Отзывы магазин / курьер / товар |
| 4 — Pricing | DeliveryZone полигоны, surge factors |
| 5 — Multi-currency | UZS / KZT / KGS / RUB framework |
| 6 — Payments scaffold | Click / Payme / Uzum заглушки + saved methods |
| 7 — Multi-country | KZ / KG / RU markets |
| 8 — Courier payouts | Weekly + instant payout (admin-approved) |
| 9 — Social auth | Apple / Google (заменено на Telegram в Phase 15) |
| 10 — Group orders | Совместные заказы с друзьями |
| 11 — Multi-shop cart | Несколько drafts параллельно |
| 12 — Master Design v1 | Тёмный + лимонный, Playfair, JetBrainsMono, 35 экранов в `_design/master.html` |
| 13 — Mobile features | Phase 13 mobile-on-design wave |
| 14 — B2B integrations | Custom REST + iiko + Poster, scheduler, webhook delivery |
| 15 — Telegram + Yandex | Telegram auth, Yandex Geocoder, address autocomplete |
| **16 — Deploy stack** | `infra/`, `DEPLOY.md`, Docker Compose, Caddy auto-SSL |

---

## 🔐 Безопасность

- ✅ AES-256-GCM шифрование POS credentials (`infra/.env` → `INTEGRATION_ENC_KEY`)
- ✅ HMAC-SHA256 подпись Telegram webhook'ов + наших исходящих webhook'ов
- ✅ JWT с refresh-rotation (старый refresh blacklist'ится в Redis)
- ✅ Rate limits на OTP + login + global API
- ✅ HSTS / X-Frame-Options / Referrer-Policy через Caddy
- ✅ Non-root user внутри backend контейнера
- ✅ Все секреты в `.env` (gitignored), генерятся через `openssl rand`
- ✅ Внутренние сервисы (Postgres, Redis, Node) не торчат наружу — только Caddy

---

## 🤝 Контрибуции

Проект приватный. Если у вас есть доступ — workflow:

1. `git checkout -b feature/<short-name>`
2. Коммиты в conventional format: `feat: …`, `fix: …`, `refactor: …`
3. Push + PR в `main`
4. CI запускает Flutter build + backend jest
5. Merge — CI пересобирает `build/web` и автокоммитит

---

## 📞 Контакты

- **Repo**: [github.com/egeg23/tezketkaz](https://github.com/egeg23/tezketkaz)
- **Tech lead**: @egeg23
- **Issues**: [github.com/egeg23/tezketkaz/issues](https://github.com/egeg23/tezketkaz/issues)

---

## Лицензия

Proprietary. © 2026 TezKetKaz. Все права защищены.
