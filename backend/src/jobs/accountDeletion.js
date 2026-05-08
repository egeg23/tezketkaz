// BullMQ worker handler for the `accountDeletion` queue. Runs daily at
// 05:00 UTC (cron registered in src/index.js) and hard-purges users whose
// 30-day grace period has elapsed.

const prisma = require('../db');
const logger = require('../lib/logger');
const accountDeletion = require('../services/accountDeletion');

async function accountDeletionHandler(job) {
  if (job.name === 'purge') {
    try {
      const summary = await accountDeletion.purgeDue(prisma);
      logger.info(summary, 'account deletion purge complete');
      return summary;
    } catch (err) {
      logger.error({ err }, 'account deletion purge failed');
      throw err;
    }
  }
  logger.warn({ name: job.name }, 'unknown accountDeletion job');
}

module.exports = { accountDeletionHandler };
