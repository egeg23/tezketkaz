// Phase 2 routes: courier shifts (start/end/list/current), online toggle,
// and dispatch offer accept/decline. Mounted at `/api` so absolute paths
// can reference both `/api/couriers/...` and `/api/orders/...`.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware, requireRole } = require('../middleware/auth');
const dispatcher = require('../services/dispatcher');
const logger = require('../lib/logger');

function getIo(req) { return req.app.get('io'); }

// ─── POST /api/couriers/me/shifts/start ──────────────────────────────────────
router.post('/couriers/me/shifts/start', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const { zoneIds } = req.body || {};
    const userId = req.user.id;

    // Close any open shift first.
    await prisma.courierShift.updateMany({
      where: { courierId: userId, endedAt: null },
      data: { endedAt: new Date() },
    });

    const shift = await prisma.courierShift.create({
      data: {
        courierId: userId,
        startedAt: new Date(),
        zoneIds: Array.isArray(zoneIds) && zoneIds.length ? JSON.stringify(zoneIds) : null,
      },
    });

    await prisma.user.update({
      where: { id: userId },
      data: { isOnline: true, lastSeenAt: new Date() },
    });

    res.status(201).json({ shift });
  } catch (err) { next(err); }
});

// ─── POST /api/couriers/me/shifts/end ────────────────────────────────────────
router.post('/couriers/me/shifts/end', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const userId = req.user.id;
    const open = await prisma.courierShift.findFirst({
      where: { courierId: userId, endedAt: null },
      orderBy: { startedAt: 'desc' },
    });
    if (!open) {
      // Make the toggle idempotent even when no open shift exists.
      await prisma.user.update({
        where: { id: userId },
        data: { isOnline: false, lastSeenAt: new Date() },
      });
      return res.json({ shift: null });
    }
    const shift = await prisma.courierShift.update({
      where: { id: open.id },
      data: { endedAt: new Date() },
    });
    await prisma.user.update({
      where: { id: userId },
      data: { isOnline: false, lastSeenAt: new Date() },
    });
    res.json({ shift });
  } catch (err) { next(err); }
});

// ─── GET /api/couriers/me/shifts?cursor=&limit= ──────────────────────────────
router.get('/couriers/me/shifts', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const userId = req.user.id;
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const cursor = typeof req.query.cursor === 'string' && req.query.cursor ? req.query.cursor : null;

    const shifts = await prisma.courierShift.findMany({
      where: { courierId: userId },
      orderBy: { startedAt: 'desc' },
      take: limit + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    });
    const nextCursor = shifts.length > limit ? shifts[limit].id : null;
    res.json({ shifts: shifts.slice(0, limit), nextCursor });
  } catch (err) { next(err); }
});

// ─── GET /api/couriers/me/shifts/current ─────────────────────────────────────
router.get('/couriers/me/shifts/current', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const shift = await prisma.courierShift.findFirst({
      where: { courierId: req.user.id, endedAt: null },
      orderBy: { startedAt: 'desc' },
    });
    res.json({ shift: shift || null });
  } catch (err) { next(err); }
});

// ─── POST /api/couriers/me/online ────────────────────────────────────────────
router.post('/couriers/me/online', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const { isOnline } = req.body || {};
    if (typeof isOnline !== 'boolean') {
      return res.status(400).json({ error: 'isOnline (bool) required' });
    }
    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: { isOnline, lastSeenAt: new Date() },
      select: { id: true, isOnline: true, lastSeenAt: true },
    });
    res.json({ user });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:orderId/dispatch/accept ───────────────────────────────
router.post('/orders/:orderId/dispatch/accept', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const order = await dispatcher.acceptOffer(prisma, getIo(req), req.params.orderId, req.user.id);
    res.json({ order });
  } catch (err) {
    if (err.status) {
      logger.debug({ err: err.message }, 'dispatch.accept rejected');
      return res.status(err.status).json({ error: err.message });
    }
    next(err);
  }
});

// ─── POST /api/orders/:orderId/dispatch/decline ──────────────────────────────
router.post('/orders/:orderId/dispatch/decline', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const { reason } = req.body || {};
    const result = await dispatcher.declineOffer(prisma, getIo(req), req.params.orderId, req.user.id, reason);
    res.json(result);
  } catch (err) {
    if (err.status) {
      return res.status(err.status).json({ error: err.message });
    }
    next(err);
  }
});

module.exports = router;
