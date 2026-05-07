// Click.uz integration
// Documentation: https://docs.click.uz/click-api-request-shop/
const crypto = require('crypto');

const MERCHANT_ID  = process.env.CLICK_MERCHANT_ID;
const SERVICE_ID   = process.env.CLICK_SERVICE_ID;
const SECRET_KEY   = process.env.CLICK_SECRET_KEY;
const USE_MOCK     = process.env.USE_MOCK_PAYMENTS === 'true';

const CLICK_BASE = 'https://my.click.uz/services/pay';

/**
 * Создать платёжную ссылку для заказа.
 * Возвращает URL, на который нужно перенаправить пользователя.
 */
async function createInvoice(order) {
  if (USE_MOCK) {
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
    service_id: SERVICE_ID,
    merchant_id: MERCHANT_ID,
    amount: order.total.toString(),
    transaction_param: order.id,
    return_url: `https://api.tezketkaz.uz/api/payments/click/return?order=${order.id}`,
  });

  return `${CLICK_BASE}/?${params.toString()}`;
}

/**
 * Проверить callback от Click — он шлёт sign_string, который надо валидировать.
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
  } = body;

  // Click sign formula:
  // md5(click_trans_id + service_id + SECRET_KEY + merchant_trans_id + amount + action + sign_time)
  const expected = crypto
    .createHash('md5')
    .update(`${click_trans_id}${service_id}${SECRET_KEY}${merchant_trans_id}${amount}${action}${sign_time}`)
    .digest('hex');

  if (expected !== sign_string) {
    return { valid: false };
  }

  // action 0 = prepare, 1 = complete
  if (action !== '1') return { valid: true, complete: false };

  const prisma = require('../db');
  const order = await prisma.order.findUnique({ where: { id: merchant_trans_id } });
  if (!order) return { valid: false };

  return {
    valid: true,
    complete: true,
    orderId: order.id,
    buyerId: order.buyerId,
    transactionId: click_paydoc_id,
  };
}

module.exports = { createInvoice, verifyCallback };
