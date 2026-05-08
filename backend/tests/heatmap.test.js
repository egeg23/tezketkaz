// Phase 8.4 — courier demand heatmap test.
// Seeds unassigned orders at known shop coords and asserts the grid output.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');

let ctx;
let prisma;
let app;
let buyer;
let courier;
let shopCenter;
let shopFar;

async function makeUnassignedOrder(shopId, status = 'paid') {
  return prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'Test',
      customerPhone: buyer.user.phone,
      shopId,
      deliveryAddress: '1 Test St',
      paymentMethod: 'cash',
      isPaid: false,
      subtotal: 50000,
      total: 50000,
      status,
      courierId: null,
    },
  });
}

beforeAll(async () => {
  ctx = await setupTestDb('heatmap');
  prisma = ctx.prisma;
  app = ctx.app;

  buyer = await createUser(prisma);
  courier = await createUser(prisma, { isBuyer: false });
  await prisma.user.update({
    where: { id: courier.user.id },
    data: { isCourier: true, courierStatus: 'approved' },
  });
  courier.user = await prisma.user.findUnique({ where: { id: courier.user.id } });

  const ownerA = await createUser(prisma, { isShop: true });
  const ownerB = await createUser(prisma, { isShop: true });
  shopCenter = await createShopWithOwner(prisma, ownerA.user);
  shopFar = await createShopWithOwner(prisma, ownerB.user);
  await prisma.shop.update({
    where: { id: shopCenter.id },
    data: { lat: 41.31, lng: 69.24 },
  });
  await prisma.shop.update({
    where: { id: shopFar.id },
    data: { lat: 41.5, lng: 69.5 }, // ~30 km from centre
  });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

beforeEach(async () => {
  await prisma.order.deleteMany({});
});

describe('GET /api/couriers/heatmap', () => {
  test('aggregates unassigned orders into 1km grid cells with normalised intensity', async () => {
    // 3 orders at the same shop -> same cell (count 3, intensity 1.0)
    await makeUnassignedOrder(shopCenter.id);
    await makeUnassignedOrder(shopCenter.id);
    await makeUnassignedOrder(shopCenter.id);

    const res = await request(app)
      .get('/api/couriers/heatmap?lat=41.31&lng=69.24&radiusKm=10')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(res.body.cells.length).toBe(1);
    expect(res.body.cells[0].count).toBe(3);
    expect(res.body.cells[0].intensity).toBe(1);
    expect(res.body.cells[0].lat).toBeCloseTo(41.31, 2);
    expect(res.body.cells[0].lng).toBeCloseTo(69.24, 2);
    expect(res.body.windowMs).toBe(60 * 60 * 1000);
  });

  test('excludes cells outside the supplied radius', async () => {
    await makeUnassignedOrder(shopCenter.id);
    await makeUnassignedOrder(shopFar.id); // 100 km off

    const res = await request(app)
      .get('/api/couriers/heatmap?lat=41.31&lng=69.24&radiusKm=10')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(res.body.cells.length).toBe(1);
    // Cell must be the centre, not the far shop.
    expect(res.body.cells[0].lat).toBeCloseTo(41.31, 2);
  });

  test('skips assigned orders and statuses outside the active demand set', async () => {
    // Assigned order (has a courier) — must be skipped.
    await prisma.order.create({
      data: {
        buyerId: buyer.user.id,
        customerName: 'Test',
        customerPhone: buyer.user.phone,
        shopId: shopCenter.id,
        deliveryAddress: '1 Test St',
        paymentMethod: 'cash',
        isPaid: true,
        subtotal: 50000,
        total: 50000,
        status: 'courierAssigned',
        courierId: courier.user.id,
      },
    });
    // Delivered (final) — must be skipped.
    await makeUnassignedOrder(shopCenter.id, 'delivered');
    // One genuine unassigned order.
    await makeUnassignedOrder(shopCenter.id, 'paid');

    const res = await request(app)
      .get('/api/couriers/heatmap?lat=41.31&lng=69.24&radiusKm=10')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(res.body.cells.length).toBe(1);
    expect(res.body.cells[0].count).toBe(1);
  });

  test('returns relative intensities when multiple cells', async () => {
    // 2 orders at centre.
    await makeUnassignedOrder(shopCenter.id);
    await makeUnassignedOrder(shopCenter.id);
    // 1 order at the far shop, but with a wide radius so it's included.
    await makeUnassignedOrder(shopFar.id);

    const res = await request(app)
      .get('/api/couriers/heatmap?lat=41.31&lng=69.24&radiusKm=200')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(res.body.cells.length).toBe(2);
    const top = res.body.cells[0];
    const second = res.body.cells[1];
    expect(top.count).toBe(2);
    expect(top.intensity).toBe(1);
    expect(second.count).toBe(1);
    expect(second.intensity).toBeCloseTo(0.5, 4);
  });

  test('rejects non-couriers', async () => {
    const stranger = await createUser(prisma);
    const res = await request(app)
      .get('/api/couriers/heatmap?lat=41.31&lng=69.24')
      .set('Authorization', stranger.auth);
    expect(res.status).toBe(403);
  });
});
