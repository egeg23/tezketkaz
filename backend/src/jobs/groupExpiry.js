// BullMQ worker handler for the `groupExpiry` queue. Runs once a day to
// expire group orders ('open' status, expiresAt < now) so the buyer/host
// doesn't see them lingering in their list.
//
// Production cron (registered in src/index.js): `0 6 * * *` daily at 06:00 UTC.

const prisma = require('../db');
const logger = require('../lib/logger');
const orderGroup = require('../services/orderGroup');

async function groupExpiryHandler(job) {
  if (job.name === 'sweep') {
    try {
      const summary = await orderGroup.expireDue(prisma);
      logger.info(summary, 'group expiry sweep complete');
      return summary;
    } catch (err) {
      logger.error({ err }, 'group expiry sweep failed');
      throw err;
    }
  }
  logger.warn({ name: job.name }, 'unknown groupExpiry job');
}

module.exports = { groupExpiryHandler };
