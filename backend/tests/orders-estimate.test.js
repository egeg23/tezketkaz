// Integration tests for POST /api/orders/estimate.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb, createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let buyer;
let owner;
let shop;
let product;

const BIG_SQUARE = [
  [41.20, 69.10],
  [41.20, 69.30],
  [41.40, 69.30],
  [41.40, 69.10],
];

beforeAll(async () => {
  ctx = await setupTestDb('orders-estimate');
  owner = await createUser(ctx.prisma, { name: 'Owner', isShop: true });
  buyer = await createUser(ctx.prisma, { name: 'Buyer' });
  shop = await createShopWithOwner(ctx.prisma, owner.user);
  // Update shop coordinates and set min order
  shop = await ctx.prisma.shop.update({
    where: { id: shop.id },
    data: { lat: 41.30, lng: 69.20, vertical: 'grocery' },
  });
  product = await createProduct(ctx.prisma, shop.id, { price: 25000 });
  await ctx.prisma.deliveryZone.create({
    data: {
      shopId: shop.id,
      name: 'Center',
      polygon: JSON.stringify(BIG_SQUARE),
      baseFee: 12000, perKmFee: 2000, freeKm: 0, minOrder: 30000,
    },
  });
});

afterAll(async () => {
  await teardownTestDb(ctx);
});

describe('POST /api/orders/estimate', () => {
  test('returns full breakdown when in zone', async () => {
    const res = await request(ctx.app)
      .post('/api/orders/estimate')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        address: { lat: 41.32, lng: 69.22, fullAddress: '1 Test St' },
        items: [{ productId: product.id, quantity: 2 }],
      });
    expect(res.status).toBe(200);
    expect(res.body.subtotal).toBe(50000);
    expect(res.body.deliveryFee).toBeGreaterThanOrEqual(12000);
    // Phase 7 — VAT (12% in UZ) is added on top of subtotal-discount.
    // total = subtotal + deliveryFee - discount + taxAmount.
    expect(res.body.taxAmount).toBe(Math.round(res.body.subtotal * res.body.taxRate));
    expect(res.body.total).toBe(
      res.body.subtotal + res.body.deliveryFee - res.body.discount + res.body.taxAmount,
    );
    expect(res.body.minOrder).toBe(30000);
    expect(res.body.minOrderMet).toBe(true);
    expect(res.body.zoneId).toBeTruthy();
    expect(res.body.distanceKm).toBeGreaterThan(0);
    expect(res.body.etaMinutes).toBeGreaterThan(0);
    expect(res.body.surgeFactor).toBe(1.0);
    expect(res.body.items).toHaveLength(1);
    expect(res.body.items[0].productId).toBe(product.id);
    expect(res.body.items[0].unitPrice).toBe(25000);
    expect(res.body.items[0].total).toBe(50000);
  });

  test('out-of-zone returns 400', async () => {
    const res = await request(ctx.app)
      .post('/api/orders/estimate')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        address: { lat: 39.0, lng: 66.0, fullAddress: 'Samarkand' },
        items: [{ productId: product.id, quantity: 1 }],
      });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('out_of_zone');
  });

  test('subtotal below minOrder → 200 with minOrderMet:false', async () => {
    // Single product = 25000, minOrder = 30000
    const res = await request(ctx.app)
      .post('/api/orders/estimate')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        address: { lat: 41.31, lng: 69.21, fullAddress: 'X' },
        items: [{ productId: product.id, quantity: 1 }],
      });
    expect(res.status).toBe(200);
    expect(res.body.subtotal).toBe(25000);
    expect(res.body.minOrder).toBe(30000);
    expect(res.body.minOrderMet).toBe(false);
  });

  test('rejects missing address coords', async () => {
    const res = await request(ctx.app)
      .post('/api/orders/estimate')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        address: { fullAddress: 'no coords' },
        items: [{ productId: product.id, quantity: 1 }],
      });
    expect(res.status).toBe(400);
  });

  test('does not write any order', async () => {
    const before = await ctx.prisma.order.count();
    await request(ctx.app)
      .post('/api/orders/estimate')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        address: { lat: 41.32, lng: 69.22 },
        items: [{ productId: product.id, quantity: 1 }],
      });
    const after = await ctx.prisma.order.count();
    expect(after).toBe(before);
  });
});
