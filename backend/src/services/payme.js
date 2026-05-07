// Payme integration
// Documentation: https://developer.help.paycom.uz/
const MERCHANT_ID = process.env.PAYME_MERCHANT_ID;
const KEY         = process.env.PAYME_KEY;
const USE_MOCK    = process.env.USE_MOCK_PAYMENTS === 'true';

const PAYME_CHECKOUT = 'https://checkout.paycom.uz';

/**
 * Создать платёжную ссылку через Base64-параметры (формат Payme).
 */
async function createInvoice(order) {
  if (USE_MOCK) {
    const prisma = require('../db');
    setTimeout(async () => {
      await prisma.order.update({
        where: { id: order.id },
        data: { isPaid: true, paymentRef: `mock_payme_${Date.now()}` },
      });
    }, 2000);
    return `tezketkaz://payment-result?orderId=${order.id}&status=success`;
  }

  // Payme принимает параметры в Base64
  const params = `m=${MERCHANT_ID};ac.order_id=${order.id};a=${Math.round(order.total * 100)}`;
  const encoded = Buffer.from(params).toString('base64');
  return `${PAYME_CHECKOUT}/${encoded}`;
}

/**
 * Обработать JSON-RPC callback от Payme.
 * Payme использует Merchant API: CheckPerformTransaction, CreateTransaction,
 * PerformTransaction, CancelTransaction, CheckTransaction, GetStatement.
 */
async function handleCallback(body) {
  const { method, params, id } = body;
  const prisma = require('../db');

  switch (method) {
    case 'CheckPerformTransaction': {
      const order = await prisma.order.findUnique({ where: { id: params.account.order_id } });
      if (!order) return errResp(id, -31050, 'Order not found');
      if (order.isPaid) return errResp(id, -31051, 'Already paid');
      if (Math.round(order.total * 100) !== params.amount) return errResp(id, -31001, 'Wrong amount');
      return { id, result: { allow: true } };
    }

    case 'CreateTransaction': {
      const order = await prisma.order.findUnique({ where: { id: params.account.order_id } });
      if (!order) return errResp(id, -31050, 'Order not found');
      // Сохраняем transaction id
      await prisma.order.update({
        where: { id: order.id },
        data: { paymentRef: params.id },
      });
      return { id, result: { create_time: Date.now(), transaction: params.id, state: 1 } };
    }

    case 'PerformTransaction': {
      const order = await prisma.order.findFirst({ where: { paymentRef: params.id } });
      if (!order) return errResp(id, -31003, 'Transaction not found');
      await prisma.order.update({
        where: { id: order.id },
        data: { isPaid: true },
      });
      return { id, result: { transaction: params.id, perform_time: Date.now(), state: 2 } };
    }

    case 'CancelTransaction': {
      const order = await prisma.order.findFirst({ where: { paymentRef: params.id } });
      if (!order) return errResp(id, -31003, 'Transaction not found');
      return { id, result: { transaction: params.id, cancel_time: Date.now(), state: -1 } };
    }

    case 'CheckTransaction': {
      const order = await prisma.order.findFirst({ where: { paymentRef: params.id } });
      if (!order) return errResp(id, -31003, 'Transaction not found');
      return {
        id,
        result: {
          transaction: params.id,
          state: order.isPaid ? 2 : 1,
          create_time: order.createdAt.getTime(),
          perform_time: order.isPaid ? (order.acceptedAt?.getTime() || 0) : 0,
        },
      };
    }

    default:
      return errResp(id, -32601, 'Method not found');
  }
}

function errResp(id, code, message) {
  return { id, error: { code, message } };
}

module.exports = { createInvoice, handleCallback };
