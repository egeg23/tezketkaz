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
  if (env.useMockPayments) {
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

  // Real Click integration
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

module.exports = { createInvoice, verifyCallback };
