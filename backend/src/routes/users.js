const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const logger = require('../lib/logger');
const country = require('../services/country');

// Phase 7 — supported locales (mirror auth.js).
const VALID_LOCALES = new Set(['uz', 'ru', 'en', 'kk']);

// ─── PATCH /api/users/me — Phase 7 multi-country profile update ─────────────
// Body: { country?, locale?, name? }
//   • country must be a key of services/country.js COUNTRIES (UZ, KZ, KG, RU)
//   • locale must be uz | ru | en | kk
//   • name is trimmed; empty string → null
// Returns the patched user.
router.patch('/me', authMiddleware, async (req, res, next) => {
  try {
    const { country: countryCode, locale, name } = req.body || {};
    const data = {};

    if (countryCode !== undefined) {
      if (typeof countryCode !== 'string' || !Object.prototype.hasOwnProperty.call(country.COUNTRIES, countryCode)) {
        return res.status(400).json({
          error: 'Invalid country',
          allowed: Object.keys(country.COUNTRIES),
        });
      }
      data.country = countryCode;
    }

    if (locale !== undefined) {
      if (typeof locale !== 'string' || !VALID_LOCALES.has(locale)) {
        return res.status(400).json({
          error: 'Invalid locale',
          allowed: ['uz', 'ru', 'en', 'kk'],
        });
      }
      data.locale = locale;
    }

    if (name !== undefined) {
      if (typeof name !== 'string') {
        return res.status(400).json({ error: 'Invalid name' });
      }
      data.name = name.trim() || null;
    }

    // Phase 11 — onboardedAt is a "complete the intro" stamp. Server-controlled:
    // we set new Date() whenever the field is present in the body, regardless
    // of the value the client sent ("now", an ISO string, or anything truthy).
    // The Flutter side just needs a way to flip the flag.
    if ('onboardedAt' in (req.body || {})) {
      data.onboardedAt = new Date();
    }

    if (Object.keys(data).length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    const user = await prisma.user.update({
      where: { id: req.user.id },
      data,
    });

    res.json({
      user: {
        id: user.id,
        phone: user.phone,
        name: user.name,
        locale: user.locale,
        country: user.country || 'UZ',
        onboardedAt: user.onboardedAt,
      },
    });
  } catch (err) { next(err); }
});

// ─── GET /api/users/me/onboarding-status — Phase 11 ─────────────────────────
// Returns whether the buyer has completed the first-run intro flow. Cheap
// endpoint hit on every cold start by the Flutter app to decide whether to
// show the 3-slide intro + role select.
router.get('/me/onboarding-status', authMiddleware, async (req, res, next) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
      select: { onboardedAt: true },
    });
    if (!user) return res.status(404).json({ error: 'User not found' });
    const onboarded = !!user.onboardedAt;
    res.json({
      onboarded,
      ...(onboarded ? { completedAt: user.onboardedAt } : {}),
    });
  } catch (err) { next(err); }
});

// ─── GET /api/users/me/stats — buyer stats ───────────────────────────────────
router.get('/me/stats', authMiddleware, async (req, res, next) => {
  try {
    const [total, active, delivered] = await Promise.all([
      prisma.order.count({ where: { buyerId: req.user.id } }),
      prisma.order.count({
        where: { buyerId: req.user.id, status: { notIn: ['delivered', 'confirmedByBuyer', 'cancelled'] } },
      }),
      prisma.order.count({
        where: { buyerId: req.user.id, status: { in: ['delivered', 'confirmedByBuyer'] } },
      }),
    ]);
    res.json({ total, active, delivered });
  } catch (err) { next(err); }
});

// ─── GET /api/users/addresses ────────────────────────────────────────────────
router.get('/addresses', authMiddleware, async (req, res, next) => {
  try {
    const addresses = await prisma.address.findMany({
      where: { userId: req.user.id },
      orderBy: [{ isDefault: 'desc' }, { id: 'asc' }],
    });
    res.json({ addresses });
  } catch (err) { next(err); }
});

// ─── POST /api/users/addresses ───────────────────────────────────────────────
router.post('/addresses', authMiddleware, async (req, res, next) => {
  try {
    const {
      label, fullAddress, lat, lng, comment, isDefault,
      entrance, floor, apartment, intercom, instructions,
    } = req.body || {};
    if (!label || !fullAddress) return res.status(400).json({ error: 'label and fullAddress required' });

    if (isDefault) {
      await prisma.address.updateMany({
        where: { userId: req.user.id }, data: { isDefault: false },
      });
    }
    const address = await prisma.address.create({
      data: {
        userId: req.user.id,
        label, fullAddress, lat, lng, comment,
        isDefault: !!isDefault,
        entrance, floor, apartment, intercom, instructions,
      },
    });
    res.status(201).json({ address });
  } catch (err) { next(err); }
});

// ─── PATCH /api/users/addresses/:id ──────────────────────────────────────────
router.patch('/addresses/:id', authMiddleware, async (req, res, next) => {
  try {
    const existing = await prisma.address.findUnique({ where: { id: req.params.id } });
    if (!existing || existing.userId !== req.user.id) {
      return res.status(404).json({ error: 'Address not found' });
    }
    const fields = ['label', 'fullAddress', 'lat', 'lng', 'comment',
      'entrance', 'floor', 'apartment', 'intercom', 'instructions'];
    const data = {};
    for (const f of fields) if (f in req.body) data[f] = req.body[f];
    if ('isDefault' in req.body) {
      data.isDefault = !!req.body.isDefault;
      if (data.isDefault) {
        await prisma.address.updateMany({
          where: { userId: req.user.id, id: { not: req.params.id } },
          data: { isDefault: false },
        });
      }
    }
    const address = await prisma.address.update({ where: { id: req.params.id }, data });
    res.json({ address });
  } catch (err) { next(err); }
});

// ─── POST /api/users/addresses/:id/default ───────────────────────────────────
// Mark this address as the user's default. Unsets every other address atomically.
router.post('/addresses/:id/default', authMiddleware, async (req, res, next) => {
  try {
    const existing = await prisma.address.findUnique({ where: { id: req.params.id } });
    if (!existing || existing.userId !== req.user.id) {
      return res.status(404).json({ error: 'Address not found' });
    }
    const [, address] = await prisma.$transaction([
      prisma.address.updateMany({
        where: { userId: req.user.id, id: { not: req.params.id } },
        data: { isDefault: false },
      }),
      prisma.address.update({
        where: { id: req.params.id },
        data: { isDefault: true },
      }),
    ]);
    res.json({ address });
  } catch (err) { next(err); }
});

// ─── DELETE /api/users/addresses/:id ─────────────────────────────────────────
router.delete('/addresses/:id', authMiddleware, async (req, res, next) => {
  try {
    const existing = await prisma.address.findUnique({ where: { id: req.params.id } });
    if (!existing || existing.userId !== req.user.id) {
      return res.status(404).json({ error: 'Address not found' });
    }
    await prisma.address.delete({ where: { id: req.params.id } });
    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ─── POST /api/users/fcm-token — register FCM device token ───────────────────
router.post('/fcm-token', authMiddleware, async (req, res, next) => {
  try {
    const { token, platform } = req.body || {};
    if (!token || typeof token !== 'string' || token.length < 16) {
      return res.status(400).json({ error: 'Invalid token' });
    }
    const plat = ['android', 'ios', 'web'].includes(platform) ? platform : 'android';
    // Upsert by token: if it's already on a different user (re-installed app) we
    // re-bind to current user. The unique constraint on `token` enforces this.
    await prisma.fcmToken.upsert({
      where: { token },
      create: { userId: req.user.id, token, platform: plat },
      update: { userId: req.user.id, platform: plat, lastSeenAt: new Date() },
    });
    res.json({ ok: true });
  } catch (err) {
    logger.warn({ err: err.message }, 'fcm-token register failed');
    next(err);
  }
});

// ─── DELETE /api/users/fcm-token — unregister (called on logout) ─────────────
router.delete('/fcm-token', authMiddleware, async (req, res, next) => {
  try {
    const token = req.body?.token || req.query?.token;
    if (!token) return res.status(400).json({ error: 'token required' });
    await prisma.fcmToken.deleteMany({ where: { token, userId: req.user.id } });
    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ─── PATCH /api/users/me/notification-prefs ──────────────────────────────────
router.patch('/me/notification-prefs', authMiddleware, async (req, res, next) => {
  try {
    const prefs = req.body || {};
    const allowed = { promo: !!prefs.promo, orderUpdates: prefs.orderUpdates !== false, sound: prefs.sound !== false };
    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: { notificationPrefs: JSON.stringify(allowed) },
    });
    await audit({ actorId: req.user.id, action: 'user.update_prefs', metadata: allowed, ipAddress: req.ip });
    res.json({ notificationPrefs: allowed, ok: true, userId: user.id });
  } catch (err) { next(err); }
});

module.exports = router;
