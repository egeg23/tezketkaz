const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const shopHours = require('../services/shopHours');

// Phase 6.4 — annotate a shop with currentlyOpen + opensAt + currency.
// Mutates a shallow copy and returns it.
async function enrichShop(shop, hoursById = null) {
  if (!shop) return shop;
  let workingHours;
  if (hoursById) {
    workingHours = hoursById.get(shop.id) || [];
  } else {
    workingHours = await prisma.shopWorkingHours.findMany({
      where: { shopId: shop.id },
      orderBy: [{ dayOfWeek: 'asc' }, { startsAt: 'asc' }],
    });
  }
  const isOpen = shopHours.isOpenNow({ ...shop, workingHours });
  const out = {
    ...shop,
    currency: shop.currency || 'UZS',
    workingHours,
    currentlyOpen: isOpen,
  };
  if (!isOpen) {
    const next = shopHours.nextOpenAt({ ...shop, workingHours });
    out.opensAt = next ? next.toISOString() : null;
  } else {
    out.opensAt = null;
  }
  return out;
}

// Great-circle distance in km using the haversine formula.
function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// ─── GET /api/shops ──────────────────────────────────────────────────────────
// Public list with optional geo filter.
//   vertical, isActive (default true), q (LIKE on name)
//   lat,lng,radiusKm — if all three provided, filters + sorts by distance ASC
//   limit (default 30, max 100)
router.get('/', async (req, res, next) => {
  try {
    const { vertical, q } = req.query;
    const limit = Math.min(parseInt(req.query.limit, 10) || 30, 100);

    const where = {};
    if (req.query.isActive === undefined) {
      where.isActive = true;
    } else {
      where.isActive = req.query.isActive === 'true' || req.query.isActive === '1';
    }
    if (vertical) where.vertical = vertical;
    if (q && String(q).trim()) {
      where.name = { contains: String(q) };
    }

    const lat = req.query.lat !== undefined ? Number(req.query.lat) : null;
    const lng = req.query.lng !== undefined ? Number(req.query.lng) : null;
    const radiusKm = req.query.radiusKm !== undefined ? Number(req.query.radiusKm) : null;
    const geo = Number.isFinite(lat) && Number.isFinite(lng) && Number.isFinite(radiusKm);

    let shops;
    if (geo) {
      // Fetch a reasonably wide pool (we have to compute distance in JS). Cap
      // the working set at 1000 to keep memory bounded.
      const pool = await prisma.shop.findMany({ where, take: 1000 });
      const withDist = [];
      for (const s of pool) {
        if (s.lat == null || s.lng == null) continue;
        const distanceKm = haversineKm(lat, lng, s.lat, s.lng);
        if (distanceKm <= radiusKm) withDist.push({ ...s, distanceKm });
      }
      withDist.sort((a, b) => a.distanceKm - b.distanceKm);
      shops = withDist.slice(0, limit);
    } else {
      shops = await prisma.shop.findMany({
        where,
        orderBy: { rating: 'desc' },
        take: limit,
      });
    }

    // Batch-load working hours for the result set so we don't do N queries.
    let hoursById = new Map();
    if (shops.length > 0) {
      const ids = shops.map((s) => s.id);
      const hours = await prisma.shopWorkingHours.findMany({
        where: { shopId: { in: ids } },
        orderBy: [{ dayOfWeek: 'asc' }, { startsAt: 'asc' }],
      });
      for (const h of hours) {
        const arr = hoursById.get(h.shopId) || [];
        arr.push(h);
        hoursById.set(h.shopId, arr);
      }
    }
    const enriched = await Promise.all(shops.map((s) => enrichShop(s, hoursById)));

    res.json({ items: enriched, shops: enriched, total: enriched.length });
  } catch (err) { next(err); }
});

// ─── GET /api/shops/:id ──────────────────────────────────────────────────────
router.get('/:id', async (req, res, next) => {
  try {
    const shop = await prisma.shop.findUnique({
      where: { id: req.params.id },
      include: { products: { where: { isAvailable: true } } },
    });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });
    const enriched = await enrichShop(shop);
    res.json({ shop: enriched });
  } catch (err) { next(err); }
});

// ─── POST /api/shops/connect ─────────────────────────────────────────────────
// Прототип — в реальности магазин подключается через invite-код
router.post('/connect', authMiddleware, async (req, res, next) => {
  try {
    const { shopId } = req.body;
    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });

    await prisma.shopMember.upsert({
      where: { userId_shopId: { userId: req.user.id, shopId } },
      update: {},
      create: { userId: req.user.id, shopId, role: 'manager' },
    });

    await prisma.user.update({
      where: { id: req.user.id },
      data: { isShop: true },
    });

    res.json({ success: true });
  } catch (err) { next(err); }
});

module.exports = router;
