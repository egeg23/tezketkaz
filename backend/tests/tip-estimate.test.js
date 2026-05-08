// Phase 8.2 — tipEstimate service unit tests.
//
// Three branches:
//   1. Buyer with 3+ tip-paid orders → mean of last 5.
//   2. Buyer below threshold + shop history → shop avg * confidence cap.
//   3. Otherwise → 0.

const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner,
} = require('./helpers/db');
const tipEstimate = require('../src/services/tipEstimate');

let ctx;
let prisma;
let owner;
let shop;
let courier;

beforeAll(async () => {
  ctx = await setupTestDb('tip-estimate');
  prisma = ctx.prisma;
  owner = await createUser(prisma, { isShop: true });
  shop = await createShopWithOwner(prisma, owner.user);
  courier = await createUser(prisma, { isCourier: true, courierStatus: 'approved' });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makeOrder({
  buyerId, shopId = shop.id, total = 100000, courierReward = 12000,
  status = 'delivered', tipAmount = 0, tipPaidAt = null, deliveredAt = new Date(),
}) {
  return prisma.order.create({
    data: {
      buyerId,
      customerName: 'X', customerPhone: '+99800',
      shopId,
      courierId: courier.user.id,
      deliveryAddress: 'addr', paymentMethod: 'cash',
      subtotal: total, total, courierReward,
      status,
      deliveredAt,
      tipAmount,
      tipPaidAt,
    },
  });
}

describe('tipEstimate.estimateForOrder', () => {
  test('uses buyer mean when buyer has >= 3 tip-paid orders', async () => {
    const buyer = await createUser(prisma);
    // 4 historical tip-paid orders for this buyer (different shop is fine).
    const tips = [3000, 5000, 7000, 9000];
    let i = 0;
    for (const t of tips) {
      i += 1;
      await makeOrder({
        buyerId: buyer.user.id,
        tipAmount: t,
        tipPaidAt: new Date(Date.now() - i * 60_000),
      });
    }
    // Current order to estimate against.
    const current = await makeOrder({ buyerId: buyer.user.id, status: 'pending' });
    const est = await tipEstimate.estimateForOrder(prisma, current.id);
    // Mean of 4 tips (since <5) → (3+5+7+9)/4 = 6000.
    expect(est).toBe(6000);
  });

  test('only considers last 5 buyer orders', async () => {
    const buyer = await createUser(prisma);
    // 6 tip-paid orders. Oldest first; last 5 should be {2,3,4,5,6}*1000 → mean 4000.
    for (let n = 1; n <= 6; n += 1) {
      await makeOrder({
        buyerId: buyer.user.id,
        tipAmount: n * 1000,
        tipPaidAt: new Date(2025, 0, n, 12, 0, 0), // increasing timestamps
      });
    }
    const current = await makeOrder({ buyerId: buyer.user.id, status: 'pending' });
    const est = await tipEstimate.estimateForOrder(prisma, current.id);
    expect(est).toBe(4000);
  });

  test('falls back to shop avg * 0.5 when buyer has < 3 tipped orders', async () => {
    const otherOwner = await createUser(prisma, { isShop: true });
    const otherShop = await createShopWithOwner(prisma, otherOwner.user);

    // Two random buyers contribute 4 delivered orders to the shop. Tips:
    // 10000, 0, 8000, 0 → avg = 4500 → confidence cap 0.5 → 2250 → round to 2300.
    const b1 = await createUser(prisma);
    const b2 = await createUser(prisma);
    await makeOrder({
      buyerId: b1.user.id, shopId: otherShop.id,
      tipAmount: 10000, tipPaidAt: new Date(),
    });
    await makeOrder({ buyerId: b1.user.id, shopId: otherShop.id });
    await makeOrder({
      buyerId: b2.user.id, shopId: otherShop.id,
      tipAmount: 8000, tipPaidAt: new Date(),
    });
    await makeOrder({ buyerId: b2.user.id, shopId: otherShop.id });

    // New buyer with 1 tip — under threshold, falls back to shop heuristic.
    const newBuyer = await createUser(prisma);
    await makeOrder({
      buyerId: newBuyer.user.id, shopId: otherShop.id,
      tipAmount: 1000, tipPaidAt: new Date(),
    });

    const current = await makeOrder({
      buyerId: newBuyer.user.id, shopId: otherShop.id, status: 'pending',
    });
    const est = await tipEstimate.estimateForOrder(prisma, current.id);
    // (10000 + 0 + 8000 + 0 + 1000) / 5 = 3800 * 0.5 = 1900.
    expect(est).toBe(1900);
  });

  test('returns 0 when no buyer history and no shop history', async () => {
    const lonelyOwner = await createUser(prisma, { isShop: true });
    const lonelyShop = await createShopWithOwner(prisma, lonelyOwner.user);
    const buyer = await createUser(prisma);
    const current = await makeOrder({
      buyerId: buyer.user.id, shopId: lonelyShop.id, status: 'pending',
    });
    const est = await tipEstimate.estimateForOrder(prisma, current.id);
    expect(est).toBe(0);
  });

  test('returns 0 when shop history exists but no tips at all', async () => {
    const dryOwner = await createUser(prisma, { isShop: true });
    const dryShop = await createShopWithOwner(prisma, dryOwner.user);
    const b1 = await createUser(prisma);
    for (let n = 0; n < 3; n += 1) {
      await makeOrder({ buyerId: b1.user.id, shopId: dryShop.id });
    }
    const buyer = await createUser(prisma);
    const current = await makeOrder({
      buyerId: buyer.user.id, shopId: dryShop.id, status: 'pending',
    });
    const est = await tipEstimate.estimateForOrder(prisma, current.id);
    expect(est).toBe(0);
  });
});

describe('tipEstimate.estimateForBatch', () => {
  test('averages estimates across member orders', async () => {
    const buyer = await createUser(prisma);
    // Make this buyer have predictable per-order estimate of 5000 by giving
    // them 3 tip-paid orders all at 5000.
    for (let n = 0; n < 3; n += 1) {
      await makeOrder({
        buyerId: buyer.user.id, tipAmount: 5000, tipPaidAt: new Date(Date.now() - n * 1000),
      });
    }
    const o1 = await makeOrder({ buyerId: buyer.user.id, status: 'pending' });
    const o2 = await makeOrder({ buyerId: buyer.user.id, status: 'pending' });
    const est = await tipEstimate.estimateForBatch(prisma, [o1.id, o2.id]);
    expect(est).toBe(5000);
  });

  test('returns 0 for empty list', async () => {
    expect(await tipEstimate.estimateForBatch(prisma, [])).toBe(0);
  });
});
