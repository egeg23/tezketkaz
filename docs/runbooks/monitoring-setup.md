# Monitoring Setup Runbook

Пошаговое руководство по настройке production-мониторинга TezKetKaz.
После прохождения этого документа у вас должны быть:

- Sentry (ошибки + performance) на бэкенде и в Flutter-приложении.
- Grafana (или Hosted Prometheus) с дашбордами и алертами.
- UptimeRobot (или BetterUptime) с проверкой `/healthz` каждые 5 минут.
- Slack-канал `#alerts` с уведомлениями от всех трёх систем.

Время выполнения: ~3 часа при первой настройке, ~30 минут при повторной
(для нового окружения).

> Цены, упомянутые ниже, **приблизительные** на 2026 год. Уточняйте на
> сайтах сервисов перед закупкой — тарифы меняются.

---

## 1. Sentry — ошибки и performance

В коде Sentry уже частично настроен:
- Бэкенд: `backend/src/lib/sentry.js` (Express integration).
- Мобильный: `lib/services/sentry_service.dart` (Flutter SDK).

Осталось создать project в Sentry и прописать DSN в env.

### 1.1 Создать проекты

1. Зарегистрироваться на `https://sentry.io` (бесплатный тариф — 5k events/mo).
2. Создать организацию `tezketkaz`.
3. Создать два проекта:
   - **Platform:** Node.js → name `tezketkaz-backend`.
   - **Platform:** Flutter → name `tezketkaz-mobile`.
4. Скопировать **DSN** обоих проектов (выглядит как
   `https://<key>@oXXXXXX.ingest.sentry.io/YYYYYY`).

### 1.2 Прописать env vars

На хостинге бэкенда (Render / Railway / Fly):

```
SENTRY_DSN=https://...@oXXX.ingest.sentry.io/YYY
SENTRY_ENVIRONMENT=production       # или staging
SENTRY_TRACES_SAMPLE_RATE=0.1       # 10% трассировок (см. §1.3)
SENTRY_RELEASE=tezketkaz@<git-sha>  # обновляется CI на каждом деплое
```

Для Flutter-приложения — в `lib/config/env.dart` либо через
`--dart-define` при сборке:

```bash
flutter build apk --release \
  --dart-define=SENTRY_DSN=https://...@oXXX.ingest.sentry.io/ZZZ \
  --dart-define=SENTRY_ENVIRONMENT=production
```

### 1.3 Recommended sample rates

| Окружение | Traces | Errors |
|---|---|---|
| Production | 0.1 (10%) | 1.0 (100%) |
| Staging | 0.5 (50%) | 1.0 (100%) |
| Dev / test | 0 | 0 |

Почему 10% трассировок в проде — Sentry free tier даёт 10k transactions/мес.
При 100k запросов/день нужен sampling. 10% — достаточно для percentile-метрик
и одновременно остаётся в бюджете.

### 1.4 Source map upload

Скрипт уже существует: `backend/scripts/upload-sourcemaps.sh`. Вызывается
из CI после успешной сборки:

```yaml
# .github/workflows/deploy.yml (фрагмент)
- name: Upload source maps to Sentry
  env:
    SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
    SENTRY_ORG: tezketkaz
    SENTRY_PROJECT: tezketkaz-backend
    SENTRY_RELEASE: tezketkaz@${{ github.sha }}
  run: bash backend/scripts/upload-sourcemaps.sh
```

Для Flutter — `sentry-cli` через `flutter_sentry` plugin (см.
`pubspec.yaml` `sentry_flutter`). Команда:

```bash
sentry-cli upload-dif \
  --org tezketkaz \
  --project tezketkaz-mobile \
  build/app/intermediates/merged_native_libs/release/out/lib
```

Без source map'ов stack trace'ы из minified-кода нечитаемы.

### 1.5 Alert rules

В Sentry → Alerts → Create Alert:

| Rule | Условие | Action |
|---|---|---|
| **Error rate spike** | event count >5/min для текущего release-tag | Slack `#alerts` + PagerDuty |
| **New error type** | новый Issue впервые появляется в проде | Slack `#alerts` |
| **Performance regression** | p95 latency для transaction `GET /api/shops` вырастает >1.5x от 7-day baseline | Slack `#alerts` |
| **Quota approaching** | >80% месячного квота events | Email + Slack |

### 1.6 Slack integration

Sentry Slack app: `https://sentry-slack.com/install` →
- Authorize: workspace TezKetKaz.
- Subscribe `#alerts` к: tezketkaz-backend issues + tezketkaz-mobile issues.

После установки в alert rule выбирается `Send to Slack → #alerts`.

### 1.7 Performance budgets

Целевые значения, при нарушении которых триггерятся алерты:

| Метрика | Бюджет |
|---|---|
| Backend p95 response time (любой роут) | <500 мс |
| Backend p95 response time (`POST /api/orders`) | <800 мс |
| Backend p99 response time | <1500 мс |
| Mobile cold start (Flutter, mid-range Android) | <3 сек |
| Mobile warm start | <1 сек |
| Mobile API call p95 (через сеть 4G) | <2 сек |

При просадке — алерт + investigate в течение дня (не emergency,
но обязательно к разбору).

---

## 2. Grafana Cloud (или self-hosted Prometheus)

### 2.1 Setup Grafana Cloud (рекомендованный путь — free tier)

1. Зарегистрироваться на `https://grafana.com/auth/sign-up/create-user`.
2. Free tier даёт: 10k series в Prometheus, 50GB логов, 50GB трейсов.
   Для нагрузки 1k DAU — достаточно. **Approximate** $0/mo, upgrade
   до Pro ~$8/user/mo when crossing limits.
3. Создать stack `tezketkaz`. Получить:
   - Prometheus endpoint: `https://prometheus-prod-XX.grafana.net/api/prom`
   - Username (numeric stack ID).
   - API key (Editor / MetricsPublisher role).

### 2.2 Backend `/metrics` endpoint

> **Зависимость:** требуется `prom-client` npm package. **Не добавляем
> сейчас** — только если бизнес выберет Grafana. Альтернатива без
> dependency: парсить `pino` логи в Loki (см. §6).

Если решили включать — отдельный PR:

```js
// backend/src/routes/metrics.js (если будет принято решение)
const promClient = require('prom-client');
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

// HTTP request histogram
const httpDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.05, 0.1, 0.25, 0.5, 1, 2, 5],
});
register.registerMetric(httpDuration);

router.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.send(await register.metrics());
});
```

### 2.3 Scrape config

В Grafana Cloud → Connections → "Hosted Prometheus" → Scrape Config:

```yaml
scrape_configs:
  - job_name: tezketkaz-backend
    scrape_interval: 30s
    metrics_path: /metrics
    scheme: https
    basic_auth:
      username: tezketkaz-metrics
      password_file: /run/secrets/metrics-password
    static_configs:
      - targets: ['api.tezketkaz.uz']
```

Защитить `/metrics` basic-auth'ом (env `METRICS_USERNAME`, `METRICS_PASSWORD`)
или ограничить по IP (Grafana Cloud egress IPs документированы).

### 2.4 Дашборды (минимум 3)

#### Backend dashboard

Панели:
- **RPS** (requests/sec) — общая нагрузка.
- **Error rate** (5xx / total) — по роуту.
- **Response time** (p50 / p95 / p99) — по роуту.
- **DB connection pool** — `pg_pool_idle`, `pg_pool_active`, `pg_pool_waiting`.
- **Queue depth** — `bullmq_dispatch_pending`, `bullmq_payouts_pending`.
- **Active users** — distinct user_id за 5 минут (если трекаем).

JSON-экспорт дашборда хранить в `ops/grafana/backend-dashboard.json`
для воссоздания.

#### Mobile dashboard

Из Sentry Performance + Crashlytics экспорт в Grafana:
- **Crash rate** (% сессий с крэшем) — daily.
- **Slow renders** (UI frames >16ms) — daily.
- **ANR rate** (Android) — daily.
- **Cold start time** p95.
- **API call success rate** (с устройств).

#### Business dashboard

Метрики, которые волнуют бизнес, не инженеров. Берутся прямыми SQL-запросами
к БД (Grafana Postgres datasource, read-only user).

- **Orders/hour** — последние 24 часа.
- **GMV** (gross merchandise value) — сегодня vs вчера.
- **Courier utilization** — % курьеров с >5 заказами в смену.
- **Conversion** — order_completed / order_created.
- **Avg basket** — сред. чек.
- **Acceptance rate** — accepted / offered (на курьерской стороне).

### 2.5 Alert rules (Grafana)

| Алерт | Условие | Severity |
|---|---|---|
| **Backend down** | `up{job="tezketkaz-backend"} == 0` for 2m | P0 |
| **Error rate spike** | `rate(http_requests_total{status=~"5.."}[5m]) > 0.05` | P1 |
| **Queue backup** | `bullmq_dispatch_pending > 100` for 5m | P1 |
| **DB pool exhaustion** | `pg_pool_waiting > 5` for 2m | P1 |
| **Slow endpoint** | `histogram_quantile(0.95, http_request_duration_seconds) > 1` for 10m | P2 |
| **Courier coverage gap** | в зоне X нет онлайн-курьеров >30 минут в пиковые часы | P2 |
| **Orders/hour drop** | orders/hour <50% от среднего за 7 дней (sudden drop) | P1 |

Notification channel: Slack webhook → `#alerts`.

---

## 3. UptimeRobot / BetterUptime

External uptime check — на случай если приложение само не может алертить.

### 3.1 UptimeRobot (free tier)

`https://uptimerobot.com/` — free tier даёт 50 мониторов / 5-min interval.

Создать 4 монитора:

| Name | URL | Type | Interval |
|---|---|---|---|
| **API healthz** | `https://api.tezketkaz.uz/healthz` | HTTPS, expect 200 + body contains `"status":"ok"` | 5 min |
| **API home** | `https://api.tezketkaz.uz/` | HTTPS, expect 200 | 5 min |
| **Landing** | `https://tezketkaz.uz` | HTTPS, expect 200 | 5 min |
| **Admin** | `https://admin.tezketkaz.uz` | HTTPS, expect 200 | 5 min |

### 3.2 BetterUptime (альтернатива)

`https://betterstack.com/uptime` — free tier 10 мониторов, более красивый
UI, status-page бесплатно. **Approximate** $18/mo за upgrade.

### 3.3 Notification

Из UptimeRobot → Integrations:
- **Slack:** webhook → `#alerts`.
- **SMS:** премиум, ~$3/mo за 50 SMS. Только для P0 (sent when 2 consecutive
  checks fail = ~10 min downtime).
- **Email:** дежурный + `@tech-lead`.

### 3.4 Maintenance windows

Перед запланированным окном (§9 в `change-management.md`):
UptimeRobot → Maintenance Window → schedule на 03:00–05:00 UTC+5.
Иначе на пустом месте просядут метрики аптайма.

---

## 4. Бэкенд `/healthz` endpoint

Эндпоинт уже добавлен в `backend/src/routes/health.js` (см. также
`/health`, `/ready`, `/version`).

### 4.1 Поведение

```bash
curl https://api.tezketkaz.uz/healthz
```

Ответ (200 OK при здоровье):
```json
{
  "status": "ok",
  "db": "connected",
  "redis": "connected",
  "queues": "running"
}
```

Ответ (503 при проблеме):
```json
{
  "status": "degraded",
  "db": "error: timeout after 2000ms",
  "redis": "connected",
  "queues": "running"
}
```

### 4.2 Что проверяется

- **db:** `SELECT 1` с таймаутом 2 сек.
- **redis:** `PING` с таймаутом 2 сек. `"disabled"` если Redis отключён
  (dev/test) — не считается ошибкой.
- **queues:** статус BullMQ — `running` (Redis активен + воркеры стартанули),
  `disabled` (Redis выключен).

### 4.3 Эндпоинты-родственники

- **`/health`** — liveness probe. Возвращает 200 если процесс жив.
  Используется Kubernetes / Docker healthcheck. Не делает внешних вызовов.
- **`/ready`** — readiness probe. Делает БД + Redis check, возвращает
  503 при проблеме. Используется Kubernetes для решения «направлять ли
  трафик».
- **`/healthz`** — operator-friendly aggregated check (этот эндпоинт).
  Используется UptimeRobot и людьми.
- **`/version`** — build metadata. `{ commit, version, startedAt }`.

### 4.4 Что НЕ покрывается

- Здоровье внешних провайдеров (Click, Payme, Soliq, Eskiz) — отдельные
  алерты на error rate в `/api/payments/*` через Sentry / Grafana.
- FCM delivery (см. §7).
- Здоровье воркеров — `queues: running` показывает, что Redis активен, но
  не гарантирует, что воркеры действительно обрабатывают задачи. Для этого
  нужны метрики через `prom-client`.

---

## 5. Логи: pino → stdout → агрегатор

### 5.1 Текущее состояние

Бэкенд логирует через `pino` (см. `backend/src/lib/logger.js`) в stdout.
Render / Railway / Fly автоматически собирают stdout и хранят в своём
log viewer.

Формат — JSON, одна строка на запись:
```json
{"level":30,"time":1736900000000,"pid":1,"hostname":"...","reqId":"abc",
 "msg":"← POST /api/orders 200"}
```

### 5.2 Просмотр в дашборде хостинга

```bash
# Render
render logs -s tezketkaz-api --tail
# Railway
railway logs --service tezketkaz-api --tail
# Fly
flyctl logs -a tezketkaz-api
```

### 5.3 Опциональный форвард в Logtail / Datadog

Render / Railway / Fly умеют форвардить stdout в:
- **Logtail (BetterStack)** — free 1GB/mo, **approximate** $20/mo paid.
- **Datadog Logs** — **approximate** $0.10/GB ingest, $0.10/M index events.
- **Grafana Loki** — если уже на Grafana Cloud, входит в free 50GB/mo.

Стоит подключать когда:
- Нужен поиск по логам за период >24 часа (хостинги обычно хранят 24–72ч).
- Нужны алерты на pattern'ы (например, «5+ raise of `'PRISMA_CLIENT'`
  errors в минуту»).
- Нужен audit trail >30 дней (compliance).

Для пилота — можно отложить, обходиться встроенными логами хостинга.

---

## 6. Mobile crash reporting

Sentry Flutter SDK уже подключён в `lib/services/sentry_service.dart` и
инициализируется в `main.dart`.

### 6.1 Что отслеживается автоматически

- Uncaught exceptions (Dart errors).
- Native crashes (через `sentry_flutter` integration).
- ANR (Application Not Responding) — Android.
- Slow / frozen frames.
- HTTP request errors (через interceptor).

### 6.2 Что нужно проверить вручную при настройке

- [ ] DSN прописан через `--dart-define=SENTRY_DSN=...`.
- [ ] `environment` выставлен в `production` для release-сборок.
- [ ] Test event отправлен — `Sentry.captureMessage('test from $platform')`.
- [ ] Видим event в Sentry → tezketkaz-mobile → Issues.
- [ ] Symbol upload работает (см. §1.4).
- [ ] User context включён (без PII — только `id`).
- [ ] Breadcrumbs включены: navigation events + API calls.

### 6.3 Альтернативный: Firebase Crashlytics

Уже частично интегрирован (см. `firebase-prod-setup.md`). Можно использовать
параллельно с Sentry — Crashlytics силён в native crashes, Sentry — в
detailed traces + performance. Дубликаты не страшны (events дешёвые на
free tier обоих сервисов).

---

## 7. Push notification delivery rate (FCM)

### 7.1 Дашборд FCM

Firebase Console → tezketkaz → Engage → Messaging → Reports.

Метрики, на которые смотреть:
- **Delivery rate** — % успешно доставленных push.
  - Цель: **>97% в пределах 5 минут** для high-priority messages.
- **Send rate** — сколько отправляем.
- **Open rate** — сколько открыто из доставленных (информативно, не алерт).

### 7.2 Когда тревожиться

- Delivery rate <90% подряд 2 дня — расследовать (FCM token expired
  массово? проблема на стороне Android FCM?).
- Send rate резко падает — баг в нашем backend (queue не разгребается?).

Алерт можно добавить в Grafana, если будем экспортировать FCM API:
```
GET https://fcmdata.googleapis.com/v1/projects/<project>/reports
```
(требует service account с `firebase.messaging.viewer`).

### 7.3 Мобильный side

В приложении:
- `lib/services/fcm_service.dart` — регистрация токена при логине,
  обновление при ротации.
- Backend stores tokens in `User.fcmTokens[]` — удаляем при логауте.
- Каждые 30 дней — рефреш токенов (FCM деактивирует неактивные).

---

## 8. Costs (приблизительно, 2026)

| Сервис | Free tier | Upgrade trigger |
|---|---|---|
| **Sentry** | 5k events/мес (~1k DAU при средней error rate) | ~$26/mo за 50k events |
| **Grafana Cloud** | 10k series, 50GB logs/traces | ~$8/user/mo при превышении |
| **UptimeRobot** | 50 мониторов / 5-min interval | ~$7/mo за 1-min interval |
| **BetterUptime** | 10 мониторов | ~$18/mo за upgrade |
| **Logtail** | 1GB logs/мес | ~$20/mo за 10GB |
| **Firebase** | Spark plan = free для FCM, ограничения на Functions/Storage | Blaze (pay as you go) |

> Числа **approximate** по состоянию на 2026 год. Перепроверять на сайтах
> сервисов перед закупкой / при планировании бюджета.

---

## 9. Мониторинг расходов

### 9.1 Месячный review (1-е число каждого месяца)

- [ ] **Cloudflare** — DNS / CDN. Обычно <$5/mo на pro plan.
- [ ] **Render / Railway / Fly** — бэкенд + БД. По нагрузке: pilot
      ~$30–80/mo, после roll-out может вырасти до $200–500/mo.
- [ ] **Neon** — Postgres. Free до 0.5GB, pro $19/mo + usage.
- [ ] **Redis** (Upstash или Render) — pilot $0–10/mo.
- [ ] **R2 / S3** — image storage. R2 zero egress, ~$0.015/GB stored.
- [ ] **Sentry** — см. §8.
- [ ] **Grafana Cloud** — см. §8.
- [ ] **Firebase** — обычно <$5/mo на pilot.
- [ ] **Eskiz SMS** — основной OTP-провайдер UZ. ~80–200 сум за SMS,
      зависит от объёма OTP.
- [ ] **Resend** — email. Free до 100/день, $20/mo за 50k/мес.

Итого pilot — **approximate** $150–300/mo. После 5k DAU — **approximate**
$500–1500/mo.

### 9.2 Cap alerts (защита от runaway costs)

Везде, где провайдер поддерживает:
- **Hard cap** на месячный спенд — Render Spending Limit, Neon usage cap,
  Firebase Blaze budget alert. Если превышено — провайдер останавливает
  биллингуемые услуги, не списывает дальше.
- **Soft alert** на 50% / 80% / 100% от месячного бюджета — email + Slack.

Без этого: одна забытая cron-job, генерящая 10k push'ей в час, может
сжечь месячный бюджет за день.

---

## 10. Чеклист первой настройки

При деплое в новое окружение (staging / production / новый регион):

- [ ] Sentry projects созданы (backend + mobile), DSN прописаны в env.
- [ ] Sentry source map upload работает в CI.
- [ ] Sentry alert rules настроены (error spike, new error, perf
      regression).
- [ ] Sentry Slack integration подключена.
- [ ] Grafana stack создан (если выбрали Grafana).
- [ ] Grafana scrape config настроен → metrics приходят.
- [ ] Grafana дашборды импортированы (backend, mobile, business).
- [ ] Grafana alert rules настроены.
- [ ] UptimeRobot мониторы созданы (healthz + landing + admin).
- [ ] UptimeRobot Slack integration подключена.
- [ ] UptimeRobot SMS подключён (только для P0).
- [ ] `/healthz` отвечает 200 в проде.
- [ ] FCM dashboard проверен — delivery rate >97%.
- [ ] Cap alerts настроены у всех биллингуемых провайдеров.
- [ ] `#alerts` канал создан + правильные люди подписаны.
- [ ] On-call rotation календарь в Notion обновлён.

После прохождения — записать дату и автора:
```
Configured: YYYY-MM-DD by @имя
Re-verified: YYYY-MM-DD by @имя
```

---

## 11. Регулярные проверки

| Что | Как часто | Кто |
|---|---|---|
| Sentry quota не приближается к лимиту | еженедельно | ops-on-call |
| Grafana dashboards грузятся, нет broken panels | еженедельно | ops-on-call |
| UptimeRobot — все мониторы зелёные за последние 7 дней | еженедельно | ops-on-call |
| `/healthz` отвечает 200 (вручную) | ежедневно (можно скриптом) | ops-on-call |
| FCM delivery rate >97% | ежедневно | ops-on-call |
| Cost review (см. §9.1) | ежемесячно | tech lead + finance |
| Test backup restore (см. `disaster-recovery.md`) | ежемесячно | ops-on-call |
| Алерты не «зашумлены» (>5 ложных в неделю → тюнинг) | ежемесячно | ops-on-call |

---

## 12. Когда что-то не работает

- **Sentry events не приходят:** проверить DSN env var, network reachability
  (`curl -X POST $SENTRY_DSN/api/X/store/`); проверить sample rate (0 → ничего
  не отправляется).
- **Grafana показывает «No data»:** проверить scrape — Grafana → Explore →
  query `up{job="tezketkaz-backend"}`. Если `up == 0` — Prometheus не
  достучался до `/metrics`. Если series нет совсем — basic auth неверный.
- **UptimeRobot ложно срабатывает:** проверить, что `/healthz` действительно
  возвращает 200; проверить, что не попали в случайный 429 (rate-limit) —
  `/healthz` смонтирован до rate-limiter в `backend/src/index.js`.
- **Алерт пришёл, но в Slack ничего:** integration token expired — пересоздать.

См. также `incident-response.md` для общей процедуры реагирования на
любые алерты.
