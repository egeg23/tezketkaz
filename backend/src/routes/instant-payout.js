// Phase 8.5 — instant payout endpoints. Two surfaces:
//
//   • Courier-facing  (mounted at /api):
//       GET  /couriers/me/balance
//       POST /couriers/me/payout/request
//
//   • Admin-facing (mounted at /api/admin):
//       GET  /payouts/instant?status=&cursor=&limit=
//       POST /payouts/:id/approve
//       POST /payouts/:id/reject
//
// Routes are deliberately split into two routers so we can mount them under
// the existing `/api` and `/api/admin` prefixes without colliding with other
// router paths.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware, requireRole, requireAdmin } = require('../middleware/auth');
const instantPayout = require('../services/instantPayout');
const notifications = require('../services/notifications');

// ─── COURIER ────────────────────────────────────────────────────────────────

// GET /api/couriers/me/balance
router.get('/couriers/me/balance', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const [balance, pending] = await Promise.all([
      instantPayout.availableBalance(prisma, req.user.id),
      instantPayout.hasPendingInstant(prisma, req.user.id),
    ]);
    res.json({
      availableBalance: balance,
      currency: 'UZS',
      minPayout: instantPayout.MIN_PAYOUT_UZS,
      hasPending: pending,
    });
  } catch (err) { next(err); }
});

// POST /api/couriers/me/payout/request
router.post('/couriers/me/payout/request', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    let payout;
    try {
      payout = await instantPayout.request(prisma, req.user.id, { ipAddress: req.ip });
    } catch (err) {
      if (err && err.code) {
        return res.status(err.status || 400).json({
          error: err.message,
          reason: err.code,
          balance: err.balance,
          minPayout: err.minPayout,
        });
      }
      throw err;
    }

    // Fire-and-forget courier notification.
    const io = req.app.get('io');
    notifications.sendOrderEvent(prisma, io, {
      userId: req.user.id,
      type: 'instant_payout_requested',
      data: { netAmount: payout.netAmount, payoutId: payout.id },
    }).catch(() => {});

    res.json({ payout });
  } catch (err) { next(err); }
});

// ─── ADMIN ──────────────────────────────────────────────────────────────────

// GET /api/admin/payouts/instant
router.get('/admin/payouts/instant', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { status } = req.query;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const cursor = req.query.cursor || null;

    const where = { source: 'instant' };
    if (status) where.status = String(status);

    const findArgs = {
      where,
      orderBy: [{ requestedAt: 'desc' }, { id: 'asc' }],
      take: limit + 1,
    };
    if (cursor) {
      findArgs.cursor = { id: String(cursor) };
      findArgs.skip = 1;
    }

    const rows = await prisma.payout.findMany(findArgs);
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;

    // Resolve courier names.
    const courierIds = page.map((p) => p.recipientId);
    const users = courierIds.length
      ? await prisma.user.findMany({
          where: { id: { in: courierIds } },
          select: { id: true, name: true, phone: true },
        })
      : [];
    const userMap = new Map(users.map((u) => [u.id, u]));
    const enriched = page.map((p) => {
      const u = userMap.get(p.recipientId);
      return {
        ...p,
        recipientName: u?.name || null,
        recipientPhone: u?.phone || null,
      };
    });

    res.json({
      payouts: enriched,
      nextCursor: hasMore ? page[page.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// POST /api/admin/payouts/:id/approve
router.post('/admin/payouts/:id/approve', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { txnRef, notes } = req.body || {};
    let payout;
    try {
      payout = await instantPayout.approve(prisma, req.params.id, {
        txnRef, notes, actorId: req.user.id, ipAddress: req.ip,
      });
    } catch (err) {
      if (err && err.code) {
        return res.status(err.status || 400).json({ error: err.message, reason: err.code });
      }
      throw err;
    }

    const io = req.app.get('io');
    notifications.sendOrderEvent(prisma, io, {
      userId: payout.recipientId,
      type: 'instant_payout_paid',
      data: { netAmount: payout.netAmount, txnRef: payout.txnRef, payoutId: payout.id },
    }).catch(() => {});

    res.json({ payout });
  } catch (err) { next(err); }
});

// POST /api/admin/payouts/:id/reject
router.post('/admin/payouts/:id/reject', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { notes } = req.body || {};
    let payout;
    try {
      payout = await instantPayout.reject(prisma, req.params.id, {
        notes, actorId: req.user.id, ipAddress: req.ip,
      });
    } catch (err) {
      if (err && err.code) {
        return res.status(err.status || 400).json({ error: err.message, reason: err.code });
      }
      throw err;
    }

    const io = req.app.get('io');
    notifications.sendOrderEvent(prisma, io, {
      userId: payout.recipientId,
      type: 'instant_payout_rejected',
      data: { reason: notes || null, payoutId: payout.id },
    }).catch(() => {});

    res.json({ payout });
  } catch (err) { next(err); }
});

module.exports = router;
