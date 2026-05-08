// Phase 8.1 stacked-dispatch integration tests.
//
// Covers buildBatchCandidates clustering rules, batched acceptance (all
// member orders inherit the same courier + the courier's activeOrderId is
// pinned to the first sequence), and progressive completion of a batch.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const dispatcher = require('../src/services/dispatcher');
const presence = require('../src/services/redis-state');

let ctx;
let prisma;
let app;
let buyer;
let shopA;
let shopB; // far-away shop
let io;

async function makeOnlineCourier(suffix, lat, lng) {
  const u = await createUser(ctx.prisma, { isBuyer: false, name: `Courier ${suffix}` });
  await ctx.prisma.user.update({
    where: { id: u.user.id },
    data: {
      isCourier: true,
      courierStatus: 'approved',
      isOnline: true,
      rating: 5,
      ordersCount: 25,
    },
  });
  await presence.setCourierOnline(u.user.id, `sock-${suffix}`);
  await presence.setCourierLocation(u.user.id, lat, lng);
  // Re-load (so courier.auth carries fresh fields).
  u.user = await ctx.prisma.user.findUnique({ where: { id: u.user.id } });
  return u;
}

async function makeOrder(opts = {}) {
  return prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'Test',
      customerPhone: buyer.user.phone,
      shopId: opts.shopId || shopA.id,
      deliveryAddress: '1 Test St',
      paymentMethod: 'cash',
      isPaid: false,
      subtotal: 50000,
      total: 50000,
      status: opts.status || 'paid',
      courierReward: 12000,
      ...(opts.createdAt ? { createdAt: opts.createdAt } : {}),
    },
  });
}

beforeAll(async () => {
  ctx = await setupTestDb('dispatch-stacked');
  prisma = ctx.prisma;
  app = ctx.app;

  io = { to: () => ({ emit: () => {} }), emit: () => {} };

  const ownerA = await createUser(prisma, { isShop: true });
  const ownerB = await createUser(prisma, { isShop: true });
  buyer = await createUser(prisma);
  shopA = await createShopWithOwner(prisma, ownerA.user);
  shopB = await createShopWithOwner(prisma, ownerB.user);

  // Shop A in central Tashkent.
  await prisma.shop.update({
    where: { id: shopA.id },
    data: { lat: 41.31, lng: 69.24 },
  });
  // Shop B 30 km away.
  await prisma.shop.update({
    where: { id: shopB.id },
    data: { lat: 41.6, lng: 69.6 },
  });
}, 30000);

afterAll(async () => {
  await dispatcher.flushPending();
  for (const id of await presence.listOnlineCouriers()) {
    await presence.setCourierOffline(id);
  }
  await teardownTestDb(ctx);
});

beforeEach(async () => {
  // Clean offers/batches/orders between tests.
  await prisma.dispatchOffer.deleteMany({});
  // Detach orders from batches before deleting batches (FK).
  await prisma.order.updateMany({ data: { batchId: null, batchSequence: null } });
  await prisma.orderBatch.deleteMany({});
  await prisma.order.deleteMany({});
  await prisma.user.updateMany({
    where: { isCourier: true },
    data: { activeOrderId: null, isOnline: false },
  });
  for (const id of await presence.listOnlineCouriers()) {
    await presence.setCourierOffline(id);
  }
});

describe('buildBatchCandidates', () => {
  test('groups two orders from the same shop within the time window', async () => {
    const o1 = await makeOrder();
    const o2 = await makeOrder();
    const candidates = await dispatcher.buildBatchCandidates(prisma, {
      seedOrderId: o1.id,
    });
    expect(candidates).toHaveLength(1);
    expect(candidates[0].memberOrderIds.sort()).toEqual([o1.id, o2.id].sort());
    expect(candidates[0].totalReward).toBeGreaterThan(0);
  });

  test('does not cluster orders from far-away shops', async () => {
    const o1 = await makeOrder({ shopId: shopA.id });
    await makeOrder({ shopId: shopB.id });
    const candidates = await dispatcher.buildBatchCandidates(prisma, {
      seedOrderId: o1.id,
      radiusKm: 1,
    });
    expect(candidates).toEqual([]);
  });

  test('does not cluster when only one pending order exists', async () => {
    const o1 = await makeOrder();
    const candidates = await dispatcher.buildBatchCandidates(prisma, {
      seedOrderId: o1.id,
    });
    expect(candidates).toEqual([]);
  });

  test('caps batch size at 3', async () => {
    const orders = [];
    for (let i = 0; i < 5; i += 1) orders.push(await makeOrder());
    const [seed] = orders;
    const candidates = await dispatcher.buildBatchCandidates(prisma, {
      seedOrderId: seed.id,
      batchCap: 3,
    });
    expect(candidates).toHaveLength(1);
    expect(candidates[0].memberOrderIds.length).toBe(3);
  });

  test('skips orders outside the time window', async () => {
    const o1 = await makeOrder();
    // Build the second order with a createdAt 1 hour earlier than o1.
    await prisma.order.create({
      data: {
        buyerId: buyer.user.id,
        customerName: 'Test',
        customerPhone: buyer.user.phone,
        shopId: shopA.id,
        deliveryAddress: '1 Test St',
        paymentMethod: 'cash',
        isPaid: false,
        subtotal: 50000,
        total: 50000,
        status: 'paid',
        courierReward: 12000,
        createdAt: new Date(o1.createdAt.getTime() - 60 * 60 * 1000),
      },
    });
    const candidates = await dispatcher.buildBatchCandidates(prisma, {
      seedOrderId: o1.id,
      windowMs: 5 * 60 * 1000,
    });
    expect(candidates).toEqual([]);
  });
});

describe('offerNextBatch + acceptOffer with batches', () => {
  test('accepting a batched offer assigns courier to all member orders', async () => {
    const c1 = await makeOnlineCourier('c1', 41.310, 69.240);
    await makeOnlineCourier('c2', 41.315, 69.245);

    const o1 = await makeOrder();
    const o2 = await makeOrder();

    const result = await dispatcher.offerNextBatch(prisma, io, o1.id, { batchSize: 2 });
    expect(result.reason).toBe('ok');

    // The orders should now be linked to a single OrderBatch.
    const linked = await prisma.order.findMany({ where: { id: { in: [o1.id, o2.id] } } });
    const batchIds = new Set(linked.map((o) => o.batchId).filter(Boolean));
    expect(batchIds.size).toBe(1);
    const batchId = [...batchIds][0];
    expect(batchId).toBeTruthy();

    // Offer rows should carry the batchId.
    const offers = await prisma.dispatchOffer.findMany({ where: { orderId: o1.id } });
    expect(offers.length).toBeGreaterThanOrEqual(1);
    expect(offers[0].batchId).toBe(batchId);

    // Accept on behalf of c1.
    await dispatcher.acceptOffer(prisma, io, o1.id, c1.user.id);

    const batch = await prisma.orderBatch.findUnique({ where: { id: batchId } });
    expect(batch.status).toBe('accepted');
    expect(batch.courierId).toBe(c1.user.id);

    const post = await prisma.order.findMany({
      where: { batchId },
      orderBy: { batchSequence: 'asc' },
    });
    expect(post).toHaveLength(2);
    expect(post.every((o) => o.courierId === c1.user.id)).toBe(true);
    expect(post.every((o) => o.status === 'courierAssigned')).toBe(true);
    expect(post[0].batchSequence).toBe(0);
    expect(post[1].batchSequence).toBe(1);

    const courier = await prisma.user.findUnique({ where: { id: c1.user.id } });
    // activeOrderId must be the FIRST order in batch sequence.
    expect(courier.activeOrderId).toBe(post[0].id);
  });
});

describe('courier/complete with a batch', () => {
  test('completing first advances activeOrderId; completing last clears it', async () => {
    const c1 = await makeOnlineCourier('cx', 41.310, 69.240);
    const o1 = await makeOrder();
    const o2 = await makeOrder();

    await dispatcher.offerNextBatch(prisma, io, o1.id, { batchSize: 1 });
    await dispatcher.acceptOffer(prisma, io, o1.id, c1.user.id);

    const sequenced = await prisma.order.findMany({
      where: { id: { in: [o1.id, o2.id] } },
      orderBy: { batchSequence: 'asc' },
    });
    const [first, second] = sequenced;
    expect(first.batchId).toBeTruthy();

    // Complete the first order via the HTTP endpoint.
    let res = await request(app)
      .post(`/api/orders/${first.id}/courier/complete`)
      .set('Authorization', c1.auth);
    expect(res.status).toBe(200);

    let courier = await prisma.user.findUnique({ where: { id: c1.user.id } });
    expect(courier.activeOrderId).toBe(second.id);

    let batch = await prisma.orderBatch.findUnique({ where: { id: first.batchId } });
    expect(batch.deliveriesCompleted).toBe(1);
    expect(batch.status).toBe('accepted');

    // Complete the second/last order.
    res = await request(app)
      .post(`/api/orders/${second.id}/courier/complete`)
      .set('Authorization', c1.auth);
    expect(res.status).toBe(200);

    courier = await prisma.user.findUnique({ where: { id: c1.user.id } });
    expect(courier.activeOrderId).toBeNull();

    batch = await prisma.orderBatch.findUnique({ where: { id: first.batchId } });
    expect(batch.deliveriesCompleted).toBe(2);
    expect(batch.status).toBe('completed');
    expect(batch.completedAt).toBeTruthy();
  });
});
