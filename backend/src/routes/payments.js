// Payment routes
//
// Hardening notes (Phase 0):
//  • Every webhook is signature-verified BEFORE any side effect.
//  • Every webhook is idempotent: a repeated (provider, externalId) replays
//    the exact stored response — so retries never double-charge / double-emit.
//  • Side effects (DB write, socket emit, audit) all happen INSIDE the
//    idempotency guard.
//
// Body parsing for Uzum:
//   Uzum signs the *raw bytes*, so HMAC verification needs the exact body.
//   We register `express.raw` on `/uzum/callback` so that — provided the
//   global JSON parser in `src/index.js` is configured to skip this path —
//   `req.body` arrives as a Buffer and we can verify before parsing.
//   FALLBACK: if the global parser ran first (`req.body` is an object), we
//   re-serialize via `JSON.stringify` and clearly mark that this is a
//   degraded mode. Production deploys must mount raw before json on this path
//   for guaranteed signature integrity.
const express = require('express');
const router = express.Router();
const prisma = require('../db');
const logger = require('../lib/logger');
const { authMiddleware } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const click = require('../services/click');
const payme = require('../services/payme');
const uzum = require('../services/uzum');
const kaspi = require('../services/kaspi');
const { queues } = require('../lib/queues');

// Phase 13.3.9 — enqueue Soliq fiscal-receipt job after payment confirmation.
// Best-effort: callers swallow failures so a queue blip can't break a webhook.
async function enqueueFiscalIssue(orderId) {
  if (!orderId) return;
  try {
    await queues().fiscal.add(
      'issue',
      { orderId },
      {
        attempts: 5,
        backoff: { type: 'exponential', delay: 60 * 1000 },
        removeOnComplete: 100,
        removeOnFail: 500,
      },
    );
  } catch (err) {
    logger.warn({ err: err.message, orderId }, 'fiscal enqueue failed');
  }
}

const VALID_INIT_METHODS = new Set(['click', 'payme', 'uzumpay']);

/**
 * Idempotency helper. Looks up an existing (provider, externalId) record.
 * If present, returns the cached parsed response. If absent, runs `processFn`,
 * persists the result, and returns it. Concurrent duplicates that lose the
 * unique-constraint race fall back to reading the now-existing record.
 */
async function withIdempotency({ provider, externalId, payload, orderId }, processFn) {
  if (!externalId) {
    // Without an externalId we cannot key idempotency — process unguarded.
    // (Callers should reject this case earlier; this is just a safety net.)
    return processFn();
  }

  const existing = await prisma.processedWebhook.findUnique({
    where: { provider_externalId: { provider, externalId } },
  });
  if (existing) {
    try {
      return JSON.parse(existing.result);
    } catch (_) {
      logger.warn({ provider, externalId }, 'processed webhook stored result is not valid JSON');
      return {};
    }
  }

  const result = await processFn();

  try {
    await prisma.processedWebhook.create({
      data: {
        provider,
        externalId: String(externalId),
        orderId: orderId || null,
        payload: safeJsonStringify(payload),
        result: safeJsonStringify(result),
      },
    });
  } catch (err) {
    // Unique-constraint race: another concurrent worker already inserted.
    // Replay that one's response so we converge.
    if (err && (err.code === 'P2002' || /Unique/i.test(String(err.message)))) {
      const winner = await prisma.processedWebhook.findUnique({
        where: { provider_externalId: { provider, externalId } },
      });
      if (winner) {
        try { return JSON.parse(winner.result); } catch (_) { return result; }
      }
    } else {
      logger.warn({ err: err.message, provider, externalId }, 'failed to persist processed webhook');
    }
  }

  return result;
}

function safeJsonStringify(v) {
  try {
    return JSON.stringify(v);
  } catch (_) {
    return JSON.stringify({ unserializable: true });
  }
}

// ─── POST /api/payments/init — initialize payment for order ──────────────────
router.post('/init', authMiddleware, async (req, res, next) => {
  try {
    const { orderId, method } = req.body || {};
    if (!orderId || !method) return res.status(400).json({ error: 'orderId and method required' });
    if (method === 'cash') return res.status(400).json({ error: 'Cash does not require init' });
    if (!VALID_INIT_METHODS.has(method)) return res.status(400).json({ error: 'Invalid method' });

    const order = await prisma.order.findUnique({ where: { id: orderId } });
    if (!order) return res.status(404).json({ error: 'Order not found' });
    if (order.buyerId !== req.user.id) return res.status(403).json({ error: 'Not your order' });
    if (order.isPaid) return res.status(400).json({ error: 'Already paid' });

    let url;
    switch (method) {
      case 'click':   url = await click.createInvoice(order); break;
      case 'payme':   url = await payme.createInvoice(order); break;
      case 'uzumpay': url = await uzum.createInvoice(order); break;
      // VALID_INIT_METHODS guards default — unreachable.
    }

    res.json({ url });
  } catch (err) { next(err); }
});

// ─── GET /api/payments/:orderId/status ───────────────────────────────────────
router.get('/:orderId/status', authMiddleware, async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({ where: { id: req.params.orderId } });
    if (!order) return res.status(404).json({ error: 'Order not found' });

    const isBuyer = order.buyerId === req.user.id;
    const isShopMember = Array.isArray(req.user.shopMemberships)
      && req.user.shopMemberships.some((m) => m.shopId === order.shopId);
    if (!isBuyer && !isShopMember) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    res.json({
      isPaid: order.isPaid,
      paymentRef: order.paymentRef || null,
      paymentMethod: order.paymentMethod,
    });
  } catch (err) { next(err); }
});

// ─── POST /api/payments/click/callback ───────────────────────────────────────
// Click retries on non-200, so we always reply 200 with a body — error: -1
// signals bad signature per Click's docs (see "click-api-request-shop").
router.post('/click/callback', async (req, res, next) => {
  try {
    const body = req.body || {};
    const result = await click.verifyCallback(body);

    if (!result.valid) {
      // 200 + error:-1 (Click expects 2xx; non-2xx triggers retry storm)
      return res.status(200).json({ error: -1, error_note: 'SIGN CHECK FAILED' });
    }

    if (!result.complete) {
      // Prepare phase — ack without paying.
      return res.status(200).json({
        click_trans_id: body.click_trans_id,
        merchant_trans_id: body.merchant_trans_id,
        merchant_prepare_id: body.click_trans_id,
        error: 0,
      });
    }

    const externalId = String(body.click_trans_id);
    const stored = await withIdempotency(
      { provider: 'click', externalId, payload: body, orderId: result.orderId },
      async () => {
        // Amount guard — Click sends `amount` as decimal sum (e.g. "120000.00").
        // Compare in integer cents to avoid float drift.
        const order = await prisma.order.findUnique({ where: { id: result.orderId } });
        if (!order) {
          return { error: -5, error_note: 'Order not found' };
        }
        const expectedCents = Math.round(order.total * 100);
        const reportedCents = Math.round(parseFloat(body.amount) * 100);
        if (!Number.isFinite(reportedCents) || expectedCents !== reportedCents) {
          return { error: -2, error_note: 'Amount mismatch' };
        }

        await prisma.order.update({
          where: { id: result.orderId },
          data: { isPaid: true, paymentRef: result.transactionId },
        });

        const io = req.app.get('io');
        if (io) io.to(`buyer:${result.buyerId}`).emit('payment:success', { orderId: result.orderId });

        await audit({
          actorId: result.buyerId,
          action: 'payment.received',
          targetType: 'Order',
          targetId: result.orderId,
          metadata: { provider: 'click', externalId },
        });

        // Phase 13.3.9 — fiscal receipt issuance.
        await enqueueFiscalIssue(result.orderId);

        return {
          click_trans_id: body.click_trans_id,
          merchant_trans_id: body.merchant_trans_id,
          merchant_confirm_id: body.click_trans_id,
          error: 0,
          error_note: 'Success',
        };
      },
    );

    return res.status(200).json(stored);
  } catch (err) { next(err); }
});

// ─── POST /api/payments/payme/callback ───────────────────────────────────────
// Payme uses HTTP Basic auth — no body signature. Bad auth ⇒ JSON-RPC -32504.
router.post('/payme/callback', async (req, res, next) => {
  try {
    const body = req.body || {};
    const id = body.id;

    if (!payme.verifyAuthHeader(req.headers.authorization)) {
      return res.status(200).json({
        id,
        error: { code: -32504, message: 'Insufficient privilege' },
      });
    }

    // Idempotency keyed on Payme's transaction id (`params.id`). Some methods
    // (CheckPerformTransaction) don't carry a tx id — process them unguarded
    // since they are read-only.
    const externalId = body && body.params && body.params.id ? String(body.params.id) : null;
    const writingMethod = body.method === 'PerformTransaction' || body.method === 'CancelTransaction';

    if (externalId && writingMethod) {
      const stored = await withIdempotency(
        { provider: 'payme', externalId, payload: body },
        async () => {
          const result = await payme.handleCallback(body);
          // Side-effects on successful Perform: emit + audit.
          if (body.method === 'PerformTransaction' && result && result.result) {
            const order = await prisma.order.findFirst({ where: { paymentRef: externalId } });
            if (order) {
              const io = req.app.get('io');
              if (io) io.to(`buyer:${order.buyerId}`).emit('payment:success', { orderId: order.id });
              await audit({
                actorId: order.buyerId,
                action: 'payment.received',
                targetType: 'Order',
                targetId: order.id,
                metadata: { provider: 'payme', externalId },
              });
              // Phase 13.3.9 — fiscal receipt issuance.
              await enqueueFiscalIssue(order.id);
            }
          }
          return result;
        },
      );
      return res.status(200).json(stored);
    }

    const result = await payme.handleCallback(body);
    return res.status(200).json(result);
  } catch (err) { next(err); }
});

// ─── POST /api/payments/uzum/callback ────────────────────────────────────────
// Raw body parser must run BEFORE any JSON parser so we can HMAC the exact
// bytes the provider sent. See module header for the index.js caveat.
router.post(
  '/uzum/callback',
  express.raw({ type: '*/*', limit: '256kb' }),
  async (req, res, next) => {
    try {
      // Resolve raw bytes + parsed JSON. Two paths:
      //   1) raw parser ran first (correct prod config): req.body is a Buffer.
      //   2) global json parser ran first (current index.js): req.body is an
      //      object — we re-serialize. This is degraded but at least keeps
      //      the API contract; HMAC may not match if the producer's exact
      //      bytes differ from JSON.stringify output.
      let rawBody;
      let body;
      if (Buffer.isBuffer(req.body)) {
        rawBody = req.body;
        try {
          body = rawBody.length ? JSON.parse(rawBody.toString('utf8')) : {};
        } catch (_) {
          return res.status(400).json({ error: 'invalid json' });
        }
      } else if (req.body && typeof req.body === 'object') {
        body = req.body;
        rawBody = Buffer.from(JSON.stringify(body), 'utf8');
        logger.warn(
          'Uzum callback: raw body unavailable (global json parser ran first); HMAC verification is degraded',
        );
      } else {
        return res.status(400).json({ error: 'empty body' });
      }

      const sigHeader = req.get('X-Uzum-Signature') || req.get('x-uzum-signature');
      const signatureValid = uzum.verifySignature(rawBody, sigHeader);
      if (!signatureValid) {
        logger.warn({ transactionId: body && body.transactionId }, 'Uzum sig mismatch');
        return res.status(401).json({ error: 'invalid signature' });
      }

      const externalId = body && body.transactionId ? String(body.transactionId) : null;
      if (!externalId) {
        return res.status(400).json({ error: 'missing transactionId' });
      }

      const stored = await withIdempotency(
        { provider: 'uzum', externalId, payload: body, orderId: body.orderId },
        async () => {
          // Amount guard — body may carry `amount` in raw sum or cents
          // depending on Uzum's contract. We compare in cents and accept
          // either representation conservatively (if value matches either
          // raw sum * 100 or raw cents, allow). When `amount` is absent we
          // skip — the provider is authenticated via HMAC.
          if (body.orderId && body.amount != null) {
            const order = await prisma.order.findUnique({ where: { id: body.orderId } });
            if (!order) {
              return { ok: false, error: 'order_not_found' };
            }
            const expectedCents = Math.round(order.total * 100);
            const reported = Number(body.amount);
            if (!Number.isFinite(reported)) {
              return { ok: false, error: 'invalid_amount' };
            }
            const reportedAsCents = Math.round(reported);
            const reportedAsSum = Math.round(reported * 100);
            if (expectedCents !== reportedAsCents && expectedCents !== reportedAsSum) {
              return { ok: false, error: 'amount_mismatch' };
            }
          }

          const result = await uzum.handleCallback(body, { signatureValid: true });

          if (result && result.ok && body.status === 'paid' && body.orderId) {
            const order = await prisma.order.findUnique({ where: { id: body.orderId } });
            const io = req.app.get('io');
            if (io && order) io.to(`buyer:${order.buyerId}`).emit('payment:success', { orderId: order.id });
            if (order) {
              await audit({
                actorId: order.buyerId,
                action: 'payment.received',
                targetType: 'Order',
                targetId: order.id,
                metadata: { provider: 'uzum', externalId },
              });
              // Phase 13.3.9 — fiscal receipt issuance.
              await enqueueFiscalIssue(order.id);
            }
          }

          return result;
        },
      );

      return res.status(200).json(stored);
    } catch (err) { next(err); }
  },
);

// ─── POST /api/payments/kaspi/callback ───────────────────────────────────────
// Phase 7 — Kazakhstan launch. Kaspi signs raw bytes via HMAC-SHA256
// (X-Kaspi-Signature). The raw-body parser is mounted in index.js
// RAW_PATHS so req.body arrives as a Buffer; the inline express.raw fallback
// here mirrors the uzum route for robustness when this router is mounted in
// isolation (e.g. in tests).
router.post(
  '/kaspi/callback',
  express.raw({ type: '*/*', limit: '256kb' }),
  async (req, res, next) => {
    try {
      const result = await kaspi.callback(req);
      if (!result.ok) {
        if (result.error === 'invalid_signature') {
          return res.status(401).json({ error: 'invalid signature' });
        }
        if (result.error === 'invalid_json' || result.error === 'empty_body') {
          return res.status(400).json({ error: result.error });
        }
        if (result.error === 'missing_transactionId') {
          return res.status(400).json({ error: 'missing transactionId' });
        }
      }

      const externalId = result.externalId;
      if (!externalId) {
        return res.status(200).json(result);
      }

      const stored = await withIdempotency(
        { provider: 'kaspi', externalId, payload: result.body, orderId: result.body && result.body.orderId },
        async () => {
          // Side-effects on a successful "paid" event: socket emit + audit.
          if (result.body && result.body.status === 'paid' && result.body.orderId) {
            const order = await prisma.order.findUnique({ where: { id: result.body.orderId } });
            const io = req.app.get('io');
            if (io && order) io.to(`buyer:${order.buyerId}`).emit('payment:success', { orderId: order.id });
            if (order) {
              await audit({
                actorId: order.buyerId,
                action: 'payment.received',
                targetType: 'Order',
                targetId: order.id,
                metadata: { provider: 'kaspi', externalId },
              });
            }
          }
          return { ok: true, externalId };
        },
      );

      return res.status(200).json(stored);
    } catch (err) { next(err); }
  },
);

module.exports = router;
