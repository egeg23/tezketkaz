// Phase 6.12 — admin shops CRUD tests.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');

let ctx;
let prisma;
let admin;

beforeAll(async () => {
  ctx = await setupTestDb('admin-shops');
  prisma = ctx.prisma;
  admin = await createUser(prisma, { isAdmin: true });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makeShop(name = 'Shop A') {
  const owner = await createUser(prisma, { isShop: true });
  const shop = await prisma.shop.create({
    data: { name, address: '1 Test St', lat: 41.0, lng: 69.0 },
  });
  await prisma.shopMember.create({
    data: { userId: owner.user.id, shopId: shop.id, role: 'owner' },
  });
  return { shop, owner };
}

describe('GET /api/admin/shops', () => {
  test('lists with member count + 30d GMV', async () => {
    const { shop } = await makeShop('Listing Shop');
    const buyer = await createUser(prisma);
    await prisma.order.create({
      data: {
        buyerId: buyer.user.id, customerName: 'X', customerPhone: '+99800',
        shopId: shop.id, deliveryAddress: 'addr', paymentMethod: 'cash',
        subtotal: 50000, total: 60000, status: 'delivered',
        deliveredAt: new Date(),
      },
    });

    const res = await request(ctx.app)
      .get('/api/admin/shops')
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    const found = res.body.shops.find((s) => s.id === shop.id);
    expect(found).toBeTruthy();
    expect(found.membersCount).toBe(1);
    expect(found.ordersCount).toBe(1);
    expect(found.last30dGMV).toBeGreaterThan(0);
  });

  test('filters by status=inactive', async () => {
    const { shop } = await makeShop('Inactive Filter Shop');
    await prisma.shop.update({ where: { id: shop.id }, data: { isActive: false } });
    const res = await request(ctx.app)
      .get('/api/admin/shops?status=inactive')
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(res.body.shops.every((s) => s.isActive === false)).toBe(true);
  });
});

describe('GET /api/admin/shops/:id', () => {
  test('returns full detail with members', async () => {
    const { shop } = await makeShop('Detail Shop');
    const res = await request(ctx.app)
      .get(`/api/admin/shops/${shop.id}`)
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(res.body.shop.id).toBe(shop.id);
    expect(Array.isArray(res.body.shop.members)).toBe(true);
    expect(res.body.shop.members.length).toBeGreaterThan(0);
  });

  test('404 for unknown', async () => {
    const res = await request(ctx.app)
      .get('/api/admin/shops/no-such-id')
      .set('Authorization', admin.auth);
    expect(res.status).toBe(404);
  });
});

describe('PATCH /api/admin/shops/:id', () => {
  test('updates allowed subset only', async () => {
    const { shop } = await makeShop('Patch Shop');
    const res = await request(ctx.app)
      .patch(`/api/admin/shops/${shop.id}`)
      .set('Authorization', admin.auth)
      .send({
        name: 'Patched',
        deliveryBaseFee: 15000,
        currency: 'UZS',
        bogusField: 'should-be-ignored',
      });
    expect(res.status).toBe(200);
    expect(res.body.shop.name).toBe('Patched');
    expect(res.body.shop.deliveryBaseFee).toBe(15000);

    const stored = await prisma.shop.findUnique({ where: { id: shop.id } });
    expect(stored.name).toBe('Patched');
    // bogusField should not have been written.
    expect(stored).not.toHaveProperty('bogusField');
  });
});

describe('suspend / activate', () => {
  test('suspend sets isActive=false; activate flips back', async () => {
    const { shop } = await makeShop('Suspend Shop');
    const r1 = await request(ctx.app)
      .post(`/api/admin/shops/${shop.id}/suspend`)
      .set('Authorization', admin.auth)
      .send({ reason: 'audit' });
    expect(r1.status).toBe(200);
    expect(r1.body.shop.isActive).toBe(false);

    const r2 = await request(ctx.app)
      .post(`/api/admin/shops/${shop.id}/activate`)
      .set('Authorization', admin.auth)
      .send();
    expect(r2.status).toBe(200);
    expect(r2.body.shop.isActive).toBe(true);
  });
});

describe('DELETE /api/admin/shops/:id', () => {
  test('refuses with open orders → 409', async () => {
    const { shop } = await makeShop('Open-Orders Shop');
    const buyer = await createUser(prisma);
    await prisma.order.create({
      data: {
        buyerId: buyer.user.id, customerName: 'X', customerPhone: '+99800',
        shopId: shop.id, deliveryAddress: 'addr', paymentMethod: 'cash',
        subtotal: 50000, total: 60000, status: 'pending',
      },
    });
    const res = await request(ctx.app)
      .delete(`/api/admin/shops/${shop.id}`)
      .set('Authorization', admin.auth);
    expect(res.status).toBe(409);
  });

  test('soft-deletes (isActive=false + name suffix) when no open orders', async () => {
    const { shop } = await makeShop('Archivable');
    const res = await request(ctx.app)
      .delete(`/api/admin/shops/${shop.id}`)
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(res.body.archived).toBe(true);
    expect(res.body.shop.isActive).toBe(false);
    expect(res.body.shop.name).toMatch(/\[archived\]$/);
  });
});

describe('non-admin guard', () => {
  test('non-admin GET /api/admin/shops → 403', async () => {
    const u = await createUser(prisma);
    const res = await request(ctx.app)
      .get('/api/admin/shops')
      .set('Authorization', u.auth);
    expect(res.status).toBe(403);
  });
});
