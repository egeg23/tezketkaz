// Auth routes: OTP send/verify, token refresh, logout, /me.
// Issues an access + refresh pair; refresh rotation revokes the previous DB row.
// Logout blacklists the access JWT (in Redis with ttl) and revokes the refresh.

const router = require('express').Router();
const jwt = require('jsonwebtoken');

const prisma = require('../db');
const env = require('../config/env');
const logger = require('../lib/logger');
const redis = require('../lib/redis');
const jwtLib = require('../lib/jwt');
const { audit } = require('../lib/audit');
const { sendOtp } = require('../services/sms');
const { authMiddleware } = require('../middleware/auth');
const country = require('../services/country');

// Phase 7 — Kazakh joins the supported set on the auth /me PATCH path. This is
// the same set as routes/users.js PATCH /me; keep them in sync.
const VALID_LOCALES = new Set(['uz', 'ru', 'en', 'kk']);
const OTP_RATE_KEY = (phone) => `otp:rate:${phone}`;
const OTP_FAIL_KEY = (phone) => `otp:fail:${phone}`;
const OTP_RATE_WINDOW_S = 3600;     // 1 hour
const OTP_RATE_MAX = 5;             // max OTPs per phone per hour
const OTP_FAIL_WINDOW_S = 600;      // 10 min
const OTP_FAIL_MAX = 5;             // max failed verify per 10 min

function errResp(res, status, message) {
  return res.status(status).json({ error: message });
}

function genCode() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function normalizePhone(phone) {
  // E.164: +<countrycode><number>. UZ stays the default; Phase 7 also allows
  // KZ (+7), KG (+996), and RU (+7) phones — see isAllowedPhone below.
  const digits = String(phone || '').replace(/\D/g, '');
  return '+' + digits;
}

// Phase 7 — accept E.164 phones from any TezKetKaz market.
//   UZ: +998 + 9 digits  (12 chars total incl. +)
//   KZ: +77  + 9 digits  (12)
//   KG: +996 + 9 digits  (13)
//   RU: +7   + 10 digits (12) — but +77... is KZ, so prefer +7[0-689]...
// We keep this lenient: any +<digits> with 11–14 chars passes. Production OTP
// rate limits + provider-side validity catch garbage.
function isAllowedPhone(p) {
  if (!p || typeof p !== 'string') return false;
  if (!/^\+\d{10,14}$/.test(p)) return false;
  if (p.startsWith('+998') && p.length === 13) return true;   // UZ
  if (p.startsWith('+996') && p.length === 13) return true;   // KG
  if (p.startsWith('+7') && p.length === 12) return true;     // KZ (+77...) or RU
  return false;
}

// ─── POST /api/auth/send-otp ─────────────────────────────────────────────────
router.post('/send-otp', async (req, res, next) => {
  try {
    const phone = normalizePhone(req.body.phone || '');
    if (!isAllowedPhone(phone)) {
      return errResp(res, 400, 'Invalid phone number');
    }

    // Per-phone hourly rate limit (max 5 / hour)
    const count = await redis.incrWithTtl(OTP_RATE_KEY(phone), OTP_RATE_WINDOW_S);
    if (count > OTP_RATE_MAX) {
      return errResp(res, 429, 'Too many OTP requests, try again later');
    }

    // 60-second per-phone debounce via DB
    const recent = await prisma.otpCode.findFirst({
      where: { phone, createdAt: { gt: new Date(Date.now() - 60_000) } },
    });
    if (recent) {
      return errResp(res, 429, 'Too many requests, wait 60s');
    }

    // In dev / mock SMS: always 123456 for testing
    const code = env.isProd && !env.useMockSms ? genCode() : '123456';

    await prisma.otpCode.create({
      data: {
        phone,
        code,
        expiresAt: new Date(Date.now() + 5 * 60_000), // 5 min
      },
    });

    await sendOtp(phone, code);
    res.json({
      success: true,
      devCode: !env.isProd || env.useMockSms ? code : undefined,
    });
  } catch (err) { next(err); }
});

// ─── POST /api/auth/verify-otp ───────────────────────────────────────────────
router.post('/verify-otp', async (req, res, next) => {
  try {
    const phone = normalizePhone(req.body.phone || '');
    const { code } = req.body;
    if (!isAllowedPhone(phone) || !code) {
      return errResp(res, 400, 'Invalid phone or code');
    }

    // Lockout if too many failed attempts in last 10 min
    const failKey = OTP_FAIL_KEY(phone);
    const fails = Number(await redis.get(failKey)) || 0;
    if (fails >= OTP_FAIL_MAX) {
      return errResp(res, 429, 'Too many failed attempts, try again later');
    }

    const otp = await prisma.otpCode.findFirst({
      where: { phone, code, used: false, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });

    if (!otp) {
      // Track failed attempts (if there's a latest unused OTP, also bump its `attempts`)
      await redis.incrWithTtl(failKey, OTP_FAIL_WINDOW_S);
      const latest = await prisma.otpCode.findFirst({
        where: { phone, used: false },
        orderBy: { createdAt: 'desc' },
      });
      if (latest) {
        await prisma.otpCode.update({
          where: { id: latest.id },
          data: { attempts: { increment: 1 } },
        });
      }
      return errResp(res, 400, 'Invalid or expired code');
    }

    await prisma.otpCode.update({ where: { id: otp.id }, data: { used: true } });
    // Reset fail counter on success
    await redis.del(failKey);

    // Find or create user (default locale 'uz')
    let user = await prisma.user.findUnique({
      where: { phone },
      include: { shopMemberships: { include: { shop: true } } },
    });
    if (!user) {
      // Phase 7 — auto-detect country + locale from phone prefix at signup.
      // (User can override later via PATCH /me.)
      const detectedCountry = country.fromPhone(phone);
      const detectedLocale = country.info(detectedCountry).locale || 'uz';
      user = await prisma.user.create({
        data: { phone, locale: detectedLocale, country: detectedCountry },
        include: { shopMemberships: { include: { shop: true } } },
      });
    } else if (!user.country) {
      // Backfill: existing accounts created before Phase 7 had no country.
      // Set once on first verify after upgrade so downstream tax/provider
      // logic has a value to dispatch on. Existing locale is preserved.
      const detectedCountry = country.fromPhone(phone);
      try {
        user = await prisma.user.update({
          where: { id: user.id },
          data: { country: detectedCountry },
          include: { shopMemberships: { include: { shop: true } } },
        });
      } catch (err) {
        logger.warn({ err: err.message, userId: user.id }, 'country backfill failed');
      }
    }

    const userAgent = req.get('user-agent') || null;
    const ipAddress = req.ip || null;

    const { token: accessToken } = jwtLib.signAccess(user.id);
    const { token: refreshToken } = await jwtLib.signRefresh(user.id, { userAgent, ipAddress });

    await audit({
      actorId: user.id,
      action: 'auth.login',
      targetType: 'User',
      targetId: user.id,
      ipAddress,
      metadata: { userAgent },
    });

    res.json({ accessToken, refreshToken, user: serializeUser(user) });
  } catch (err) { next(err); }
});

// ─── POST /api/auth/refresh ──────────────────────────────────────────────────
router.post('/refresh', async (req, res, next) => {
  try {
    const { refreshToken } = req.body || {};
    if (!refreshToken || typeof refreshToken !== 'string') {
      return errResp(res, 400, 'Missing refreshToken');
    }

    let result;
    try {
      result = await jwtLib.verifyRefresh(refreshToken);
    } catch (err) {
      logger.warn({ err: err.message }, 'refresh token rejected');
      return errResp(res, 401, 'Invalid refresh token');
    }
    const { decoded, dbToken } = result;

    const user = await prisma.user.findUnique({ where: { id: decoded.userId } });
    if (!user) return errResp(res, 401, 'User not found');

    const userAgent = req.get('user-agent') || null;
    const ipAddress = req.ip || null;

    // Rotate: revoke old, issue new pair
    const { token: newRefresh } = await jwtLib.rotateRefresh(dbToken, { userAgent, ipAddress });
    const { token: newAccess } = jwtLib.signAccess(user.id);

    // If a stale access token was sent in Authorization header, blacklist it.
    const header = req.headers.authorization;
    if (header && header.startsWith('Bearer ')) {
      await jwtLib.blacklistAccessToken(header.substring(7));
    }

    await audit({
      actorId: user.id,
      action: 'auth.refresh',
      targetType: 'User',
      targetId: user.id,
      ipAddress,
      metadata: { userAgent, oldJti: decoded.jti },
    });

    res.json({ accessToken: newAccess, refreshToken: newRefresh });
  } catch (err) { next(err); }
});

// ─── POST /api/auth/logout ───────────────────────────────────────────────────
router.post('/logout', authMiddleware, async (req, res, next) => {
  try {
    // Blacklist current access (must be done before we lose req.user)
    const header = req.headers.authorization;
    if (header && header.startsWith('Bearer ')) {
      await jwtLib.blacklistAccessToken(header.substring(7));
    }

    // Revoke refresh token if provided
    const { refreshToken } = req.body || {};
    if (refreshToken && typeof refreshToken === 'string') {
      try {
        const decoded = jwt.decode(refreshToken);
        if (decoded?.jti) await jwtLib.revokeRefresh(decoded.jti);
      } catch (err) {
        logger.warn({ err: err.message }, 'logout: could not decode refresh token');
      }
    }

    await audit({
      actorId: req.user.id,
      action: 'auth.logout',
      targetType: 'User',
      targetId: req.user.id,
      ipAddress: req.ip || null,
      metadata: { userAgent: req.get('user-agent') || null },
    });

    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ─── POST /api/auth/logout-all ───────────────────────────────────────────────
router.post('/logout-all', authMiddleware, async (req, res, next) => {
  try {
    const header = req.headers.authorization;
    if (header && header.startsWith('Bearer ')) {
      await jwtLib.blacklistAccessToken(header.substring(7));
    }
    await jwtLib.revokeAllUserRefresh(req.user.id);

    await audit({
      actorId: req.user.id,
      action: 'auth.logout_all',
      targetType: 'User',
      targetId: req.user.id,
      ipAddress: req.ip || null,
      metadata: { userAgent: req.get('user-agent') || null },
    });

    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ─── GET /api/auth/me ────────────────────────────────────────────────────────
router.get('/me', authMiddleware, async (req, res) => {
  res.json({ user: serializeUser(req.user) });
});

// ─── PATCH /api/auth/me ──────────────────────────────────────────────────────
router.patch('/me', authMiddleware, async (req, res, next) => {
  try {
    const { name, locale, notificationPrefs } = req.body || {};
    const data = {};

    if (typeof name === 'string') data.name = name.trim() || null;

    if (locale !== undefined) {
      if (typeof locale !== 'string' || !VALID_LOCALES.has(locale)) {
        return errResp(res, 400, 'Invalid locale (allowed: uz, ru, en, kk)');
      }
      data.locale = locale;
    }

    if (notificationPrefs !== undefined) {
      if (notificationPrefs === null) {
        data.notificationPrefs = null;
      } else if (typeof notificationPrefs === 'object') {
        try {
          data.notificationPrefs = JSON.stringify(notificationPrefs);
        } catch {
          return errResp(res, 400, 'Invalid notificationPrefs');
        }
      } else {
        return errResp(res, 400, 'Invalid notificationPrefs');
      }
    }

    const user = await prisma.user.update({
      where: { id: req.user.id },
      data,
      include: { shopMemberships: { include: { shop: true } } },
    });
    res.json({ user: serializeUser(user) });
  } catch (err) { next(err); }
});

function serializeUser(user) {
  let prefs = null;
  if (user.notificationPrefs) {
    try { prefs = JSON.parse(user.notificationPrefs); } catch { prefs = null; }
  }
  return {
    id: user.id,
    phone: user.phone,
    name: user.name,
    avatarUrl: user.avatarUrl,
    isBuyer: user.isBuyer,
    isCourier: user.isCourier,
    isShop: user.isShop,
    isAdmin: user.isAdmin,
    locale: user.locale,
    country: user.country || 'UZ',
    notificationPrefs: prefs,
    courierStatus: user.courierStatus,
    rating: user.rating,
    ordersCount: user.ordersCount,
    shops: user.shopMemberships?.map((m) => ({
      id: m.shop.id,
      name: m.shop.name,
      role: m.role,
    })) || [],
  };
}

module.exports = router;
