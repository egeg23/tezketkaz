const router = require('express').Router();
const prisma = require('../db');
const env = require('../config/env');
const { authMiddleware, requireAdmin } = require('../middleware/auth');
const { audit } = require('../lib/audit');

// Bootstrap admin: if `ADMIN_PHONES` env is set and a user with that phone has
// `isAdmin = false`, promote them on first login through `/admin/me`. This lets
// the very first admin self-promote without needing a DB shell.
router.post('/bootstrap', authMiddleware, async (req, res, next) => {
  try {
    const phones = (env.ADMIN_PHONES || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (!phones.includes(req.user.phone)) {
      return res.status(403).json({ error: 'Not in ADMIN_PHONES whitelist' });
    }
    if (req.user.isAdmin) return res.json({ ok: true, alreadyAdmin: true });
    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: { isAdmin: true },
    });
    await audit({ actorId: req.user.id, action: 'admin.self_bootstrap', targetType: 'User', targetId: user.id });
    res.json({ ok: true, user: { id: user.id, isAdmin: user.isAdmin } });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/stats ────────────────────────────────────────────────────
router.get('/stats', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const startOfDay = new Date(); startOfDay.setHours(0, 0, 0, 0);
    const [users, orders, couriers, pending, todayRevenue, todayOrders, ordersByStatus] = await Promise.all([
      prisma.user.count(),
      prisma.order.count(),
      prisma.user.count({ where: { isCourier: true, courierStatus: 'approved' } }),
      prisma.user.count({ where: { courierStatus: 'pending' } }),
      prisma.order.aggregate({
        where: { status: 'delivered', deliveredAt: { gte: startOfDay } },
        _sum: { total: true },
      }),
      prisma.order.count({ where: { createdAt: { gte: startOfDay } } }),
      prisma.order.groupBy({ by: ['status'], _count: { _all: true } }),
    ]);
    res.json({
      users, orders, couriers, pending,
      revenue: todayRevenue._sum.total || 0,
      todayOrders,
      ordersByStatus: Object.fromEntries(ordersByStatus.map((o) => [o.status, o._count._all])),
    });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/couriers ─────────────────────────────────────────────────
router.get('/couriers', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const couriers = await prisma.user.findMany({
      where: { OR: [{ isCourier: true }, { courierStatus: { in: ['pending', 'rejected'] } }] },
      orderBy: [{ courierStatus: 'asc' }, { createdAt: 'desc' }],
      take: 200,
    });
    res.json({ couriers });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/couriers/:id/approve ────────────────────────────────────
router.post('/couriers/:id/approve', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const user = await prisma.user.update({
      where: { id: req.params.id },
      data: { courierStatus: 'approved', isCourier: true },
    });
    await audit({
      actorId: req.user.id, action: 'courier.approve',
      targetType: 'User', targetId: user.id, ipAddress: req.ip,
    });
    res.json({ user });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/couriers/:id/reject ─────────────────────────────────────
router.post('/couriers/:id/reject', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { reason } = req.body || {};
    const user = await prisma.user.update({
      where: { id: req.params.id },
      data: { courierStatus: 'rejected', isCourier: false },
    });
    await audit({
      actorId: req.user.id, action: 'courier.reject',
      targetType: 'User', targetId: user.id, metadata: { reason }, ipAddress: req.ip,
    });
    res.json({ user });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/orders ───────────────────────────────────────────────────
router.get('/orders', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const status = req.query.status;
    const where = status ? { status } : {};
    const orders = await prisma.order.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: 100,
      include: { shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });
    res.json({ orders });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/users ────────────────────────────────────────────────────
router.get('/users', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const users = await prisma.user.findMany({
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json({ users });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/users/:id/admin ─────────────────────────────────────────
router.post('/users/:id/admin', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { isAdmin } = req.body || {};
    const user = await prisma.user.update({
      where: { id: req.params.id },
      data: { isAdmin: !!isAdmin },
    });
    await audit({
      actorId: req.user.id,
      action: isAdmin ? 'admin.grant' : 'admin.revoke',
      targetType: 'User', targetId: user.id, ipAddress: req.ip,
    });
    res.json({ user: { id: user.id, isAdmin: user.isAdmin } });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/audit ────────────────────────────────────────────────────
router.get('/audit', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const logs = await prisma.auditLog.findMany({
      orderBy: { createdAt: 'desc' },
      take: 200,
      include: { actor: { select: { id: true, name: true, phone: true } } },
    });
    res.json({ logs });
  } catch (err) { next(err); }
});

module.exports = router;
