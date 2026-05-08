// Phase 6.12 — admin users CRUD tests.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser } = require('./helpers/db');

let ctx;
let prisma;
let admin;

beforeAll(async () => {
  ctx = await setupTestDb('admin-users');
  prisma = ctx.prisma;
  admin = await createUser(prisma, { isAdmin: true });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('GET /api/admin/users', () => {
  test('paginated list, filterable by role', async () => {
    await createUser(prisma);
    const courier = await createUser(prisma, { isCourier: true, isBuyer: false });

    const res = await request(ctx.app)
      .get('/api/admin/users?role=courier&limit=10')
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.users)).toBe(true);
    expect(res.body.users.some((u) => u.id === courier.user.id)).toBe(true);
    expect(res.body.users.every((u) => u.isCourier === true)).toBe(true);
  });

  test('search by phone substring', async () => {
    const u = await createUser(prisma, { phone: `+998901234567` });
    const res = await request(ctx.app)
      .get('/api/admin/users?q=901234567')
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(res.body.users.some((x) => x.id === u.user.id)).toBe(true);
  });
});

describe('GET /api/admin/users/:id', () => {
  test('returns user + stats', async () => {
    const u = await createUser(prisma);
    const res = await request(ctx.app)
      .get(`/api/admin/users/${u.user.id}`)
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(res.body.user.id).toBe(u.user.id);
    expect(typeof res.body.ordersCount).toBe('number');
    expect(typeof res.body.totalSpent).toBe('number');
    expect(Array.isArray(res.body.recentOrders)).toBe(true);
  });

  test('404 for unknown', async () => {
    const res = await request(ctx.app)
      .get('/api/admin/users/no-such-id')
      .set('Authorization', admin.auth);
    expect(res.status).toBe(404);
  });
});

describe('PATCH /api/admin/users/:id', () => {
  test('updates role flags', async () => {
    const u = await createUser(prisma);
    const res = await request(ctx.app)
      .patch(`/api/admin/users/${u.user.id}`)
      .set('Authorization', admin.auth)
      .send({ isCourier: true, courierStatus: 'approved', name: 'Renamed' });
    expect(res.status).toBe(200);
    expect(res.body.user.isCourier).toBe(true);
    expect(res.body.user.courierStatus).toBe('approved');
    expect(res.body.user.name).toBe('Renamed');
  });
});

describe('ban / unban', () => {
  test('ban revokes refresh tokens and clears role flags', async () => {
    const u = await createUser(prisma, { isCourier: true, isShop: true });
    // Pre-create some active refresh tokens.
    await prisma.refreshToken.createMany({
      data: [
        {
          id: `rt1-${u.user.id}`,
          userId: u.user.id,
          jti: `jti-1-${u.user.id}`,
          expiresAt: new Date(Date.now() + 24 * 3600 * 1000),
        },
        {
          id: `rt2-${u.user.id}`,
          userId: u.user.id,
          jti: `jti-2-${u.user.id}`,
          expiresAt: new Date(Date.now() + 24 * 3600 * 1000),
        },
      ],
    });

    const res = await request(ctx.app)
      .post(`/api/admin/users/${u.user.id}/ban`)
      .set('Authorization', admin.auth)
      .send({ reason: 'fraud' });
    expect(res.status).toBe(200);
    expect(res.body.user.isCourier).toBe(false);
    expect(res.body.user.isShop).toBe(false);
    expect(res.body.user.courierStatus).toBe('rejected');

    const tokens = await prisma.refreshToken.findMany({ where: { userId: u.user.id } });
    expect(tokens.length).toBeGreaterThan(0);
    expect(tokens.every((t) => t.revokedAt !== null)).toBe(true);
  });

  test('unban restores buyer role', async () => {
    const u = await createUser(prisma);
    await request(ctx.app)
      .post(`/api/admin/users/${u.user.id}/ban`)
      .set('Authorization', admin.auth)
      .send({ reason: 'oops' });

    const res = await request(ctx.app)
      .post(`/api/admin/users/${u.user.id}/unban`)
      .set('Authorization', admin.auth)
      .send();
    expect(res.status).toBe(200);
    expect(res.body.user.isBuyer).toBe(true);
  });
});

describe('non-admin guard', () => {
  test('non-admin PATCH → 403', async () => {
    const u = await createUser(prisma);
    const res = await request(ctx.app)
      .patch(`/api/admin/users/${u.user.id}`)
      .set('Authorization', u.auth)
      .send({ name: 'foo' });
    expect(res.status).toBe(403);
  });
});
