// Phase 13.2.5 — courier delivery-photo proof.
//
// Covers:
//   1. Happy path: courier uploads photo → status flips to `delivered`,
//      deliveryPhotoUrl/At persist.
//   2. Missing photo → 400 `delivery_photo_required`.
//   3. Wrong courier (not assigned) → 403.
//   4. Order not in inDelivery/arrivedAtCustomer → 409 `invalid_status`.
//   5. arrivedAtCustomer is also a valid pre-state.
//   6. GET /orders/:id surfaces `deliveryPhotoUrl` after upload.
//   7. Buyer can see own order's photo via GET /orders/:id.
//   8. A different buyer CANNOT see another user's order (403).

const request = require('supertest');
const path = require('path');
const fs = require('fs');
const os = require('os');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner,
} = require('./helpers/db');

let ctx;
let prisma;
let shop;
let buyer;
let buyerB;
let courier;
let otherCourier;

beforeAll(async () => {
  ctx = await setupTestDb('delivery-photo');
  prisma = ctx.prisma;

  const owner = await createUser(prisma, { isShop: true });
  buyer = await createUser(prisma);
  buyerB = await createUser(prisma);
  courier = await createUser(prisma, { isCourier: true, courierStatus: 'approved' });
  otherCourier = await createUser(prisma, { isCourier: true, courierStatus: 'approved' });
  shop = await createShopWithOwner(prisma, owner.user);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

// Smallest possible valid PNG (1x1 transparent), used as upload payload.
const PNG_1x1 = Buffer.from(
  '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4'
  + '890000000d49444154789c63f8cf00000000010001036e0a0c0000000049454e44ae426082',
  'hex',
);

function tmpPng() {
  const p = path.join(os.tmpdir(), `delivery-${Date.now()}-${Math.random().toString(36).slice(2)}.png`);
  fs.writeFileSync(p, PNG_1x1);
  return p;
}

async function makeOrder({ status = 'inDelivery', courierId = courier.user.id, buyerId = buyer.user.id } = {}) {
  return prisma.order.create({
    data: {
      buyerId,
      customerName: 'X', customerPhone: '+998111',
      shopId: shop.id,
      courierId,
      deliveryAddress: '1 Test St', paymentMethod: 'cash',
      subtotal: 50000, total: 50000, courierReward: 12000,
      isPaid: false, status, currency: 'UZS',
    },
  });
}

describe('POST /api/orders/:id/courier/delivered', () => {
  test('happy path: photo uploaded → order delivered with deliveryPhoto fields set', async () => {
    const order = await makeOrder();
    const file = tmpPng();
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/courier/delivered`)
      .set('Authorization', courier.auth)
      .attach('photo', file);
    fs.unlinkSync(file);

    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('delivered');
    expect(res.body.order.deliveredAt).toBeTruthy();
    expect(res.body.order.deliveryPhotoUrl).toMatch(/delivery-photos\//);
    expect(res.body.order.deliveryPhotoAt).toBeTruthy();

    const stored = await prisma.order.findUnique({ where: { id: order.id } });
    expect(stored.status).toBe('delivered');
    expect(stored.deliveryPhotoUrl).toBeTruthy();
    expect(stored.deliveryPhotoAt).toBeTruthy();
  });

  test('arrivedAtCustomer is also a valid pre-delivered state', async () => {
    const order = await makeOrder({ status: 'arrivedAtCustomer' });
    const file = tmpPng();
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/courier/delivered`)
      .set('Authorization', courier.auth)
      .attach('photo', file);
    fs.unlinkSync(file);

    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('delivered');
  });

  test('missing photo → 400 delivery_photo_required', async () => {
    const order = await makeOrder();
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/courier/delivered`)
      .set('Authorization', courier.auth);
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('delivery_photo_required');

    // Order should NOT have flipped status.
    const stored = await prisma.order.findUnique({ where: { id: order.id } });
    expect(stored.status).toBe('inDelivery');
    expect(stored.deliveryPhotoUrl).toBeNull();
  });

  test('not the assigned courier → 403', async () => {
    const order = await makeOrder(); // assigned to `courier`
    const file = tmpPng();
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/courier/delivered`)
      .set('Authorization', otherCourier.auth)
      .attach('photo', file);
    fs.unlinkSync(file);

    expect(res.status).toBe(403);
    const stored = await prisma.order.findUnique({ where: { id: order.id } });
    expect(stored.status).toBe('inDelivery');
  });

  test('wrong status (pickedUp) → 409 invalid_status', async () => {
    const order = await makeOrder({ status: 'pickedUp' });
    const file = tmpPng();
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/courier/delivered`)
      .set('Authorization', courier.auth)
      .attach('photo', file);
    fs.unlinkSync(file);

    expect(res.status).toBe(409);
    expect(res.body.error).toBe('invalid_status');
    const stored = await prisma.order.findUnique({ where: { id: order.id } });
    expect(stored.status).toBe('pickedUp');
    expect(stored.deliveryPhotoUrl).toBeNull();
  });
});

describe('GET /api/orders/:id with delivery photo', () => {
  test('after upload, GET surfaces deliveryPhotoUrl', async () => {
    const order = await makeOrder();
    const file = tmpPng();
    await request(ctx.app)
      .post(`/api/orders/${order.id}/courier/delivered`)
      .set('Authorization', courier.auth)
      .attach('photo', file);
    fs.unlinkSync(file);

    const res = await request(ctx.app)
      .get(`/api/orders/${order.id}`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.order.deliveryPhotoUrl).toMatch(/delivery-photos\//);
    expect(res.body.order.deliveryPhotoAt).toBeTruthy();
  });

  test('buyer can see their own order\'s photo', async () => {
    const order = await makeOrder();
    const file = tmpPng();
    await request(ctx.app)
      .post(`/api/orders/${order.id}/courier/delivered`)
      .set('Authorization', courier.auth)
      .attach('photo', file);
    fs.unlinkSync(file);

    const res = await request(ctx.app)
      .get(`/api/orders/${order.id}`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.order.buyerId).toBe(buyer.user.id);
    expect(res.body.order.deliveryPhotoUrl).toBeTruthy();
  });

  test('a different buyer CANNOT see another user\'s order photo (403)', async () => {
    const order = await makeOrder({ buyerId: buyer.user.id });
    const file = tmpPng();
    await request(ctx.app)
      .post(`/api/orders/${order.id}/courier/delivered`)
      .set('Authorization', courier.auth)
      .attach('photo', file);
    fs.unlinkSync(file);

    const res = await request(ctx.app)
      .get(`/api/orders/${order.id}`)
      .set('Authorization', buyerB.auth);
    expect(res.status).toBe(403);
  });
});
