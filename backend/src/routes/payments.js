const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const click = require('../services/click');
const payme = require('../services/payme');
const uzum = require('../services/uzum');

// ─── POST /api/payments/init — initialize payment for order ──────────────────
router.post('/init', authMiddleware, async (req, res, next) => {
  try {
    const { orderId, method } = req.body;
    const order = await prisma.order.findUnique({ where: { id: orderId } });
    if (!order) return res.status(404).json({ error: 'Order not found' });
    if (order.buyerId !== req.user.id) return res.status(403).json({ error: 'Not your order' });
    if (order.isPaid) return res.status(400).json({ error: 'Already paid' });

    let url;
    switch (method) {
      case 'click':   url = await click.createInvoice(order); break;
      case 'payme':   url = await payme.createInvoice(order); break;
      case 'uzumpay': url = await uzum.createInvoice(order); break;
      default: return res.status(400).json({ error: 'Invalid method' });
    }

    res.json({ url });
  } catch (err) { next(err); }
});

// ─── POST /api/payments/click/callback ───────────────────────────────────────
// Click отправит callback после оплаты. Подпись проверяется в click.verifyCallback
router.post('/click/callback', async (req, res, next) => {
  try {
    const result = await click.verifyCallback(req.body);
    if (!result.valid) return res.status(400).json({ error: 'Invalid signature' });

    await prisma.order.update({
      where: { id: result.orderId },
      data: { isPaid: true, paymentRef: result.transactionId },
    });

    // Уведомить покупателя через socket
    const io = req.app.get('io');
    io.to(`buyer:${result.buyerId}`).emit('payment:success', { orderId: result.orderId });

    res.json({ click_trans_id: result.transactionId, error: 0 });
  } catch (err) { next(err); }
});

// ─── POST /api/payments/payme/callback ───────────────────────────────────────
router.post('/payme/callback', async (req, res, next) => {
  try {
    const result = await payme.handleCallback(req.body);
    res.json(result);
  } catch (err) { next(err); }
});

// ─── POST /api/payments/uzum/callback ────────────────────────────────────────
router.post('/uzum/callback', async (req, res, next) => {
  try {
    const result = await uzum.handleCallback(req.body);
    res.json(result);
  } catch (err) { next(err); }
});

module.exports = router;
