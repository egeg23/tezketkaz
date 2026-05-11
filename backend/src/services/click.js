// Click.uz integration
// Documentation: https://docs.click.uz/click-api-request-shop/
const crypto = require('crypto');
const env = require('../config/env');
const logger = require('../lib/logger');

const CLICK_BASE = 'https://my.click.uz/services/pay';

/**
 * Создать платёжную ссылку для заказа.
 * Возвращает URL, на который нужно перенаправить пользователя.
 */
async function createInvoice(order) {
  if (env.useMockClick) {
    // В mock-режиме сразу помечаем как оплачено и возвращаем deep link обратно в app
    const prisma = require('../db');
    setTimeout(async () => {
      await prisma.order.update({
        where: { id: order.id },
        data: { isPaid: true, paymentRef: `mock_click_${Date.now()}` },
      });
    }, 2000);
    return `tezketkaz://payment-result?orderId=${order.id}&status=success`;
  }

  // Real Click integration — hosted "services/pay" redirect, no server-side
  // signature needed; the merchant_id + service_id pair is the auth, and the
  // back-channel POST to /click/callback carries the signed result.
  // Verify after activation: Click expects `amount` as decimal sum (e.g.
  // "120000.00"), not cents. order.total is stored in major units; we send
  // it raw. If your Click merchant dashboard says "amount in tiyin", you will
  // need to multiply by 100 here.
  const params = new URLSearchParams({
    service_id: env.CLICK_SERVICE_ID,
    merchant_id: env.CLICK_MERCHANT_ID,
    amount: order.total.toString(),
    transaction_param: order.id,
    return_url: `https://api.tezketkaz.uz/api/payments/click/return?order=${order.id}`,
  });

  return `${CLICK_BASE}/?${params.toString()}`;
}

/**
 * Constant-time hex string compare. Buffers must already be hex-encoded
 * strings; we decode them and compare byte-by-byte. Length mismatch ⇒ false
 * without invoking timingSafeEqual (which throws on length mismatch).
 *
 * Why timing-safe: signature comparison is the canonical timing-attack target.
 */
function safeEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  const bufA = Buffer.from(a, 'hex');
  const bufB = Buffer.from(b, 'hex');
  if (bufA.length === 0 || bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

/**
 * Проверить callback от Click — он шлёт sign_string, который надо валидировать.
 *
 * Click sign formula (MD5 — required by their API; we cannot upgrade):
 *   md5(click_trans_id + service_id + SECRET_KEY + merchant_trans_id + amount + action + sign_time)
 *
 * Returns:
 *   { valid: false }                                            — bad request / bad signature
 *   { valid: true, complete: false }                            — prepare phase (action=0)
 *   { valid: true, complete: true, orderId, buyerId, transactionId, amount }  — completion (action=1)
 */
async function verifyCallback(body) {
  const {
    click_trans_id,
    service_id,
    click_paydoc_id,
    merchant_trans_id,
    amount,
    action,
    sign_time,
    sign_string,
  } = body || {};

  // Reject early if any required field is missing — never trust the body shape.
  if (
    click_trans_id == null ||
    service_id == null ||
    sign_string == null ||
    sign_time == null
  ) {
    return { valid: false };
  }

  // Optional binding to our service_id to fend off cross-service replay.
  // Only enforced in prod when CLICK_SERVICE_ID is configured.
  if (env.isProd && env.CLICK_SERVICE_ID && String(service_id) !== String(env.CLICK_SERVICE_ID)) {
    logger.warn({ click_trans_id, service_id }, 'Click sig mismatch');
    return { valid: false };
  }

  if (!env.CLICK_SECRET_KEY) {
    // Without a secret we cannot verify; refuse rather than accept blindly.
    logger.warn({ click_trans_id }, 'Click sig mismatch');
    return { valid: false };
  }

  const expected = crypto
    .createHash('md5')
    .update(
      `${click_trans_id}${service_id}${env.CLICK_SECRET_KEY}${merchant_trans_id}${amount}${action}${sign_time}`,
    )
    .digest('hex');

  if (!safeEqualHex(expected, String(sign_string))) {
    logger.warn({ click_trans_id, service_id }, 'Click sig mismatch');
    return { valid: false };
  }

  // action 0 = prepare, 1 = complete
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

/**
 * Phase 6.1 — saved payment methods.
 *
 * Initiate Click card tokenization. In production this redirects the user to
 * Click's hosted "Save Card" page; on success Click returns a token via the
 * existing webhook (event_type=tokenize) which the confirm endpoint persists.
 *
 * In dev/test mode (no CLICK_MERCHANT_ID / mock payments enabled) we return a
 * deterministic mock token so tests can exercise the full flow without a
 * provider round-trip.
 *
 * Returns { provider, redirectUrl, state, mockToken? }.
 *   - state is an opaque string the client echoes back on /confirm; it lets
 *     us bind the eventual webhook to the user that started the flow.
 *   - mockToken is only set in mock mode (so tests can pass it to /confirm).
 */
async function tokenizeCard(userId) {
  if (!userId) {
    throw Object.assign(new Error('userId required'), { status: 400 });
  }
  const state = `click_state_${userId}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  if (env.useMockClick || !env.CLICK_MERCHANT_ID) {
    const mockToken = `mock_click_${userId}_${Date.now()}`;
    return {
      provider: 'click',
      redirectUrl: `tezketkaz://payment-method-result?provider=click&state=${state}&status=success&token=${mockToken}`,
      state,
      mockToken,
    };
  }

  // Production hosted flow. Click's card-token endpoint takes service_id +
  // merchant_id + return_url; user enters card on their page, then Click
  // POSTs the resulting token to our webhook. We pre-stash `state` so the
  // webhook can map back to the originating user.
  const params = new URLSearchParams({
    service_id: env.CLICK_SERVICE_ID || '',
    merchant_id: env.CLICK_MERCHANT_ID,
    transaction_param: state,
    return_url: `https://api.tezketkaz.uz/api/payment-methods/click/confirm?state=${state}`,
  });
  return {
    provider: 'click',
    redirectUrl: `${CLICK_BASE}/card_token?${params.toString()}`,
    state,
  };
}

/**
 * Charge a previously tokenized card. Used for orders with paymentMethodId
 * (no browser redirect) and for tipping.
 *
 * Returns { ok, externalId, message }.
 *   - ok=true:  externalId is the provider-side transaction id we should
 *               persist as paymentRef.
 *   - ok=false: message explains the failure (insufficient_funds, etc.).
 *
 * In mock mode we always succeed and return a fake transaction id, so test
 * flows are deterministic.
 */
async function chargeWithToken(token, amount, orderId, currency = 'UZS') {
  if (!token) {
    return { ok: false, externalId: null, message: 'token_required' };
  }
  if (!Number.isFinite(Number(amount)) || Number(amount) <= 0) {
    return { ok: false, externalId: null, message: 'invalid_amount' };
  }
  if (env.useMockClick || !env.CLICK_MERCHANT_ID) {
    // Deterministic fake — surfaces enough info for tests + audit logs.
    return {
      ok: true,
      externalId: `mock_click_charge_${orderId || 'noorder'}_${Date.now()}`,
      message: 'ok',
    };
  }

  // Real Click recurring-charge endpoint. Currently we don't have a sandbox
  // contract so we conservatively return a NotImplemented error rather than
  // pretending it succeeded. Production wiring lands when Click provisions
  // the merchant account.
  logger.warn(
    { orderId, currency },
    'Click chargeWithToken called without sandbox; returning failure',
  );
  return { ok: false, externalId: null, message: 'click_recurring_not_configured' };
}

module.exports = { createInvoice, verifyCallback, tokenizeCard, chargeWithToken };
