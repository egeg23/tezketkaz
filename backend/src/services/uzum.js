// Uzum Pay integration
// Documentation: https://docs.business.uzum.uz/
//
// NOTE on auth: Uzum signs webhook bodies with HMAC-SHA256 hex over the raw
// request bytes, sent in the `X-Uzum-Signature` header. We must compute the
// HMAC over the *exact* bytes the provider sent — re-serializing JSON would
// produce a different byte sequence and break verification. The route handler
// is responsible for capturing rawBody.

const crypto = require('crypto');
const env = require('../config/env');
const logger = require('../lib/logger');

async function createInvoice(order) {
  if (env.useMockUzum) {
    const prisma = require('../db');
    setTimeout(async () => {
      await prisma.order.update({
        where: { id: order.id },
        data: { isPaid: true, paymentRef: `mock_uzum_${Date.now()}` },
      });
    }, 2000);
    return `tezketkaz://payment-result?orderId=${order.id}&status=success`;
  }

  // Verify after activation: Uzum's production flow most likely requires a
  // POST to https://api.business.uzum.uz/v1/payment/create with a signed body
  // returning a `redirectUrl`. The bare GET URL below is a fallback used by
  // their legacy checkout — it is known to work for sandbox links but the
  // production contract gives you a dynamic URL per invoice. After receiving
  // merchant credentials, replace this with the POST-and-parse flow per
  // https://docs.business.uzum.uz/. The webhook verification (HMAC-SHA256
  // over raw body) is already production-ready.
  return `https://checkout.uzum.uz/?merchantId=${env.UZUM_MERCHANT_ID}&orderId=${order.id}&amount=${order.total}`;
}

/**
 * Verify HMAC-SHA256 hex signature of the raw webhook body.
 *
 * @param {Buffer|string} rawBody  Raw request bytes (NOT re-serialized JSON).
 * @param {string}        signatureHex  Value of `X-Uzum-Signature`.
 * @returns {boolean}
 *
 * Why timing-safe: signature comparison is the canonical timing-attack target.
 * Why we equalize lengths first: `crypto.timingSafeEqual` throws on length
 * mismatch, which itself can leak timing information; short-circuit instead.
 */
function verifySignature(rawBody, signatureHex) {
  if (!env.UZUM_SECRET_KEY) return false;
  if (!signatureHex || typeof signatureHex !== 'string') return false;
  if (rawBody == null) return false;

  const body = Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(String(rawBody), 'utf8');
  const expectedHex = crypto
    .createHmac('sha256', env.UZUM_SECRET_KEY)
    .update(body)
    .digest('hex');

  if (expectedHex.length !== signatureHex.length) return false;

  const a = Buffer.from(expectedHex, 'utf8');
  const b = Buffer.from(signatureHex, 'utf8');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Handle a verified Uzum webhook.
 *
 * @param {object} body                       Parsed JSON body.
 * @param {{signatureValid: boolean}} ctx     Caller MUST verify the signature
 *                                            first and pass the result here.
 *                                            We refuse to mutate state otherwise.
 */
async function handleCallback(body, { signatureValid } = {}) {
  if (!signatureValid) {
    return { ok: false, error: 'invalid_signature' };
  }

  const prisma = require('../db');
  if (body && body.status === 'paid' && body.orderId) {
    await prisma.order.update({
      where: { id: body.orderId },
      data: { isPaid: true, paymentRef: body.transactionId },
    });
  }
  return { ok: true };
}

/**
 * Stub for future status polling. Real Uzum credentials are not yet
 * provisioned; throw NotImplemented until they are. In mock mode we return a
 * benign placeholder so the surrounding code paths can be exercised.
 */
async function getStatusFromUzum(externalRef) {
  if (env.useMockUzum) {
    return { externalRef, status: 'pending', mock: true };
  }
  const err = new Error('NotImplemented: Uzum status polling pending production keys');
  err.code = 'NOT_IMPLEMENTED';
  logger.warn({ externalRef }, 'Uzum getStatusFromUzum called without keys');
  throw err;
}

module.exports = { createInvoice, handleCallback, verifySignature, getStatusFromUzum };
