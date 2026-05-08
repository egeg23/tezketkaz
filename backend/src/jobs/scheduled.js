// BullMQ worker handler for the `scheduled` queue. Activates a scheduled order
// when its timer fires (~30 minutes before the slot).

const prisma = require('../db');
const logger = require('../lib/logger');
const scheduling = require('../services/scheduling');
const { queues } = require('../lib/queues');

function getIo() {
  try {
    // eslint-disable-next-line global-require
    const sockets = require('../sockets');
    return sockets.io || null;
  } catch {
    return null;
  }
}

async function scheduledHandler(job) {
  const { orderId } = job.data || {};
  if (!orderId) return;
  try {
    await scheduling.activateScheduledOrder(prisma, getIo(), queues, orderId);
  } catch (err) {
    logger.error({ err, orderId }, 'scheduled activate failed');
    throw err;
  }
}

module.exports = { scheduledHandler };
