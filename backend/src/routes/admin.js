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
// Phase 6.12 — paginated, filterable, searchable user list.
//   role     — buyer | courier | shop | admin
//   status   — courierStatus filter (none | pending | approved | rejected)
//   q        — search phone or name (case-insensitive contains)
router.get('/users', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { role, status, q } = req.query;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const cursor = req.query.cursor || null;

    const where = {};
    if (role === 'buyer') where.isBuyer = true;
    else if (role === 'courier') where.isCourier = true;
    else if (role === 'shop') where.isShop = true;
    else if (role === 'admin') where.isAdmin = true;

    if (status) where.courierStatus = String(status);

    if (q && String(q).trim()) {
      const needle = String(q).trim();
      where.OR = [
        { phone: { contains: needle } },
        { name: { contains: needle } },
      ];
    }

    const findArgs = {
      where,
      orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
      take: limit + 1,
    };
    if (cursor) {
      findArgs.cursor = { id: String(cursor) };
      findArgs.skip = 1;
    }

    const rows = await prisma.user.findMany(findArgs);
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    res.json({
      users: page,
      nextCursor: hasMore ? page[page.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/users/:id ────────────────────────────────────────────────
router.get('/users/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.params.id },
      include: {
        shopMemberships: { include: { shop: { select: { id: true, name: true } } } },
        loyalty: true,
      },
    });
    if (!user) return res.status(404).json({ error: 'Not found' });

    const [ordersCount, totalSpentAgg, recentOrders] = await Promise.all([
      prisma.order.count({ where: { buyerId: user.id } }),
      prisma.order.aggregate({
        where: { buyerId: user.id, status: { in: ['delivered', 'confirmedByBuyer'] } },
        _sum: { total: true },
      }),
      prisma.order.findMany({
        where: { buyerId: user.id },
        orderBy: { createdAt: 'desc' },
        take: 20,
        select: {
          id: true, orderNumber: true, status: true, total: true,
          createdAt: true, deliveredAt: true, shopId: true,
        },
      }),
    ]);

    res.json({
      user,
      ordersCount,
      totalSpent: totalSpentAgg._sum.total || 0,
      lastSeenAt: user.lastSeenAt,
      recentOrders,
    });
  } catch (err) { next(err); }
});

// ─── PATCH /api/admin/users/:id ──────────────────────────────────────────────
router.patch('/users/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const ALLOWED = ['name', 'isAdmin', 'isCourier', 'isShop', 'courierStatus', 'locale'];
    const data = {};
    for (const k of ALLOWED) {
      if (req.body && Object.prototype.hasOwnProperty.call(req.body, k)) {
        data[k] = req.body[k];
      }
    }
    if (data.isAdmin !== undefined) data.isAdmin = !!data.isAdmin;
    if (data.isCourier !== undefined) data.isCourier = !!data.isCourier;
    if (data.isShop !== undefined) data.isShop = !!data.isShop;

    const user = await prisma.user.update({ where: { id: req.params.id }, data });
    await audit({
      actorId: req.user.id,
      action: 'user.update',
      targetType: 'User', targetId: user.id,
      metadata: data, ipAddress: req.ip,
    });
    res.json({ user });
  } catch (err) {
    if (err && err.code === 'P2025') return res.status(404).json({ error: 'Not found' });
    next(err);
  }
});

// ─── POST /api/admin/users/:id/admin ─────────────────────────────────────────
// Legacy endpoint — kept for backward compatibility with existing clients.
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

// ─── POST /api/admin/users/:id/ban ───────────────────────────────────────────
// We don't have a `User.isActive`/`isBanned` column yet. To avoid touching the
// schema, the lowest-friction approach is:
//   1. Revoke ALL refresh tokens for this user (forces re-login + locks them
//      out because verify-otp is the only entry path and admins can refuse).
//   2. Demote: clear isAdmin, isCourier, isShop. courierStatus -> 'rejected'.
//   3. Audit-log the action with the supplied reason in metadata.
// To unban: re-issue tokens isn't possible, but we restore role flags so when
// they re-authenticate they're back to a normal account.
router.post('/users/:id/ban', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { reason } = req.body || {};
    const target = await prisma.user.findUnique({ where: { id: req.params.id } });
    if (!target) return res.status(404).json({ error: 'Not found' });

    const now = new Date();
    const [, user] = await Promise.all([
      prisma.refreshToken.updateMany({
        where: { userId: target.id, revokedAt: null },
        data: { revokedAt: now },
      }),
      prisma.user.update({
        where: { id: target.id },
        data: {
          isAdmin: false,
          isCourier: false,
          isShop: false,
          courierStatus: 'rejected',
        },
      }),
    ]);

    await audit({
      actorId: req.user.id,
      action: 'user.ban',
      targetType: 'User', targetId: user.id,
      metadata: { reason: reason || null }, ipAddress: req.ip,
    });
    res.json({ user, banned: true });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/users/:id/unban ─────────────────────────────────────────
// Restores the buyer role; admin/courier/shop flags must be re-granted
// explicitly via PATCH /api/admin/users/:id afterwards.
router.post('/users/:id/unban', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const target = await prisma.user.findUnique({ where: { id: req.params.id } });
    if (!target) return res.status(404).json({ error: 'Not found' });

    const user = await prisma.user.update({
      where: { id: target.id },
      data: { isBuyer: true, courierStatus: target.courierStatus === 'rejected' ? 'none' : target.courierStatus },
    });
    await audit({
      actorId: req.user.id,
      action: 'user.unban',
      targetType: 'User', targetId: user.id,
      ipAddress: req.ip,
    });
    res.json({ user, banned: false });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/shops ────────────────────────────────────────────────────
// Phase 6.12 — list shops with member count, order count, last 30d GMV.
router.get('/shops', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { status, q, vertical } = req.query;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const cursor = req.query.cursor || null;

    const where = {};
    if (status === 'active') where.isActive = true;
    else if (status === 'inactive') where.isActive = false;
    if (vertical) where.vertical = String(vertical);
    if (q && String(q).trim()) {
      const needle = String(q).trim();
      where.OR = [
        { name: { contains: needle } },
        { address: { contains: needle } },
        { phone: { contains: needle } },
      ];
    }

    const findArgs = {
      where,
      orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
      take: limit + 1,
      include: {
        _count: { select: { members: true, orders: true } },
      },
    };
    if (cursor) {
      findArgs.cursor = { id: String(cursor) };
      findArgs.skip = 1;
    }

    const rows = await prisma.shop.findMany(findArgs);
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;

    // Compute last-30d GMV per shop in a single groupBy.
    const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const ids = page.map((s) => s.id);
    const gmvAgg = ids.length
      ? await prisma.order.groupBy({
          by: ['shopId'],
          where: {
            shopId: { in: ids },
            createdAt: { gte: since },
            status: { in: ['delivered', 'confirmedByBuyer'] },
          },
          _sum: { total: true },
        })
      : [];
    const gmvMap = new Map(gmvAgg.map((g) => [g.shopId, g._sum.total || 0]));

    const shops = page.map((s) => ({
      ...s,
      membersCount: s._count?.members ?? 0,
      ordersCount: s._count?.orders ?? 0,
      lastWeekGMV: gmvMap.get(s.id) || 0,        // legacy alias used by some clients
      last30dGMV: gmvMap.get(s.id) || 0,
    }));
    res.json({
      shops,
      nextCursor: hasMore ? page[page.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/shops/:id ────────────────────────────────────────────────
router.get('/shops/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const shop = await prisma.shop.findUnique({
      where: { id: req.params.id },
      include: {
        members: {
          include: { user: { select: { id: true, name: true, phone: true } } },
        },
        _count: { select: { orders: true, products: true } },
      },
    });
    if (!shop) return res.status(404).json({ error: 'Not found' });

    const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const gmvAgg = await prisma.order.aggregate({
      where: {
        shopId: shop.id,
        createdAt: { gte: since },
        status: { in: ['delivered', 'confirmedByBuyer'] },
      },
      _sum: { total: true },
    });
    res.json({
      shop,
      membersCount: shop.members.length,
      ordersCount: shop._count?.orders ?? 0,
      productsCount: shop._count?.products ?? 0,
      last30dGMV: gmvAgg._sum.total || 0,
    });
  } catch (err) { next(err); }
});

// ─── PATCH /api/admin/shops/:id ──────────────────────────────────────────────
router.patch('/shops/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const ALLOWED = [
      'name', 'isActive', 'vertical', 'address', 'phone',
      'deliveryBaseFee', 'deliveryPerKm', 'freeDeliveryKm',
      'minOrderAmount', 'currency',
    ];
    const data = {};
    for (const k of ALLOWED) {
      if (req.body && Object.prototype.hasOwnProperty.call(req.body, k)) {
        data[k] = req.body[k];
      }
    }
    if (data.isActive !== undefined) data.isActive = !!data.isActive;
    for (const num of ['deliveryBaseFee', 'deliveryPerKm', 'freeDeliveryKm', 'minOrderAmount']) {
      if (data[num] !== undefined && data[num] !== null && data[num] !== '') {
        data[num] = Number(data[num]);
      } else if (data[num] === '' || data[num] === null) {
        data[num] = null;
      }
    }

    const shop = await prisma.shop.update({ where: { id: req.params.id }, data });
    await audit({
      actorId: req.user.id,
      action: 'shop.update',
      targetType: 'Shop', targetId: shop.id,
      metadata: data, ipAddress: req.ip,
    });
    res.json({ shop });
  } catch (err) {
    if (err && err.code === 'P2025') return res.status(404).json({ error: 'Not found' });
    next(err);
  }
});

// ─── POST /api/admin/shops/:id/suspend ───────────────────────────────────────
router.post('/shops/:id/suspend', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const shop = await prisma.shop.update({
      where: { id: req.params.id },
      data: { isActive: false },
    });
    await audit({
      actorId: req.user.id,
      action: 'shop.suspend',
      targetType: 'Shop', targetId: shop.id,
      metadata: { reason: req.body?.reason || null }, ipAddress: req.ip,
    });
    res.json({ shop });
  } catch (err) {
    if (err && err.code === 'P2025') return res.status(404).json({ error: 'Not found' });
    next(err);
  }
});

// ─── POST /api/admin/shops/:id/activate ──────────────────────────────────────
router.post('/shops/:id/activate', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const shop = await prisma.shop.update({
      where: { id: req.params.id },
      data: { isActive: true },
    });
    await audit({
      actorId: req.user.id,
      action: 'shop.activate',
      targetType: 'Shop', targetId: shop.id, ipAddress: req.ip,
    });
    res.json({ shop });
  } catch (err) {
    if (err && err.code === 'P2025') return res.status(404).json({ error: 'Not found' });
    next(err);
  }
});

// ─── DELETE /api/admin/shops/:id ─────────────────────────────────────────────
// Soft-delete: refuse if there are still open orders, otherwise mark inactive
// + suffix the name so it's clear in lists.
router.delete('/shops/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const shop = await prisma.shop.findUnique({ where: { id: req.params.id } });
    if (!shop) return res.status(404).json({ error: 'Not found' });

    const OPEN_STATUSES = [
      'pending', 'confirmed', 'collecting', 'readyForPickup',
      'courierAssigned', 'pickedUp', 'inDelivery',
    ];
    const openCount = await prisma.order.count({
      where: { shopId: shop.id, status: { in: OPEN_STATUSES } },
    });
    if (openCount > 0) {
      return res.status(409).json({ error: 'Shop has open orders', openCount });
    }

    const suffix = ' [archived]';
    const newName = shop.name && shop.name.endsWith(suffix) ? shop.name : `${shop.name}${suffix}`;
    const updated = await prisma.shop.update({
      where: { id: shop.id },
      data: { isActive: false, name: newName },
    });
    await audit({
      actorId: req.user.id,
      action: 'shop.delete',
      targetType: 'Shop', targetId: shop.id, ipAddress: req.ip,
    });
    res.json({ shop: updated, archived: true });
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
