// Delivery-zone CRUD.
//
// Routes inside this router use absolute paths so it MUST be mounted at /api.
//   GET    /api/shops/:shopId/zones        — public list (active by default)
//   POST   /api/shops/:shopId/zones        — owner/admin create
//   GET    /api/zones/:zoneId              — public read
//   PATCH  /api/zones/:zoneId              — owner/admin update
//   DELETE /api/zones/:zoneId              — owner/admin delete

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');

async function isShopMember(userId, shopId) {
  if (!userId || !shopId) return false;
  const m = await prisma.shopMember.findUnique({
    where: { userId_shopId: { userId, shopId } },
  });
  return !!m;
}

async function canManageShop(user, shopId) {
  if (!user) return false;
  if (user.isAdmin) return true;
  return isShopMember(user.id, shopId);
}

// Validate a polygon submitted by a client. Accepts either a JSON string or
// a parsed array. Returns { ok, polygon, error }.
function validatePolygon(raw) {
  let arr = raw;
  if (typeof raw === 'string') {
    try { arr = JSON.parse(raw); } catch { return { ok: false, error: 'polygon must be valid JSON' }; }
  }
  if (!Array.isArray(arr)) return { ok: false, error: 'polygon must be an array' };
  if (arr.length < 3) return { ok: false, error: 'polygon must have at least 3 points' };
  for (const p of arr) {
    if (!Array.isArray(p) || p.length < 2) {
      return { ok: false, error: 'polygon point must be [lat,lng]' };
    }
    const [lat, lng] = p;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return { ok: false, error: 'polygon points must be numeric' };
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return { ok: false, error: 'polygon points out of valid lat/lng range' };
    }
  }
  return { ok: true, polygon: arr };
}

// Map allowed body fields onto the Prisma data shape, coercing numerics.
const ZONE_FIELDS = [
  'name', 'baseFee', 'perKmFee', 'freeKm', 'minOrder',
  'startsAt', 'endsAt', 'isActive', 'sortOrder',
];
function pickZoneFields(input) {
  const out = {};
  for (const k of ZONE_FIELDS) {
    if (input[k] !== undefined) out[k] = input[k];
  }
  for (const k of ['baseFee', 'perKmFee', 'freeKm', 'minOrder']) {
    if (out[k] !== undefined && out[k] !== null) out[k] = Number(out[k]);
  }
  if (out.sortOrder !== undefined) out.sortOrder = parseInt(out.sortOrder, 10) || 0;
  if (out.isActive !== undefined) out.isActive = Boolean(out.isActive);
  return out;
}

// Optional auth shim — like optionalAuth in middleware/auth.js but tolerant
// for use only here so `?all=1` checks still work when caller is admin/owner.
async function maybeAuth(req, _res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) return next();
  try {
    const jwtLib = require('../lib/jwt');
    const decoded = await jwtLib.verifyAccess(header.substring(7));
    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      include: { shopMemberships: true },
    });
    if (user) req.user = user;
  } catch {
    // ignore — public read still works
  }
  next();
}

// ─── GET /api/shops/:shopId/zones — public list ─────────────────────────────
router.get('/shops/:shopId/zones', maybeAuth, async (req, res, next) => {
  try {
    const { shopId } = req.params;
    const wantAll = req.query.all === '1' || req.query.all === 'true';
    const where = { shopId };

    let allowAll = false;
    if (wantAll) {
      allowAll = await canManageShop(req.user, shopId);
    }
    if (!allowAll) where.isActive = true;

    const zones = await prisma.deliveryZone.findMany({
      where,
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
    });
    res.json({ zones });
  } catch (err) { next(err); }
});

// ─── POST /api/shops/:shopId/zones — create ─────────────────────────────────
router.post('/shops/:shopId/zones', authMiddleware, async (req, res, next) => {
  try {
    const { shopId } = req.params;
    if (!(await canManageShop(req.user, shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }
    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });

    const { name } = req.body || {};
    if (!name || !String(name).trim()) {
      return res.status(400).json({ error: 'name required' });
    }
    const polyCheck = validatePolygon(req.body.polygon);
    if (!polyCheck.ok) return res.status(400).json({ error: polyCheck.error });

    const fields = pickZoneFields(req.body);
    const zone = await prisma.deliveryZone.create({
      data: {
        shopId,
        name: String(name).trim(),
        polygon: JSON.stringify(polyCheck.polygon),
        baseFee: fields.baseFee ?? 12000,
        perKmFee: fields.perKmFee ?? 2000,
        freeKm: fields.freeKm ?? 2,
        minOrder: fields.minOrder ?? 0,
        startsAt: fields.startsAt ?? null,
        endsAt: fields.endsAt ?? null,
        isActive: fields.isActive ?? true,
        sortOrder: fields.sortOrder ?? 0,
      },
    });
    res.status(201).json({ zone });
  } catch (err) { next(err); }
});

// ─── GET /api/zones/:zoneId — public read ──────────────────────────────────
router.get('/zones/:zoneId', async (req, res, next) => {
  try {
    const zone = await prisma.deliveryZone.findUnique({
      where: { id: req.params.zoneId },
    });
    if (!zone) return res.status(404).json({ error: 'Not found' });
    res.json({ zone });
  } catch (err) { next(err); }
});

// ─── PATCH /api/zones/:zoneId — owner/admin update ─────────────────────────
router.patch('/zones/:zoneId', authMiddleware, async (req, res, next) => {
  try {
    const zone = await prisma.deliveryZone.findUnique({
      where: { id: req.params.zoneId },
    });
    if (!zone) return res.status(404).json({ error: 'Not found' });
    if (!(await canManageShop(req.user, zone.shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }

    const data = pickZoneFields(req.body || {});
    if (req.body && req.body.polygon !== undefined) {
      const polyCheck = validatePolygon(req.body.polygon);
      if (!polyCheck.ok) return res.status(400).json({ error: polyCheck.error });
      data.polygon = JSON.stringify(polyCheck.polygon);
    }
    if (data.name !== undefined) data.name = String(data.name).trim();

    const updated = await prisma.deliveryZone.update({
      where: { id: zone.id },
      data,
    });
    res.json({ zone: updated });
  } catch (err) { next(err); }
});

// ─── DELETE /api/zones/:zoneId — owner/admin ────────────────────────────────
router.delete('/zones/:zoneId', authMiddleware, async (req, res, next) => {
  try {
    const zone = await prisma.deliveryZone.findUnique({
      where: { id: req.params.zoneId },
    });
    if (!zone) return res.status(404).json({ error: 'Not found' });
    if (!(await canManageShop(req.user, zone.shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }
    await prisma.deliveryZone.delete({ where: { id: zone.id } });
    res.json({ deleted: true });
  } catch (err) { next(err); }
});

module.exports = router;
