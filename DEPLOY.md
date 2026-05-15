# 🚀 TezKetKaz — деплой staging-сервера

Инструкция для **первого запуска** на чистом Ubuntu 24+ сервере. Все
команды выполнять последовательно, из-под пользователя с `sudo`.

> **Этот файл предназначен для Kimi Claw (агент на сервере).** Выполни шаги
> сверху вниз, останавливаясь на пунктах помеченных ⚠ и спрашивая
> подтверждение у пользователя.

---

## Спецификация целевого сервера

| Параметр | Значение |
|---|---|
| Провайдер | TimeWeb Cloud |
| ОС | Ubuntu 24+ |
| CPU | 4 vCPU @ 4.44 GHz |
| RAM | 12 GB |
| Disk | 50 GB NVMe |
| Стек | Caddy + Node 20 + Postgres 16 + Redis 7 (4 контейнера) |

---

## 📋 Pre-flight checklist

⚠ **Перед началом убедись что:**

- [ ] Домен куплен (например `tezketkaz.uz` или `app.tezketkaz.uz`)
- [ ] DNS A-record указывает на IP сервера. Проверить: `dig +short <твой-домен>` — должно вернуть IP сервера
- [ ] Порты 80, 443 открыты (TimeWeb обычно открыты по умолчанию, проверить
      файрволл в админке)
- [ ] У тебя есть root или sudo

---

## Шаг 1 — Установка Docker

```bash
# Обновляем индекс пакетов
sudo apt update

# Ставим Docker одной командой (официальный скрипт)
curl -fsSL https://get.docker.com | sudo sh

# Добавляем текущего пользователя в группу docker (чтобы не sudo каждый раз)
sudo usermod -aG docker $USER
newgrp docker

# Проверка
docker --version
docker compose version
```

Ожидаемый вывод: `Docker version 27.x.x`, `Docker Compose version v2.x.x`.

---

## Шаг 2 — Клонируем репозиторий

```bash
# Создаём папку для приложения
sudo mkdir -p /opt/tezketkaz
sudo chown $USER:$USER /opt/tezketkaz
cd /opt/tezketkaz

# Клонируем
git clone https://github.com/egeg23/tezketkaz.git .
```

Проверь что появилась папка `infra/`:

```bash
ls infra/
# должно быть: Caddyfile  docker-compose.yml  Dockerfile.backend
#              .env.production.example  deploy.sh
```

---

## Шаг 3 — Первая инициализация (генерирует секреты)

```bash
cd /opt/tezketkaz
chmod +x infra/deploy.sh
./infra/deploy.sh
```

Скрипт создаст `infra/.env`, **сгенерирует** случайные:
- `JWT_SECRET` (64-hex)
- `INTEGRATION_ENC_KEY` (32-byte base64)
- `TELEGRAM_WEBHOOK_SECRET`
- `POSTGRES_PASSWORD`

И остановится — попросит вписать `DOMAIN` и `ADMIN_EMAIL` вручную.

⚠ **Действие пользователя**: открой `infra/.env` и впиши:

```bash
nano infra/.env
```

Найди строку и измени значения:

```
DOMAIN=staging.tezketkaz.uz       # ваш реальный домен
ADMIN_EMAIL=your.email@gmail.com  # для Let's Encrypt уведомлений
```

Сохрани (`Ctrl+O`, Enter, `Ctrl+X`).

---

## Шаг 4 — Полный запуск стека

```bash
./infra/deploy.sh
```

Что произойдёт автоматически:

1. ✅ Pulls and builds 4 контейнера: Caddy, Node backend, Postgres, Redis
2. ✅ Caddy запросит SSL-сертификат у Let's Encrypt (HTTP-01 challenge)
3. ✅ Postgres стартует с auto-tuned параметрами под 12 GB RAM
4. ✅ Backend применит Prisma-схему (`db push`) при старте
5. ✅ Telegram webhook автоматически перепривяжется на `https://$DOMAIN/api/auth/telegram/webhook`
6. ✅ Healthcheck подождёт пока всё поднимется (~30-60 секунд)

Ожидаемый финальный вывод:

```
✓ Backend healthy
✓ Webhook attached
✓ Deploy complete.

  Health: https://staging.tezketkaz.uz/health
  App:    https://staging.tezketkaz.uz/
```

---

## Шаг 5 — Проверка

```bash
# Health
curl https://$DOMAIN/health
# Ожидаем: {"ok":true,"ts":...}

# Telegram webhook info
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo" | python3 -m json.tool
# Поле "url" должно быть нашим: https://$DOMAIN/api/auth/telegram/webhook

# Frontend
curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN/
# Ожидаем 200
```

В браузере: открой `https://$DOMAIN` — должна загрузиться TezKetKaz с master design.

---

## ⚙ Полезные команды

```bash
# Логи в реальном времени
docker compose -f infra/docker-compose.yml logs -f backend

# Только последние 200 строк
docker compose -f infra/docker-compose.yml logs --tail 200 backend

# Перезапустить только backend (например после `git pull`)
docker compose -f infra/docker-compose.yml restart backend

# Полная остановка
docker compose -f infra/docker-compose.yml down

# Pull latest code + rebuild
cd /opt/tezketkaz
git pull
./infra/deploy.sh

# Зайти внутрь backend контейнера
docker compose -f infra/docker-compose.yml exec backend sh

# Прямой доступ к Postgres
docker compose -f infra/docker-compose.yml exec postgres \
  psql -U $POSTGRES_USER -d $POSTGRES_DB
```

---

## 📦 Обновление приложения

Когда я (Claude) запушу новые коммиты в `main`:

```bash
cd /opt/tezketkaz
git pull
./infra/deploy.sh   # пере-билдит backend образ, рестартит контейнеры
```

CI пересобирает `build/web` автоматически, так что Flutter-фронт уже в коммите.

---

## 🔥 Что делать если что-то сломалось

### Backend контейнер не стартует

```bash
docker compose -f infra/docker-compose.yml logs backend
```

Чаще всего:
- **`prisma db push` упал** → проверить что Postgres healthy: `docker compose -f infra/docker-compose.yml ps`
- **Не находит `.env`** → проверь что `infra/.env` существует и читаем
- **`Cannot find module 'prisma'`** → передёрни build: `./infra/deploy.sh`

### Caddy не выдаёт SSL

```bash
docker compose -f infra/docker-compose.yml logs caddy
```

Чаще всего:
- DNS A-record не указывает на сервер → `dig +short $DOMAIN`
- Порт 80 закрыт файрволлом → `sudo ufw allow 80,443/tcp`
- Let's Encrypt rate limit (5 попыток на домен в час) → подождать 1 час

### Постгрес заполнился

```bash
docker compose -f infra/docker-compose.yml exec postgres \
  du -sh /var/lib/postgresql/data
```

50 GB должно хватать на ~1M заказов. Если близко — нужен бэкап-стратегия (см. ниже).

---

## 💾 Backup стратегия (минимальная)

Простой cron для дампа Postgres каждые 6 часов:

```bash
# Создаём скрипт
sudo tee /opt/tezketkaz/infra/backup.sh > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
DIR=/opt/tezketkaz/backups
mkdir -p $DIR
docker compose -f /opt/tezketkaz/infra/docker-compose.yml exec -T postgres \
  pg_dump -U tezketkaz tezketkaz | gzip > $DIR/db-$(date +%Y%m%d-%H%M%S).sql.gz
# Храним 7 дней
find $DIR -name 'db-*.sql.gz' -mtime +7 -delete
EOF
sudo chmod +x /opt/tezketkaz/infra/backup.sh

# Добавляем в cron на 0:00, 6:00, 12:00, 18:00
(crontab -l 2>/dev/null; echo "0 */6 * * * /opt/tezketkaz/infra/backup.sh") | crontab -
```

---

## 🔐 Безопасность — что сделать после первого запуска

1. **Файрволл** — закрыть всё кроме 22 (SSH), 80, 443:
   ```bash
   sudo ufw allow ssh
   sudo ufw allow 80,443/tcp
   sudo ufw enable
   ```

2. **SSH** — отключить пароли, оставить только ключи в `/etc/ssh/sshd_config`:
   ```
   PasswordAuthentication no
   PermitRootLogin no
   ```
   Затем `sudo systemctl restart ssh`.

3. **Unattended-upgrades** — авто-патчи безопасности:
   ```bash
   sudo apt install unattended-upgrades
   sudo dpkg-reconfigure --priority=low unattended-upgrades
   ```

4. **Backup-файлы НЕ в публичный каталог** — храни в `/opt/tezketkaz/backups`, не в `/var/www`.

---

## 🎯 Что дальше

После того как staging запущен:

- [ ] Дай мне (Claude) знать URL — я обновлю env-файлы в проекте на новый домен
- [ ] Прислать первым тестерам — пробежаться по флоу (логин Telegram → заказ → доставка)
- [ ] Продолжаем дорабатывать (cart, courier screens, Postgres-tuning, FCM push, etc.)
- [ ] Когда staging стабилен 2-3 недели + Click/Payme контракты → ставим production сервер

---

**При проблемах — пиши Claude в чате, он подскажет.**
