// Unit tests for loyalty service (earn, spend, refund, referral, tier promotion).

const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const loyalty = require('../src/services/loyalty');

let ctx;
let prisma;

beforeAll(async () => {
  ctx = await setupTestDb('loyalty');
  prisma = ctx.prisma;
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makeBuyerWithOrder(overrides = {}) {
  const owner = await createUser(prisma, { isShop: true });
  const buyer = await createUser(prisma);
  const shop = await createShopWithOwner(prisma, owner.user);
  const order = await prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'X', customerPhone: '+998999999999',
      shopId: shop.id,
      deliveryAddress: 'addr',
      paymentMethod: 'cash',
      subtotal: overrides.subtotal ?? 100000,
      total: overrides.total ?? 100000,
      status: overrides.status ?? 'delivered',
    },
  });
  return { buyer, shop, order };
}

describe('loyalty.creditOrder', () => {
  test('credits points proportional to total * tier multiplier (bronze=1.0)', async () => {
    const { buyer, order } = await makeBuyerWithOrder({ total: 50000 });
    const result = await loyalty.creditOrder(prisma, buyer.user.id, order.id, 50000);
    expect(result.pointsAdded).toBe(50); // 50000 / 1000 * 1.0
    const acc = await prisma.loyaltyAccount.findUnique({ where: { userId: buyer.user.id } });
    expect(acc.points).toBe(50);
    expect(acc.lifetimeSpent).toBe(50000);
  });

  test('silver tier multiplies earn by 1.2', async () => {
    const { buyer, order } = await makeBuyerWithOrder({ total: 100000 });
    // Pre-promote to silver.
    await loyalty.getOrCreateAccount(prisma, buyer.user.id);
    await prisma.loyaltyAccount.update({
      where: { userId: buyer.user.id },
      data: { tier: 'silver' },
    });
    const result = await loyalty.creditOrder(prisma, buyer.user.id, order.id, 100000);
    expect(result.pointsAdded).toBe(120); // 100 * 1.2
  });

  test('promotes tier when lifetimeSpent crosses threshold', async () => {
    const { buyer, order } = await makeBuyerWithOrder({ total: 600000 });
    const result = await loyalty.creditOrder(prisma, buyer.user.id, order.id, 600000);
    expect(result.newTier).toBe('silver');
    const acc = await prisma.loyaltyAccount.findUnique({ where: { userId: buyer.user.id } });
    expect(acc.tier).toBe('silver');
  });
});

describe('loyalty.spendPoints', () => {
  test('insufficient balance throws', async () => {
    const { buyer } = await makeBuyerWithOrder();
    await loyalty.getOrCreateAccount(prisma, buyer.user.id);
    await expect(
      loyalty.spendPoints(prisma, buyer.user.id, 100, 'order-x'),
    ).rejects.toThrow();
  });

  test('debits points and returns discount', async () => {
    const { buyer, order } = await makeBuyerWithOrder({ total: 200000 });
    await loyalty.creditOrder(prisma, buyer.user.id, order.id, 200000); // 200 pts
    const result = await loyalty.spendPoints(prisma, buyer.user.id, 50, 'other-order');
    expect(result.discount).toBe(50 * 100); // 5000 UZS
    const acc = await prisma.loyaltyAccount.findUnique({ where: { userId: buyer.user.id } });
    expect(acc.points).toBe(150);
  });
});

describe('loyalty.refundOrder', () => {
  test('reverses earn + spend transactions', async () => {
    const { buyer, order } = await makeBuyerWithOrder({ total: 100000 });
    await loyalty.creditOrder(prisma, buyer.user.id, order.id, 100000); // +100
    await loyalty.spendPoints(prisma, buyer.user.id, 30, order.id); // -30, net = +70

    const result = await loyalty.refundOrder(prisma, buyer.user.id, order.id);
    expect(result.reversed).toBe(-70);
    const acc = await prisma.loyaltyAccount.findUnique({ where: { userId: buyer.user.id } });
    expect(acc.points).toBe(0); // 100 - 30 - 70 = 0
  });
});

describe('loyalty.bonusReferral', () => {
  test('credits 500 to both parties on first delivered order', async () => {
    const referrer = await createUser(prisma);
    const referee = await createUser(prisma);
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.user.update({
      where: { id: referee.user.id },
      data: { referredById: referrer.user.id },
    });
    // Single delivered order for the referee.
    await prisma.order.create({
      data: {
        buyerId: referee.user.id,
        customerName: 'X', customerPhone: '+99800',
        shopId: shop.id,
        deliveryAddress: 'addr',
        paymentMethod: 'cash',
        subtotal: 50000, total: 50000,
        status: 'delivered',
      },
    });

    const result = await loyalty.bonusReferral(prisma, referee.user.id);
    expect(result.credited).toBe(true);
    expect(result.points).toBe(500);
    const accReferee = await prisma.loyaltyAccount.findUnique({ where: { userId: referee.user.id } });
    const accReferrer = await prisma.loyaltyAccount.findUnique({ where: { userId: referrer.user.id } });
    expect(accReferee.points).toBe(500);
    expect(accReferrer.points).toBe(500);
  });

  test('does not credit when no referrer', async () => {
    const lone = await createUser(prisma);
    const result = await loyalty.bonusReferral(prisma, lone.user.id);
    expect(result.credited).toBe(false);
  });

  test('does not double-credit on subsequent calls', async () => {
    const referrer = await createUser(prisma);
    const referee = await createUser(prisma);
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.user.update({
      where: { id: referee.user.id },
      data: { referredById: referrer.user.id },
    });
    await prisma.order.create({
      data: {
        buyerId: referee.user.id,
        customerName: 'X', customerPhone: '+99801',
        shopId: shop.id, deliveryAddress: 'addr', paymentMethod: 'cash',
        subtotal: 1000, total: 1000, status: 'delivered',
      },
    });
    const r1 = await loyalty.bonusReferral(prisma, referee.user.id);
    expect(r1.credited).toBe(true);
    const r2 = await loyalty.bonusReferral(prisma, referee.user.id);
    expect(r2.credited).toBe(false);
  });
});

describe('loyalty.tierForSpend', () => {
  test('thresholds map correctly', () => {
    expect(loyalty.tierForSpend(0)).toBe('bronze');
    expect(loyalty.tierForSpend(499_000)).toBe('bronze');
    expect(loyalty.tierForSpend(500_000)).toBe('silver');
    expect(loyalty.tierForSpend(2_000_000)).toBe('gold');
    expect(loyalty.tierForSpend(10_000_000)).toBe('platinum');
  });
});
