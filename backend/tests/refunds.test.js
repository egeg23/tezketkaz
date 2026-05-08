// Unit tests for the refunds service. Verifies status transitions,
// loyalty reversal, partial vs. full refund accounting, and validation.

const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const refunds = require('../src/services/refunds');
const loyalty = require('../src/services/loyalty');

let ctx;
let prisma;

beforeAll(async () => {
  ctx = await setupTestDb('refunds');
  prisma = ctx.prisma;
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makeDeliveredOrder({ total = 100000, subtotal = 100000 } = {}) {
  const owner = await createUser(prisma, { isShop: true });
  const buyer = await createUser(prisma);
  const shop = await createShopWithOwner(prisma, owner.user);
  const order = await prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'X', customerPhone: '+998999999999',
      shopId: shop.id,
      deliveryAddress: 'addr', paymentMethod: 'cash',
      subtotal, total, status: 'delivered', deliveredAt: new Date(),
    },
  });
  return { buyer, shop, order };
}

describe('refunds.refundOrder', () => {
  test('full refund marks order as refunded and reverses loyalty', async () => {
    const { buyer, order } = await makeDeliveredOrder({ total: 100000 });
    await loyalty.creditOrder(prisma, buyer.user.id, order.id, 100000);
    const accBefore = await prisma.loyaltyAccount.findUnique({ where: { userId: buyer.user.id } });
    expect(accBefore.points).toBe(100);

    const updated = await refunds.refundOrder(prisma, {
      orderId: order.id, amount: 100000, reason: 'damaged',
    });
    expect(updated.status).toBe('refunded');
    expect(updated.refundedAt).not.toBeNull();
    expect(updated.refundedAmount).toBe(100000);
    const accAfter = await prisma.loyaltyAccount.findUnique({ where: { userId: buyer.user.id } });
    expect(accAfter.points).toBe(0);
  });

  test('partial refund accumulates refundedAmount and keeps status', async () => {
    const { order } = await makeDeliveredOrder({ total: 50000 });
    const r1 = await refunds.refundOrder(prisma, { orderId: order.id, amount: 10000, reason: 'late' });
    expect(r1.status).toBe('delivered');
    expect(r1.refundedAmount).toBe(10000);
    const r2 = await refunds.refundOrder(prisma, { orderId: order.id, amount: 15000, reason: 'damaged' });
    expect(r2.status).toBe('delivered');
    expect(r2.refundedAmount).toBe(25000);
  });

  test('refund exceeding total throws 400', async () => {
    const { order } = await makeDeliveredOrder({ total: 30000 });
    await refunds.refundOrder(prisma, { orderId: order.id, amount: 20000, reason: 'r' });
    await expect(
      refunds.refundOrder(prisma, { orderId: order.id, amount: 20000, reason: 'r' }),
    ).rejects.toMatchObject({ status: 400 });
  });

  test('refund on non-refundable status throws 400', async () => {
    const { order } = await makeDeliveredOrder({ total: 30000 });
    await prisma.order.update({ where: { id: order.id }, data: { status: 'pending' } });
    await expect(
      refunds.refundOrder(prisma, { orderId: order.id, amount: 100, reason: 'r' }),
    ).rejects.toMatchObject({ status: 400 });
  });

  test('zero or negative amount throws 400', async () => {
    const { order } = await makeDeliveredOrder({ total: 30000 });
    await expect(
      refunds.refundOrder(prisma, { orderId: order.id, amount: 0, reason: 'r' }),
    ).rejects.toMatchObject({ status: 400 });
    await expect(
      refunds.refundOrder(prisma, { orderId: order.id, amount: -10, reason: 'r' }),
    ).rejects.toMatchObject({ status: 400 });
  });
});
