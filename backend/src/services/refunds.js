// Refunds service — reverses payment, loyalty, and updates the order.
//
// Validates: order exists; status in (delivered/cancelled/in_delivery, etc.);
//   refundedAmount + amount <= total. Reverses loyalty (earn + spend).
//   If full refund → status='refunded', refundedAt=now. Else refundedAmount += amount.

const loyalty = require('./loyalty');
const { audit } = require('../lib/audit');

// Statuses that can be refunded. We allow late-stage statuses + cancelled.
const REFUNDABLE_STATUSES = new Set([
  'delivered',
  'confirmedByBuyer',
  'cancelled',
  'inDelivery',
  'arrivedAtCustomer',
  'pickedUp',
  'in_delivery', // tolerate alt spelling
]);

// eslint-disable-next-line global-require
const logger = require('../lib/logger');

async function refundOrder(prisma, { orderId, amount, reason, actorId, ipAddress }) {
  if (!orderId) {
    throw Object.assign(new Error('orderId required'), { status: 400 });
  }
  const amt = Number(amount);
  if (!Number.isFinite(amt) || amt <= 0) {
    throw Object.assign(new Error('amount must be > 0'), { status: 400 });
  }
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) {
    throw Object.assign(new Error('Order not found'), { status: 404 });
  }
  if (!REFUNDABLE_STATUSES.has(order.status)) {
    throw Object.assign(new Error(`Order status ${order.status} not refundable`), { status: 400 });
  }
  const alreadyRefunded = Number(order.refundedAmount || 0);
  if (alreadyRefunded + amt > Number(order.total) + 0.001) {
    throw Object.assign(new Error('Refund exceeds order total'), { status: 400 });
  }

  // 1. Reverse loyalty (idempotent — only first refund call reverses; subsequent
  //    calls won't re-reverse because reason="refund" creates a tx that
  //    the helper doesn't filter out, but the net delta only counts earn/spend).
  try {
    await loyalty.refundOrder(prisma, order.buyerId, order.id);
  } catch (err) {
    // Don't block refund on loyalty failure, but DO emit a structured log so
    // support can see when loyalty reversal needs manual cleanup.
    logger.warn(
      { err: err.message, orderId, userId: order.buyerId },
      'refund: loyalty reversal failed',
    );
  }

  const newRefunded = alreadyRefunded + amt;
  const fullRefund = Math.abs(newRefunded - Number(order.total)) < 0.5;

  const data = {
    refundedAmount: newRefunded,
    refundReason: reason || order.refundReason || null,
  };
  if (fullRefund) {
    data.status = 'refunded';
    data.refundedAt = new Date();
  } else if (!order.refundedAt) {
    // partial — leave refundedAt null until full refund
  }

  const updated = await prisma.order.update({
    where: { id: order.id },
    data,
  });

  await audit({
    actorId: actorId || null,
    action: 'order.refund',
    targetType: 'Order',
    targetId: order.id,
    metadata: { amount: amt, reason, totalRefunded: newRefunded, full: fullRefund },
    ipAddress: ipAddress || null,
  });

  return updated;
}

module.exports = { refundOrder, REFUNDABLE_STATUSES };
