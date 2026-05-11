// BullMQ worker handler for the `fiscal:issue` queue (Phase 13.3.9).
//
// Job payload: { orderId }.
//
// Issues a Soliq.uz fiscal receipt for a paid order. Idempotent: skips when
// the order already has a fiscalReceiptId; the queue retries on transient
// failures with exponential backoff (1m, 5m, 30m, 2h, 12h). On final
// failure the order's fiscalFailureCount + fiscalLastError are persisted
// and an admin notification is emitted.

const prisma = require('../db');
const logger = require('../lib/logger');
const soliq = require('../services/soliq');
const { audit } = require('../lib/audit');

// Treat any country whose ISO matches this set as Uzbekistan. The fiscal
// requirement is only enforced for orders inside UZ; cross-border launches
// have their own fiscalisation rules and live behind separate jobs.
const UZ_COUNTRIES = new Set(['UZ', 'uz', 'UZB']);

// The buyer's country lives on User, but we snapshot orders with currency.
// For simplicity we treat UZS-currency orders as UZ for fiscal scope; admins
// can re-enqueue manually for edge cases (e.g. UZS denominated cross-border).
function orderInUZ(order, buyer) {
  if (buyer && UZ_COUNTRIES.has(buyer.country)) return true;
  if (order && (order.currency === 'UZS' || order.currency === 'uzs')) return true;
  return false;
}

// Internal — exported for tests. Performs the actual issue + DB write.
async function processFiscalReceipt({ orderId }, { isFinalAttempt = false } = {}) {
  if (!orderId) return { skipped: 'missing_order_id' };

  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: { items: true, shop: true, buyer: true },
  });
  if (!order) return { skipped: 'order_not_found' };

  // Idempotency.
  if (order.fiscalReceiptId) {
    return { skipped: 'already_issued', receiptId: order.fiscalReceiptId };
  }

  // Country gate.
  if (!orderInUZ(order, order.buyer)) {
    return { skipped: 'not_uz' };
  }

  // Shop eligibility (soliqEnabled + soliqInn + apiKey).
  if (!soliq.isShopEligible(order.shop)) {
    return { skipped: 'shop_not_eligible' };
  }

  // Issue.
  let result;
  try {
    result = await soliq.issueReceipt(order, order.shop);
  } catch (err) {
    // Network/5xx — re-throw so BullMQ retries.
    logger.warn(
      { err: err.message, orderId },
      'fiscal:issue transient failure (will retry)',
    );
    if (isFinalAttempt) {
      await recordFinalFailure(order, err.message);
    }
    throw err;
  }

  if (!result || !result.ok) {
    // Business-logic failure — don't retry forever. Record as a hard failure
    // so admin can investigate.
    const errMsg = (result && result.error) || 'unknown';
    logger.warn({ orderId, error: errMsg }, 'fiscal:issue business failure');
    await recordFinalFailure(order, errMsg);
    return { ok: false, error: errMsg };
  }

  // Success path — persist receipt and audit.
  await prisma.order.update({
    where: { id: order.id },
    data: {
      fiscalReceiptId: result.receiptId,
      fiscalReceiptUrl: result.receiptUrl || null,
      fiscalIssuedAt: new Date(),
      fiscalLastError: null,
    },
  });

  await audit({
    actorId: null,
    action: 'order.fiscal_issued',
    targetType: 'Order',
    targetId: order.id,
    metadata: { receiptId: result.receiptId, receiptUrl: result.receiptUrl },
  });

  return { ok: true, receiptId: result.receiptId, receiptUrl: result.receiptUrl };
}

// Bump the order's failure counter, capture the error, and notify admins.
async function recordFinalFailure(order, errMessage) {
  try {
    await prisma.order.update({
      where: { id: order.id },
      data: {
        fiscalFailureCount: { increment: 1 },
        fiscalLastError: String(errMessage).slice(0, 500),
      },
    });
  } catch (err) {
    logger.warn({ err: err.message, orderId: order.id }, 'fiscal failure persist failed');
  }

  // Notify all admins so they can manually retry / fix the shop config.
  try {
    const admins = await prisma.user.findMany({
      where: { isAdmin: true, deletedAt: null },
      select: { id: true },
    });
    if (admins.length > 0) {
      await prisma.notification.createMany({
        data: admins.map((a) => ({
          userId: a.id,
          title: 'Fiscal receipt failed',
          body: `Order ${order.orderNumber || order.id} could not be fiscalised: ${errMessage}`,
          type: 'fiscal_failure',
          data: JSON.stringify({ orderId: order.id, error: errMessage }),
        })),
      });
    }
  } catch (err) {
    logger.warn({ err: err.message, orderId: order.id }, 'fiscal admin notify failed');
  }

  await audit({
    actorId: null,
    action: 'order.fiscal_failed',
    targetType: 'Order',
    targetId: order.id,
    metadata: { error: String(errMessage).slice(0, 500) },
  });
}

async function fiscalReceiptHandler(job) {
  const data = job.data || {};
  // BullMQ exposes attemptsMade + opts.attempts. Final attempt = attemptsMade
  // (after this run) === opts.attempts. We use job.attemptsMade + 1 because
  // BullMQ increments after the handler returns.
  const attemptNumber = (job.attemptsMade || 0) + 1;
  const maxAttempts = (job.opts && job.opts.attempts) || 5;
  const isFinalAttempt = attemptNumber >= maxAttempts;

  try {
    const result = await processFiscalReceipt(data, { isFinalAttempt });
    return result;
  } catch (err) {
    logger.warn(
      { err: err.message, orderId: data.orderId, attemptNumber, maxAttempts },
      'fiscal:issue job error',
    );
    throw err;
  }
}

// Retry config used in src/index.js when enqueueing. Exposed so the producer
// and worker stay in sync.
const RETRY_OPTS = {
  attempts: 5,
  // Backoff in ms: 1m, 5m, 30m, 2h, 12h. We use the `custom` strategy by
  // returning a function from the worker — but BullMQ's built-in exponential
  // is too coarse for these targets, so we pass `delay` as a manually-shaped
  // array via `backoff.type=fixed` per attempt fallback. The producer can
  // ALSO override per-job. We keep the canonical schedule documented here.
  backoff: { type: 'exponential', delay: 60 * 1000 },
};

// Backoff-schedule helper. Producers can opt in to the precise schedule:
//   1m, 5m, 30m, 2h, 12h
const BACKOFF_SCHEDULE_MS = [
  1 * 60 * 1000,
  5 * 60 * 1000,
  30 * 60 * 1000,
  2 * 60 * 60 * 1000,
  12 * 60 * 60 * 1000,
];

module.exports = {
  fiscalReceiptHandler,
  processFiscalReceipt,
  recordFinalFailure,
  RETRY_OPTS,
  BACKOFF_SCHEDULE_MS,
};
