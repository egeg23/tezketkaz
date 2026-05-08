// Integration test: dispatcher.offerNextBatch / acceptOffer / declineOffer
// against the real (per-test) Prisma DB. io is stubbed and the BullMQ retry
// queue is a no-op (REDIS_ENABLED=false in tests/setup.js).

const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const dispatcher = require('../src/services/dispatcher');
const presence = require('../src/services/redis-state');

let ctx;
let prisma;
let shop;
let buyer;
let couriers;
let emittedEvents;
let io;

async function makeOnlineCourier(suffix, lat, lng, ratingOverride) {
  const u = await createUser(ctx.prisma, { isBuyer: false, name: `Courier ${suffix}` });
  await ctx.prisma.user.update({
    where: { id: u.user.id },
    data: {
      isCourier: true,
      courierStatus: 'approved',
      isOnline: true,
      rating: ratingOverride ?? 5.0,
      ordersCount: 25,
    },
  });
  await presence.setCourierOnline(u.user.id, `sock-${suffix}`);
  await presence.setCourierLocation(u.user.id, lat, lng);
  return u.user;
}

beforeAll(async () => {
  ctx = await setupTestDb('dispatch-flow');
  prisma = ctx.prisma;

  // Stub io with an event recorder so we can assert without sockets.
  emittedEvents = [];
  io = {
    to(room) {
      return {
        emit(event, data) { emittedEvents.push({ room, event, data }); },
      };
    },
    emit(event, data) { emittedEvents.push({ room: null, event, data }); },
  };

  const owner = await createUser(prisma, { isShop: true });
  buyer = await createUser(prisma);
  shop = await createShopWithOwner(prisma, owner.user);
  // Shop at a Tashkent-ish coordinate.
  await prisma.shop.update({
    where: { id: shop.id },
    data: { lat: 41.31, lng: 69.24 },
  });
}, 30000);

afterAll(async () => {
  // Drain any deferred follow-ups before the DB is torn down.
  await dispatcher.flushPending();
  // Cleanup presence so other test files start fresh.
  for (const id of await presence.listOnlineCouriers()) {
    await presence.setCourierOffline(id);
  }
  await teardownTestDb(ctx);
});

beforeEach(async () => {
  emittedEvents.length = 0;
  // Clean offers + reset couriers between tests.
  await prisma.dispatchOffer.deleteMany({});
  await prisma.order.deleteMany({});
  // Remove old couriers so each test gets fresh ones.
  for (const id of await presence.listOnlineCouriers()) {
    await presence.setCourierOffline(id);
  }
  await prisma.user.updateMany({
    where: { isCourier: true },
    data: { activeOrderId: null, isOnline: false },
  });
});

async function makeOrder() {
  return prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'Test',
      customerPhone: buyer.user.phone,
      shopId: shop.id,
      deliveryAddress: '1 Test St',
      paymentMethod: 'cash',
      isPaid: false,
      subtotal: 50000,
      total: 50000,
      status: 'pending',
    },
  });
}

describe('dispatcher.offerNextBatch', () => {
  test('creates DispatchOffer rows for top candidates', async () => {
    couriers = [];
    couriers.push(await makeOnlineCourier('1', 41.310, 69.240, 5));   // ~0 km
    couriers.push(await makeOnlineCourier('2', 41.315, 69.245, 4.8)); // ~0.7 km
    couriers.push(await makeOnlineCourier('3', 41.320, 69.250, 4.5)); // ~1.4 km
    couriers.push(await makeOnlineCourier('4', 41.330, 69.260, 4.0)); // ~2.7 km

    const order = await makeOrder();

    const result = await dispatcher.offerNextBatch(prisma, io, order.id, { batchSize: 3 });
    expect(result.reason).toBe('ok');
    expect(result.offered).toHaveLength(3);

    const rows = await prisma.dispatchOffer.findMany({ where: { orderId: order.id } });
    expect(rows).toHaveLength(3);
    for (const r of rows) {
      expect(r.status).toBe('pending');
      expect(r.expiresAt instanceof Date).toBe(true);
    }

    // The offer events should have been emitted to courier rooms.
    const offerEvents = emittedEvents.filter((e) => e.event === 'dispatch:offer');
    expect(offerEvents).toHaveLength(3);
  });
});

describe('dispatcher.acceptOffer', () => {
  test('assigns courier, supersedes other pending offers, emits notifications', async () => {
    const c1 = await makeOnlineCourier('a', 41.310, 69.240, 5);
    const c2 = await makeOnlineCourier('b', 41.315, 69.245, 5);
    const c3 = await makeOnlineCourier('c', 41.320, 69.250, 5);
    const order = await makeOrder();

    await dispatcher.offerNextBatch(prisma, io, order.id, { batchSize: 3 });
    emittedEvents.length = 0;

    const updated = await dispatcher.acceptOffer(prisma, io, order.id, c1.id);
    expect(updated.courierId).toBe(c1.id);
    expect(updated.status).toBe('courierAssigned');

    const offers = await prisma.dispatchOffer.findMany({ where: { orderId: order.id } });
    const accepted = offers.find((o) => o.courierId === c1.id);
    expect(accepted.status).toBe('accepted');
    const others = offers.filter((o) => o.courierId !== c1.id);
    expect(others.every((o) => o.status === 'superseded')).toBe(true);

    const courierUser = await prisma.user.findUnique({ where: { id: c1.id } });
    expect(courierUser.activeOrderId).toBe(order.id);

    expect(emittedEvents.find((e) => e.event === 'order:assigned')).toBeTruthy();
    expect(emittedEvents.find((e) => e.event === 'order:updated')).toBeTruthy();
    // Two superseded couriers should be told the offer is cancelled.
    const cancelEvents = emittedEvents.filter((e) => e.event === 'dispatch:offer_cancelled');
    expect(cancelEvents.length).toBe(2);
    // Suppress unused-var lint for c2/c3.
    expect([c2.id, c3.id].sort()).toEqual(others.map((o) => o.courierId).sort());
  });

  test('rejects accept when offer is not pending', async () => {
    const c1 = await makeOnlineCourier('z', 41.310, 69.240, 5);
    const order = await makeOrder();
    await dispatcher.offerNextBatch(prisma, io, order.id, { batchSize: 3 });
    await dispatcher.acceptOffer(prisma, io, order.id, c1.id);

    await expect(
      dispatcher.acceptOffer(prisma, io, order.id, c1.id),
    ).rejects.toThrow();
  });
});

describe('dispatcher.declineOffer', () => {
  test('marks offer declined and triggers next batch when all decline', async () => {
    const c1 = await makeOnlineCourier('x', 41.310, 69.240, 5);
    const c2 = await makeOnlineCourier('y', 41.315, 69.245, 5);
    const order = await makeOrder();

    await dispatcher.offerNextBatch(prisma, io, order.id, { batchSize: 2 });

    await dispatcher.declineOffer(prisma, io, order.id, c1.id, 'busy');
    let offers = await prisma.dispatchOffer.findMany({ where: { orderId: order.id } });
    expect(offers.find((o) => o.courierId === c1.id).status).toBe('declined');

    // Still one pending — no new batch triggered.
    expect(offers.filter((o) => o.status === 'pending').length).toBe(1);

    await dispatcher.declineOffer(prisma, io, order.id, c2.id, 'busy');
    // Flush deferred offerNextBatch so it doesn't outlive the test DB.
    await dispatcher.flushPending();

    offers = await prisma.dispatchOffer.findMany({ where: { orderId: order.id } });
    // All originals are declined; no other candidates so no new offers.
    const declinedCount = offers.filter((o) => o.status === 'declined').length;
    expect(declinedCount).toBe(2);
  });
});
