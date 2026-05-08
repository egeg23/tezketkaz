// Unit tests for disputes service. Covers buyer-only enforcement, the
// configurable dispute window, refund vs. reject resolution paths.

const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const disputesSvc = require('../src/services/disputes');

let ctx;
let prisma;

beforeAll(async () => {
  ctx = await setupTestDb('disputes');
  prisma = ctx.prisma;
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makeOrder({ status = 'delivered', deliveredAt = new Date(), total = 100000 } = {}) {
  const owner = await createUser(prisma, { isShop: true });
  const buyer = await createUser(prisma);
  const other = await createUser(prisma);
  const shop = await createShopWithOwner(prisma, owner.user);
  const order = await prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'X', customerPhone: '+99800',
      shopId: shop.id,
      deliveryAddress: 'addr', paymentMethod: 'cash',
      subtotal: total, total, status, deliveredAt,
    },
  });
  return { buyer, other, shop, order };
}

describe('disputes.openDispute', () => {
  test('buyer can open dispute on delivered order', async () => {
    const { buyer, order } = await makeOrder();
    const dispute = await disputesSvc.openDispute(prisma, {
      orderId: order.id, openedById: buyer.user.id,
      reason: 'damaged', description: 'box smashed',
    });
    expect(dispute.status).toBe('open');
    expect(dispute.reason).toBe('damaged');
    expect(dispute.orderId).toBe(order.id);
  });

  test('non-buyer cannot open dispute', async () => {
    const { other, order } = await makeOrder();
    await expect(
      disputesSvc.openDispute(prisma, {
        orderId: order.id, openedById: other.user.id, reason: 'damaged',
      }),
    ).rejects.toMatchObject({ status: 403 });
  });

  test('disallowed reason throws 400', async () => {
    const { buyer, order } = await makeOrder();
    await expect(
      disputesSvc.openDispute(prisma, {
        orderId: order.id, openedById: buyer.user.id, reason: 'bogus',
      }),
    ).rejects.toMatchObject({ status: 400 });
  });

  test('outside dispute window throws 400', async () => {
    const longAgo = new Date(Date.now() - 100 * 60 * 60 * 1000); // 100 hours ago
    const { buyer, order } = await makeOrder({ deliveredAt: longAgo });
    await expect(
      disputesSvc.openDispute(prisma, {
        orderId: order.id, openedById: buyer.user.id, reason: 'damaged',
      }),
    ).rejects.toMatchObject({ status: 400 });
  });

  test('non-disputable status throws 400', async () => {
    const { buyer, order } = await makeOrder({ status: 'pending' });
    await expect(
      disputesSvc.openDispute(prisma, {
        orderId: order.id, openedById: buyer.user.id, reason: 'damaged',
      }),
    ).rejects.toMatchObject({ status: 400 });
  });

  test('cannot open second dispute on same order', async () => {
    const { buyer, order } = await makeOrder();
    await disputesSvc.openDispute(prisma, {
      orderId: order.id, openedById: buyer.user.id, reason: 'damaged',
    });
    await expect(
      disputesSvc.openDispute(prisma, {
        orderId: order.id, openedById: buyer.user.id, reason: 'late',
      }),
    ).rejects.toMatchObject({ status: 409 });
  });
});

describe('disputes.resolveDispute', () => {
  test('resolution=refund triggers full refund and marks resolved', async () => {
    const { buyer, order } = await makeOrder({ total: 80000 });
    const d = await disputesSvc.openDispute(prisma, {
      orderId: order.id, openedById: buyer.user.id, reason: 'damaged',
    });
    const updated = await disputesSvc.resolveDispute(prisma, {
      disputeId: d.id, actorId: 'admin-1', resolution: 'refund',
    });
    expect(updated.status).toBe('resolved');
    expect(updated.resolution).toBe('refund');
    expect(updated.refundAmount).toBe(80000);
    const refreshed = await prisma.order.findUnique({ where: { id: order.id } });
    expect(refreshed.status).toBe('refunded');
    expect(refreshed.refundedAmount).toBe(80000);
  });

  test('resolution=partial_refund honors refundAmount', async () => {
    const { buyer, order } = await makeOrder({ total: 100000 });
    const d = await disputesSvc.openDispute(prisma, {
      orderId: order.id, openedById: buyer.user.id, reason: 'missing_items',
    });
    const updated = await disputesSvc.resolveDispute(prisma, {
      disputeId: d.id, actorId: 'admin-1',
      resolution: 'partial_refund', refundAmount: 25000,
    });
    expect(updated.refundAmount).toBe(25000);
    const refreshed = await prisma.order.findUnique({ where: { id: order.id } });
    expect(refreshed.refundedAmount).toBe(25000);
    expect(refreshed.status).toBe('delivered');
  });

  test('resolution=rejected creates no refund and marks rejected', async () => {
    const { buyer, order } = await makeOrder({ total: 60000 });
    const d = await disputesSvc.openDispute(prisma, {
      orderId: order.id, openedById: buyer.user.id, reason: 'late',
    });
    const updated = await disputesSvc.resolveDispute(prisma, {
      disputeId: d.id, actorId: 'admin-1', resolution: 'rejected', note: 'within SLA',
    });
    expect(updated.status).toBe('rejected');
    expect(updated.refundAmount).toBe(0);
    const refreshed = await prisma.order.findUnique({ where: { id: order.id } });
    expect(refreshed.refundedAmount).toBe(0);
    expect(refreshed.status).toBe('delivered');
  });

  test('cannot resolve same dispute twice', async () => {
    const { buyer, order } = await makeOrder({ total: 60000 });
    const d = await disputesSvc.openDispute(prisma, {
      orderId: order.id, openedById: buyer.user.id, reason: 'late',
    });
    await disputesSvc.resolveDispute(prisma, {
      disputeId: d.id, actorId: 'admin-1', resolution: 'rejected',
    });
    await expect(
      disputesSvc.resolveDispute(prisma, {
        disputeId: d.id, actorId: 'admin-1', resolution: 'no_action',
      }),
    ).rejects.toMatchObject({ status: 400 });
  });
});
