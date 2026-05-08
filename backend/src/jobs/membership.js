// BullMQ worker handler for the `membership` queue. Drives daily renewal of
// active memberships, expiry of stale rows, and grace-period exhaustion.
//
// Production cron (registered in src/index.js): `0 4 * * *` daily at 04:00 UTC.

const prisma = require('../db');
const logger = require('../lib/logger');
const subscription = require('../services/subscription');

async function membershipHandler(job) {
  if (job.name === 'renew') {
    try {
      const summary = await subscription.renewDueMemberships(prisma);
      logger.info(summary, 'membership renewal pass complete');
      return summary;
    } catch (err) {
      logger.error({ err }, 'membership renewal failed');
      throw err;
    }
  }
  logger.warn({ name: job.name }, 'unknown membership job');
}

module.exports = { membershipHandler };
