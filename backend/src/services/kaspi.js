// Kaspi.kz integration (Kazakhstan).
//
// Kaspi is Kazakhstan's dominant payment app — buyers pay via QR + push to
// their phone. Production uses Kaspi's createInvoice REST API; we mirror the
// click.js mock-mode pattern so dev/test runs without provider credentials.
//
// Webhook auth: HMAC-SHA256 over the raw request body, signature in the
// `X-Kaspi-Signature` header (hex). Mirror uzum.js's verifySignature pattern.
const crypto = require('crypto');
const env = require('../config/env');
const logger = require('../lib/logger');

const KASPI_BASE = 'https://kaspi.kz/api/v1';

/**
 * Initiate a payment for an order. Returns a redirect URL (QR/redirect to the
 * Kaspi app) plus the provider-side externalId we should persist.
 *
 * @param {object} args
 * @param {string} args.orderId
 * @param {number} args.amount        major currency units (KZT)
 * @param {string} [args.currency]    defaults to 'KZT'
 * @param {string} [args.customerPhone]
 * @returns {Promise<{ ok: boolean, redirectUrl: string, externalId: string }>}
 */
async function pay({ orderId, amount, currency = 'KZT', customerPhone } = {}) {
  if (!orderId) {
    throw Object.assign(new Error('orderId required'), { status: 400 });
  }
  if (env.useMockPayments || !env.KASPI_MERCHANT_ID) {
    // Auto-mock-confirm: in mock mode we eagerly mark the order paid so the
    // dev e2e flow advances without a provider round-trip. Mirror click.js.
    // .unref() so the timer doesn't keep the test runner alive.
    const t = setTimeout(async () => {
      try {
        const prisma = require('../db');
        await prisma.order.update({
          where: { id: orderId },
          data: { isPaid: true, paymentRef: `mock_kaspi_${Date.now()}` },
        });
      } catch (err) {
        logger.warn({ err: err.message, orderId }, 'kaspi mock auto-confirm failed');
      }
    }, 2000);
    if (typeof t.unref === 'function') t.unref();
    return {
      ok: true,
      redirectUrl: `mock://kaspi/${orderId}`,
      externalId: `mock_kaspi_${orderId}`,
    };
  }

  // Production wiring would POST to ${KASPI_BASE}/createInvoice with the
  // merchant signature and parse the redirect URL out of the response. The
  // sandbox contract isn't provisioned yet — return a structured failure so
  // callers can surface a meaningful error rather than pretending it succeeded.
  void KASPI_BASE;
  void currency;
  void customerPhone;
  void amount;
  logger.warn({ orderId }, 'Kaspi pay called without sandbox; returning failure');
  return { ok: false, redirectUrl: null, externalId: null, message: 'kaspi_not_configured' };
}

/**
 * Tokenize a card for recurring billing (subscriptions, saved-card orders).
 * Mock mode returns a deterministic fake token so tests can exercise the flow.
 *
 * Returns { provider, redirectUrl, state, mockToken? } in production-shape so
 * routes/payment-methods.js can consume it like click/payme.
 */
async function tokenizeCard(userId) {
  if (!userId) {
    throw Object.assign(new Error('userId required'), { status: 400 });
  }
  const state = `kaspi_state_${userId}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  if (env.useMockPayments || !env.KASPI_MERCHANT_ID) {
    const mockToken = `mock_kaspi_token_${userId}_${Date.now()}`;
    return {
      provider: 'kaspi',
      redirectUrl: `tezketkaz://payment-method-result?provider=kaspi&state=${state}&status=success&token=${mockToken}`,
      state,
      mockToken,
    };
  }
  // Real Kaspi tokenization runs as a hosted page; user enters card on their
  // domain, then Kaspi POSTs the token via the webhook. Pre-stash `state` so
  // we can correlate the eventual webhook back to the originating user.
  return {
    provider: 'kaspi',
    redirectUrl: `${KASPI_BASE}/tokenize?merchant=${env.KASPI_MERCHANT_ID}&state=${state}`,
    state,
  };
}

/**
 * Charge a previously tokenized Kaspi card.
 * Returns { ok, externalId, message } following the click/payme convention.
 */
async function chargeWithToken(token, amount, orderId, currency = 'KZT') {
  if (!token) {
    return { ok: false, externalId: null, message: 'token_required' };
  }
  if (!Number.isFinite(Number(amount)) || Number(amount) <= 0) {
    return { ok: false, externalId: null, message: 'invalid_amount' };
  }
  if (env.useMockPayments || !env.KASPI_MERCHANT_ID) {
    return {
      ok: true,
      externalId: `mock_kaspi_charge_${orderId || 'noorder'}_${Date.now()}`,
      message: 'ok',
    };
  }
  // Real recurring charge: POST to ${KASPI_BASE}/charge with the saved token
  // + merchant signature. Sandbox not yet provisioned at launch.
  void currency;
  return { ok: false, externalId: null, message: 'kaspi_recurring_not_configured' };
}

/**
 * HMAC-SHA256 verification over raw body. Constant-time compare; never throws
 * on length mismatch. Mirrors uzum.verifySignature.
 */
function verifySignature(rawBody, signatureHex) {
  if (!env.KASPI_SECRET) return false;
  if (!signatureHex || typeof signatureHex !== 'string') return false;
  if (rawBody == null) return false;

  const body = Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(String(rawBody), 'utf8');
  const expectedHex = crypto
    .createHmac('sha256', env.KASPI_SECRET)
    .update(body)
    .digest('hex');

  if (expectedHex.length !== signatureHex.length) return false;
  const a = Buffer.from(expectedHex, 'utf8');
  const b = Buffer.from(signatureHex, 'utf8');
  if (a.length !== b.length) return false;
  // Why timing-safe: signature comparison is the canonical timing-attack target.
  return crypto.timingSafeEqual(a, b);
}

/**
 * Webhook entrypoint. Validates signature against the raw body, then marks
 * the order paid on `status === 'paid'`. Idempotency is enforced one layer
 * up via withIdempotency in routes/payments.js (ProcessedWebhook table),
 * matching the click/payme/uzum flow.
 *
 * @param {object} req  Express request — must have raw `body` (Buffer).
 * @returns {Promise<{ ok: boolean, error?: string, body?: object, externalId?: string }>}
 */
async function callback(req) {
  if (!req) return { ok: false, error: 'invalid_request' };

  let rawBody;
  let body;
  if (Buffer.isBuffer(req.body)) {
    rawBody = req.body;
    try {
      body = rawBody.length ? JSON.parse(rawBody.toString('utf8')) : {};
    } catch (_) {
      return { ok: false, error: 'invalid_json' };
    }
  } else if (req.body && typeof req.body === 'object') {
    body = req.body;
    rawBody = Buffer.from(JSON.stringify(body), 'utf8');
    logger.warn(
      'Kaspi callback: raw body unavailable (global json parser ran first); HMAC verification is degraded',
    );
  } else {
    return { ok: false, error: 'empty_body' };
  }

  const sigHeader = (req.get && (req.get('X-Kaspi-Signature') || req.get('x-kaspi-signature')))
    || (req.headers && (req.headers['x-kaspi-signature'] || req.headers['X-Kaspi-Signature']));

  if (!verifySignature(rawBody, sigHeader)) {
    logger.warn({ orderId: body && body.orderId }, 'Kaspi sig mismatch');
    return { ok: false, error: 'invalid_signature' };
  }

  const externalId = body && body.transactionId ? String(body.transactionId) : null;
  if (!externalId) {
    return { ok: false, error: 'missing_transactionId' };
  }

  if (body.status === 'paid' && body.orderId) {
    const prisma = require('../db');
    try {
      await prisma.order.update({
        where: { id: body.orderId },
        data: { isPaid: true, paymentRef: externalId },
      });
    } catch (err) {
      logger.warn({ err: err.message, orderId: body.orderId }, 'kaspi callback: order update failed');
      return { ok: false, error: 'order_update_failed', externalId };
    }
  }

  return { ok: true, body, externalId };
}

module.exports = { pay, tokenizeCard, chargeWithToken, callback, verifySignature };
