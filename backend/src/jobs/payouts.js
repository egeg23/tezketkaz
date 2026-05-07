// BullMQ worker handler for the `payouts` queue. Generates weekly payouts
// (couriers + shops) for the most recently completed week.

const prisma = require('../db');
const logger = require('../lib/logger');
const payouts = require('../services/payouts');

async function payoutsHandler(job) {
  if (job.name === 'weekly') {
    try {
      const weekStart = payouts.getLastMonday();
      const result = await payouts.generateWeeklyPayouts(prisma, { weekStart });
      logger.info({ count: result.length, weekStart }, 'weekly payouts generated');
      return { count: result.length };
    } catch (err) {
      logger.error({ err }, 'weekly payouts failed');
      throw err;
    }
  }
  logger.warn({ name: job.name }, 'unknown payouts job');
}

module.exports = { payoutsHandler };
