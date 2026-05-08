// Unit tests for coupon validation + discount math.

const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const { validateCoupon, computeDiscount } = require('../src/services/coupons');

let ctx;
let prisma;
let buyer;
let shop;

beforeAll(async () => {
  ctx = await setupTestDb('coupons');
  prisma = ctx.prisma;
  const owner = await createUser(prisma, { isShop: true });
  buyer = await createUser(prisma);
  shop = await createShopWithOwner(prisma, owner.user);
}, 30000);

afterAll(async () => {
  await teardownTestDb(ctx);
});

async function makeCoupon(overrides = {}) {
  const now = new Date();
  return prisma.coupon.create({
    data: {
      code: overrides.code || `C${Math.random().toString(36).slice(2, 8).toUpperCase()}`,
      type: 'PERCENT',
      value: 10,
      validFrom: overrides.validFrom || new Date(now.getTime() - 60_000),
      validUntil: overrides.validUntil || new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000),
      isActive: overrides.isActive !== false,
      ...overrides,
    },
  });
}

describe('computeDiscount', () => {
  test('PERCENT applies value/100 of subtotal, capped by maxDiscount', () => {
    const c = { type: 'PERCENT', value: 20, maxDiscount: 5000 };
    expect(computeDiscount(c, { subtotal: 100000, deliveryFee: 12000 })).toBe(5000);
    const c2 = { type: 'PERCENT', value: 20, maxDiscount: null };
    expect(computeDiscount(c2, { subtotal: 100000 })).toBe(20000);
  });

  test('FIXED is min(value, subtotal)', () => {
    const c = { type: 'FIXED', value: 7000 };
    expect(computeDiscount(c, { subtotal: 5000 })).toBe(5000);
    expect(computeDiscount(c, { subtotal: 50000 })).toBe(7000);
  });

  test('FREE_DELIVERY equals deliveryFee', () => {
    const c = { type: 'FREE_DELIVERY', value: 0 };
    expect(computeDiscount(c, { subtotal: 50000, deliveryFee: 12000 })).toBe(12000);
  });
});

describe('validateCoupon', () => {
  test('PERCENT with maxDiscount cap returns capped discount', async () => {
    const c = await makeCoupon({ type: 'PERCENT', value: 50, maxDiscount: 8000 });
    const r = await validateCoupon(prisma, {
      code: c.code, userId: buyer.user.id, subtotal: 100000,
    });
    expect(r.valid).toBe(true);
    expect(r.discount).toBe(8000);
  });

  test('expired coupon → reason expired', async () => {
    const past = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const earlier = new Date(Date.now() - 48 * 60 * 60 * 1000);
    const c = await makeCoupon({ validFrom: earlier, validUntil: past });
    const r = await validateCoupon(prisma, { code: c.code, userId: buyer.user.id, subtotal: 50000 });
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('expired');
  });

  test('not-yet-active coupon → reason not_started', async () => {
    const future = new Date(Date.now() + 24 * 60 * 60 * 1000);
    const later = new Date(Date.now() + 48 * 60 * 60 * 1000);
    const c = await makeCoupon({ validFrom: future, validUntil: later });
    const r = await validateCoupon(prisma, { code: c.code, userId: buyer.user.id, subtotal: 50000 });
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('not_started');
  });

  test('usagePerUser limit returns user_limit', async () => {
    const c = await makeCoupon({ usagePerUser: 1 });
    // Insert a fake redemption for this user.
    await prisma.couponRedemption.create({
      data: { couponCode: c.code, userId: buyer.user.id, orderId: 'order-fake-1', discount: 1000 },
    });
    const r = await validateCoupon(prisma, { code: c.code, userId: buyer.user.id, subtotal: 50000 });
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('user_limit');
  });

  test('usageLimit reached returns usage_limit', async () => {
    const c = await makeCoupon({ usageLimit: 5 });
    await prisma.coupon.update({ where: { code: c.code }, data: { usedCount: 5 } });
    const r = await validateCoupon(prisma, { code: c.code, userId: buyer.user.id, subtotal: 50000 });
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('usage_limit');
  });

  test('firstOrderOnly + user has prior orders → first_order_only', async () => {
    const c = await makeCoupon({ firstOrderOnly: true });
    // Create one prior delivered order for the user.
    await prisma.order.create({
      data: {
        buyerId: buyer.user.id,
        customerName: 'X', customerPhone: '+998999999999',
        shopId: shop.id,
        deliveryAddress: 'addr',
        paymentMethod: 'cash',
        subtotal: 10000, total: 22000,
        status: 'delivered',
      },
    });
    const r = await validateCoupon(prisma, { code: c.code, userId: buyer.user.id, subtotal: 50000 });
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('first_order_only');
  });

  test('wrong vertical → wrong_vertical', async () => {
    const c = await makeCoupon({ vertical: 'restaurant' });
    const otherUser = await createUser(prisma);
    const r = await validateCoupon(prisma, {
      code: c.code, userId: otherUser.user.id, vertical: 'grocery', shopId: shop.id, subtotal: 50000,
    });
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('wrong_vertical');
  });

  test('wrong shop → wrong_shop', async () => {
    const c = await makeCoupon({ shopId: 'some-other-shop-id' });
    const otherUser = await createUser(prisma);
    const r = await validateCoupon(prisma, {
      code: c.code, userId: otherUser.user.id, shopId: shop.id, subtotal: 50000,
    });
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('wrong_shop');
  });

  test('FREE_DELIVERY discount equals deliveryFee', async () => {
    const c = await makeCoupon({ type: 'FREE_DELIVERY', value: 0 });
    const otherUser = await createUser(prisma);
    const r = await validateCoupon(prisma, {
      code: c.code, userId: otherUser.user.id, subtotal: 50000, deliveryFee: 15000,
    });
    expect(r.valid).toBe(true);
    expect(r.discount).toBe(15000);
  });

  test('minOrder unmet → min_order', async () => {
    const c = await makeCoupon({ minOrder: 100000 });
    const otherUser = await createUser(prisma);
    const r = await validateCoupon(prisma, {
      code: c.code, userId: otherUser.user.id, subtotal: 50000,
    });
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('min_order');
  });

  test('not_found / inactive', async () => {
    const r1 = await validateCoupon(prisma, { code: 'NOPE-XX-12345', userId: buyer.user.id, subtotal: 0 });
    expect(r1.reason).toBe('not_found');

    const c = await makeCoupon({ isActive: false });
    const r2 = await validateCoupon(prisma, { code: c.code, userId: buyer.user.id, subtotal: 50000 });
    expect(r2.reason).toBe('inactive');
  });
});
