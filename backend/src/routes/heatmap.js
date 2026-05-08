// Phase 8.4 — courier demand heatmap.
// GET /api/couriers/heatmap?lat=&lng=&radiusKm=10
// Returns a coarse 1km grid of unassigned orders in the last 60 minutes,
// optionally filtered by a courier-supplied centre + radius.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware, requireRole } = require('../middleware/auth');
const { distanceKm } = require('../lib/geo');
const logger = require('../lib/logger');

const WINDOW_MS = 60 * 60 * 1000; // last hour
const DEFAULT_RADIUS_KM = 10;
const MAX_RADIUS_KM = 50;
const MAX_CELLS = 200;
// Bucket lat/lng to 0.01° (~1.1km) — coarse enough to anonymise individual
// drops but fine enough to show meaningful density clusters.
const GRID_DEG = 0.01;

const ACTIVE_DEMAND_STATUSES = [
  'paid', 'confirmed', 'collecting', 'readyForPickup', 'courierSearching',
];

function bucket(v) {
  return Math.round(v / GRID_DEG) * GRID_DEG;
}

router.get('/heatmap', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const lat = req.query.lat != null ? Number(req.query.lat) : null;
    const lng = req.query.lng != null ? Number(req.query.lng) : null;
    let radiusKm = req.query.radiusKm != null ? Number(req.query.radiusKm) : DEFAULT_RADIUS_KM;
    if (!Number.isFinite(radiusKm) || radiusKm <= 0) radiusKm = DEFAULT_RADIUS_KM;
    radiusKm = Math.min(MAX_RADIUS_KM, radiusKm);

    const since = new Date(Date.now() - WINDOW_MS);

    const orders = await prisma.order.findMany({
      where: {
        createdAt: { gte: since },
        courierId: null,
        status: { in: ACTIVE_DEMAND_STATUSES },
      },
      select: {
        id: true,
        shop: { select: { lat: true, lng: true } },
      },
    });

    const cellMap = new Map();
    for (const o of orders) {
      const sLat = o.shop?.lat;
      const sLng = o.shop?.lng;
      if (sLat == null || sLng == null) continue;
      if (!Number.isFinite(sLat) || !Number.isFinite(sLng)) continue;
      // Optional radius filter from courier-supplied centre.
      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        const d = distanceKm(lat, lng, sLat, sLng);
        if (!Number.isFinite(d) || d > radiusKm) continue;
      }
      const cLat = bucket(sLat);
      const cLng = bucket(sLng);
      const key = `${cLat.toFixed(2)}|${cLng.toFixed(2)}`;
      let cell = cellMap.get(key);
      if (!cell) {
        cell = { lat: Number(cLat.toFixed(4)), lng: Number(cLng.toFixed(4)), count: 0 };
        cellMap.set(key, cell);
      }
      cell.count += 1;
    }

    const cells = [...cellMap.values()].sort((a, b) => b.count - a.count);
    const top = cells.slice(0, MAX_CELLS);
    const max = top.reduce((m, c) => (c.count > m ? c.count : m), 0);
    for (const c of top) {
      c.intensity = max > 0 ? Number((c.count / max).toFixed(4)) : 0;
    }

    res.json({
      cells: top,
      windowMs: WINDOW_MS,
      radiusKm,
    });
  } catch (err) {
    logger.warn({ err: err.message, userId: req.user?.id }, 'heatmap failed');
    next(err);
  }
});

module.exports = router;
