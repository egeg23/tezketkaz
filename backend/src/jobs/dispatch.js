// BullMQ worker handlers for dispatch + auto-cancel queues.
//
// Both handlers grab a singleton prisma + io. The io instance is exported by
// `src/index.js` after the http server bootstraps; for tests we let the
// handler tolerate a missing io.

const prisma = require('../db');
const logger = require('../lib/logger');
const dispatcher = require('../services/dispatcher');

function getIo() {
  // Resolved lazily so the require cycle (sockets/index.js → queues → jobs)
  // doesn't trip up.
  try {
    // eslint-disable-next-line global-require
    const sockets = require('../sockets');
    return sockets.io || null;
  } catch {
    return null;
  }
}

async function dispatchHandler(job) {
  const { type, orderId, opts } = job.data || {};
  if (!orderId) return;

  const io = getIo();
  if (type === 'startDispatch') {
    await dispatcher.offerNextBatch(prisma, io, orderId);
    return;
  }
  if (type === 'retry') {
    await dispatcher.expireOverdueOffers(prisma, orderId);
    await dispatcher.offerNextBatch(prisma, io, orderId, opts || {});
    return;
  }
  logger.warn({ type, orderId }, 'unknown dispatch job type');
}

async function autoCancelHandler(job) {
  const { orderId, expectedStatus } = job.data || {};
  if (!orderId) return;

  const order = await prisma.order.findUnique({ where: { id: orderId } });
  if (!order) return;
  if (order.courierId) return; // already taken
  if (expectedStatus && order.status !== expectedStatus) return; // moved on
  if (['delivered', 'confirmedByBuyer', 'cancelled'].includes(order.status)) return;

  const updated = await prisma.order.update({
    where: { id: orderId },
    data: {
      status: 'cancelled',
      cancelledAt: new Date(),
      cancelReason: 'auto_no_courier',
    },
  });

  const io = getIo();
  if (io) {
    try {
      io.to(`buyer:${updated.buyerId}`).emit('order:updated', updated);
      io.to(`shop:${updated.shopId}`).emit('order:updated', updated);
    } catch (err) {
      logger.warn({ err: err.message }, 'autoCancel emit failed');
    }
  }
}

module.exports = { dispatchHandler, autoCancelHandler };
