// Phase 6.4 — working hours service + route + closed-shop order guard.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');
const shopHours = require('../src/services/shopHours');

let ctx;
let owner;
let buyer;
let shop;
let product;

const ZONE = [
  [41.20, 69.10], [41.20, 69.30], [41.40, 69.30], [41.40, 69.10],
];

beforeAll(async () => {
  ctx = await setupTestDb('working-hours');
  owner = await createUser(ctx.prisma, { isShop: true });
  buyer = await createUser(ctx.prisma);
  shop = await createShopWithOwner(ctx.prisma, owner.user);
  shop = await ctx.prisma.shop.update({
    where: { id: shop.id },
    data: { lat: 41.30, lng: 69.20, vertical: 'grocery' },
  });
  product = await createProduct(ctx.prisma, shop.id, { price: 25000 });
  await ctx.prisma.deliveryZone.create({
    data: {
      shopId: shop.id,
      name: 'Center',
      polygon: JSON.stringify(ZONE),
      baseFee: 12000, perKmFee: 2000, freeKm: 0, minOrder: 0,
    },
  });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

// Helper — return a Date that, when interpreted in Tashkent (UTC+5), lands
// on the requested year/month/day/hour/minute. We compute the UTC instant.
function tashkent(year, month, day, hour, minute = 0) {
  // Tashkent local time → UTC = local - 5h
  const utcMs = Date.UTC(year, month - 1, day, hour - 5, minute, 0, 0);
  return new Date(utcMs);
}

describe('shopHours.isOpenNow / nextOpenAt', () => {
  test('Mon 09–22: Mon 10:00 → open', () => {
    // 2026-05-04 was a Monday.
    const sh = {
      workingHours: [{ dayOfWeek: 1, startsAt: '09:00', endsAt: '22:00', isClosed: false }],
    };
    expect(shopHours.isOpenNow(sh, tashkent(2026, 5, 4, 10, 0))).toBe(true);
  });

  test('Mon 09–22: Mon 23:00 → closed', () => {
    const sh = {
      workingHours: [{ dayOfWeek: 1, startsAt: '09:00', endsAt: '22:00', isClosed: false }],
    };
    expect(shopHours.isOpenNow(sh, tashkent(2026, 5, 4, 23, 0))).toBe(false);
  });

  test('cross-midnight Mon 18:00–02:00: Mon 23:00 OK; Tue 01:00 OK; Tue 03:00 closed', () => {
    const sh = {
      workingHours: [{ dayOfWeek: 1, startsAt: '18:00', endsAt: '02:00', isClosed: false }],
    };
    expect(shopHours.isOpenNow(sh, tashkent(2026, 5, 4, 23, 0))).toBe(true);   // Monday 23:00
    expect(shopHours.isOpenNow(sh, tashkent(2026, 5, 5, 1, 0))).toBe(true);    // Tuesday 01:00
    expect(shopHours.isOpenNow(sh, tashkent(2026, 5, 5, 3, 0))).toBe(false);   // Tuesday 03:00
  });

  test('isClosed flag overrides times', () => {
    const sh = {
      workingHours: [{ dayOfWeek: 1, startsAt: '00:00', endsAt: '23:59', isClosed: true }],
    };
    expect(shopHours.isOpenNow(sh, tashkent(2026, 5, 4, 12, 0))).toBe(false);
  });

  test('empty workingHours → open by default (legacy fallback)', () => {
    expect(shopHours.isOpenNow({ workingHours: [] }, new Date())).toBe(true);
  });

  test('nextOpenAt returns next opening across days', () => {
    const sh = {
      workingHours: [
        { dayOfWeek: 2, startsAt: '09:00', endsAt: '18:00', isClosed: false }, // Tuesday
      ],
    };
    // Sunday in Tashkent → next open is Tuesday 09:00.
    const from = tashkent(2026, 5, 3, 12, 0); // Sunday 12:00
    const next = shopHours.nextOpenAt(sh, from);
    expect(next).not.toBeNull();
    // Convert back: should be Tuesday 09:00 Tashkent → UTC 04:00.
    const expected = tashkent(2026, 5, 5, 9, 0);
    expect(next.getTime()).toBe(expected.getTime());
  });
});

describe('PUT /api/shops/:id/working-hours', () => {
  test('owner can replace schedule', async () => {
    const items = [];
    for (let dow = 0; dow < 7; dow++) {
      items.push({ dayOfWeek: dow, startsAt: '08:00', endsAt: '20:00', isClosed: false });
    }
    const res = await request(ctx.app)
      .put(`/api/shops/${shop.id}/working-hours`)
      .set('Authorization', owner.auth)
      .send(items);
    expect(res.status).toBe(200);
    expect(res.body.items.length).toBe(7);
  });

  test('non-owner forbidden', async () => {
    const res = await request(ctx.app)
      .put(`/api/shops/${shop.id}/working-hours`)
      .set('Authorization', buyer.auth)
      .send([{ dayOfWeek: 0, startsAt: '08:00', endsAt: '20:00', isClosed: false }]);
    expect(res.status).toBe(403);
  });

  test('rejects invalid time format', async () => {
    const res = await request(ctx.app)
      .put(`/api/shops/${shop.id}/working-hours`)
      .set('Authorization', owner.auth)
      .send([{ dayOfWeek: 0, startsAt: '99:99', endsAt: '20:00', isClosed: false }]);
    expect(res.status).toBe(400);
  });

  test('public GET returns the schedule', async () => {
    const res = await request(ctx.app)
      .get(`/api/shops/${shop.id}/working-hours`);
    expect(res.status).toBe(200);
    expect(res.body.items.length).toBe(7);
  });
});

describe('order create — closed-shop guard', () => {
  test('rejects 400 with code shop_closed when closed and no scheduledFor', async () => {
    // Replace schedule with all-day closed.
    await ctx.prisma.shopWorkingHours.deleteMany({ where: { shopId: shop.id } });
    for (let dow = 0; dow < 7; dow++) {
      await ctx.prisma.shopWorkingHours.create({
        data: {
          shopId: shop.id, dayOfWeek: dow,
          startsAt: '00:00', endsAt: '00:00', isClosed: true,
        },
      });
    }
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        items: [{ productId: product.id, quantity: 1 }],
        deliveryAddress: '1 Test St',
        deliveryLat: 41.32, deliveryLng: 69.22,
        paymentMethod: 'cash',
      });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('shop_closed');
  });

  test('accepts when scheduledFor is set', async () => {
    const future = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        items: [{ productId: product.id, quantity: 1 }],
        deliveryAddress: '1 Test St',
        deliveryLat: 41.32, deliveryLng: 69.22,
        paymentMethod: 'cash',
        scheduledFor: future,
      });
    expect(res.status).toBe(201);
  });

  test('estimate exposes shopOpen flag without rejecting', async () => {
    const res = await request(ctx.app)
      .post('/api/orders/estimate')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        address: { lat: 41.32, lng: 69.22 },
        items: [{ productId: product.id, quantity: 1 }],
      });
    expect(res.status).toBe(200);
    expect(res.body.shopOpen).toBe(false);
    expect(res.body.currency).toBe('UZS');
  });
});
