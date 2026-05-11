// Soliq.uz fiscal receipt routes (Phase 13.3.9).
//
// Buyer-facing:
//   GET  /api/orders/:id/fiscal-receipt — returns receipt URL if issued.
//
// Admin-only:
//   POST /api/admin/orders/:id/fiscal-retry — re-enqueues the issue job.
//   GET  /api/admin/fiscal/failures        — lists orders with failures.
//
// All endpoints declare absolute paths so they can be mounted directly under
// `/api` in src/index.js (matching the convention of other cross-cutting
// route modules like reviews, chat, verification, banners).

const router = require('express').Router();
const prisma = require('../db');
const logger = require('../lib/logger');
const { queues } = require('../lib/queues');
const { authMiddleware, requireAdmin } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const fiscalJob = require('../jobs/fiscal-receipt');

// ─── GET /api/orders/:id/fiscal-receipt ─────────────────────────────────────
// Either the order's buyer OR a shop member can view. 404 when no receipt
// has been issued yet. 403 for other users.
router.get('/orders/:id/fiscal-receipt', authMiddleware, async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      select: {
        id: true,
        buyerId: true,
        shopId: true,
        fiscalReceiptId: true,
        fiscalReceiptUrl: true,
        fiscalIssuedAt: true,
        fiscalFailureCount: true,
        fiscalLastError: true,
      },
    });
    if (!order) return res.status(404).json({ error: 'order_not_found' });

    const user = req.user;
    const isOwner = user.id === order.buyerId;
    // Shop members are allowed (they need the receipt for accounting).
    const memberships = Array.isArray(user.shopMemberships) ? user.shopMemberships : [];
    const isShopMember = memberships.some((m) => m.shopId === order.shopId);
    if (!isOwner && !isShopMember && !user.isAdmin) {
      return res.status(403).json({ error: 'forbidden' });
    }

    if (!order.fiscalReceiptId) {
      return res.status(404).json({
        error: 'not_issued',
        failureCount: order.fiscalFailureCount,
        lastError: order.fiscalLastError,
      });
    }

    return res.json({
      orderId: order.id,
      receiptId: order.fiscalReceiptId,
      receiptUrl: order.fiscalReceiptUrl,
      issuedAt: order.fiscalIssuedAt,
    });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/orders/:id/fiscal-retry ────────────────────────────────
// Re-enqueues the fiscal issue job. Useful after Soliq outage. If Redis is
// disabled (dev/test), runs the handler inline so tests can still exercise
// the retry path end-to-end.
router.post(
  '/admin/orders/:id/fiscal-retry',
  authMiddleware,
  requireAdmin,
  async (req, res, next) => {
    try {
      const order = await prisma.order.findUnique({
        where: { id: req.params.id },
        select: { id: true, fiscalReceiptId: true },
      });
      if (!order) return res.status(404).json({ error: 'order_not_found' });

      // Reset lastError so the dashboard doesn't keep showing stale state.
      await prisma.order.update({
        where: { id: order.id },
        data: { fiscalLastError: null },
      });

      // Best-effort BullMQ enqueue (no-op in dev/test).
      try {
        await queues().fiscal.add(
          'issue',
          { orderId: order.id },
          {
            attempts: 5,
            backoff: { type: 'exponential', delay: 60 * 1000 },
            removeOnComplete: 100,
            removeOnFail: 500,
          },
        );
      } catch (err) {
        logger.warn({ err: err.message, orderId: order.id }, 'fiscal retry enqueue failed');
      }

      // In dev/test, also run the job inline so the operator sees an
      // immediate result (and tests don't need a real Redis).
      let inlineResult = null;
      if (process.env.NODE_ENV !== 'production') {
        try {
          inlineResult = await fiscalJob.processFiscalReceipt({ orderId: order.id });
        } catch (err) {
          logger.warn({ err: err.message, orderId: order.id }, 'inline fiscal retry failed');
        }
      }

      await audit({
        actorId: req.user.id,
        action: 'order.fiscal_retry',
        targetType: 'Order',
        targetId: order.id,
        metadata: { result: inlineResult },
      });

      return res.json({ ok: true, result: inlineResult });
    } catch (err) { next(err); }
  },
);

// ─── GET /api/admin/fiscal/failures ─────────────────────────────────────────
// Lists orders that have had at least one fiscal failure. Used by the
// admin-next dashboard to surface them for manual retry.
router.get('/admin/fiscal/failures', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const orders = await prisma.order.findMany({
      where: { fiscalFailureCount: { gt: 0 } },
      orderBy: { updatedAt: 'desc' },
      take: limit,
      select: {
        id: true,
        orderNumber: true,
        shopId: true,
        buyerId: true,
        total: true,
        currency: true,
        paymentMethod: true,
        isPaid: true,
        createdAt: true,
        fiscalReceiptId: true,
        fiscalReceiptUrl: true,
        fiscalIssuedAt: true,
        fiscalFailureCount: true,
        fiscalLastError: true,
        shop: { select: { id: true, name: true, soliqEnabled: true, soliqInn: true } },
      },
    });
    return res.json({ orders });
  } catch (err) { next(err); }
});

module.exports = router;
