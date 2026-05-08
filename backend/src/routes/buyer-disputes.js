// User-facing dispute endpoints. Mounted at `/api`, declares absolute paths
// under `/orders/:id/dispute` so it can sit alongside reviews/chat routers.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const disputes = require('../services/disputes');

// POST /api/orders/:orderId/dispute — buyer opens dispute.
router.post('/orders/:orderId/dispute', authMiddleware, async (req, res, next) => {
  try {
    const { reason, description, evidence } = req.body || {};
    const dispute = await disputes.openDispute(prisma, {
      orderId: req.params.orderId,
      openedById: req.user.id,
      reason,
      description,
      evidence,
      ipAddress: req.ip,
    });
    res.status(201).json({ dispute });
  } catch (err) { next(err); }
});

// GET /api/orders/:orderId/dispute — buyer or admin can fetch.
router.get('/orders/:orderId/dispute', authMiddleware, async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({ where: { id: req.params.orderId } });
    if (!order) return res.status(404).json({ error: 'Order not found' });
    if (order.buyerId !== req.user.id && !req.user.isAdmin) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const dispute = await prisma.dispute.findUnique({ where: { orderId: order.id } });
    res.json({ dispute: dispute || null });
  } catch (err) { next(err); }
});

module.exports = router;
