// Phase 6.1 — order create with saved payment method (tokenized).

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let buyer;
let buyerB;
let owner;
let shop;
let product;

beforeAll(async () => {
  ctx = await setupTestDb('orders-saved-pm');
  owner = await createUser(ctx.prisma, { isShop: true });
  buyer = await createUser(ctx.prisma);
  buyerB = await createUser(ctx.prisma);
  shop = await createShopWithOwner(ctx.prisma, owner.user);
  shop = await ctx.prisma.shop.update({
    where: { id: shop.id },
    data: { lat: 41.30, lng: 69.20, currency: 'UZS' },
  });
  product = await createProduct(ctx.prisma, shop.id, { price: 25000 });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function saveMethodFor(auth) {
  const r = await request(ctx.app)
    .post('/api/payment-methods/me/confirm')
    .set('Authorization', auth)
    .send({
      provider: 'click',
      mockToken: 'mock_click_token',
      last4: '1111',
      brand: 'visa',
    });
  return r.body.method;
}

describe('POST /api/orders with paymentMethodId', () => {
  test('charges via mock token, marks isPaid=true, links method', async () => {
    const method = await saveMethodFor(buyer.auth);
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        items: [{ productId: product.id, quantity: 2 }],
        deliveryAddress: '1 Test St',
        paymentMethod: 'click',
        paymentMethodId: method.id,
      });
    expect(res.status).toBe(201);
    expect(res.body.order.isPaid).toBe(true);
    expect(res.body.order.paymentMethodId).toBe(method.id);
    // paymentRef set from the mock charge externalId.
    expect(res.body.order.paymentRef).toMatch(/^mock_click_charge_/);
    // Money envelope should be present alongside raw fields.
    expect(res.body.order.totalMoney).toBeTruthy();
    expect(res.body.order.totalMoney.currency).toBe('UZS');
    expect(res.body.order.currency).toBe('UZS');
  });

  test('using another user\'s method → 404 payment_method_not_found', async () => {
    const method = await saveMethodFor(buyer.auth);
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyerB.auth)
      .send({
        shopId: shop.id,
        items: [{ productId: product.id, quantity: 1 }],
        deliveryAddress: '1 Test St',
        paymentMethod: 'click',
        paymentMethodId: method.id,
      });
    expect(res.status).toBe(404);
    expect(res.body.error).toBe('payment_method_not_found');
  });

  test('soft-deleted method rejected', async () => {
    const method = await saveMethodFor(buyer.auth);
    await request(ctx.app)
      .delete(`/api/payment-methods/${method.id}`)
      .set('Authorization', buyer.auth);
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        items: [{ productId: product.id, quantity: 1 }],
        deliveryAddress: '1 Test St',
        paymentMethod: 'click',
        paymentMethodId: method.id,
      });
    expect(res.status).toBe(404);
  });

  test('without paymentMethodId — legacy flow still works (cash)', async () => {
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shop.id,
        items: [{ productId: product.id, quantity: 1 }],
        deliveryAddress: '1 Test St',
        paymentMethod: 'cash',
      });
    expect(res.status).toBe(201);
    expect(res.body.order.isPaid).toBe(false);
    expect(res.body.order.paymentMethodId).toBeNull();
  });
});
