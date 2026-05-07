// Coupon endpoints — buyer-facing validate/list, admin CRUD.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware, requireAdmin } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const { validateCoupon, computeDiscount, VALID_TYPES } = require('../services/coupons');

function normalizeCode(c) {
  return String(c || '').trim().toUpperCase();
}

function couponBodyValidationErrors(body, { partial = false } = {}) {
  const errors = [];
  if (!partial || body.type !== undefined) {
    if (!VALID_TYPES.includes(body.type)) errors.push('type must be PERCENT|FIXED|FREE_DELIVERY');
  }
  if (!partial || body.value !== undefined) {
    const v = Number(body.value);
    if (!Number.isFinite(v) || v < 0) errors.push('value must be a non-negative number');
    if (body.type === 'PERCENT' && (v <= 0 || v > 100)) errors.push('PERCENT value must be 1..100');
  }
  if (!partial || body.validFrom !== undefined) {
    if (!body.validFrom || Number.isNaN(new Date(body.validFrom).getTime())) {
      errors.push('validFrom required (ISO date)');
    }
  }
  if (!partial || body.validUntil !== undefined) {
    if (!body.validUntil || Number.isNaN(new Date(body.validUntil).getTime())) {
      errors.push('validUntil required (ISO date)');
    }
  }
  if (body.validFrom && body.validUntil &&
      new Date(body.validFrom) >= new Date(body.validUntil)) {
    errors.push('validUntil must be after validFrom');
  }
  if (body.usageLimit != null) {
    const n = Number(body.usageLimit);
    if (!Number.isInteger(n) || n < 0) errors.push('usageLimit must be a non-negative integer');
  }
  if (body.usagePerUser != null) {
    const n = Number(body.usagePerUser);
    if (!Number.isInteger(n) || n < 1) errors.push('usagePerUser must be >= 1');
  }
  return errors;
}

// ─── POST /api/coupons/validate ──────────────────────────────────────────────
router.post('/validate', authMiddleware, async (req, res, next) => {
  try {
    const { code, shopId, vertical, subtotal, deliveryFee = 0 } = req.body || {};
    if (!code) return res.status(400).json({ error: 'code required' });
    const result = await validateCoupon(prisma, {
      code: normalizeCode(code),
      userId: req.user.id,
      vertical,
      shopId,
      subtotal: Number(subtotal) || 0,
      deliveryFee: Number(deliveryFee) || 0,
    });
    if (!result.valid) {
      return res.json({ valid: false, discount: 0, reason: result.reason });
    }
    return res.json({ valid: true, discount: result.discount, coupon: {
      code: result.coupon.code,
      type: result.coupon.type,
      value: result.coupon.value,
      maxDiscount: result.coupon.maxDiscount,
    } });
  } catch (err) { next(err); }
});

// ─── GET /api/coupons — admin lists active coupons ───────────────────────────
router.get('/', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const coupons = await prisma.coupon.findMany({
      where: { isActive: true },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json({ coupons });
  } catch (err) { next(err); }
});

// ─── POST /api/coupons — create ──────────────────────────────────────────────
router.post('/', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const body = req.body || {};
    const errs = couponBodyValidationErrors(body);
    if (errs.length) return res.status(400).json({ error: errs.join('; ') });
    const code = normalizeCode(body.code);
    if (!code) return res.status(400).json({ error: 'code required' });

    const existing = await prisma.coupon.findUnique({ where: { code } });
    if (existing) return res.status(409).json({ error: 'Coupon already exists' });

    const coupon = await prisma.coupon.create({
      data: {
        code,
        type: body.type,
        value: Number(body.value) || 0,
        minOrder: body.minOrder != null ? Number(body.minOrder) : null,
        maxDiscount: body.maxDiscount != null ? Number(body.maxDiscount) : null,
        validFrom: new Date(body.validFrom),
        validUntil: new Date(body.validUntil),
        usageLimit: body.usageLimit != null ? Number(body.usageLimit) : null,
        usagePerUser: body.usagePerUser != null ? Number(body.usagePerUser) : 1,
        vertical: body.vertical || null,
        shopId: body.shopId || null,
        firstOrderOnly: !!body.firstOrderOnly,
        isActive: body.isActive == null ? true : !!body.isActive,
      },
    });
    audit({ actorId: req.user.id, action: 'coupon.create', targetType: 'Coupon', targetId: code });
    res.status(201).json({ coupon });
  } catch (err) { next(err); }
});

// ─── PATCH /api/coupons/:code ────────────────────────────────────────────────
router.patch('/:code', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const code = normalizeCode(req.params.code);
    const existing = await prisma.coupon.findUnique({ where: { code } });
    if (!existing) return res.status(404).json({ error: 'Not found' });

    const body = req.body || {};
    const errs = couponBodyValidationErrors(body, { partial: true });
    if (errs.length) return res.status(400).json({ error: errs.join('; ') });

    const data = {};
    const fields = ['type', 'value', 'minOrder', 'maxDiscount', 'usageLimit',
      'usagePerUser', 'vertical', 'shopId', 'firstOrderOnly', 'isActive'];
    for (const f of fields) {
      if (body[f] !== undefined) {
        if (['value', 'minOrder', 'maxDiscount', 'usageLimit', 'usagePerUser'].includes(f)) {
          data[f] = body[f] == null ? null : Number(body[f]);
        } else if (['firstOrderOnly', 'isActive'].includes(f)) {
          data[f] = !!body[f];
        } else {
          data[f] = body[f] == null ? null : body[f];
        }
      }
    }
    if (body.validFrom !== undefined) data.validFrom = new Date(body.validFrom);
    if (body.validUntil !== undefined) data.validUntil = new Date(body.validUntil);

    const coupon = await prisma.coupon.update({ where: { code }, data });
    audit({ actorId: req.user.id, action: 'coupon.update', targetType: 'Coupon', targetId: code });
    res.json({ coupon });
  } catch (err) { next(err); }
});

// ─── DELETE /api/coupons/:code ───────────────────────────────────────────────
router.delete('/:code', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const code = normalizeCode(req.params.code);
    const existing = await prisma.coupon.findUnique({ where: { code } });
    if (!existing) return res.status(404).json({ error: 'Not found' });

    const used = await prisma.couponRedemption.count({ where: { couponCode: code } });
    if (used > 0) {
      return res.status(409).json({ error: 'Coupon has redemptions; deactivate instead' });
    }
    await prisma.coupon.delete({ where: { code } });
    audit({ actorId: req.user.id, action: 'coupon.delete', targetType: 'Coupon', targetId: code });
    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ─── GET /api/coupons/me/eligible ────────────────────────────────────────────
router.get('/me/eligible', authMiddleware, async (req, res, next) => {
  try {
    const subtotal = Number(req.query.subtotal) || 0;
    const shopId = req.query.shopId || null;

    let vertical = null;
    if (shopId) {
      const shop = await prisma.shop.findUnique({ where: { id: shopId } });
      if (shop) vertical = shop.vertical;
    }

    const now = new Date();
    const candidates = await prisma.coupon.findMany({
      where: {
        isActive: true,
        validFrom: { lte: now },
        validUntil: { gte: now },
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });

    const eligible = [];
    for (const c of candidates) {
      // Pre-filter scope cheaply.
      if (c.shopId && shopId && c.shopId !== shopId) continue;
      if (c.vertical && vertical && c.vertical !== vertical) continue;
      const result = await validateCoupon(prisma, {
        code: c.code,
        userId: req.user.id,
        vertical,
        shopId,
        subtotal,
      });
      if (result.valid) {
        eligible.push({
          code: c.code,
          type: c.type,
          value: c.value,
          maxDiscount: c.maxDiscount,
          discount: result.discount,
          minOrder: c.minOrder,
          validUntil: c.validUntil,
        });
      }
    }
    res.json({ coupons: eligible });
  } catch (err) { next(err); }
});

module.exports = router;
module.exports.computeDiscount = computeDiscount;
