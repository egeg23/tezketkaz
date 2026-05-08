const router = require('express').Router();
const prisma = require('../db');
const env = require('../config/env');
const state = require('../services/redis-state');
const { authMiddleware, requireRole } = require('../middleware/auth');
const { audit } = require('../lib/audit');

// ─── POST /api/couriers/location — courier reports current GPS ───────────────
router.post('/location', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const { lat, lng, orderId } = req.body || {};
    if (lat == null || lng == null) return res.status(400).json({ error: 'lat/lng required' });
    await state.setCourierLocation(req.user.id, lat, lng);
    if (orderId) {
      const io = req.app.get('io');
      io.to(`order:${orderId}`).emit('courier:location', {
        orderId, courierId: req.user.id, lat: Number(lat), lng: Number(lng), ts: Date.now(),
      });
    }
    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ─── GET /api/couriers/location/:orderId ─────────────────────────────────────
// Buyer/shop poll fallback when sockets are unavailable
router.get('/location/:orderId', authMiddleware, async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({ where: { id: req.params.orderId } });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (![order.buyerId, order.courierId].includes(req.user.id)) {
      const isShopMember = order.shopId && await prisma.shopMember.findUnique({
        where: { userId_shopId: { userId: req.user.id, shopId: order.shopId } },
      });
      if (!isShopMember) return res.status(403).json({ error: 'Forbidden' });
    }
    if (!order.courierId) return res.json({ location: null });
    const loc = await state.getCourierLocation(order.courierId);
    res.json({ location: loc || null });
  } catch (err) { next(err); }
});

// Mock STIR check — in production, call Tax Committee API
async function verifyStir(stir) {
  if (env.useMockTax) return { valid: stir.length === 9, selfEmployed: true };
  // TODO: real Tax API call
  return { valid: false };
}

// ─── POST /api/couriers/apply — verification request ─────────────────────────
router.post('/apply', authMiddleware, async (req, res, next) => {
  try {
    const { fullName, stir, passportSeries } = req.body || {};
    if (!fullName || !stir || !passportSeries) {
      return res.status(400).json({ error: 'Missing fields' });
    }

    if (req.user.courierStatus === 'pending' || req.user.courierStatus === 'approved') {
      return res.status(400).json({ error: 'Already applied or approved' });
    }

    const stirCheck = await verifyStir(stir);
    if (!stirCheck.valid) return res.status(400).json({ error: 'Invalid STIR' });

    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: {
        name: fullName,
        stir,
        passportSeries,
        courierStatus: 'pending',
      },
    });
    await audit({
      actorId: req.user.id, action: 'courier.apply',
      targetType: 'User', targetId: user.id, ipAddress: req.ip,
    });

    res.json({ user });
  } catch (err) { next(err); }
});

// ─── POST /api/couriers/me/approve (DEV ONLY) ────────────────────────────────
// In production this is done from admin panel. Hard-disable in prod.
router.post('/me/approve', authMiddleware, async (req, res, next) => {
  if (env.isProd) return res.status(403).json({ error: 'Not available in production' });
  try {
    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: { courierStatus: 'approved', isCourier: true },
    });
    res.json({ user });
  } catch (err) { next(err); }
});

// ─── GET /api/couriers/me/earnings ───────────────────────────────────────────
router.get('/me/earnings', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const orders = await prisma.order.findMany({
      where: { courierId: req.user.id, status: 'delivered' },
      orderBy: { deliveredAt: 'desc' },
      take: 50,
    });

    const today = new Date(); today.setHours(0, 0, 0, 0);
    const todayOrders = orders.filter((o) => o.deliveredAt >= today);
    const todayEarnings = todayOrders.reduce((s, o) => s + o.courierReward, 0);

    const month = new Date(today.getFullYear(), today.getMonth(), 1);
    const monthEarnings = orders
      .filter((o) => o.deliveredAt >= month)
      .reduce((s, o) => s + o.courierReward, 0);

    // Mock balance — in real system tracked separately via Payout model.
    const balance = monthEarnings * 0.8;
    const pending = monthEarnings * 0.2;

    res.json({
      balance, pending, todayEarnings,
      todayOrdersCount: todayOrders.length,
      monthEarnings,
      history: orders.slice(0, 20),
    });
  } catch (err) { next(err); }
});

module.exports = router;
