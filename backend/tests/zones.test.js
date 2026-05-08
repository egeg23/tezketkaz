// Integration tests for /api/shops/:shopId/zones and /api/zones/:zoneId.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb, createUser, createShopWithOwner,
} = require('./helpers/db');

let ctx;
let owner;
let outsider;
let shop;

// A small square polygon roughly around Tashkent center.
const SQUARE = [
  [41.30, 69.20],
  [41.30, 69.30],
  [41.40, 69.30],
  [41.40, 69.20],
];

beforeAll(async () => {
  ctx = await setupTestDb('zones');
  owner = await createUser(ctx.prisma, { name: 'Owner', isShop: true });
  outsider = await createUser(ctx.prisma, { name: 'Outsider' });
  shop = await createShopWithOwner(ctx.prisma, owner.user);
});

afterAll(async () => {
  await teardownTestDb(ctx);
});

describe('Delivery zone CRUD', () => {
  let zoneId;

  test('owner can create a zone', async () => {
    const res = await request(ctx.app)
      .post(`/api/shops/${shop.id}/zones`)
      .set('Authorization', owner.auth)
      .send({ name: 'Center', polygon: SQUARE, baseFee: 15000, perKmFee: 2500, freeKm: 1 });
    expect(res.status).toBe(201);
    expect(res.body.zone.id).toBeTruthy();
    expect(res.body.zone.name).toBe('Center');
    zoneId = res.body.zone.id;
  });

  test('non-owner cannot create a zone', async () => {
    const res = await request(ctx.app)
      .post(`/api/shops/${shop.id}/zones`)
      .set('Authorization', outsider.auth)
      .send({ name: 'Bad', polygon: SQUARE });
    expect(res.status).toBe(403);
  });

  test('polygon validation rejects fewer than 3 points', async () => {
    const res = await request(ctx.app)
      .post(`/api/shops/${shop.id}/zones`)
      .set('Authorization', owner.auth)
      .send({ name: 'Tiny', polygon: [[41.0, 69.0], [41.1, 69.1]] });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/at least 3 points/);
  });

  test('polygon validation rejects bad point shape', async () => {
    const res = await request(ctx.app)
      .post(`/api/shops/${shop.id}/zones`)
      .set('Authorization', owner.auth)
      .send({ name: 'Bad', polygon: [[41, 69], 'oops', [41.2, 69.2]] });
    expect(res.status).toBe(400);
  });

  test('GET active-only by default', async () => {
    // Add an inactive second zone.
    await ctx.prisma.deliveryZone.create({
      data: {
        shopId: shop.id,
        name: 'Hidden',
        polygon: JSON.stringify(SQUARE),
        isActive: false,
        sortOrder: 5,
      },
    });

    const resPublic = await request(ctx.app).get(`/api/shops/${shop.id}/zones`);
    expect(resPublic.status).toBe(200);
    const namesPublic = resPublic.body.zones.map((z) => z.name);
    expect(namesPublic).toContain('Center');
    expect(namesPublic).not.toContain('Hidden');

    // Owner with ?all=1 sees inactive too.
    const resOwner = await request(ctx.app)
      .get(`/api/shops/${shop.id}/zones?all=1`)
      .set('Authorization', owner.auth);
    expect(resOwner.status).toBe(200);
    const namesOwner = resOwner.body.zones.map((z) => z.name);
    expect(namesOwner).toContain('Hidden');

    // Anonymous with ?all=1 still gets active-only.
    const resAnon = await request(ctx.app).get(`/api/shops/${shop.id}/zones?all=1`);
    const namesAnon = resAnon.body.zones.map((z) => z.name);
    expect(namesAnon).not.toContain('Hidden');
  });

  test('owner can patch zone', async () => {
    const res = await request(ctx.app)
      .patch(`/api/zones/${zoneId}`)
      .set('Authorization', owner.auth)
      .send({ baseFee: 20000, sortOrder: 2 });
    expect(res.status).toBe(200);
    expect(res.body.zone.baseFee).toBe(20000);
    expect(res.body.zone.sortOrder).toBe(2);
  });

  test('non-owner cannot patch zone', async () => {
    const res = await request(ctx.app)
      .patch(`/api/zones/${zoneId}`)
      .set('Authorization', outsider.auth)
      .send({ baseFee: 1 });
    expect(res.status).toBe(403);
  });

  test('non-owner cannot delete zone', async () => {
    const res = await request(ctx.app)
      .delete(`/api/zones/${zoneId}`)
      .set('Authorization', outsider.auth);
    expect(res.status).toBe(403);
  });

  test('owner can delete zone', async () => {
    const res = await request(ctx.app)
      .delete(`/api/zones/${zoneId}`)
      .set('Authorization', owner.auth);
    expect(res.status).toBe(200);
    expect(res.body.deleted).toBe(true);
  });
});
