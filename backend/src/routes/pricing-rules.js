// Admin-only PricingRule CRUD. Mounted at /api/admin/pricing-rules so all
// route paths here are relative.
//
//   GET    /                 list (?active=1 to filter active+current)
//   POST   /                 create
//   PATCH  /:id              update
//   DELETE /:id              delete

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware, requireAdmin } = require('../middleware/auth');

router.use(authMiddleware, requireAdmin);

const FIELDS = ['vertical', 'zoneId', 'surgeFactor', 'reason', 'validFrom', 'validUntil', 'isActive'];

function pickFields(input) {
  const out = {};
  for (const k of FIELDS) {
    if (input[k] !== undefined) out[k] = input[k];
  }
  if (out.surgeFactor !== undefined) out.surgeFactor = Number(out.surgeFactor);
  if (out.validFrom !== undefined && out.validFrom !== null) out.validFrom = new Date(out.validFrom);
  if (out.validUntil !== undefined && out.validUntil !== null) out.validUntil = new Date(out.validUntil);
  if (out.isActive !== undefined) out.isActive = Boolean(out.isActive);
  return out;
}

function validate(data, { partial = false } = {}) {
  const errors = [];
  if (!partial || data.surgeFactor !== undefined) {
    if (data.surgeFactor === undefined || data.surgeFactor === null) {
      errors.push('surgeFactor required');
    } else if (!Number.isFinite(data.surgeFactor) || data.surgeFactor < 0.1 || data.surgeFactor > 5) {
      errors.push('surgeFactor must be between 0.1 and 5');
    }
  }
  if (!partial || data.reason !== undefined) {
    if (!data.reason || !String(data.reason).trim()) errors.push('reason required');
  }
  for (const k of ['validFrom', 'validUntil']) {
    if (!partial || data[k] !== undefined) {
      if (!data[k] || isNaN(data[k]?.getTime?.())) errors.push(`${k} required (ISO date)`);
    }
  }
  if (data.validFrom && data.validUntil && data.validFrom >= data.validUntil) {
    errors.push('validFrom must be before validUntil');
  }
  return errors;
}

// ─── GET / ────────────────────────────────────────────────────────────────
router.get('/', async (req, res, next) => {
  try {
    const where = {};
    if (req.query.active === '1' || req.query.active === 'true') {
      const now = new Date();
      where.isActive = true;
      where.validFrom = { lte: now };
      where.validUntil = { gte: now };
    }
    const rules = await prisma.pricingRule.findMany({
      where,
      orderBy: [{ validFrom: 'desc' }],
      take: 200,
    });
    res.json({ rules });
  } catch (err) { next(err); }
});

// ─── POST / ───────────────────────────────────────────────────────────────
router.post('/', async (req, res, next) => {
  try {
    const data = pickFields(req.body || {});
    const errors = validate(data);
    if (errors.length) return res.status(400).json({ error: errors.join('; ') });

    if (data.zoneId) {
      const zone = await prisma.deliveryZone.findUnique({ where: { id: data.zoneId } });
      if (!zone) return res.status(400).json({ error: 'zoneId does not exist' });
    }

    const rule = await prisma.pricingRule.create({
      data: {
        vertical: data.vertical ?? null,
        zoneId: data.zoneId ?? null,
        surgeFactor: data.surgeFactor,
        reason: String(data.reason).trim(),
        validFrom: data.validFrom,
        validUntil: data.validUntil,
        isActive: data.isActive ?? true,
      },
    });
    res.status(201).json({ rule });
  } catch (err) { next(err); }
});

// ─── PATCH /:id ───────────────────────────────────────────────────────────
router.patch('/:id', async (req, res, next) => {
  try {
    const existing = await prisma.pricingRule.findUnique({ where: { id: req.params.id } });
    if (!existing) return res.status(404).json({ error: 'Not found' });

    const data = pickFields(req.body || {});
    const errors = validate(
      { ...existing, ...data, validFrom: data.validFrom ?? existing.validFrom, validUntil: data.validUntil ?? existing.validUntil },
      { partial: true },
    );
    if (errors.length) return res.status(400).json({ error: errors.join('; ') });

    if (data.zoneId) {
      const zone = await prisma.deliveryZone.findUnique({ where: { id: data.zoneId } });
      if (!zone) return res.status(400).json({ error: 'zoneId does not exist' });
    }

    const updated = await prisma.pricingRule.update({
      where: { id: existing.id },
      data,
    });
    res.json({ rule: updated });
  } catch (err) { next(err); }
});

// ─── DELETE /:id ──────────────────────────────────────────────────────────
router.delete('/:id', async (req, res, next) => {
  try {
    const existing = await prisma.pricingRule.findUnique({ where: { id: req.params.id } });
    if (!existing) return res.status(404).json({ error: 'Not found' });
    await prisma.pricingRule.delete({ where: { id: existing.id } });
    res.json({ deleted: true });
  } catch (err) { next(err); }
});

module.exports = router;
