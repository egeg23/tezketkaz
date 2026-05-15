// Telegram authentication.
//
// Two flows that share the same User row + JWT issuance:
//
//   A) LOGIN WIDGET — production web (https://core.telegram.org/widgets/login)
//      The user clicks the Telegram-rendered widget, Telegram redirects to
//      our `/api/auth/telegram/widget` endpoint with the auth payload (id,
//      first_name, …, hash). We verify the hash using HMAC-SHA256 over a
//      sorted data_check_string with key = SHA256(bot_token). Then we
//      upsert the User and return our JWTs.
//
//   B) DEEP-LINK — dev tunnels, mobile, any case where setting a domain
//      on @BotFather is inconvenient. Flow:
//        1. Client calls POST /api/auth/telegram/begin → server returns
//           { challengeId, botUrl: "https://t.me/<bot>?start=<id>" }.
//        2. Client opens botUrl (new tab on web, intent on mobile).
//        3. User taps "Start" in Telegram. Telegram delivers `/start <id>`
//           to our bot via the webhook we set on bootstrap.
//        4. Our webhook handler finds the challenge by id, attaches the
//           Telegram user to it, and stamps it ready.
//        5. Client has been polling /api/auth/telegram/poll?challengeId=…
//           — once ready, server upserts the User and returns JWTs.
//
// Environment:
//   TELEGRAM_BOT_TOKEN   — required. From @BotFather.
//   TELEGRAM_BOT_USERNAME — required. Public bot handle without "@".
//   TELEGRAM_WEBHOOK_SECRET — optional. If set, we configure Telegram to send
//                             X-Telegram-Bot-Api-Secret-Token: <value>; we
//                             reject webhook hits whose header doesn't match.

const router = require('express').Router();
const crypto = require('crypto');
const prisma = require('../db');
const jwtLib = require('../lib/jwt');
const logger = require('../lib/logger');
const { audit } = require('../lib/audit');

const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || '';
const BOT_USERNAME = process.env.TELEGRAM_BOT_USERNAME || '';
const WEBHOOK_SECRET = process.env.TELEGRAM_WEBHOOK_SECRET || '';

// In-memory store for the deep-link flow. For multi-instance prod, swap to
// Redis with the same key shape. We don't persist these to Postgres because
// they're throwaway (10-minute TTL) and high-churn.
const challenges = new Map(); // challengeId -> { createdAt, telegramUser? }
const CHALLENGE_TTL_MS = 10 * 60 * 1000;

function cleanupChallenges() {
  const now = Date.now();
  for (const [k, v] of challenges) {
    if (now - v.createdAt > CHALLENGE_TTL_MS) challenges.delete(k);
  }
}
setInterval(cleanupChallenges, 60_000).unref();

// ────────────────────────────────────────────────────────────────────────────
// Shared: build data_check_string per https://core.telegram.org/widgets/login
function dataCheckString(payload) {
  return Object.keys(payload)
    .filter((k) => k !== 'hash' && payload[k] != null)
    .sort()
    .map((k) => `${k}=${payload[k]}`)
    .join('\n');
}

function verifyWidgetHash(payload) {
  if (!BOT_TOKEN) return false;
  const dcs = dataCheckString(payload);
  const secretKey = crypto.createHash('sha256').update(BOT_TOKEN).digest();
  const hmac = crypto.createHmac('sha256', secretKey).update(dcs).digest('hex');
  return crypto.timingSafeEqual(
    Buffer.from(hmac, 'hex'),
    Buffer.from(String(payload.hash || ''), 'hex'),
  );
}

// Upsert + token issue. Same for both flows.
async function loginWithTelegram(tg, req) {
  // tg = { id, first_name?, last_name?, username?, photo_url? }
  const telegramId = String(tg.id);
  const username = tg.username ? String(tg.username) : null;
  const fullName = [tg.first_name, tg.last_name].filter(Boolean).join(' ').trim();

  // Find by telegramId first; if not found, create. We do NOT auto-merge
  // accounts by phone here — the buyer can link Telegram in profile later.
  let user = await prisma.user.findUnique({
    where: { telegramId },
    include: { shopMemberships: { include: { shop: true } } },
  });

  if (!user) {
    user = await prisma.user.create({
      data: {
        telegramId,
        telegramUsername: username,
        name: fullName || null,
        avatarUrl: tg.photo_url || null,
        // Country defaults to UZ since that's our home market. User can change.
        country: 'UZ',
        locale: 'ru',
      },
      include: { shopMemberships: { include: { shop: true } } },
    });
  } else if (user.telegramUsername !== username || (!user.name && fullName)) {
    // Refresh stale username + fill name on first login if it's blank.
    user = await prisma.user.update({
      where: { id: user.id },
      data: {
        telegramUsername: username,
        name: user.name || fullName || null,
        avatarUrl: user.avatarUrl || tg.photo_url || null,
      },
      include: { shopMemberships: { include: { shop: true } } },
    });
  }

  const userAgent = req.get?.('user-agent') || null;
  const ipAddress = req.ip || null;
  const { token: accessToken } = jwtLib.signAccess(user.id);
  const { token: refreshToken } =
    await jwtLib.signRefresh(user.id, { userAgent, ipAddress });

  await audit({
    actorId: user.id,
    action: 'auth.telegram_login',
    targetType: 'User',
    targetId: user.id,
    ipAddress,
    metadata: { method: 'telegram', telegramId, username },
  });

  return { accessToken, refreshToken, user: serializeUser(user) };
}

function serializeUser(u) {
  return {
    id: u.id,
    phone: u.phone,
    name: u.name,
    avatarUrl: u.avatarUrl,
    telegramId: u.telegramId,
    telegramUsername: u.telegramUsername,
    isBuyer: u.isBuyer,
    isCourier: u.isCourier,
    isShop: u.isShop,
    isAdmin: u.isAdmin,
    locale: u.locale,
    country: u.country || 'UZ',
    courierStatus: u.courierStatus,
    rating: u.rating,
    ordersCount: u.ordersCount,
    shops: u.shopMemberships?.map((m) => ({
      id: m.shop.id, name: m.shop.name, role: m.role,
    })) || [],
  };
}

// ─── FLOW A: Login Widget callback ──────────────────────────────────────────
// POST /api/auth/telegram/widget   body: { id, first_name, ..., auth_date, hash }
router.post('/widget', async (req, res, next) => {
  try {
    if (!BOT_TOKEN) {
      return res.status(503).json({ error: 'telegram_not_configured' });
    }
    const payload = req.body || {};
    if (!payload.id || !payload.hash || !payload.auth_date) {
      return res.status(400).json({ error: 'invalid_payload' });
    }
    // Reject auth older than 1 day to avoid replay attacks
    if (Number(payload.auth_date) * 1000 < Date.now() - 24 * 3600_000) {
      return res.status(400).json({ error: 'auth_expired' });
    }
    if (!verifyWidgetHash(payload)) {
      return res.status(401).json({ error: 'invalid_hash' });
    }
    const result = await loginWithTelegram(payload, req);
    res.json(result);
  } catch (err) { next(err); }
});

// ─── FLOW B: Deep-link begin ────────────────────────────────────────────────
// POST /api/auth/telegram/begin  → { challengeId, botUrl, expiresAt }
router.post('/begin', async (req, res, next) => {
  try {
    if (!BOT_USERNAME) {
      return res.status(503).json({ error: 'telegram_not_configured' });
    }
    const challengeId = crypto.randomBytes(16).toString('hex');
    challenges.set(challengeId, { createdAt: Date.now() });
    res.json({
      challengeId,
      botUrl: `https://t.me/${BOT_USERNAME}?start=${challengeId}`,
      expiresAt: new Date(Date.now() + CHALLENGE_TTL_MS).toISOString(),
    });
  } catch (err) { next(err); }
});

// ─── FLOW B: webhook called by Telegram when user taps Start ────────────────
// POST /api/auth/telegram/webhook  (Telegram → us)
//
// Body is a standard Telegram Update object. We only care about /start <id>.
router.post('/webhook', async (req, res, next) => {
  try {
    // Optional shared secret check.
    if (WEBHOOK_SECRET) {
      const got = req.get('x-telegram-bot-api-secret-token');
      if (got !== WEBHOOK_SECRET) {
        logger.warn('telegram webhook: bad secret');
        return res.status(401).end();
      }
    }
    const update = req.body || {};
    const msg = update.message;
    if (!msg || typeof msg.text !== 'string' || !msg.from) {
      return res.json({ ok: true }); // ignore non-/start updates
    }
    if (!msg.text.startsWith('/start')) {
      return res.json({ ok: true });
    }
    const parts = msg.text.split(/\s+/, 2);
    const challengeId = parts[1] ? parts[1].trim() : null;
    if (!challengeId) {
      return res.json({ ok: true }); // /start with no param — ignore
    }
    const c = challenges.get(challengeId);
    if (!c) {
      // Reply via Telegram so the user sees a friendly hint. Best-effort.
      await replyToChat(msg.chat.id, 'Этот запрос устарел или уже использован. Откройте приложение TezKetKaz и попробуйте ещё раз.').catch(() => {});
      return res.json({ ok: true });
    }
    c.telegramUser = {
      id: msg.from.id,
      first_name: msg.from.first_name,
      last_name: msg.from.last_name,
      username: msg.from.username,
      photo_url: null, // not present in update payloads
    };
    challenges.set(challengeId, c);
    await replyToChat(msg.chat.id, '✅ Вход подтверждён. Возвращайтесь в приложение TezKetKaz.').catch(() => {});
    res.json({ ok: true });
  } catch (err) { next(err); }
});

async function replyToChat(chatId, text) {
  if (!BOT_TOKEN) return;
  try {
    await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, text }),
    });
  } catch (err) {
    logger.debug?.({ err: err.message }, 'telegram sendMessage failed');
  }
}

// ─── FLOW B: client polls until the challenge is fulfilled ──────────────────
// GET /api/auth/telegram/poll?challengeId=...
router.get('/poll', async (req, res, next) => {
  try {
    const id = String(req.query.challengeId || '');
    if (!id) return res.status(400).json({ error: 'challengeId_required' });
    const c = challenges.get(id);
    if (!c) return res.status(404).json({ error: 'challenge_not_found' });
    if (!c.telegramUser) {
      return res.json({ ready: false });
    }
    // Consume + fulfil
    challenges.delete(id);
    const result = await loginWithTelegram(c.telegramUser, req);
    res.json({ ready: true, ...result });
  } catch (err) { next(err); }
});

// ─── Helper for the bootstrap script to register our webhook with Telegram ──
//
// Call once per deploy:
//   node -e 'require("./src/routes/telegram-auth").setupWebhook("https://api.tezketkaz.uz")'
// Not mounted as an HTTP route — operator-side only.
async function setupWebhook(publicBaseUrl) {
  if (!BOT_TOKEN) throw new Error('TELEGRAM_BOT_TOKEN not set');
  const url = `${publicBaseUrl.replace(/\/$/, '')}/api/auth/telegram/webhook`;
  const body = { url, allowed_updates: ['message'] };
  if (WEBHOOK_SECRET) body.secret_token = WEBHOOK_SECRET;
  const r = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/setWebhook`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const j = await r.json();
  return j;
}

module.exports = router;
module.exports.setupWebhook = setupWebhook;
