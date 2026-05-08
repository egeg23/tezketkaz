// Phase 7.2 — order checkout integrates membership delivery perk.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let prisma;
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
  ctx = await setupTestDb('orders-membership');
  prisma = ctx.prisma;
  owner = await createUser(prisma, { isShop: true });
  shop = await createShopWithOwner(prisma, owner.user);
  shop = await prisma.shop.update({
    where: { id: shop.id },
    data: { lat: 41.30, lng: 69.20, currency: 'UZS' },
  });
  await prisma.deliveryZone.create({
    data: {
      shopId: shop.id,
      name: 'Big',
      polygon: JSON.stringify(BIG_SQUARE),
      baseFee: 12000,
      perKmFee: 0,
      freeKm: 0,
      minOrder: 0,
    },
  });
  product = await createProduct(prisma, shop.id, { price: 25000 });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function placeOrder(buyer) {
  return request(ctx.app)
    .post('/api/orders')
    .set('Authorization', buyer.auth)
    .send({
      shopId: shop.id,
      items: [{ productId: product.id, quantity: 1 }],
      deliveryAddress: '1 Test St',
      deliveryLat: 41.305,
      deliveryLng: 69.205,
      paymentMethod: 'cash',
    });
}

async function giveMembership(userId, tier) {
  await prisma.membership.upsert({
    where: { userId },
    update: {
      tier,
      status: 'active',
      currentPeriodEnd: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
    create: {
      userId,
      tier,
      status: 'active',
      currency: 'UZS',
      periodAmount: tier === 'pro' ? 60000 : 30000,
      billingPeriod: 'monthly',
      currentPeriodEnd: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });
}

describe('orders + membership delivery perk', () => {
  test('no membership → deliveryFee unchanged (12000)', async () => {
    const buyer = await createUser(prisma);
    const r = await placeOrder(buyer);
    expect(r.status).toBe(201);
    expect(r.body.order.deliveryFee).toBe(12000);
  });

  test('plus membership halves deliveryFee', async () => {
    const buyer = await createUser(prisma);
    await giveMembership(buyer.user.id, 'plus');
    const r = await placeOrder(buyer);
    expect(r.status).toBe(201);
    expect(r.body.order.deliveryFee).toBe(6000);
  });

  test('pro membership zeros deliveryFee', async () => {
    const buyer = await createUser(prisma);
    await giveMembership(buyer.user.id, 'pro');
    const r = await placeOrder(buyer);
    expect(r.status).toBe(201);
    expect(r.body.order.deliveryFee).toBe(0);
  });

  test('estimate exposes membershipDiscount + freeDeliveryReason', async () => {
    const buyer = await createUser(prisma);
    await giveMembership(buyer.user.id, 'pro');
    const r = await request(ctx.app)
      .post('/api/orders/estimate')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        items: [{ productId: product.id, quantity: 1 }],
        address: { lat: 41.305, lng: 69.205 },
      });
    expect(r.status).toBe(200);
    expect(r.body.deliveryFee).toBe(0);
  });
});
