// BullMQ queues + worker bootstrap. When Redis is disabled, exports no-op
// shims so dev/test environments don't crash when code enqueues jobs.

const env = require('../config/env');
const logger = require('./logger');
const { getRedis } = require('./redis');

let _queues = null;
let _workers = null;

// Inline-run the dispatcher when Redis is absent so dev environments aren't
// silently broken (orders would otherwise stay in 'pending' forever because
// the BullMQ worker never starts).
async function runDispatchInline(jobName, data) {
  try {
    // eslint-disable-next-line global-require
    const prisma = require('../db');
    // eslint-disable-next-line global-require
    const dispatcher = require('../services/dispatcher');
    const io = global.__tkk_io || null;
    if (jobName === 'startDispatch' || data?.type === 'startDispatch') {
      await dispatcher.offerNextBatch(prisma, io, data.orderId);
    } else if (jobName === 'retry' || data?.type === 'retry') {
      await dispatcher.expireOverdueOffers(prisma, data.orderId);
      await dispatcher.offerNextBatch(prisma, io, data.orderId);
    }
  } catch (err) {
    logger.warn({ err: err.message, jobName, data }, 'inline dispatch failed');
  }
}

function makeNoopQueue(name) {
  return {
    name,
    async add(jobName, data, opts) {
      logger.debug({ queue: name, jobName, data, opts }, 'queue noop add');
      // dispatch is the one queue we MUST execute even without Redis,
      // otherwise orders never reach a courier in dev. Other queues
      // (autoCancel/scheduled/payouts) all rely on delays/cron and
      // safely no-op in dev.
      //
      // In test env, skip the inline run — Jest tears down the module
      // registry before deferred timers fire, which makes the require()
      // calls inside `runDispatchInline` blow up. Tests that exercise
      // dispatch call `dispatcher.offerNextBatch` directly.
      if (name === 'dispatch' && process.env.NODE_ENV !== 'test') {
        if (opts?.delay && opts.delay > 0) {
          setTimeout(() => runDispatchInline(jobName, data), opts.delay);
        } else {
          setImmediate(() => runDispatchInline(jobName, data));
        }
      }
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
    payouts: makeNoopQueue('payouts'),
    membership: makeNoopQueue('membership'),
    accountDeletion: makeNoopQueue('accountDeletion'),
    backup: makeNoopQueue('backup'),
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
    payouts: new Queue('payouts', { connection }),
    membership: new Queue('membership', { connection }),
    accountDeletion: new Queue('accountDeletion', { connection }),
    backup: new Queue('backup', { connection }),
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
  if (handlers.payouts) {
    _workers.push(new Worker('payouts', handlers.payouts, { connection, concurrency: 1 }));
  }
  if (handlers.membership) {
    _workers.push(new Worker('membership', handlers.membership, { connection, concurrency: 1 }));
  }
  if (handlers.accountDeletion) {
    _workers.push(new Worker('accountDeletion', handlers.accountDeletion, { connection, concurrency: 1 }));
  }
  if (handlers.backup) {
    _workers.push(new Worker('backup', handlers.backup, { connection, concurrency: 1 }));
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
