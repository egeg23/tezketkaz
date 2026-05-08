// Phase 6.4 — shop working hours.
//
// Public read; owner/admin write. We declare absolute paths under /api/shops
// so this router can be mounted at /api alongside the other shop-relative
// routers (zones, modifiers).

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { audit } = require('../lib/audit');

const HHMM_RE = /^(\d{1,2}):(\d{1,2})$/;

function isValidHHMM(s) {
  if (typeof s !== 'string') return false;
  const m = HHMM_RE.exec(s.trim());
  if (!m) return false;
  const hh = parseInt(m[1], 10);
  const mm = parseInt(m[2], 10);
  if (!Number.isFinite(hh) || !Number.isFinite(mm)) return false;
  if (hh < 0 || hh > 24 || mm < 0 || mm > 59) return false;
  // Accept 24:00 as end-of-day shorthand.
  if (hh === 24 && mm !== 0) return false;
  return true;
}

async function isShopOwnerOrAdmin(user, shopId) {
  if (!user) return false;
  if (user.isAdmin) return true;
  const m = await prisma.shopMember.findUnique({
    where: { userId_shopId: { userId: user.id, shopId } },
  });
  return !!m && (m.role === 'owner' || m.role === 'manager');
}

// ─── GET /api/shops/:shopId/working-hours ────────────────────────────────────
// Public. Returns rows ordered by dayOfWeek (Sun..Sat). May return 0–N rows
// per day.
router.get('/shops/:shopId/working-hours', async (req, res, next) => {
  try {
    const shop = await prisma.shop.findUnique({ where: { id: req.params.shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });

    const rows = await prisma.shopWorkingHours.findMany({
      where: { shopId: req.params.shopId },
      orderBy: [{ dayOfWeek: 'asc' }, { startsAt: 'asc' }],
    });
    res.json({ items: rows });
  } catch (err) { next(err); }
});

// ─── PUT /api/shops/:shopId/working-hours ────────────────────────────────────
// Owner/admin. Replaces all rows in a single transaction so the schedule
// is always coherent.
router.put('/shops/:shopId/working-hours', authMiddleware, async (req, res, next) => {
  try {
    const shopId = req.params.shopId;
    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });
    if (!(await isShopOwnerOrAdmin(req.user, shopId))) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const body = Array.isArray(req.body) ? req.body : req.body && req.body.items;
    if (!Array.isArray(body)) {
      return res.status(400).json({ error: 'expected_array' });
    }

    // Validate every row before any DB write.
    const cleaned = [];
    for (const row of body) {
      if (!row || typeof row !== 'object') {
        return res.status(400).json({ error: 'invalid_row' });
      }
      const dow = Number(row.dayOfWeek);
      if (!Number.isInteger(dow) || dow < 0 || dow > 6) {
        return res.status(400).json({ error: 'invalid_dayOfWeek' });
      }
      const isClosed = !!row.isClosed;
      let startsAt = row.startsAt || '00:00';
      let endsAt = row.endsAt || '00:00';
      if (!isClosed) {
        if (!isValidHHMM(startsAt) || !isValidHHMM(endsAt)) {
          return res.status(400).json({ error: 'invalid_time_format' });
        }
      }
      cleaned.push({
        shopId,
        dayOfWeek: dow,
        startsAt: String(startsAt),
        endsAt: String(endsAt),
        isClosed,
      });
    }

    await prisma.$transaction(async (tx) => {
      await tx.shopWorkingHours.deleteMany({ where: { shopId } });
      for (const row of cleaned) {
        await tx.shopWorkingHours.create({ data: row });
      }
    });

    audit({
      actorId: req.user.id,
      action: 'shop.working_hours.update',
      targetType: 'Shop',
      targetId: shopId,
      metadata: { rowCount: cleaned.length },
    });

    const rows = await prisma.shopWorkingHours.findMany({
      where: { shopId },
      orderBy: [{ dayOfWeek: 'asc' }, { startsAt: 'asc' }],
    });
    res.json({ items: rows });
  } catch (err) { next(err); }
});

module.exports = router;
