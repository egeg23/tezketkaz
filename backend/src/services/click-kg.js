// Click KG integration (Kyrgyzstan).
//
// Variation of services/click.js — same surface, different API base + KGS
// currency, and reads CLICK_KG_* env vars instead of CLICK_*. Mock-mode covers
// dev/test the same way; production wiring lands when Click KG provisions
// merchant credentials.
const crypto = require('crypto');
const env = require('../config/env');
const logger = require('../lib/logger');

const CLICK_KG_BASE = 'https://my.click.kg/services/pay';

/**
 * Initiate a payment for an order.
 * Returns the redirect URL and the externalId we should persist.
 */
async function pay({ orderId, amount, currency = 'KGS' } = {}) {
  if (!orderId) {
    throw Object.assign(new Error('orderId required'), { status: 400 });
  }
  if (env.useMockPayments || !env.CLICK_KG_MERCHANT_ID) {
    // .unref() so the timer doesn't keep the test runner alive.
    const t = setTimeout(async () => {
      try {
        const prisma = require('../db');
        await prisma.order.update({
          where: { id: orderId },
          data: { isPaid: true, paymentRef: `mock_click_kg_${Date.now()}` },
        });
      } catch (err) {
        logger.warn({ err: err.message, orderId }, 'click-kg mock auto-confirm failed');
      }
    }, 2000);
    if (typeof t.unref === 'function') t.unref();
    return {
      ok: true,
      redirectUrl: `mock://click_kg/${orderId}`,
      externalId: `mock_click_kg_${orderId}`,
    };
  }

  // Production — same shape as click.uz `services/pay` redirect.
  const params = new URLSearchParams({
    service_id: env.CLICK_KG_SERVICE_ID || '',
    merchant_id: env.CLICK_KG_MERCHANT_ID,
    amount: String(amount || 0),
    transaction_param: orderId,
    return_url: `https://api.tezketkaz.uz/api/payments/click-kg/return?order=${orderId}`,
  });
  void currency;
  return {
    ok: true,
    redirectUrl: `${CLICK_KG_BASE}/?${params.toString()}`,
    externalId: null,
  };
}

/**
 * Tokenize a card. Mock mode returns a deterministic fake token.
 */
async function tokenizeCard(userId) {
  if (!userId) {
    throw Object.assign(new Error('userId required'), { status: 400 });
  }
  const state = `click_kg_state_${userId}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  if (env.useMockPayments || !env.CLICK_KG_MERCHANT_ID) {
    const mockToken = `mock_click_kg_${userId}_${Date.now()}`;
    return {
      provider: 'click_kg',
      redirectUrl: `tezketkaz://payment-method-result?provider=click_kg&state=${state}&status=success&token=${mockToken}`,
      state,
      mockToken,
    };
  }
  const params = new URLSearchParams({
    service_id: env.CLICK_KG_SERVICE_ID || '',
    merchant_id: env.CLICK_KG_MERCHANT_ID,
    transaction_param: state,
    return_url: `https://api.tezketkaz.uz/api/payment-methods/click-kg/confirm?state=${state}`,
  });
  return {
    provider: 'click_kg',
    redirectUrl: `${CLICK_KG_BASE}/card_token?${params.toString()}`,
    state,
  };
}

/**
 * Charge a previously tokenized card.
 * Returns { ok, externalId, message }.
 */
async function chargeWithToken(token, amount, orderId, currency = 'KGS') {
  if (!token) {
    return { ok: false, externalId: null, message: 'token_required' };
  }
  if (!Number.isFinite(Number(amount)) || Number(amount) <= 0) {
    return { ok: false, externalId: null, message: 'invalid_amount' };
  }
  if (env.useMockPayments || !env.CLICK_KG_MERCHANT_ID) {
    return {
      ok: true,
      externalId: `mock_click_kg_charge_${orderId || 'noorder'}_${Date.now()}`,
      message: 'ok',
    };
  }
  void currency;
  logger.warn({ orderId }, 'click-kg chargeWithToken called without sandbox; returning failure');
  return { ok: false, externalId: null, message: 'click_kg_recurring_not_configured' };
}

/**
 * Webhook callback. Click KG uses the same MD5 sign formula as Click UZ;
 * we accept the same body shape and verify against CLICK_KG_SECRET_KEY.
 *
 * Returns { valid: bool, complete?: bool, orderId?, transactionId?, amount? }.
 */
async function callback(body) {
  if (!body || typeof body !== 'object') return { valid: false };
  const {
    click_trans_id,
    service_id,
    click_paydoc_id,
    merchant_trans_id,
    amount,
    action,
    sign_time,
    sign_string,
  } = body;

  if (
    click_trans_id == null
    || service_id == null
    || sign_string == null
    || sign_time == null
  ) {
    return { valid: false };
  }
  if (!env.CLICK_KG_SECRET_KEY) {
    logger.warn({ click_trans_id }, 'Click KG sig mismatch (no secret)');
    return { valid: false };
  }

  const expected = crypto
    .createHash('md5')
    .update(
      `${click_trans_id}${service_id}${env.CLICK_KG_SECRET_KEY}${merchant_trans_id}${amount}${action}${sign_time}`,
    )
    .digest('hex');

  // Constant-time compare on hex strings.
  const a = Buffer.from(expected, 'hex');
  const b = Buffer.from(String(sign_string), 'hex');
  if (a.length === 0 || a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    logger.warn({ click_trans_id }, 'Click KG sig mismatch');
    return { valid: false };
  }

  if (String(action) !== '1') return { valid: true, complete: false };

  const prisma = require('../db');
  const order = await prisma.order.findUnique({ where: { id: merchant_trans_id } });
  if (!order) return { valid: false };

  return {
    valid: true,
    complete: true,
    orderId: order.id,
    buyerId: order.buyerId,
    transactionId: click_paydoc_id,
    amount,
  };
}

module.exports = { pay, tokenizeCard, chargeWithToken, callback };
