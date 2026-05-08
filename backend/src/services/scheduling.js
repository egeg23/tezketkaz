// Scheduled-order service. Wraps queue enqueue + DB row creation; the BullMQ
// worker (src/jobs/scheduled.js) calls activateScheduledOrder ~30 minutes
// before the slot to kick off dispatch with normal lead time.

const logger = require('../lib/logger');

const MAX_SCHEDULE_DAYS = 7;
const ACTIVATE_LEAD_MS = 30 * 60 * 1000; // 30 minutes

function bad(msg, code = 'invalid_schedule') {
  return Object.assign(new Error(msg), { status: 400, code });
}

async function scheduleOrder(prisma, queues, { orderId, scheduledFor }) {
  if (!orderId) throw bad('orderId required');
  const when = scheduledFor instanceof Date ? scheduledFor : new Date(scheduledFor);
  if (Number.isNaN(when.getTime())) throw bad('Invalid scheduledFor');

  const now = new Date();
  if (when.getTime() <= now.getTime()) {
    throw bad('scheduledFor must be in the future', 'past_schedule');
  }
  const maxAt = new Date(now.getTime() + MAX_SCHEDULE_DAYS * 24 * 60 * 60 * 1000);
  if (when.getTime() > maxAt.getTime()) {
    throw bad('scheduledFor must be within 7 days', 'too_far_schedule');
  }

  const row = await prisma.scheduledOrder.upsert({
    where: { orderId },
    create: { orderId, scheduledFor: when, status: 'pending' },
    update: { scheduledFor: when, status: 'pending', activatedAt: null },
  });

  // Mirror onto the order for indexed queries.
  try {
    await prisma.order.update({
      where: { id: orderId },
      data: { scheduledFor: when },
    });
  } catch (err) {
    logger.warn({ err: err.message, orderId }, 'order.scheduledFor mirror failed');
  }

  // Best-effort enqueue; queue may be a no-op shim in dev/tests.
  if (queues && typeof queues === 'function') {
    try {
      const q = queues();
      if (q && q.scheduled && typeof q.scheduled.add === 'function') {
        const delay = Math.max(0, when.getTime() - ACTIVATE_LEAD_MS - Date.now());
        await q.scheduled.add(
          'activate',
          { orderId },
          { delay, removeOnComplete: true, removeOnFail: false },
        );
      }
    } catch (err) {
      logger.warn({ err: err.message, orderId }, 'scheduled queue enqueue failed');
    }
  }

  return row;
}

async function activateScheduledOrder(prisma, io, queues, orderId) {
  const row = await prisma.scheduledOrder.findUnique({ where: { orderId } });
  if (!row) return { ok: false, reason: 'not_found' };
  if (row.status === 'cancelled') return { ok: false, reason: 'cancelled' };
  if (row.status === 'activated') return { ok: true, alreadyActivated: true };

  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) return { ok: false, reason: 'order_missing' };
  if (['cancelled', 'delivered', 'confirmedByBuyer'].includes(order.status)) {
    return { ok: false, reason: 'order_finalized' };
  }

  const now = new Date();
  await prisma.scheduledOrder.update({
    where: { orderId },
    data: { status: 'activated', activatedAt: now },
  });

  // Promote the order to a state that actually triggers dispatch — leave it
  // at `pending` for shop accept (matches the standard flow).
  let updated = order;
  if (order.status === 'pending') {
    updated = await prisma.order.update({
      where: { id: orderId },
      data: { status: 'pending' },
    });
  }

  // Enqueue dispatch (or invoke directly when queues are no-ops).
  if (queues && typeof queues === 'function') {
    try {
      const q = queues();
      if (q && q.dispatch && typeof q.dispatch.add === 'function') {
        await q.dispatch.add('startDispatch', { type: 'startDispatch', orderId });
      }
    } catch (err) {
      logger.warn({ err: err.message, orderId }, 'dispatch enqueue failed');
    }
  }

  if (io && typeof io.to === 'function' && updated) {
    try {
      io.to(`buyer:${updated.buyerId}`).emit('order:updated', updated);
    } catch (err) {
      logger.warn({ err: err.message }, 'scheduled activate emit failed');
    }
  }

  return { ok: true, order: updated };
}

async function cancelScheduledOrder(prisma, queues, orderId) {
  const row = await prisma.scheduledOrder.findUnique({ where: { orderId } });
  if (!row) return { ok: false, reason: 'not_found' };
  if (row.status === 'activated') return { ok: false, reason: 'already_activated' };
  if (row.status === 'cancelled') return { ok: true, alreadyCancelled: true };

  await prisma.scheduledOrder.update({
    where: { orderId },
    data: { status: 'cancelled' },
  });
  return { ok: true };
}

module.exports = {
  scheduleOrder,
  activateScheduledOrder,
  cancelScheduledOrder,
  MAX_SCHEDULE_DAYS,
  ACTIVATE_LEAD_MS,
};
