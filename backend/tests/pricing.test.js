// Unit tests for backend/src/services/pricing.js. Exercises zone selection,
// fee composition, freeKm, surge factors, and out-of-zone behavior.

const { setupTestDb, teardownTestDb } = require('./helpers/db');

let ctx;
let computeDelivery;
let shop;

// Polygon ~10 km square around (41.30, 69.20). Tashkent area.
const BIG_SQUARE = [
  [41.20, 69.10],
  [41.20, 69.30],
  [41.40, 69.30],
  [41.40, 69.10],
];

// Inner small box used to test sortOrder preference (must lie inside BIG_SQUARE).
const SMALL_SQUARE = [
  [41.28, 69.18],
  [41.28, 69.22],
  [41.32, 69.22],
  [41.32, 69.18],
];

beforeAll(async () => {
  ctx = await setupTestDb('pricing');
  ({ computeDelivery } = require('../src/services/pricing'));

  shop = await ctx.prisma.shop.create({
    data: {
      name: 'Pricing Shop',
      address: 'X',
      lat: 41.30,
      lng: 69.20,
      vertical: 'grocery',
    },
  });
});

afterAll(async () => {
  await teardownTestDb(ctx);
});

describe('computeDelivery', () => {
  beforeEach(async () => {
    await ctx.prisma.pricingRule.deleteMany();
    await ctx.prisma.deliveryZone.deleteMany();
  });

  test('outside all zones → outOfZone:true', async () => {
    await ctx.prisma.deliveryZone.create({
      data: {
        shopId: shop.id,
        name: 'Tiny',
        polygon: JSON.stringify([
          [41.30, 69.20],
          [41.30, 69.21],
          [41.31, 69.21],
          [41.31, 69.20],
        ]),
        baseFee: 10000, perKmFee: 2000, freeKm: 0,
      },
    });
    const r = await computeDelivery(ctx.prisma, {
      shopId: shop.id, destLat: 39.0, destLng: 66.0, // Samarkand
    });
    expect(r.outOfZone).toBe(true);
    expect(r.zoneId).toBeNull();
  });

  test('inside zone → returns fee + distance + eta', async () => {
    await ctx.prisma.deliveryZone.create({
      data: {
        shopId: shop.id,
        name: 'Big',
        polygon: JSON.stringify(BIG_SQUARE),
        baseFee: 12000, perKmFee: 2000, freeKm: 0, minOrder: 30000,
      },
    });
    // Destination ~about 0.05° lat (~5.55 km) north
    const r = await computeDelivery(ctx.prisma, {
      shopId: shop.id, destLat: 41.35, destLng: 69.20,
    });
    expect(r.outOfZone).toBe(false);
    expect(r.zoneId).toBeTruthy();
    expect(r.distanceKm).toBeGreaterThan(4);
    expect(r.distanceKm).toBeLessThan(7);
    expect(r.deliveryFee).toBeGreaterThan(12000);
    expect(r.eta).toBeGreaterThan(15);
    expect(r.minOrder).toBe(30000);
    expect(r.surgeFactor).toBe(1.0);
  });

  test('freeKm: distance < freeKm → fee == baseFee', async () => {
    await ctx.prisma.deliveryZone.create({
      data: {
        shopId: shop.id,
        name: 'Free near',
        polygon: JSON.stringify(BIG_SQUARE),
        baseFee: 9000, perKmFee: 2000, freeKm: 50,
      },
    });
    const r = await computeDelivery(ctx.prisma, {
      shopId: shop.id, destLat: 41.305, destLng: 69.205,
    });
    expect(r.outOfZone).toBe(false);
    expect(r.deliveryFee).toBe(9000);
  });

  test('multiple matching zones: lowest sortOrder wins', async () => {
    await ctx.prisma.deliveryZone.create({
      data: {
        shopId: shop.id,
        name: 'Outer (high sort)',
        polygon: JSON.stringify(BIG_SQUARE),
        baseFee: 30000, perKmFee: 5000, freeKm: 0,
        sortOrder: 10,
      },
    });
    const inner = await ctx.prisma.deliveryZone.create({
      data: {
        shopId: shop.id,
        name: 'Inner (low sort)',
        polygon: JSON.stringify(SMALL_SQUARE),
        baseFee: 10000, perKmFee: 1000, freeKm: 0,
        sortOrder: 1,
      },
    });
    // Destination inside the inner box, also inside the outer box.
    const r = await computeDelivery(ctx.prisma, {
      shopId: shop.id, destLat: 41.30, destLng: 69.20,
    });
    expect(r.zoneId).toBe(inner.id);
    expect(r.baseFee).toBe(10000);
  });

  test('active surge rule multiplies fee', async () => {
    await ctx.prisma.deliveryZone.create({
      data: {
        shopId: shop.id,
        name: 'Z',
        polygon: JSON.stringify(BIG_SQUARE),
        baseFee: 10000, perKmFee: 0, freeKm: 0,
      },
    });
    const now = new Date();
    await ctx.prisma.pricingRule.create({
      data: {
        vertical: 'grocery',
        surgeFactor: 1.5,
        reason: 'rain',
        validFrom: new Date(now.getTime() - 3600 * 1000),
        validUntil: new Date(now.getTime() + 3600 * 1000),
        isActive: true,
      },
    });
    const r = await computeDelivery(ctx.prisma, {
      shopId: shop.id, destLat: 41.305, destLng: 69.205,
    });
    expect(r.surgeFactor).toBe(1.5);
    expect(r.surgeReason).toBe('rain');
    expect(r.deliveryFee).toBe(15000);
  });

  test('expired surge rule is ignored', async () => {
    await ctx.prisma.deliveryZone.create({
      data: {
        shopId: shop.id,
        name: 'Z',
        polygon: JSON.stringify(BIG_SQUARE),
        baseFee: 10000, perKmFee: 0, freeKm: 0,
      },
    });
    const now = new Date();
    await ctx.prisma.pricingRule.create({
      data: {
        vertical: 'grocery',
        surgeFactor: 2.0,
        reason: 'old_promo',
        validFrom: new Date(now.getTime() - 7200 * 1000),
        validUntil: new Date(now.getTime() - 3600 * 1000),
        isActive: true,
      },
    });
    const r = await computeDelivery(ctx.prisma, {
      shopId: shop.id, destLat: 41.305, destLng: 69.205,
    });
    expect(r.surgeFactor).toBe(1.0);
    expect(r.surgeReason).toBeNull();
    expect(r.deliveryFee).toBe(10000);
  });
});
