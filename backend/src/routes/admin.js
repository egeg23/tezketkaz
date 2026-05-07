const router = require('express').Router();
const prisma = require('../db');
const env = require('../config/env');
const { authMiddleware, requireAdmin } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const refunds = require('../services/refunds');
const payoutsSvc = require('../services/payouts');
const disputesSvc = require('../services/disputes');

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

// ─── Phase 4: Refunds, Payouts, Disputes, Dashboard ──────────────────────────

// ─── POST /api/admin/orders/:orderId/refund ──────────────────────────────────
router.post('/orders/:orderId/refund', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { amount, reason } = req.body || {};
    const order = await refunds.refundOrder(prisma, {
      orderId: req.params.orderId,
      amount: Number(amount),
      reason,
      actorId: req.user.id,
      ipAddress: req.ip,
    });
    res.json({ order });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/payouts ──────────────────────────────────────────────────
router.get('/payouts', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { recipientType, status, periodStart } = req.query;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const cursor = req.query.cursor || null;
    const where = {};
    if (recipientType) where.recipientType = recipientType;
    if (status) where.status = status;
    if (periodStart) where.periodStart = new Date(periodStart);
    const findArgs = {
      where,
      orderBy: [{ periodStart: 'desc' }, { id: 'asc' }],
      take: limit + 1,
    };
    if (cursor) {
      findArgs.cursor = { id: cursor };
      findArgs.skip = 1;
    }
    const rows = await prisma.payout.findMany(findArgs);
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    // Resolve recipient names.
    const courierIds = page.filter((p) => p.recipientType === 'courier').map((p) => p.recipientId);
    const shopIds = page.filter((p) => p.recipientType === 'shop').map((p) => p.recipientId);
    const [users, shops] = await Promise.all([
      courierIds.length
        ? prisma.user.findMany({ where: { id: { in: courierIds } }, select: { id: true, name: true, phone: true } })
        : [],
      shopIds.length
        ? prisma.shop.findMany({ where: { id: { in: shopIds } }, select: { id: true, name: true } })
        : [],
    ]);
    const userMap = new Map(users.map((u) => [u.id, u]));
    const shopMap = new Map(shops.map((s) => [s.id, s]));
    const enriched = page.map((p) => {
      const recipient = p.recipientType === 'courier'
        ? userMap.get(p.recipientId)
        : shopMap.get(p.recipientId);
      return {
        ...p,
        recipientName: recipient?.name || null,
        recipientPhone: p.recipientType === 'courier' ? recipient?.phone || null : null,
      };
    });
    res.json({
      payouts: enriched,
      nextCursor: hasMore ? page[page.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/payouts/generate ────────────────────────────────────────
router.post('/payouts/generate', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    let weekStart;
    if (req.body && req.body.weekStart) {
      weekStart = new Date(req.body.weekStart);
      if (Number.isNaN(weekStart.getTime())) {
        return res.status(400).json({ error: 'Invalid weekStart' });
      }
    } else {
      weekStart = payoutsSvc.getLastMonday();
    }
    const result = await payoutsSvc.generateWeeklyPayouts(prisma, { weekStart });
    await audit({
      actorId: req.user.id,
      action: 'payouts.generate',
      targetType: 'Payout',
      targetId: null,
      metadata: { weekStart, count: result.length },
      ipAddress: req.ip,
    });
    res.json({ count: result.length, weekStart, payouts: result });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/payouts/:id/pay ─────────────────────────────────────────
router.post('/payouts/:id/pay', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { txnRef, notes } = req.body || {};
    const payout = await payoutsSvc.markPayoutPaid(prisma, req.params.id, {
      txnRef, notes, actorId: req.user.id, ipAddress: req.ip,
    });
    res.json({ payout });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/payouts/export.csv ───────────────────────────────────────
router.get('/payouts/export.csv', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const where = {};
    if (req.query.periodStart) where.periodStart = new Date(req.query.periodStart);
    if (req.query.recipientType) where.recipientType = req.query.recipientType;
    if (req.query.status) where.status = req.query.status;
    const rows = await prisma.payout.findMany({ where, orderBy: { periodStart: 'desc' }, take: 5000 });
    const courierIds = rows.filter((p) => p.recipientType === 'courier').map((p) => p.recipientId);
    const shopIds = rows.filter((p) => p.recipientType === 'shop').map((p) => p.recipientId);
    const [users, shops] = await Promise.all([
      courierIds.length
        ? prisma.user.findMany({ where: { id: { in: courierIds } }, select: { id: true, name: true } })
        : [],
      shopIds.length
        ? prisma.shop.findMany({ where: { id: { in: shopIds } }, select: { id: true, name: true } })
        : [],
    ]);
    const nameMap = new Map();
    for (const u of users) nameMap.set(`courier:${u.id}`, u.name);
    for (const s of shops) nameMap.set(`shop:${s.id}`, s.name);
    const enriched = rows.map((p) => ({
      ...p,
      recipientName: nameMap.get(`${p.recipientType}:${p.recipientId}`) || '',
    }));
    const csv = payoutsSvc.exportPayoutsCsv(enriched);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="payouts.csv"');
    res.send(csv);
  } catch (err) { next(err); }
});

// ─── GET /api/admin/disputes ─────────────────────────────────────────────────
router.get('/disputes', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { status } = req.query;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const cursor = req.query.cursor || null;
    const where = {};
    if (status) where.status = status;
    const findArgs = {
      where,
      orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
      take: limit + 1,
      include: {
        order: {
          select: {
            id: true, orderNumber: true, total: true, refundedAmount: true,
            buyerId: true, shopId: true, status: true, deliveredAt: true,
          },
        },
      },
    };
    if (cursor) {
      findArgs.cursor = { id: cursor };
      findArgs.skip = 1;
    }
    const rows = await prisma.dispute.findMany(findArgs);
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    res.json({
      disputes: page,
      nextCursor: hasMore ? page[page.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/disputes/:id/resolve ────────────────────────────────────
router.post('/disputes/:id/resolve', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { resolution, refundAmount, note } = req.body || {};
    const dispute = await disputesSvc.resolveDispute(prisma, {
      disputeId: req.params.id,
      actorId: req.user.id,
      resolution,
      refundAmount,
      note,
      ipAddress: req.ip,
    });
    res.json({ dispute });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/dashboard/stats ──────────────────────────────────────────
router.get('/dashboard/stats', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const since = req.query.since ? new Date(req.query.since) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const until = req.query.until ? new Date(req.query.until) : new Date();
    const baseWhere = { createdAt: { gte: since, lt: until } };

    const [ordersCount, gmvAgg, deliveredCount, openDisputes, allOrders, topShopAgg, topCourierAgg] = await Promise.all([
      prisma.order.count({ where: baseWhere }),
      prisma.order.aggregate({ where: baseWhere, _sum: { total: true } }),
      prisma.order.count({ where: { ...baseWhere, status: { in: ['delivered', 'confirmedByBuyer'] } } }),
      prisma.dispute.count({ where: { status: { in: ['open', 'under_review'] } } }),
      prisma.order.findMany({
        where: baseWhere,
        select: { id: true, total: true, createdAt: true, shopId: true, courierId: true, status: true, courierReward: true },
      }),
      prisma.order.groupBy({
        by: ['shopId'],
        where: baseWhere,
        _count: { _all: true },
        _sum: { total: true },
        orderBy: { _sum: { total: 'desc' } },
        take: 5,
      }),
      prisma.order.groupBy({
        by: ['courierId'],
        where: { ...baseWhere, courierId: { not: null }, status: { in: ['delivered', 'confirmedByBuyer'] } },
        _count: { _all: true },
        _sum: { courierReward: true },
        orderBy: { _sum: { courierReward: 'desc' } },
        take: 5,
      }),
    ]);

    const gmv = gmvAgg._sum.total || 0;
    const deliveredRate = ordersCount > 0 ? deliveredCount / ordersCount : 0;
    const avgOrderValue = ordersCount > 0 ? gmv / ordersCount : 0;

    // Resolve top shop names.
    const shopIds = topShopAgg.map((s) => s.shopId).filter(Boolean);
    const courierIds = topCourierAgg.map((c) => c.courierId).filter(Boolean);
    const [shops, couriers] = await Promise.all([
      shopIds.length
        ? prisma.shop.findMany({ where: { id: { in: shopIds } }, select: { id: true, name: true } })
        : [],
      courierIds.length
        ? prisma.user.findMany({ where: { id: { in: courierIds } }, select: { id: true, name: true } })
        : [],
    ]);
    const shopMap = new Map(shops.map((s) => [s.id, s.name]));
    const courierMap = new Map(couriers.map((u) => [u.id, u.name]));

    const topShops = topShopAgg.map((s) => ({
      shopId: s.shopId,
      name: shopMap.get(s.shopId) || null,
      ordersCount: s._count._all,
      gmv: s._sum.total || 0,
    }));
    const topCouriers = topCourierAgg.map((c) => ({
      userId: c.courierId,
      name: courierMap.get(c.courierId) || null,
      ordersCount: c._count._all,
      totalEarned: c._sum.courierReward || 0,
    }));

    // Aggregate orders by day.
    const buckets = new Map();
    for (const o of allOrders) {
      const d = new Date(o.createdAt);
      const day = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
      const e = buckets.get(day) || { day, count: 0, gmv: 0 };
      e.count += 1;
      e.gmv += Number(o.total || 0);
      buckets.set(day, e);
    }
    const ordersByDay = Array.from(buckets.values()).sort((a, b) => a.day.localeCompare(b.day));

    res.json({
      ordersCount,
      gmv,
      deliveredRate,
      avgOrderValue,
      topShops,
      topCouriers,
      ordersByDay,
      openDisputes,
    });
  } catch (err) { next(err); }
});

module.exports = router;
