// Phase 6.9 — tipping endpoint.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let buyer;
let buyerB;
let courier;
let owner;
let shop;
let product;

beforeAll(async () => {
  ctx = await setupTestDb('tipping');
  owner = await createUser(ctx.prisma, { isShop: true });
  buyer = await createUser(ctx.prisma);
  buyerB = await createUser(ctx.prisma);
  courier = await createUser(ctx.prisma, { isCourier: true, courierStatus: 'approved' });
  shop = await createShopWithOwner(ctx.prisma, owner.user);
  product = await createProduct(ctx.prisma, shop.id, { price: 50000 });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makeMethod(userAuth, opts = {}) {
  const res = await request(ctx.app)
    .post('/api/payment-methods/me/confirm')
    .set('Authorization', userAuth)
    .send({
      provider: opts.provider || 'click',
      mockToken: opts.token || 'mock_click_xxx',
      last4: '4242',
      brand: 'visa',
    });
  return res.body.method;
}

async function makeDeliveredOrder({ buyerId, paymentMethodId = null, total = 100000 } = {}) {
  return ctx.prisma.order.create({
    data: {
      buyerId,
      customerName: 'X', customerPhone: '+998999',
      shopId: shop.id,
      courierId: courier.user.id,
      deliveryAddress: 'addr', paymentMethod: 'click',
      paymentMethodId,
      subtotal: total, total, courierReward: 12000,
      isPaid: true, status: 'delivered', deliveredAt: new Date(),
      currency: 'UZS',
    },
  });
}

describe('POST /api/orders/:id/tip', () => {
  test('tip on delivered order with saved method succeeds and accumulates', async () => {
    const method = await makeMethod(buyer.auth);
    const order = await makeDeliveredOrder({ buyerId: buyer.user.id, paymentMethodId: method.id });

    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/tip`)
      .set('Authorization', buyer.auth)
      .send({ amount: 10000 });
    expect(res.status).toBe(200);
    expect(res.body.order.tipAmount).toBe(10000);
    expect(res.body.order.tipPaidAt).toBeTruthy();

    // Second tip accumulates.
    const r2 = await request(ctx.app)
      .post(`/api/orders/${order.id}/tip`)
      .set('Authorization', buyer.auth)
      .send({ amount: 5000 });
    expect(r2.status).toBe(200);
    expect(r2.body.order.tipAmount).toBe(15000);
  });

  test('tip on non-delivered → 400', async () => {
    const method = await makeMethod(buyer.auth, { token: 'mock_click_x2' });
    const order = await ctx.prisma.order.create({
      data: {
        buyerId: buyer.user.id,
        customerName: 'X', customerPhone: '+998888',
        shopId: shop.id, courierId: courier.user.id,
        deliveryAddress: 'addr', paymentMethod: 'click',
        paymentMethodId: method.id,
        subtotal: 50000, total: 50000, courierReward: 10000,
        status: 'inDelivery', currency: 'UZS',
      },
    });
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/tip`)
      .set('Authorization', buyer.auth)
      .send({ amount: 5000 });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('order_not_delivered');
  });

  test('tip > 50% of total → 400', async () => {
    const method = await makeMethod(buyer.auth, { token: 'mock_click_x3' });
    const order = await makeDeliveredOrder({
      buyerId: buyer.user.id, paymentMethodId: method.id, total: 20000,
    });
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/tip`)
      .set('Authorization', buyer.auth)
      .send({ amount: 11000 });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('tip_too_large');
  });

  test('tip without paymentMethodId or saved method → 400', async () => {
    const order = await makeDeliveredOrder({ buyerId: buyer.user.id, paymentMethodId: null, total: 50000 });
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/tip`)
      .set('Authorization', buyer.auth)
      .send({ amount: 5000 });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('payment_method_required');
  });

  test('cannot tip another user\'s order', async () => {
    const method = await makeMethod(buyer.auth, { token: 'mock_click_x4' });
    const order = await makeDeliveredOrder({ buyerId: buyer.user.id, paymentMethodId: method.id });
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/tip`)
      .set('Authorization', buyerB.auth)
      .send({ amount: 1000 });
    expect(res.status).toBe(403);
  });

  test('invalid amount → 400', async () => {
    const method = await makeMethod(buyer.auth, { token: 'mock_click_x5' });
    const order = await makeDeliveredOrder({ buyerId: buyer.user.id, paymentMethodId: method.id });
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/tip`)
      .set('Authorization', buyer.auth)
      .send({ amount: 0 });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('invalid_amount');
  });
});
