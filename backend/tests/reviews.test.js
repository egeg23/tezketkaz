// Phase 3 reviews API integration tests.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let buyer, otherBuyer, courier;
let shop, product;

async function makeDeliveredOrder(prismaClient, opts = {}) {
  const order = await prismaClient.order.create({
    data: {
      buyerId: opts.buyerId || buyer.user.id,
      customerName: 'Test',
      customerPhone: '+998900000000',
      shopId: opts.shopId || shop.id,
      courierId: opts.courierId || courier.user.id,
      deliveryAddress: '1 Test',
      paymentMethod: 'cash',
      isPaid: false,
      subtotal: 30000, total: 30000, deliveryFee: 0,
      status: opts.status || 'delivered',
      deliveredAt: new Date(),
      items: {
        create: [{
          productId: product.id,
          productName: product.name,
          quantity: 1,
          price: 30000, basePrice: 30000, total: 30000,
        }],
      },
    },
    include: { items: true },
  });
  return order;
}

beforeAll(async () => {
  ctx = await setupTestDb('reviews');
  const owner = await createUser(ctx.prisma, { isShop: true });
  buyer = await createUser(ctx.prisma);
  otherBuyer = await createUser(ctx.prisma);
  courier = await createUser(ctx.prisma, { isCourier: true });
  // Mark courier approved by direct DB write.
  await ctx.prisma.user.update({
    where: { id: courier.user.id },
    data: { isCourier: true, courierStatus: 'approved' },
  });
  shop = await createShopWithOwner(ctx.prisma, owner.user);
  product = await createProduct(ctx.prisma, shop.id, { name: 'Pizza', price: 30000 });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('reviews', () => {
  test('buyer can review SHOP after delivery, aggregate updates', async () => {
    const order = await makeDeliveredOrder(ctx.prisma);
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/reviews`)
      .set('Authorization', buyer.auth)
      .send({ targetType: 'SHOP', targetId: shop.id, rating: 4, text: 'Good' });
    expect(res.status).toBe(201);
    expect(res.body.review.rating).toBe(4);

    const fresh = await ctx.prisma.shop.findUnique({ where: { id: shop.id } });
    expect(fresh.rating).toBeCloseTo(4, 5);
  });

  test('buyer can review COURIER and PRODUCT', async () => {
    const order = await makeDeliveredOrder(ctx.prisma);
    const c = await request(ctx.app)
      .post(`/api/orders/${order.id}/reviews`)
      .set('Authorization', buyer.auth)
      .send({ targetType: 'COURIER', targetId: courier.user.id, rating: 5 });
    expect(c.status).toBe(201);

    const p = await request(ctx.app)
      .post(`/api/orders/${order.id}/reviews`)
      .set('Authorization', buyer.auth)
      .send({ targetType: 'PRODUCT', targetId: product.id, rating: 3 });
    expect(p.status).toBe(201);

    const courierFresh = await ctx.prisma.user.findUnique({ where: { id: courier.user.id } });
    expect(courierFresh.rating).toBeCloseTo(5, 5);
  });

  test('cannot review on non-delivered order', async () => {
    const order = await makeDeliveredOrder(ctx.prisma, { status: 'inDelivery' });
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/reviews`)
      .set('Authorization', buyer.auth)
      .send({ targetType: 'SHOP', targetId: shop.id, rating: 4 });
    expect(res.status).toBe(400);
  });

  test('cannot review someone else\'s order', async () => {
    const order = await makeDeliveredOrder(ctx.prisma);
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/reviews`)
      .set('Authorization', otherBuyer.auth)
      .send({ targetType: 'SHOP', targetId: shop.id, rating: 5 });
    expect(res.status).toBe(403);
  });

  test('duplicate review returns 409', async () => {
    const order = await makeDeliveredOrder(ctx.prisma);
    const a = await request(ctx.app)
      .post(`/api/orders/${order.id}/reviews`)
      .set('Authorization', buyer.auth)
      .send({ targetType: 'SHOP', targetId: shop.id, rating: 5 });
    expect(a.status).toBe(201);
    const b = await request(ctx.app)
      .post(`/api/orders/${order.id}/reviews`)
      .set('Authorization', buyer.auth)
      .send({ targetType: 'SHOP', targetId: shop.id, rating: 4 });
    expect(b.status).toBe(409);
  });

  test('PATCH within 24h allowed; blocked after', async () => {
    const order = await makeDeliveredOrder(ctx.prisma);
    const post = await request(ctx.app)
      .post(`/api/orders/${order.id}/reviews`)
      .set('Authorization', buyer.auth)
      .send({ targetType: 'SHOP', targetId: shop.id, rating: 4 });
    expect(post.status).toBe(201);
    const id = post.body.review.id;

    const ok = await request(ctx.app)
      .patch(`/api/reviews/${id}`)
      .set('Authorization', buyer.auth)
      .send({ rating: 5, text: 'Updated' });
    expect(ok.status).toBe(200);
    expect(ok.body.review.rating).toBe(5);

    // Backdate the review by 25h.
    await ctx.prisma.review.update({
      where: { id },
      data: { createdAt: new Date(Date.now() - 25 * 60 * 60 * 1000) },
    });

    const blocked = await request(ctx.app)
      .patch(`/api/reviews/${id}`)
      .set('Authorization', buyer.auth)
      .send({ rating: 1 });
    expect(blocked.status).toBe(400);
  });

  test('GET /api/reviews lists by target', async () => {
    const res = await request(ctx.app)
      .get('/api/reviews')
      .query({ targetType: 'SHOP', targetId: shop.id });
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.reviews)).toBe(true);
    expect(res.body.reviews.length).toBeGreaterThan(0);
    const first = res.body.reviews[0];
    expect(first.reviewerName).toBeDefined();
    // No phone in the listing.
    expect(first.reviewerPhone).toBeUndefined();
  });
});
