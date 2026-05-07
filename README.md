# TezKetKaz — доставка продуктов по Узбекистану

Полнофункциональное приложение в формате «один app, три роли» (покупатель / курьер / магазин) с бэкендом, real-time синхронизацией и готовой инфраструктурой к запуску.

## ☁️ Деплой одним кликом

| Платформа | Что нужно | Как |
|---|---|---|
| **Render** (рекомендуется) | бесплатно (засыпает после 15мин неактивности) | [Dashboard → Blueprints → подключить репо](https://dashboard.render.com/blueprints) — `render.yaml` уже в корне |
| **Railway** | $5/мес (не засыпает) | [railway.app/new](https://railway.app/new) → Deploy from GitHub → выбрать `tezketkaz` — `railway.json` подхватится |
| **Fly.io** | бесплатно | `fly launch` из корня — Dockerfile уже сконфигурирован |

После деплоя бэкенд раздаёт **API + web-приложение на одном URL**. Логины тестовые: `+998 90 123 45 67` / OTP `123456` (покупатель), `+998 91 234 56 78` (курьер), `+998 93 345 67 89` (магазин).

## 📱 Разработка с телефона

1. Установите [Claude Code mobile](https://apps.apple.com/app/claude/id6473753684) — войдите тем же аккаунтом
2. Привяжите этот репозиторий в настройках Claude
3. Делайте изменения в чате → коммит → push
4. **GitHub Actions** ([.github/workflows/build-web.yml](.github/workflows/build-web.yml)) автоматически пересобирает Flutter web и коммитит обратно
5. Render/Railway подхватывает push и редеплоит. Через ~3-5 мин обновлённый сайт доступен на постоянном URL.

## 📦 Что в репозитории

```
tezketkaz/
├── backend/              # Node.js + Express + Prisma + Socket.IO
│   ├── prisma/
│   │   ├── schema.prisma # Схема БД (PostgreSQL/SQLite)
│   │   └── seed.js       # Демо-данные
│   ├── src/
│   │   ├── routes/       # REST API endpoints
│   │   ├── sockets/      # Real-time события
│   │   ├── services/     # SMS, payments
│   │   └── middleware/   # JWT auth
│   └── Dockerfile
├── lib/                  # Flutter app (~8000 строк)
│   ├── config/           # API endpoints
│   ├── models/           # Domain models
│   ├── providers/        # State management (auth, cart, orders)
│   ├── services/         # API client, sockets
│   ├── screens/          # 21 экран
│   │   ├── auth/         # Login, OTP, name
│   │   ├── buyer/        # Каталог, корзина, трекинг
│   │   ├── courier/      # Заказы, активная доставка, заработок
│   │   ├── shop/         # Заказы магазина, история
│   │   └── shared/       # Role switcher, верификация
│   ├── theme/
│   └── widgets/
├── docker-compose.yml    # Один command для всего стека
└── README.md             # Этот файл
```

## 🚀 Запуск за 5 минут

### Вариант 1: через Docker (быстрее всего)

```bash
docker-compose up
```

Backend будет на `http://localhost:3000`, БД PostgreSQL на 5432, демо-данные засеются автоматически.

### Вариант 2: локально без Docker

```bash
# 1. Backend
cd backend
cp .env.example .env
npm install
npx prisma migrate dev --name init
npx prisma generate
node prisma/seed.js
npm run dev

# 2. Flutter (в другом терминале)
cd ..
flutter pub get
flutter run
```

## 📱 Тестовые аккаунты

| Роль        | Телефон               | OTP-код |
|-------------|----------------------|---------|
| Покупатель  | +998 90 123 45 67    | 123456  |
| Курьер      | +998 91 234 56 78    | 123456  |
| Магазин     | +998 93 345 67 89    | 123456  |

В режиме `NODE_ENV=development` любой OTP `123456` пропускается. SMS-шлюз работает в mock-режиме (логирует в консоль).

## 🔄 Как работает заказ end-to-end

```
1. Покупатель → /buyer/cart → "Buyurtma berish"
   ↓ POST /api/orders
2. Магазин получает push (Socket.IO 'order:new')
   → Видит как "🔔 Yangi" во вкладке "Yangi"
   ↓ POST /api/orders/:id/shop/accept
3. Магазин: "Qabul qilish" → автогенерация номера K-247
   → Покупатель видит "📦 Yig'ilmoqda"
   ↓ POST /api/orders/:id/shop/ready
4. Магазин собрал → "Tayyor ✓" с большим номером
   → ВСЕ онлайн курьеры получают 'order:available'
5. Курьер: "Qabul qilish" → переход на activeOrder
   ↓ POST /api/orders/:id/courier/accept
6. Курьер едет в магазин → "Do'konga yetib keldim"
7. Курьер вводит номер заказа K-247 → проверка совпадения
   ↓ POST /api/orders/:id/courier/pickup { orderNumber }
   → Если номер неверный — ошибка
8. Курьер везёт → "Yetib keldim" → "Topshirildi"
   ↓ POST /api/orders/:id/courier/complete
9. Покупатель: 🎉 "Yetkazildi" → может оценить
```

Все шаги обновляются в реальном времени через Socket.IO у всех участников.

## 🎨 Дизайн-система

| Роль     | Акцент-цвет         | Хекс       |
|----------|--------------------|------------|
| Покупатель | Зелёный (свежесть) | `#2ECC71`  |
| Курьер    | Оранжевый (скорость) | `#FF6B35` |
| Магазин   | Синий (надёжность) | `#3B5BDB`  |

## ✅ Чек-лист перед публикацией в App Store / Google Play

### 🇺🇿 Юридические шаги (Узбекистан)

- [ ] **Регистрация ООО** в Узбекистане (3-5 рабочих дней, ~3 млн сум)
  - https://birdarcha.uz — онлайн-регистрация
- [ ] **ОКЭД 53.20** — курьерская деятельность, или 47.99 — розничная торговля по интернету
- [ ] **СТИР (ИНН)** для юрлица — выдаётся при регистрации
- [ ] **Расчётный счёт** в Узбекском банке (Hamkorbank, Trustbank, Asia Alliance)
- [ ] **Уведомление в Налоговый комитет** о начале электронной торговли

### 🔑 Подключение внешних сервисов

#### SMS-шлюз (Eskiz.uz)
- [ ] Регистрация на https://my.eskiz.uz
- [ ] Подача документов о юрлице (KYC)
- [ ] Регистрация sender ID (~5 рабочих дней, ~500 000 сум за регистрацию)
- [ ] Заменить в `.env`:
  ```
  USE_MOCK_SMS=false
  ESKIZ_EMAIL=your@email.uz
  ESKIZ_PASSWORD=your_password
  ESKIZ_FROM=YOUR_SENDER_ID
  ```

#### Платёжные системы
- [ ] **Click** — https://click.uz/business
  - Договор с юрлицом, документы (~7 дней)
  - Получить `merchant_id` и `secret_key`
- [ ] **Payme** — https://business.payme.uz
  - Договор + интеграция через Subscribe API
- [ ] **Uzum Pay** — https://business.uzum.uz
  - Самые низкие комиссии (0% для бизнеса до 1 млрд сум/мес)
- [ ] Реализовать платёжные виджеты в `lib/services/payments/`
  - Mock-имплементация уже есть, нужно заменить на реальные SDK

#### Карты
- [ ] **2GIS API** — https://dev.2gis.com
  - Бесплатный тариф до 25 000 запросов/мес
  - Для большего трафика — платный план
- [ ] Заменить placeholder в `tracking_screen.dart` и `active_order_screen.dart` на `YandexMap` widget
- [ ] Добавить ключ в `lib/config/api_config.dart`

#### Push-уведомления
- [ ] **Firebase Cloud Messaging (FCM)** — бесплатно
  - Создать проект https://console.firebase.google.com
  - Настроить APNs ключ для iOS
  - Установить `firebase_messaging` Flutter плагин
  - В backend добавить отправку push при `order:new` для магазина

#### Налоговый комитет
- [ ] Подать заявку в Tax Committee на партнёрский API доступ для проверки СТИР курьера
- [ ] Альтернатива: принимать сканы справки о самозанятости вручную
- [ ] Заменить в `.env`: `USE_MOCK_TAX=false` + ключи

### 📱 Магазины приложений

#### App Store (iOS)
- [ ] Apple Developer Program ($99/год) — https://developer.apple.com/programs
- [ ] Создать App ID и Provisioning Profile
- [ ] Иконки 1024x1024, скриншоты для всех размеров (5.5", 6.5", 12.9")
- [ ] Privacy Policy URL (обязательно с октября 2024)
- [ ] App Tracking Transparency description
- [ ] App Review занимает 24-48 часов
- [ ] Соответствие политике гайдлайнам:
  - Реальные транзакции работают
  - Локализация на узбекский / русский / английский

#### Google Play (Android)
- [ ] Google Play Console ($25 разово) — https://play.google.com/console
- [ ] Загрузка signed `.aab` (App Bundle, не APK)
- [ ] Pre-launch report
- [ ] Privacy Policy + Data Safety декларация
- [ ] Возрастной рейтинг (для маркетплейса — 3+)
- [ ] Review занимает несколько часов — несколько дней

### 🛡️ Безопасность production

- [ ] Сменить `JWT_SECRET` на длинную случайную строку (минимум 64 символа)
- [ ] HTTPS обязательно — Let's Encrypt бесплатно
- [ ] Rate limiting на API (например `express-rate-limit`)
- [ ] Helmet.js для security headers
- [ ] Backup БД 2 раза в день минимум
- [ ] Sentry для error tracking — https://sentry.io

### 🔧 DevOps

- [ ] **Хостинг бэкенда:** Railway / Render / DigitalOcean ($5-20/мес)
- [ ] **БД:** Managed PostgreSQL (Supabase, Neon, Railway)
- [ ] **CDN для фото:** Cloudflare R2 / AWS S3
- [ ] **Мониторинг:** UptimeRobot (free) + Grafana
- [ ] **CI/CD:** GitHub Actions для автодеплоя
- [ ] **Domain:** `api.tezketkaz.uz` с SSL сертификатом

### 📊 Аналитика и продакт

- [ ] **Mixpanel / Amplitude** для событий пользователя (free tier)
- [ ] **Firebase Analytics** для общей аналитики
- [ ] **Crashlytics** для crash reports
- [ ] **AppsFlyer / Adjust** для трекинга маркетинговых каналов

## 🛣️ Roadmap после MVP

| Приоритет | Фича | Срок |
|-----------|------|------|
| 🔴 Критично | Реальные платежи Click/Payme | 2 недели |
| 🔴 Критично | 2GIS навигация для курьера | 1 неделя |
| 🟠 Важно   | Push-уведомления FCM | 1 неделя |
| 🟠 Важно   | Админ-панель (Flutter Web) | 3 недели |
| 🟠 Важно   | Программа лояльности (бонусы за заказы) | 2 недели |
| 🟢 Nice    | Чат покупатель↔курьер | 2 недели |
| 🟢 Nice    | Расписание ежедневных доставок | 2 недели |
| 🟢 Nice    | Узбекский язык интерфейса (сейчас смешанный) | 1 неделя |

## 📈 Финансовая модель (примерная)

**Юнит-экономика на заказ:**
- Средний чек: 80 000 сум
- Комиссия с магазина: 15% = 12 000 сум
- Доставка с покупателя: 12 000 сум
- **Доход с заказа: 24 000 сум**
- Курьер получает: 12 000-18 000 сум
- Платёжная комиссия: ~2% от чека = 1 600 сум
- **Маржа: 4 400-10 400 сум за заказ**

**Чтобы выйти в плюс при $50k/мес операционных расходов:**
- Нужно ~700 заказов в день
- При 5000 активных пользователей x 4 заказа/мес = 20 000 заказов/мес = ~660/день ✓

## 🤝 Поддержка

Все типичные кейсы покрыты в коде с TODO-комментариями. Прочитайте:
- `lib/services/api_client.dart` — error handling pattern
- `backend/src/routes/orders.js` — state machine заказа
- `backend/src/sockets/index.js` — комнаты для real-time

## Лицензия

Proprietary. Все права защищены.
