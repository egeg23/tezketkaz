// End-to-end happy path:
//   OTP → verify → tokens → create address → list shops → list products →
//   estimate → place order → shop accepts → courier accepts → pickup →
//   in_delivery → delivered → buyer reviews → assertions.
//
// This walks the real route handlers (no mocking of business logic). Sockets
// + push are replaced with no-op io. Redis is disabled (in-memory shim from
// `lib/redis.js`). BullMQ queues are no-ops in this mode, so dispatch is
// driven by hitting `/orders/:id/courier/accept` directly.

const request = require('supertest');
const express = require('express');

const { setupTestDb, teardownTestDb, createUser } = require('./helpers/db');

let ctx;
let prisma;
let app;

let buyer;          // { user, token, auth } after OTP verify
let shopOwner;
let courier;
let shop;
let product;

function authHeader(token) { return `Bearer ${token}`; }

beforeAll(async () => {
  ctx = await setupTestDb('e2e-happy-path');
  prisma = ctx.prisma;

  // Build a test app that includes /api/auth (helpers/db.js doesn't mount it
  // because most tests don't need OTP). Reuse ctx.app's already-configured
  // routes for the rest by mounting auth onto ctx.app directly.
  app = ctx.app;
  app.use('/api/auth', require('../src/routes/auth'));
  app.use('/api/couriers', require('../src/routes/couriers'));
  // courier-shifts declares absolute paths under /api/couriers/me/...
  app.use('/api', require('../src/routes/courier-shifts'));

  // Seed shop + courier; we reuse the OTP flow only for the buyer (the spec
  // requirement). Shop owner + courier are created directly because their
  // roles need DB-side flags that OTP-signup wouldn't set.
  shopOwner = await createUser(prisma, { isShop: true, name: 'Owner' });
  shop = await prisma.shop.create({
    data: {
      name: 'E2E Shop',
      address: '1 Test St',
      lat: 41.31,
      lng: 69.24,
      vertical: 'grocery',
      isActive: true,
    },
  });
  await prisma.shopMember.create({
    data: { userId: shopOwner.user.id, shopId: shop.id, role: 'owner' },
  });
  await prisma.deliveryZone.create({
    data: {
      shopId: shop.id,
      name: 'All',
      polygon: JSON.stringify([
        [41.20, 69.10], [41.20, 69.40], [41.40, 69.40], [41.40, 69.10],
      ]),
      baseFee: 12000, perKmFee: 2000, freeKm: 0, minOrder: 10000,
    },
  });
  product = await prisma.product.create({
    data: {
      shopId: shop.id,
      name: 'Plov',
      nameUz: 'Plov',
      price: 35000,
      unit: 'шт',
      category: 'food',
      imageUrl: 'https://example.com/x.jpg',
      isAvailable: true,
    },
  });

  courier = await createUser(prisma, { isBuyer: false, name: 'Courier' });
  await prisma.user.update({
    where: { id: courier.user.id },
    data: { isCourier: true, courierStatus: 'approved' },
  });
}, 60000);

afterAll(async () => {
  await teardownTestDb(ctx);
});

describe('e2e happy path', () => {
  let buyerAccess;
  let buyerRefresh;
  let buyerUser;
  let addressId;
  let orderId;

  test('1. OTP send + verify yields tokens', async () => {
    const phone = '+998901234567';
    const sendRes = await request(app)
      .post('/api/auth/send-otp')
      .send({ phone });
    expect(sendRes.status).toBe(200);
    // dev mode → fixed code
    expect(sendRes.body.devCode).toBe('123456');

    const verifyRes = await request(app)
      .post('/api/auth/verify-otp')
      .send({ phone, code: '123456' });
    expect(verifyRes.status).toBe(200);
    expect(verifyRes.body.accessToken).toBeTruthy();
    expect(verifyRes.body.refreshToken).toBeTruthy();
    expect(verifyRes.body.user.phone).toBe(phone);

    buyerAccess = verifyRes.body.accessToken;
    buyerRefresh = verifyRes.body.refreshToken;
    buyerUser = verifyRes.body.user;
    buyer = { user: buyerUser, token: buyerAccess, auth: authHeader(buyerAccess) };
    expect(buyerRefresh.length).toBeGreaterThan(20);
  });

  test('2. Create delivery address', async () => {
    const res = await request(app)
      .post('/api/users/addresses')
      .set('Authorization', buyer.auth)
      .send({
        label: 'Home',
        fullAddress: 'Ул. Ширин 12',
        lat: 41.32, lng: 69.22,
        isDefault: true,
      });
    expect(res.status).toBe(201);
    expect(res.body.address.id).toBeTruthy();
    addressId = res.body.address.id;
  });

  test('3. List shops with vertical filter', async () => {
    const res = await request(app)
      .get('/api/shops?vertical=grocery&lat=41.32&lng=69.22&radiusKm=20');
    expect(res.status).toBe(200);
    const list = res.body.items || res.body.shops;
    expect(Array.isArray(list)).toBe(true);
    expect(list.find((s) => s.id === shop.id)).toBeTruthy();
  });

  test('4. List products of that shop', async () => {
    const res = await request(app).get(`/api/products?shopId=${shop.id}`);
    expect(res.status).toBe(200);
    const items = res.body.items || res.body.products || res.body;
    const list = Array.isArray(items) ? items : (items.items || []);
    expect(list.find((p) => p.id === product.id)).toBeTruthy();
  });

  test('5. POST /orders/estimate', async () => {
    const res = await request(app)
      .post('/api/orders/estimate')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        address: { lat: 41.32, lng: 69.22, fullAddress: '1 Test' },
        items: [{ productId: product.id, quantity: 2 }],
      });
    expect(res.status).toBe(200);
    expect(res.body.subtotal).toBe(70000);
    expect(res.body.total).toBeGreaterThan(0);
    expect(res.body.minOrderMet).toBe(true);
  });

  test('6. POST /orders creates order in pending', async () => {
    const res = await request(app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        items: [{ productId: product.id, quantity: 2 }],
        deliveryAddress: 'Ул. Ширин 12',
        deliveryLat: 41.32, deliveryLng: 69.22,
        paymentMethod: 'cash',
      });
    expect(res.status).toBe(201);
    expect(res.body.order.status).toBe('pending');
    expect(res.body.order.total).toBeGreaterThan(0);
    orderId = res.body.order.id;
  });

  test('7a. Shop accepts (collecting) and marks ready', async () => {
    const accept = await request(app)
      .post(`/api/orders/${orderId}/shop/accept`)
      .set('Authorization', shopOwner.auth)
      .send({});
    expect(accept.status).toBe(200);
    expect(accept.body.order.status).toBe('collecting');
    expect(accept.body.order.orderNumber).toBeTruthy();

    const ready = await request(app)
      .post(`/api/orders/${orderId}/shop/ready`)
      .set('Authorization', shopOwner.auth)
      .send({});
    expect(ready.status).toBe(200);
    expect(ready.body.order.status).toBe('readyForPickup');
  });

  test('7b. Courier accepts the order (direct accept; bypasses dispatch offers)', async () => {
    const res = await request(app)
      .post(`/api/orders/${orderId}/courier/accept`)
      .set('Authorization', courier.auth)
      .send({});
    expect(res.status).toBe(200);
    expect(res.body.order.courierId).toBe(courier.user.id);
    expect(res.body.order.status).toBe('courierAssigned');
  });

  test('8. Courier transitions: pickup → start → complete (delivered)', async () => {
    const ord = await prisma.order.findUnique({ where: { id: orderId } });
    const pickup = await request(app)
      .post(`/api/orders/${orderId}/courier/pickup`)
      .set('Authorization', courier.auth)
      .send({ orderNumber: ord.orderNumber });
    expect(pickup.status).toBe(200);
    expect(pickup.body.order.status).toBe('pickedUp');

    const start = await request(app)
      .post(`/api/orders/${orderId}/courier/start`)
      .set('Authorization', courier.auth)
      .send({});
    expect(start.status).toBe(200);
    expect(start.body.order.status).toBe('inDelivery');

    const complete = await request(app)
      .post(`/api/orders/${orderId}/courier/complete`)
      .set('Authorization', courier.auth)
      .send({});
    expect(complete.status).toBe(200);
    expect(complete.body.order.status).toBe('delivered');
    expect(complete.body.order.deliveredAt).toBeTruthy();
  });

  test('9. Buyer creates SHOP review', async () => {
    const res = await request(app)
      .post(`/api/orders/${orderId}/reviews`)
      .set('Authorization', buyer.auth)
      .send({
        targetType: 'SHOP',
        targetId: shop.id,
        rating: 5,
        text: 'Great service!',
      });
    expect(res.status).toBe(201);
    expect(res.body.review.rating).toBe(5);
  });

  test('10. Final state: delivered, loyalty > 0, shop rating updated', async () => {
    const order = await prisma.order.findUnique({ where: { id: orderId } });
    expect(order.status).toBe('delivered');

    const account = await prisma.loyaltyAccount.findUnique({
      where: { userId: buyer.user.id },
    });
    expect(account).toBeTruthy();
    expect(account.points).toBeGreaterThan(0);

    const updatedShop = await prisma.shop.findUnique({ where: { id: shop.id } });
    expect(updatedShop.rating).toBeGreaterThan(0);

    // address persisted
    const addr = await prisma.address.findUnique({ where: { id: addressId } });
    expect(addr).toBeTruthy();
  });
});
