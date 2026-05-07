// BullMQ queues + worker bootstrap. When Redis is disabled, exports no-op
// shims so dev/test environments don't crash when code enqueues jobs.

const env = require('../config/env');
const logger = require('./logger');
const { getRedis } = require('./redis');

let _queues = null;
let _workers = null;

function makeNoopQueue(name) {
  return {
    name,
    async add(jobName, data, opts) {
      // Silent no-op — caller doesn't need to know.
      logger.debug({ queue: name, jobName, data, opts }, 'queue noop add');
      return { id: 'noop', name: jobName, data };
    },
    async close() { /* noop */ },
    async getJobCounts() { return {}; },
  };
}

function noopQueues() {
  return {
    dispatch: makeNoopQueue('dispatch'),
    autoCancel: makeNoopQueue('autoCancel'),
    scheduled: makeNoopQueue('scheduled'),
  };
}

function isEnabled() {
  return Boolean(env.redisEnabled && getRedis());
}

function queues() {
  if (_queues) return _queues;
  if (!isEnabled()) {
    _queues = noopQueues();
    return _queues;
  }
  // Lazy-require BullMQ so tests without it installed don't blow up.
  // eslint-disable-next-line global-require
  const { Queue } = require('bullmq');
  const connection = getRedis();
  _queues = {
    dispatch: new Queue('dispatch', { connection }),
    autoCancel: new Queue('autoCancel', { connection }),
    scheduled: new Queue('scheduled', { connection }),
  };
  return _queues;
}

function startWorkers(handlers) {
  if (!isEnabled()) {
    logger.info('queues.startWorkers: Redis disabled, skipping');
    return [];
  }
  // eslint-disable-next-line global-require
  const { Worker } = require('bullmq');
  const connection = getRedis();
  _workers = [
    new Worker('dispatch', handlers.dispatch, { connection, concurrency: 4 }),
    new Worker('autoCancel', handlers.autoCancel, { connection, concurrency: 2 }),
  ];
  if (handlers.scheduled) {
    _workers.push(new Worker('scheduled', handlers.scheduled, { connection, concurrency: 2 }));
  }
  for (const w of _workers) {
    w.on('failed', (job, err) => logger.error({ queue: w.name, jobId: job?.id, err }, 'worker job failed'));
  }
  return _workers;
}

async function closeAll() {
  if (_workers) {
    for (const w of _workers) {
      try { await w.close(); } catch { /* noop */ }
    }
    _workers = null;
  }
  if (_queues) {
    for (const q of Object.values(_queues)) {
      try { await q.close(); } catch { /* noop */ }
    }
    _queues = null;
  }
}

module.exports = { queues, startWorkers, closeAll, isEnabled };
