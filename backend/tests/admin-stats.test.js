// Integration test for the GET /api/admin/dashboard/stats endpoint.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');

let ctx;
let prisma;
let admin;

beforeAll(async () => {
  ctx = await setupTestDb('admin-stats');
  prisma = ctx.prisma;
  admin = await createUser(prisma, { isAdmin: true });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function seedOrders() {
  const owner = await createUser(prisma, { isShop: true });
  const buyer = await createUser(prisma);
  const courier = await createUser(prisma);
  const shop = await createShopWithOwner(prisma, owner.user);

  const today = new Date();
  // 3 delivered, 1 pending, 1 cancelled.
  await prisma.order.create({
    data: {
      buyerId: buyer.user.id, customerName: 'A', customerPhone: '+99800',
      shopId: shop.id, courierId: courier.user.id,
      deliveryAddress: 'addr', paymentMethod: 'cash',
      subtotal: 50000, total: 60000, courierReward: 12000,
      status: 'delivered', deliveredAt: today, createdAt: today,
    },
  });
  await prisma.order.create({
    data: {
      buyerId: buyer.user.id, customerName: 'A', customerPhone: '+99800',
      shopId: shop.id, courierId: courier.user.id,
      deliveryAddress: 'addr', paymentMethod: 'cash',
      subtotal: 80000, total: 92000, courierReward: 12000,
      status: 'delivered', deliveredAt: today, createdAt: today,
    },
  });
  await prisma.order.create({
    data: {
      buyerId: buyer.user.id, customerName: 'A', customerPhone: '+99800',
      shopId: shop.id,
      deliveryAddress: 'addr', paymentMethod: 'cash',
      subtotal: 30000, total: 42000,
      status: 'pending', createdAt: today,
    },
  });
  return { shop, courier };
}

describe('GET /api/admin/dashboard/stats', () => {
  test('returns stats with expected shape', async () => {
    const { shop, courier } = await seedOrders();
    const res = await request(ctx.app)
      .get('/api/admin/dashboard/stats')
      .set('Authorization', admin.auth);

    expect(res.status).toBe(200);
    expect(res.body).toEqual(expect.objectContaining({
      ordersCount: expect.any(Number),
      gmv: expect.any(Number),
      deliveredRate: expect.any(Number),
      avgOrderValue: expect.any(Number),
      topShops: expect.any(Array),
      topCouriers: expect.any(Array),
      ordersByDay: expect.any(Array),
      openDisputes: expect.any(Number),
    }));

    expect(res.body.ordersCount).toBeGreaterThanOrEqual(3);
    expect(res.body.gmv).toBeGreaterThan(0);
    expect(res.body.deliveredRate).toBeGreaterThan(0);
    expect(res.body.deliveredRate).toBeLessThanOrEqual(1);

    const topShop = res.body.topShops.find((s) => s.shopId === shop.id);
    expect(topShop).toBeTruthy();
    expect(topShop.gmv).toBeGreaterThan(0);

    const topCourier = res.body.topCouriers.find((c) => c.userId === courier.user.id);
    expect(topCourier).toBeTruthy();
    expect(topCourier.totalEarned).toBeGreaterThan(0);

    expect(res.body.ordersByDay.length).toBeGreaterThan(0);
    for (const d of res.body.ordersByDay) {
      expect(d.day).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    }
  });

  test('non-admin gets 403', async () => {
    const u = await createUser(prisma);
    const res = await request(ctx.app)
      .get('/api/admin/dashboard/stats')
      .set('Authorization', u.auth);
    expect(res.status).toBe(403);
  });

  test('missing auth gets 401', async () => {
    const res = await request(ctx.app)
      .get('/api/admin/dashboard/stats');
    expect(res.status).toBe(401);
  });
});
