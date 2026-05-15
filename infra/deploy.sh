#!/usr/bin/env bash
# ============================================================================
# TezKetKaz first-run bootstrap.
#
# Запускать ОДИН раз на чистом сервере. Идемпотентен — повторный запуск
# увидит уже сгенерированные секреты и не перезапишет их.
#
# Что делает:
#   1. Проверяет что Docker + Compose установлены
#   2. Создаёт infra/.env из .env.production.example если нет
#   3. Генерирует и подставляет случайные секреты (JWT, INTEGRATION_ENC_KEY,
#      POSTGRES_PASSWORD, TELEGRAM_WEBHOOK_SECRET) — единственная ручная
#      правка после этого: указать домен DOMAIN=
#   4. docker compose up -d --build
#   5. Ждёт пока backend пройдёт healthcheck
#   6. Перепривязывает Telegram webhook на новый домен
#
# Использование:
#   ./infra/deploy.sh                — поднять с нуля (или после git pull)
#   ./infra/deploy.sh --refresh-env  — пересоздать .env (сотрёт секреты!)
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."  # repo root

INFRA=infra
ENV_FILE="$INFRA/.env"
ENV_TEMPLATE="$INFRA/.env.production.example"

step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }

# ─── 1. prerequisites ──────────────────────────────────────────────────────
step "Checking Docker"
command -v docker >/dev/null || fail "docker не установлен. Установи: curl -fsSL https://get.docker.com | sh"
docker compose version >/dev/null 2>&1 || fail "docker compose не работает. Обнови Docker до 20.10+"
ok "Docker $(docker --version | awk '{print $3}' | tr -d ',') ready"

# ─── 2. .env file ──────────────────────────────────────────────────────────
if [[ "${1:-}" == "--refresh-env" ]]; then
  rm -f "$ENV_FILE"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  step "Creating $ENV_FILE from template"
  cp "$ENV_TEMPLATE" "$ENV_FILE"

  step "Generating secrets"
  JWT=$(openssl rand -hex 32)
  ENC=$(openssl rand -base64 32 | tr -d '\n')
  WHS=$(openssl rand -hex 32)
  PWD=$(openssl rand -base64 24 | tr -d '/=+\n' | cut -c1-32)

  # `sed -i` различается на Linux/macOS — используем явный backup пустой.
  sed -i.bak "s|JWT_SECRET=__GENERATE_ME__|JWT_SECRET=$JWT|" "$ENV_FILE"
  sed -i.bak "s|INTEGRATION_ENC_KEY=__GENERATE_ME__|INTEGRATION_ENC_KEY=$ENC|" "$ENV_FILE"
  sed -i.bak "s|TELEGRAM_WEBHOOK_SECRET=__GENERATE_ME__|TELEGRAM_WEBHOOK_SECRET=$WHS|" "$ENV_FILE"
  sed -i.bak "s|POSTGRES_PASSWORD=__GENERATE_ME__|POSTGRES_PASSWORD=$PWD|" "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
  ok "Secrets generated and saved."
  warn "Откройте $ENV_FILE и впишите ваш DOMAIN= и ADMIN_EMAIL= перед продолжением."
  warn "Затем запустите ./infra/deploy.sh ещё раз."
  exit 0
fi

# ─── 3. sanity checks on .env ──────────────────────────────────────────────
step "Sanity-check $ENV_FILE"
. "$ENV_FILE"
[[ "$DOMAIN" != "staging.tezketkaz.uz" && -n "$DOMAIN" ]] || \
  fail "DOMAIN не задан в $ENV_FILE (или оставлен default-шаблонный staging.tezketkaz.uz)"
[[ "$JWT_SECRET" != "__GENERATE_ME__" ]] || fail "JWT_SECRET не сгенерирован"
[[ "$INTEGRATION_ENC_KEY" != "__GENERATE_ME__" ]] || fail "INTEGRATION_ENC_KEY не сгенерирован"
ok "Все обязательные переменные на месте"

# ─── 4. start containers ───────────────────────────────────────────────────
step "Pulling images and building backend"
docker compose -f "$INFRA/docker-compose.yml" --env-file "$ENV_FILE" pull
docker compose -f "$INFRA/docker-compose.yml" --env-file "$ENV_FILE" build

step "Starting stack"
docker compose -f "$INFRA/docker-compose.yml" --env-file "$ENV_FILE" up -d

# ─── 5. wait for healthy ───────────────────────────────────────────────────
step "Waiting for backend healthcheck (up to 90s)"
for i in $(seq 1 18); do
  status=$(docker inspect --format='{{.State.Health.Status}}' tezketkaz-backend-1 2>/dev/null || echo "none")
  if [[ "$status" == "healthy" ]]; then
    ok "Backend healthy"
    break
  fi
  printf '.'
  sleep 5
done
[[ "$status" == "healthy" ]] || warn "Backend ещё не healthy ($status) — может догоняется. Проверь логи: docker compose -f $INFRA/docker-compose.yml logs backend"

# ─── 6. register Telegram webhook ──────────────────────────────────────────
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  step "Registering Telegram webhook → https://$DOMAIN/api/auth/telegram/webhook"
  resp=$(curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
    -H 'Content-Type: application/json' \
    -d "{\"url\":\"https://${DOMAIN}/api/auth/telegram/webhook\",\"allowed_updates\":[\"message\"],\"secret_token\":\"${TELEGRAM_WEBHOOK_SECRET}\"}" || echo "")
  if [[ "$resp" == *'"ok":true'* ]]; then
    ok "Webhook attached"
  else
    warn "setWebhook failed — $resp. Можно вызвать вручную позже."
  fi
fi

# ─── 7. summary ────────────────────────────────────────────────────────────
echo
ok "Deploy complete."
echo
echo "  Health: https://$DOMAIN/health"
echo "  App:    https://$DOMAIN/"
echo "  Logs:   docker compose -f $INFRA/docker-compose.yml logs -f backend"
echo "  Stop:   docker compose -f $INFRA/docker-compose.yml down"
echo
echo "Чтобы обновить после git pull:"
echo "  ./infra/deploy.sh"
