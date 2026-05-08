// Phase 7.3 — banner CRUD + tracking.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser } = require('./helpers/db');

let ctx;
let prisma;
let admin;
let buyer;

beforeAll(async () => {
  ctx = await setupTestDb('banners');
  prisma = ctx.prisma;
  admin = await createUser(prisma, { isAdmin: true });
  buyer = await createUser(prisma, { country: 'UZ' });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makeBanner(overrides = {}) {
  return prisma.banner.create({
    data: {
      titleUz: overrides.titleUz || 'Promo',
      titleRu: overrides.titleRu || 'Промо',
      imageUrl: overrides.imageUrl || '/uploads/banners/x.jpg',
      vertical: overrides.vertical ?? 'all',
      country: overrides.country ?? null,
      priority: overrides.priority ?? 0,
      isActive: overrides.isActive ?? true,
      validFrom: overrides.validFrom ?? null,
      validUntil: overrides.validUntil ?? null,
    },
  });
}

// Wait briefly so fire-and-forget impressions land before we count them.
function flush(ms = 50) {
  return new Promise((r) => setTimeout(r, ms));
}

describe('GET /api/banners — public list', () => {
  test('filters by vertical (matches exact + "all")', async () => {
    await makeBanner({ titleRu: 'Foodie', vertical: 'restaurant', priority: 5 });
    await makeBanner({ titleRu: 'Pharma', vertical: 'pharmacy', priority: 5 });
    await makeBanner({ titleRu: 'Generic', vertical: 'all', priority: 1 });

    const res = await request(ctx.app).get('/api/banners?vertical=restaurant');
    expect(res.status).toBe(200);
    const titles = res.body.banners.map((b) => b.titleRu);
    expect(titles).toContain('Foodie');
    expect(titles).toContain('Generic');
    expect(titles).not.toContain('Pharma');
  });

  test('filters by country (matches country + null)', async () => {
    await makeBanner({ titleRu: 'UZ Only', country: 'UZ' });
    await makeBanner({ titleRu: 'KZ Only', country: 'KZ' });
    await makeBanner({ titleRu: 'Worldwide', country: null });

    const res = await request(ctx.app).get('/api/banners?country=UZ');
    const titles = res.body.banners.map((b) => b.titleRu);
    expect(titles).toContain('UZ Only');
    expect(titles).toContain('Worldwide');
    expect(titles).not.toContain('KZ Only');
  });

  test('respects validity window + isActive', async () => {
    const past = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const future = new Date(Date.now() + 24 * 60 * 60 * 1000);
    await makeBanner({ titleRu: 'Expired', validFrom: past, validUntil: past });
    await makeBanner({ titleRu: 'NotYet', validFrom: future, validUntil: future });
    await makeBanner({ titleRu: 'Inactive', isActive: false });
    await makeBanner({ titleRu: 'LiveNow', validFrom: past, validUntil: future });

    const res = await request(ctx.app).get('/api/banners');
    const titles = res.body.banners.map((b) => b.titleRu);
    expect(titles).toContain('LiveNow');
    expect(titles).not.toContain('Expired');
    expect(titles).not.toContain('NotYet');
    expect(titles).not.toContain('Inactive');
  });

  test('sorted by priority desc', async () => {
    await prisma.banner.deleteMany({});
    await makeBanner({ titleRu: 'Low', priority: 1 });
    await makeBanner({ titleRu: 'High', priority: 10 });
    await makeBanner({ titleRu: 'Mid', priority: 5 });
    const res = await request(ctx.app).get('/api/banners');
    expect(res.body.banners[0].titleRu).toBe('High');
    expect(res.body.banners[1].titleRu).toBe('Mid');
    expect(res.body.banners[2].titleRu).toBe('Low');
  });
});

describe('POST /api/banners/:id/click', () => {
  test('records a click impression', async () => {
    const banner = await makeBanner({ titleRu: 'Clickable' });
    const res = await request(ctx.app).post(`/api/banners/${banner.id}/click`);
    expect(res.status).toBe(204);
    await flush();
    const count = await prisma.bannerImpression.count({
      where: { bannerId: banner.id, kind: 'click' },
    });
    expect(count).toBe(1);
  });

  test('404 for unknown banner', async () => {
    const res = await request(ctx.app).post('/api/banners/no-such-id/click');
    expect(res.status).toBe(404);
  });
});

describe('Admin CRUD', () => {
  test('non-admin → 403 on admin endpoints', async () => {
    const res = await request(ctx.app)
      .get('/api/admin/banners')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(403);
  });

  test('admin can create + update + delete', async () => {
    const create = await request(ctx.app)
      .post('/api/admin/banners')
      .set('Authorization', admin.auth)
      .send({
        titleUz: 'YangiPromo',
        titleRu: 'НовыйПромо',
        imageUrl: '/uploads/banners/x.jpg',
        vertical: 'grocery',
        priority: 7,
      });
    expect(create.status).toBe(201);
    const id = create.body.banner.id;

    const patch = await request(ctx.app)
      .patch(`/api/admin/banners/${id}`)
      .set('Authorization', admin.auth)
      .send({ priority: 99 });
    expect(patch.status).toBe(200);
    expect(patch.body.banner.priority).toBe(99);

    const list = await request(ctx.app)
      .get('/api/admin/banners')
      .set('Authorization', admin.auth);
    expect(list.status).toBe(200);
    expect(list.body.banners.find((b) => b.id === id)).toBeTruthy();

    const del = await request(ctx.app)
      .delete(`/api/admin/banners/${id}`)
      .set('Authorization', admin.auth);
    expect(del.status).toBe(200);
    expect(del.body.deleted).toBe(true);
  });

  test('create rejects missing required fields', async () => {
    const res = await request(ctx.app)
      .post('/api/admin/banners')
      .set('Authorization', admin.auth)
      .send({ titleRu: 'Only RU' });
    expect(res.status).toBe(400);
  });
});

describe('GET /api/admin/banners/:id/stats', () => {
  test('returns view + click counts grouped by kind', async () => {
    const banner = await makeBanner({ titleRu: 'StatsBanner' });
    // Seed impressions directly (bypass fire-and-forget timing).
    await prisma.bannerImpression.createMany({
      data: [
        { bannerId: banner.id, kind: 'view' },
        { bannerId: banner.id, kind: 'view' },
        { bannerId: banner.id, kind: 'view' },
        { bannerId: banner.id, kind: 'click' },
      ],
    });
    const res = await request(ctx.app)
      .get(`/api/admin/banners/${banner.id}/stats`)
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(res.body.views).toBe(3);
    expect(res.body.clicks).toBe(1);
    expect(res.body.ctr).toBeCloseTo(1 / 3);
    expect(Array.isArray(res.body.last30dayDailyViews)).toBe(true);
  });
});
