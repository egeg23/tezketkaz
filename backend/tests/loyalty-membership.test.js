// Phase 7.2 — loyalty earn multiplier stacks with active membership.

const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const loyalty = require('../src/services/loyalty');

let ctx;
let prisma;
let owner;
let shop;

beforeAll(async () => {
  ctx = await setupTestDb('loyalty-membership');
  prisma = ctx.prisma;
  owner = await createUser(prisma, { isShop: true });
  shop = await createShopWithOwner(prisma, owner.user);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makeOrder(buyerId, total) {
  return prisma.order.create({
    data: {
      buyerId,
      customerName: 'X',
      customerPhone: '+99812345',
      shopId: shop.id,
      deliveryAddress: 'addr',
      paymentMethod: 'cash',
      subtotal: total,
      total,
      status: 'delivered',
    },
  });
}

async function giveMembership(userId, tier) {
  await prisma.membership.create({
    data: {
      userId,
      tier,
      status: 'active',
      currency: 'UZS',
      periodAmount: tier === 'pro' ? 60000 : 30000,
      billingPeriod: 'monthly',
      currentPeriodEnd: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });
}

describe('loyalty.creditOrder with membership multiplier', () => {
  test('plus membership multiplies earn by 1.5', async () => {
    const buyer = await createUser(prisma);
    await giveMembership(buyer.user.id, 'plus');
    const order = await makeOrder(buyer.user.id, 100000);
    const result = await loyalty.creditOrder(prisma, buyer.user.id, order.id, 100000);
    // bronze tier (1.0) * plus (1.5) → 100 * 1.5 = 150
    expect(result.pointsAdded).toBe(150);
  });

  test('pro membership multiplies earn by 2.0', async () => {
    const buyer = await createUser(prisma);
    await giveMembership(buyer.user.id, 'pro');
    const order = await makeOrder(buyer.user.id, 100000);
    const result = await loyalty.creditOrder(prisma, buyer.user.id, order.id, 100000);
    // bronze (1.0) * pro (2.0) → 100 * 2.0 = 200
    expect(result.pointsAdded).toBe(200);
  });

  test('no membership → unchanged earn', async () => {
    const buyer = await createUser(prisma);
    const order = await makeOrder(buyer.user.id, 100000);
    const result = await loyalty.creditOrder(prisma, buyer.user.id, order.id, 100000);
    expect(result.pointsAdded).toBe(100);
  });

  test('expired membership does NOT multiply', async () => {
    const buyer = await createUser(prisma);
    await prisma.membership.create({
      data: {
        userId: buyer.user.id,
        tier: 'pro',
        status: 'active',
        currency: 'UZS',
        periodAmount: 60000,
        billingPeriod: 'monthly',
        currentPeriodEnd: new Date(Date.now() - 24 * 60 * 60 * 1000),
      },
    });
    const order = await makeOrder(buyer.user.id, 100000);
    const result = await loyalty.creditOrder(prisma, buyer.user.id, order.id, 100000);
    expect(result.pointsAdded).toBe(100);
  });

  test('plus membership stacks with silver tier', async () => {
    const buyer = await createUser(prisma);
    await giveMembership(buyer.user.id, 'plus');
    await loyalty.getOrCreateAccount(prisma, buyer.user.id);
    await prisma.loyaltyAccount.update({
      where: { userId: buyer.user.id },
      data: { tier: 'silver' },
    });
    const order = await makeOrder(buyer.user.id, 100000);
    const result = await loyalty.creditOrder(prisma, buyer.user.id, order.id, 100000);
    // silver (1.2) * plus (1.5) → 100 * 1.8 = 180
    expect(result.pointsAdded).toBe(180);
  });
});
