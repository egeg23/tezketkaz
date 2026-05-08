// Phase 8.3 — courier performance breakdown integration test.
// Seeds dispatch offers + delivered orders + reviews for a single courier
// and asserts the aggregated /api/couriers/me/performance payload.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');

let ctx;
let prisma;
let app;
let courier;
let buyer;
let shop;

async function makeOrder(overrides = {}) {
  const now = new Date();
  return prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'Test',
      customerPhone: buyer.user.phone,
      shopId: shop.id,
      deliveryAddress: '1 Test St',
      paymentMethod: 'cash',
      isPaid: true,
      subtotal: 50000,
      total: 50000,
      status: 'delivered',
      courierId: courier.user.id,
      courierReward: 12000,
      acceptedAt: overrides.acceptedAt || new Date(now.getTime() - 30 * 60 * 1000),
      deliveredAt: overrides.deliveredAt || now,
      tipAmount: overrides.tipAmount || 0,
      tipPaidAt: overrides.tipPaidAt || null,
      ...overrides,
    },
  });
}

beforeAll(async () => {
  ctx = await setupTestDb('courier-performance');
  prisma = ctx.prisma;
  app = ctx.app;

  const owner = await createUser(prisma, { isShop: true });
  buyer = await createUser(prisma);
  courier = await createUser(prisma, { isBuyer: false });
  await prisma.user.update({
    where: { id: courier.user.id },
    data: { isCourier: true, courierStatus: 'approved' },
  });
  courier.user = await prisma.user.findUnique({ where: { id: courier.user.id } });

  shop = await createShopWithOwner(prisma, owner.user);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

beforeEach(async () => {
  await prisma.dispatchOffer.deleteMany({});
  await prisma.review.deleteMany({});
  await prisma.order.deleteMany({});
});

async function seedOffer(status, ageMin = 60) {
  return prisma.dispatchOffer.create({
    data: {
      orderId: `synth-${Math.random().toString(36).slice(2)}`,
      courierId: courier.user.id,
      status,
      score: 1.0,
      distanceKm: 1.0,
      expiresAt: new Date(Date.now() + 60 * 1000),
      offeredAt: new Date(Date.now() - ageMin * 60 * 1000),
    },
  });
}

describe('GET /api/couriers/me/performance', () => {
  test('acceptanceRate from offer mix (3 accepted, 1 declined, 1 timed_out → 0.6)', async () => {
    await seedOffer('accepted');
    await seedOffer('accepted');
    await seedOffer('accepted');
    await seedOffer('declined');
    await seedOffer('timed_out');

    const res = await request(app)
      .get('/api/couriers/me/performance?days=30')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(res.body.acceptanceRate).toBeCloseTo(0.6, 4);
  });

  test('avgRating + ratingsBreakdown reflect Review rows', async () => {
    const o1 = await makeOrder();
    const o2 = await makeOrder();
    const o3 = await makeOrder();

    for (const [order, rating] of [[o1, 5], [o2, 5], [o3, 4]]) {
      await prisma.review.create({
        data: {
          orderId: order.id,
          reviewerId: buyer.user.id,
          targetType: 'COURIER',
          targetId: courier.user.id,
          rating,
        },
      });
    }

    const res = await request(app)
      .get('/api/couriers/me/performance?days=30')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(res.body.avgRating).toBeCloseTo((5 + 5 + 4) / 3, 2);
    expect(res.body.ratingsBreakdown['5']).toBe(2);
    expect(res.body.ratingsBreakdown['4']).toBe(1);
    expect(res.body.ratingsBreakdown['3']).toBe(0);
  });

  test('totalEarnings + tipsTotal + onTimeRate from delivered orders', async () => {
    // On-time: deliveredAt 30 min after acceptedAt — under the 60-min budget.
    await makeOrder({ tipAmount: 5000, tipPaidAt: new Date() });
    await makeOrder({ tipAmount: 3000, tipPaidAt: new Date() });
    // Late: deliveredAt 2h after acceptedAt — over the budget.
    const lateAccept = new Date(Date.now() - 3 * 60 * 60 * 1000);
    await makeOrder({ acceptedAt: lateAccept, deliveredAt: new Date() });

    const res = await request(app)
      .get('/api/couriers/me/performance?days=30')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(res.body.totalOrders).toBe(3);
    expect(res.body.totalEarnings).toBe(36000);
    expect(res.body.tipsTotal).toBe(8000);
    // 2 of 3 on time.
    expect(res.body.onTimeRate).toBeCloseTo(2 / 3, 2);
  });

  test('byDay aggregates orders per ISO date', async () => {
    const today = new Date();
    const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000);

    await makeOrder({ deliveredAt: today });
    await makeOrder({ deliveredAt: today });
    await makeOrder({ deliveredAt: yesterday });

    const res = await request(app)
      .get('/api/couriers/me/performance?days=30')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.byDay)).toBe(true);
    expect(res.body.byDay.length).toBe(2);
    const sorted = [...res.body.byDay].sort((a, b) => (a.day < b.day ? -1 : 1));
    expect(sorted[0].orders).toBe(1);
    expect(sorted[1].orders).toBe(2);
    expect(sorted[1].earnings).toBe(24000);
  });

  test('rejects non-courier callers', async () => {
    const stranger = await createUser(prisma);
    const res = await request(app)
      .get('/api/couriers/me/performance')
      .set('Authorization', stranger.auth);
    expect(res.status).toBe(403);
  });
});
