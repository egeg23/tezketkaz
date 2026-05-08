// Integration tests for the upgraded GET /api/shops handler:
// haversine distance, radius filter, vertical filter.

const request = require('supertest');
const { setupTestDb, teardownTestDb } = require('./helpers/db');

let ctx;

beforeAll(async () => {
  ctx = await setupTestDb('shops-geo');

  // Tashkent (~41.31, 69.24) — three shops at varied distances.
  await ctx.prisma.shop.create({
    data: {
      name: 'Near Yunusobod', address: 'A', vertical: 'grocery',
      lat: 41.3617, lng: 69.2877, rating: 4.5,
    },
  });
  await ctx.prisma.shop.create({
    data: {
      name: 'Mid Chilonzor', address: 'B', vertical: 'grocery',
      lat: 41.2856, lng: 69.2034, rating: 4.0,
    },
  });
  // Far away — Samarkand (~280 km from Tashkent)
  await ctx.prisma.shop.create({
    data: {
      name: 'Far Samarkand', address: 'C', vertical: 'grocery',
      lat: 39.6542, lng: 66.9597, rating: 5.0,
    },
  });
  // A restaurant near Tashkent
  await ctx.prisma.shop.create({
    data: {
      name: 'Pizza Tashkent', address: 'D', vertical: 'restaurant',
      lat: 41.3000, lng: 69.2400, rating: 4.7,
    },
  });
});

afterAll(async () => {
  await teardownTestDb(ctx);
});

describe('GET /api/shops geo', () => {
  test('without geo, sorts by rating desc', async () => {
    const res = await request(ctx.app).get('/api/shops');
    expect(res.status).toBe(200);
    expect(res.body.items.length).toBe(4);
    const ratings = res.body.items.map((s) => s.rating);
    for (let i = 1; i < ratings.length; i++) {
      expect(ratings[i]).toBeLessThanOrEqual(ratings[i - 1]);
    }
  });

  test('lat+lng+radiusKm computes distance and sorts ASC', async () => {
    const res = await request(ctx.app)
      .get('/api/shops?lat=41.3&lng=69.24&radiusKm=50');
    expect(res.status).toBe(200);
    expect(res.body.items.length).toBeGreaterThan(0);
    for (const s of res.body.items) {
      expect(typeof s.distanceKm).toBe('number');
      expect(s.distanceKm).toBeLessThanOrEqual(50);
    }
    const distances = res.body.items.map((s) => s.distanceKm);
    for (let i = 1; i < distances.length; i++) {
      expect(distances[i]).toBeGreaterThanOrEqual(distances[i - 1]);
    }
  });

  test('radiusKm excludes far shops', async () => {
    const res = await request(ctx.app)
      .get('/api/shops?lat=41.3&lng=69.24&radiusKm=50');
    const names = res.body.items.map((s) => s.name);
    expect(names).not.toContain('Far Samarkand');
  });

  test('vertical filter narrows result set', async () => {
    const res = await request(ctx.app).get('/api/shops?vertical=restaurant');
    expect(res.status).toBe(200);
    for (const s of res.body.items) expect(s.vertical).toBe('restaurant');
    const names = res.body.items.map((s) => s.name);
    expect(names).toContain('Pizza Tashkent');
  });

  test('vertical+geo combine', async () => {
    const res = await request(ctx.app)
      .get('/api/shops?vertical=grocery&lat=41.3&lng=69.24&radiusKm=50');
    expect(res.status).toBe(200);
    for (const s of res.body.items) {
      expect(s.vertical).toBe('grocery');
      expect(s.distanceKm).toBeLessThanOrEqual(50);
    }
  });
});
