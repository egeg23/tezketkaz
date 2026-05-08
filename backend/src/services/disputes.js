// Disputes service — buyer-opened disputes over delivered/cancelled orders.
//
// Open: requires the order to belong to the buyer, status in
//   (delivered, inDelivery, arrivedAtCustomer, cancelled, confirmedByBuyer),
//   and the deliveredAt within the configurable dispute window
//   (default 72 hours, env DISPUTE_WINDOW_HOURS).
// Resolve: admin only — picks a resolution and optionally triggers a refund.

const { audit } = require('../lib/audit');
const refunds = require('./refunds');

const DISPUTE_WINDOW_HOURS = parseInt(process.env.DISPUTE_WINDOW_HOURS || '72', 10);
const ALLOWED_REASONS = new Set([
  'missing_items', 'wrong_items', 'late', 'damaged', 'other',
]);
const DISPUTABLE_STATUSES = new Set([
  'delivered', 'confirmedByBuyer', 'inDelivery', 'arrivedAtCustomer', 'cancelled',
]);
const RESOLUTIONS = new Set([
  'refund', 'partial_refund', 'replacement', 'rejected', 'no_action',
]);

async function openDispute(prisma, { orderId, openedById, reason, description, evidence, ipAddress }) {
  if (!orderId || !openedById) {
    throw Object.assign(new Error('orderId and openedById required'), { status: 400 });
  }
  if (!ALLOWED_REASONS.has(reason)) {
    throw Object.assign(new Error('Invalid dispute reason'), { status: 400 });
  }
  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) {
    throw Object.assign(new Error('Order not found'), { status: 404 });
  }
  if (order.buyerId !== openedById) {
    throw Object.assign(new Error('Only the buyer may open a dispute'), { status: 403 });
  }
  if (!DISPUTABLE_STATUSES.has(order.status)) {
    throw Object.assign(new Error(`Order status ${order.status} not eligible for dispute`), { status: 400 });
  }
  // If the order is delivered, ensure within the dispute window.
  const reference = order.deliveredAt || order.cancelledAt;
  if (order.status !== 'cancelled' && reference) {
    const hoursSince = (Date.now() - new Date(reference).getTime()) / (60 * 60 * 1000);
    if (hoursSince > DISPUTE_WINDOW_HOURS) {
      throw Object.assign(new Error(`Dispute window (${DISPUTE_WINDOW_HOURS}h) elapsed`), { status: 400 });
    }
  }
  const existing = await prisma.dispute.findUnique({ where: { orderId } });
  if (existing) {
    throw Object.assign(new Error('Dispute already exists for this order'), { status: 409 });
  }

  const dispute = await prisma.dispute.create({
    data: {
      orderId,
      openedById,
      reason,
      description: description || null,
      evidence: evidence ? (typeof evidence === 'string' ? evidence : JSON.stringify(evidence)) : null,
      status: 'open',
    },
  });

  await audit({
    actorId: openedById,
    action: 'dispute.open',
    targetType: 'Dispute',
    targetId: dispute.id,
    metadata: { orderId, reason },
    ipAddress: ipAddress || null,
  });

  return dispute;
}

async function resolveDispute(prisma, { disputeId, actorId, resolution, refundAmount, note, ipAddress }) {
  if (!disputeId) {
    throw Object.assign(new Error('disputeId required'), { status: 400 });
  }
  if (!RESOLUTIONS.has(resolution)) {
    throw Object.assign(new Error('Invalid resolution'), { status: 400 });
  }
  const dispute = await prisma.dispute.findUnique({ where: { id: disputeId } });
  if (!dispute) {
    throw Object.assign(new Error('Dispute not found'), { status: 404 });
  }
  if (dispute.status === 'resolved' || dispute.status === 'rejected') {
    throw Object.assign(new Error('Dispute already closed'), { status: 400 });
  }

  let actualRefund = 0;
  if (resolution === 'refund' || resolution === 'partial_refund') {
    const order = await prisma.order.findUnique({ where: { id: dispute.orderId } });
    if (!order) {
      throw Object.assign(new Error('Order not found'), { status: 404 });
    }
    const requested = Number(refundAmount);
    actualRefund = resolution === 'refund'
      ? (Number.isFinite(requested) && requested > 0 ? requested : Number(order.total) - Number(order.refundedAmount || 0))
      : (Number.isFinite(requested) && requested > 0 ? requested : 0);
    if (actualRefund <= 0) {
      throw Object.assign(new Error('refundAmount must be > 0 for refund resolutions'), { status: 400 });
    }
    await refunds.refundOrder(prisma, {
      orderId: dispute.orderId,
      amount: actualRefund,
      reason: `dispute:${dispute.reason}`,
      actorId,
      ipAddress,
    });
  }

  const newStatus = resolution === 'rejected' ? 'rejected' : 'resolved';
  const updated = await prisma.dispute.update({
    where: { id: dispute.id },
    data: {
      status: newStatus,
      resolution,
      refundAmount: actualRefund,
      resolvedById: actorId || null,
      resolvedAt: new Date(),
      resolutionNote: note || null,
    },
  });

  await audit({
    actorId: actorId || null,
    action: 'dispute.resolve',
    targetType: 'Dispute',
    targetId: dispute.id,
    metadata: { resolution, refundAmount: actualRefund, note },
    ipAddress: ipAddress || null,
  });

  return updated;
}

module.exports = {
  DISPUTE_WINDOW_HOURS,
  ALLOWED_REASONS,
  DISPUTABLE_STATUSES,
  RESOLUTIONS,
  openDispute,
  resolveDispute,
};
