// BullMQ worker handler for the `backup` queue. Cron `0 2 * * *` UTC.

const logger = require('../lib/logger');
const backup = require('../services/backup');

async function backupHandler(job) {
  if (job.name === 'daily') {
    try {
      const summary = await backup.runDailyBackup();
      logger.info(summary, 'daily backup complete');
      return summary;
    } catch (err) {
      // Should never bubble — runDailyBackup catches everything itself, but
      // belt-and-suspenders so the worker doesn't crash the process.
      logger.error({ err }, 'daily backup failed');
      return { ok: false, error: err.message };
    }
  }
  logger.warn({ name: job.name }, 'unknown backup job');
}

module.exports = { backupHandler };
