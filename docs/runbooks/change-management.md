# Change Management Runbook

Стандартная операционная процедура для **production changes** в TezKetKaz:
деплои бэкенда, миграции БД, изменения конфигов, релизы мобильного клиента.

Цель: уменьшить число инцидентов «деплой сломал прод» (см.
`incident-response.md`). Любое изменение в продакшене проходит через эту
процедуру — без исключений, кроме явных emergency hotfix (§10).

---

## 1. Типы изменений

| Тип | Риск | Примеры | Approval |
|---|---|---|---|
| **Standard** | низкий | UI-tweak (цвет, текст), исправление одного теста, обновление документации, копирайт. | 1 reviewer (любой engineer). |
| **Normal** | средний | новая фича, многофайловый backend-change, миграция БД, новый API endpoint, обновление зависимости. | 2 reviewers + ops on-call signoff. |
| **Emergency** | высокий, но **уже** в проде | hotfix для P0/P1 инцидента, security-патч. | Post-hoc: деплоим сейчас, документируем потом (§10). |

> Если сомневаетесь, какого типа изменение — берите **на ступень выше**.
> Лучше лишний approval, чем сломанный прод.

---

## 2. Требования к PR-описанию

Каждый PR на main (или production-branch) должен включать **все** секции
ниже. Шаблон находится в `.github/pull_request_template.md`; если его нет —
скопируйте из шаблона в конце этого документа (§13).

### 2.1 Summary
1–3 предложения, что меняется и зачем. Без копирования diff.

### 2.2 Test plan
Чек-лист того, что протестировано:
- [ ] Unit / integration тесты прошли локально.
- [ ] Покрыт ли новый код тестами?
- [ ] Ручная проверка staging (если применимо).
- [ ] Smoke-test (`smoke-tests.md`) после деплоя.

### 2.3 Risk assessment

- Кто из пользователей затронут? (все / только курьеры / только новые
  регистрации / только Узбекистан / ...)
- Что может пойти не так?
- Backwards compatibility: совместимо ли с предыдущей версией мобильного
  клиента?
- Зависимости: трогает ли платежи, авторизацию, БД-схему?

### 2.4 Rollback plan

**Обязательно**. Минимум один абзац:
- Как откатить, если деплой сломает прод? (re-deploy previous tag / revert
  migration / flip feature flag)
- Сколько времени займёт rollback?
- Есть ли необратимые изменения (например, DROP COLUMN)? Если да —
  Normal change с явным CTO-approval.

### 2.5 Monitoring plan

Что смотреть после деплоя в течение первых 30 минут:
- Какие Grafana-дашборды (по имени).
- Какие Sentry-фильтры (release-tag).
- Какие метрики ожидаемо изменятся (например, «увеличится p95 на 50мс из-за
  новой DB-проверки — это ожидаемо»).

---

## 3. Pre-deploy checklist

Перед нажатием «Deploy» (или мёрджем в `main`):

### 3.1 Standard change
- [ ] CI зелёный (все 560+ backend-тестов, Flutter analyze, lint).
- [ ] Один reviewer approved.
- [ ] Нет миграций БД.

### 3.2 Normal change
- [ ] CI зелёный.
- [ ] 2 reviewers approved.
- [ ] Ops on-call signoff в PR (комментарий «ops-ok @имя»).
- [ ] Smoke-test на staging прошёл (`SMOKE_BASE_URL=https://staging.api.tezketkaz.uz node backend/scripts/smoke-test.js`).
- [ ] Если миграция: проверить, что применяется к staging-БД без ошибок
      (`cd backend && DATABASE_URL=$STAGING_URL npx prisma migrate deploy`).
- [ ] Все последние миграции применены в проде (нет «свежих» миграций
      от других PR, ждущих деплоя).
- [ ] Time-of-day: не вечером пятницы, не перед обедом (когда пик трафика).
- [ ] Уведомление в `#deploys` за 10 минут: «деплою PR #N через 10 мин».

### 3.3 Emergency change
- [ ] См. §10.

---

## 4. During-deploy checklist

Во время выкатки (обычно 2–5 минут rolling deploy):

- [ ] **Терминал 1: tail логов** на хосте.
      ```bash
      # Render
      render logs -s tezketkaz-api --tail
      # Railway
      railway logs --service tezketkaz-api
      # Fly
      flyctl logs -a tezketkaz-api
      ```
- [ ] **Терминал 2: Sentry → Releases → текущий тег**. Окно с auto-refresh.
- [ ] **Терминал 3: Grafana → «Backend Overview»** дашборд (см.
      `monitoring-setup.md`).
- [ ] Замечаем всплеск ошибок >X3 от базовой линии → **немедленно
      rollback**. Не «подождём, может пройдёт». Среднее время от деплоя
      до полного rollback должно быть <2 минут.

### Полезные алерты во время деплоя
- Sentry: фильтр `release:<tag> AND level:error`.
- Grafana: панель «Error rate by route» — высматриваем новые 500s на
  конкретных роутах.
- БД connection pool: если деплой использует Prisma с другой версией —
  старые поды могут не отдать соединения.

---

## 5. Post-deploy checklist

В течение 30 минут после успешной выкатки:

- [ ] **Smoke-test против прода** (`SMOKE_BASE_URL=https://api.tezketkaz.uz
      node backend/scripts/smoke-test.js`). Должен пройти за <30 секунд.
- [ ] **Error rate**: смотрим Grafana «Error rate (last 30 min)». Должен
      быть в пределах baseline ±20%.
- [ ] **p95 latency**: не выше baseline +50мс. Если выше — расследуем
      (новый код медленнее ожидаемого?).
- [ ] **Sentry new issues**: 0 новых типов ошибок. Любая новая ошибка —
      потенциальный регресс.
- [ ] **Healthcheck**: `curl https://api.tezketkaz.uz/healthz` → 200,
      `{ status: 'ok', db: 'connected', redis: 'connected', queues: 'running' }`.
- [ ] **Обновить статус в `#deploys`**: `:white_check_mark: PR #N deployed,
      monitoring 30 min`.
- [ ] Через 30 минут: `:white_check_mark: PR #N stable, closing watch`.

---

## 6. Правила миграций БД

Миграции — самая частая причина инцидентов после деплоев. Правила
жёсткие, но именно они защищают.

### 6.1 Backwards compatibility (обязательно)

Каждая миграция должна быть **совместима с предыдущей версией приложения**
(rolling deploy assumption — во время выкатки одновременно работают
N-1 и N версии бэкенда).

- ✅ ADD COLUMN с DEFAULT / NULL — безопасно.
- ✅ ADD INDEX CONCURRENTLY — безопасно (на Postgres).
- ✅ ADD TABLE — безопасно.
- ⚠️ RENAME COLUMN — **запрещено в одну фазу**. Старый код упадёт.
       Делается в 2 фазы: добавить новую колонку + код пишет в обе → дроп
       старой в следующем релизе.
- ❌ DROP COLUMN — **2-фазный релиз** (см. §6.4).
- ❌ ALTER COLUMN с NOT NULL без DEFAULT на непустой таблице — упадёт.
- ❌ Изменение типа колонки на несовместимый — отдельный деплой с
       data migration.

### 6.2 Длинные миграции (>10 секунд)

Длинная миграция = блокировка таблицы = downtime.

- Если можно без блокировки (например, ADD INDEX CONCURRENTLY) — используем.
- Если нельзя — переносим на **maintenance window** (§9), уведомляем
  пользователей за 24 часа.
- Альтернатива: batched migration — миграция в фоне небольшими порциями
  через cron job, без блокировки.

### 6.3 Тестирование миграции

Перед мёрджем PR с миграцией:

```bash
# Локально на копии production-схемы
cd backend
DATABASE_URL=$LOCAL_DB npx prisma migrate dev

# Staging
DATABASE_URL=$STAGING_DB npx prisma migrate deploy

# Дополнительная проверка backward-compat: накатываем миграцию, потом
# делаем smoke-test предыдущей версии приложения на ту же БД.
git checkout <previous-prod-tag>
SMOKE_BASE_URL=https://staging.api.tezketkaz.uz node backend/scripts/smoke-test.js
git checkout -
```

### 6.4 DROP COLUMN — 2-фазный процесс

**Фаза 1** (релиз N):
- Перестать читать колонку в коде.
- Перестать писать в колонку.
- НЕ дропать миграцией.
- Деплоить. Подождать минимум 7 дней (или один релизный цикл мобильного
  клиента — какой больше).

**Фаза 2** (релиз N+1):
- Миграция: DROP COLUMN.
- Деплоить.

Если торопимся — **не дропаем колонку**. Цена 7 дней ожидания меньше,
чем стоимость инцидента.

---

## 7. Config-only changes

Изменение переменной окружения / feature flag — формально это тоже change.

### 7.1 Когда нужен restart

| Тип изменения | Restart? |
|---|---|
| ENV var, читаемый при boot (`env.js`) | **Да** — restart обязателен. |
| Feature flag в БД (`feature_flags` table) | Нет — берётся при каждом запросе. |
| Изменение в `legal/*.md` (privacy/ToS) | Нет — кеш `legalCache` сбрасывается через `/api/admin/legal/refresh`. |
| Rotation секрета (JWT, HMAC) | **Да** — restart всех инстансов одновременно (иначе часть запросов будет с новым ключом, часть со старым). |
| Изменение `FRONTEND_URL` / CORS | **Да**. |
| Изменение rate-limit | **Да** (читается при старте). |

### 7.2 Документировать в PR

Каждое изменение конфига коммитим как PR с обновлением `.env.example`
(или `ops/env-prod.md`, если такой файл заведём) **И** комментом:
«deployed YYYY-MM-DD HH:MM by @имя; restarted: yes/no».

### 7.3 Rotation секретов

Особый кейс — секреты ротируются с **двойным окном**:

1. Добавить новый секрет в `ENV_NEW`, оставив `ENV_OLD` активным. Код
   проверяет оба.
2. Деплой → подождать 24 часа → проверить, что ничего не валится по
   `ENV_OLD`.
3. Удалить `ENV_OLD`. Деплой.

Касается: JWT secrets, HMAC (Click / Payme / Uzum / Kaspi callbacks),
Soliq token, FCM service account.

---

## 8. Approval matrix

Кто что approve'ит. **Этот список — закон**, не «гайдлайн». Если
сомневаетесь — спросите вместо того, чтобы пушить.

| Зона | Approve | Notes |
|---|---|---|
| Standard frontend change | любой Engineer | 1 reviewer |
| Standard backend change | любой Engineer | 1 reviewer |
| Normal backend change | 2 Engineers | + ops-on-call signoff |
| Schema migration | 2 Engineers, один из них Senior+ | + DBA-on-call если есть |
| Admin role / RBAC | Senior Engineer + CTO | RBAC = security critical |
| Payment service touch (Click / Payme / Uzum / Kaspi) | Payment lead + 1 Engineer | + smoke-test обязателен |
| Secrets rotation | CTO | log в `ops/rotations.md` |
| Auth / OTP flow | Security lead + CTO | + manual QA на 3 устройствах |
| Dependencies bump (major) | Senior Engineer | + full test run |
| Dependencies bump (minor/patch) | любой Engineer | автоматический Dependabot OK |
| Feature flag flip in prod | ops-on-call | log в `#deploys` |
| Emergency hotfix | named CTO/lead approver | post-hoc PR в течение 24ч (§10) |

---

## 9. Rollback procedures

Что и как откатывается, в порядке возрастания сложности.

### 9.1 App version (backend code)

Простейший случай. Re-deploy предыдущего тега:

```bash
# Render
render deploys create --service tezketkaz-api --commit <previous-sha>
# Railway
railway redeploy --service tezketkaz-api <previous-deployment-id>
# Fly
flyctl deploy -a tezketkaz-api --image registry.fly.io/tezketkaz-api:<previous>
```

Время rollback: ~2 минуты. Запускаем smoke-test после.

### 9.2 Migration

Если миграция ушла в прод и сломала — **не пытаемся откатить миграцию,
если код N-1 совместим**. Просто откатываем код.

Если код N-1 несовместим (хотя по §6.1 он должен быть совместим — но всё
же):

```bash
cd backend

# 1. Зафиксировать миграцию как rolled-back
npx prisma migrate resolve --rolled-back <migration-name>

# 2. Применить SQL отката
psql $DATABASE_URL -f prisma/migrations/<migration-name>/down.sql
# (down.sql пишется ВРУЧНУЮ — Prisma не генерит его автоматически.
# Все миграции с риском требуют down.sql в PR.)

# 3. Re-deploy код N-1
```

> **Если down.sql нет — звоним CTO.** Решаем: жить с broken прод
> временно или писать SQL руками под стрессом. Поэтому down.sql
> обязателен для Normal changes (§6).

### 9.3 Config

```bash
# Render: dashboard → Env → revert
# Railway: railway variables set KEY=old-value
# Fly:    flyctl secrets set KEY=old-value -a tezketkaz-api
```

Restart хоста, если §7.1 требует. Время: ~1 минута.

### 9.4 Mobile app — нельзя быстро откатить

**Важный факт:** мобильное приложение **нельзя** откатить кнопкой. Если
выкатили баг в Play Store / App Store:

- **Google Play:** publish новой версии. Halt rollout текущей версии
  через Play Console (это останавливает дальнейшие загрузки, но не
  откатывает у тех, кто уже скачал). Срок review: 4–24 часа.
- **App Store:** publish новой версии. Можно сделать expedited review
  если P0 — Apple обычно идёт навстречу. Срок review: 7+ дней
  обычно, expedited — 24-72 часа.
- **Workaround:** feature flag на стороне бэкенда. Все рискованные фичи
  должны быть за флагом, чтобы можно было отключить со стороны сервера
  без выкатки новой версии.

### 9.5 Database data corruption

См. `disaster-recovery.md` §1 (Neon PITR). Не пытаемся «исправить» данные
UPDATE-скриптами под стрессом — слишком легко удалить лишнее.

---

## 10. Emergency hotfix process

Применяется **только** для P0/P1 (см. `incident-response.md` §1).
Цель — починить как можно быстрее, бюрократия — потом.

### 10.1 Шаги

1. Создать ветку от main: `hotfix/INC-YYYY-MM-DD-краткое`.
2. Написать минимально возможный фикс. **Не делать ничего лишнего** —
   только то, что нужно для устранения инцидента.
3. Получить **named approver signoff** в `#incidents`:
   ```
   @CTO approving hotfix: PR #N
   ```
   Named approver — это CTO или Senior Engineer, явно указанный по имени
   (не «кто-то из старших»). Имя пишется в commit message.
4. Деплоить. Без обязательного CI (но желательно прогнать локально).
5. Smoke-test после деплоя.
6. В течение 24 часов:
   - Открыть полноценный PR в `main` с описанием по шаблону (§2).
   - Добавить regression-test.
   - Получить retroactive review.
   - Связать с инцидент-доком и постмортемом.

### 10.2 Что НЕ является emergency

- Фича, обещанная заказчику завтра, но не успели — не emergency. Это
  Normal change на следующий день.
- Бизнес-просьба «срочно изменить процент комиссии» — не emergency. Это
  Normal change в течение дня.
- «Поправил тест, чтобы пройти CI» — НИКОГДА не emergency. Прыгать через
  red CI нельзя в принципе.

### 10.3 Audit trail

Каждый emergency hotfix логируется в `ops/emergency-deploys.md`:
```
- 2026-MM-DD HH:MM @имя
  Incident: INC-...
  Approver: @CTO
  Commit: <sha>
  PR (retroactive): #N
```

Если за квартал >2 emergency hotfix от одного человека — review процесса
с этим человеком (что мешает делать через normal flow?).

---

## 11. Maintenance windows

Окно для тяжёлых операций (большие миграции, version upgrade Postgres,
крупные изменения инфраструктуры).

- **Когда:** последняя суббота каждого месяца, 03:00–05:00 UTC+5 (ночь
  с пятницы на субботу по Ташкенту). Это минимум активных заказов
  (~5% от пикового трафика).
- **Уведомление:** push-notification + статус-страница за **24 часа**.
  Шаблон:
  ```
  Title: Технические работы
  Body:  В субботу с 3:00 до 5:00 ночи приложение может работать
         с перебоями. Заказы оформляйте заранее или после 5:00.
  ```
- **Что можно в окне:**
  - Миграции, требующие блокировки таблиц.
  - Версионный upgrade Postgres / Redis.
  - Реструктуризация индексов.
  - Переезд между провайдерами.
- **Что НЕЛЬЗЯ:**
  - Тестирование новых фич.
  - «Заодно посмотрим, может ещё что-то починим».
  - Любые изменения, не объявленные за 24 часа.

Окно ведёт **один** инженер (ops-on-call). IC по необходимости. Минимум
два человека в Slack — один работает, второй смотрит на метрики.

---

## 12. После любого деплоя — checklist обновления документации

- [ ] Если изменился API — обновили OpenAPI / README?
- [ ] Если добавили env var — добавили в `.env.example`?
- [ ] Если изменили процесс — обновили этот документ?
- [ ] Если добавили dashboard / алерт — обновили `monitoring-setup.md`?

---

## 13. Deploy checklist (шаблон для копирования)

Использовать как чек-лист в PR-описании или в `#deploys` thread.

```markdown
## Deploy: <PR #N — short title>

**Type:** Standard / Normal / Emergency
**Author:** @имя
**Approvers:** @имя1, @имя2
**Ops on-call:** @имя

### Pre-deploy
- [ ] CI зелёный (560+ backend tests + Flutter analyze + lint)
- [ ] Reviewers approved (1 для Standard, 2 для Normal)
- [ ] Smoke-test на staging прошёл
- [ ] Миграции (если есть) применены к staging без ошибок
- [ ] Все предыдущие миграции в проде
- [ ] PR описание содержит rollback plan
- [ ] PR описание содержит monitoring plan
- [ ] Time-of-day OK (не пиковые часы, не вечер пятницы)
- [ ] Уведомление в #deploys

### During deploy
- [ ] Tail логов открыт
- [ ] Sentry → Releases → новый тег открыт
- [ ] Grafana → Backend Overview открыт
- [ ] Готов к откату за <2 минуты

### Post-deploy (T+30 min)
- [ ] Smoke-test prod прошёл
- [ ] curl /healthz → 200 OK
- [ ] Error rate в пределах baseline ±20%
- [ ] p95 latency в пределах baseline +50ms
- [ ] 0 новых Sentry issues
- [ ] Push notification (если применимо) отправлен / не нужен
- [ ] #deploys: `:white_check_mark: stable, closing watch`

### Rollback (если потребуется)
- [ ] Re-deploy previous tag: `<команда>`
- [ ] Smoke-test после rollback
- [ ] Документировать причину в `ops/rollbacks.md`
- [ ] Открыть инцидент, если был user-facing impact (см. `incident-response.md`)
```
