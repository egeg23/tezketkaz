// Uzum Pay integration
// Documentation: https://docs.business.uzum.uz/
const USE_MOCK = process.env.USE_MOCK_PAYMENTS === 'true';
const MERCHANT_ID = process.env.UZUM_MERCHANT_ID;

async function createInvoice(order) {
  if (USE_MOCK) {
    const prisma = require('../db');
    setTimeout(async () => {
      await prisma.order.update({
        where: { id: order.id },
        data: { isPaid: true, paymentRef: `mock_uzum_${Date.now()}` },
      });
    }, 2000);
    return `tezketkaz://payment-result?orderId=${order.id}&status=success`;
  }

  // Real Uzum Pay flow — POST to their checkout endpoint, get redirect URL
  // (требует партнёрский API ключ)
  return `https://checkout.uzum.uz/?merchantId=${MERCHANT_ID}&orderId=${order.id}&amount=${order.total}`;
}

async function handleCallback(body) {
  // Uzum шлёт webhook с подписью HMAC-SHA256
  // TODO: проверка подписи когда получите production ключи
  const prisma = require('../db');
  if (body.status === 'paid') {
    await prisma.order.update({
      where: { id: body.orderId },
      data: { isPaid: true, paymentRef: body.transactionId },
    });
  }
  return { ok: true };
}

module.exports = { createInvoice, handleCallback };
