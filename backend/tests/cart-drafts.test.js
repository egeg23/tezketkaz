// Phase 11 — multi-shop cart drafts.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let prisma;
let buyer;
let otherBuyer;
let shopA, shopB;
let prodA1, prodA2, prodB1;

beforeAll(async () => {
  ctx = await setupTestDb('cart-drafts');
  prisma = ctx.prisma;
  const ownerA = await createUser(prisma, { isShop: true });
  const ownerB = await createUser(prisma, { isShop: true });
  buyer = await createUser(prisma);
  otherBuyer = await createUser(prisma);
  shopA = await createShopWithOwner(prisma, ownerA.user);
  shopB = await createShopWithOwner(prisma, ownerB.user);
  prodA1 = await createProduct(prisma, shopA.id, { name: 'A1', price: 10000 });
  prodA2 = await createProduct(prisma, shopA.id, { name: 'A2', price: 20000 });
  prodB1 = await createProduct(prisma, shopB.id, { name: 'B1', price: 15000 });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('PUT /api/cart-drafts/me/:shopId', () => {
  test('upserts a new draft and persists it', async () => {
    const res = await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({
        payload: [
          { productId: prodA1.id, quantity: 2, modifiers: [] },
          { productId: prodA2.id, quantity: 1, modifiers: [] },
        ],
      });
    expect(res.status).toBe(200);
    expect(res.body.draft.shopId).toBe(shopA.id);
    expect(res.body.draft.payload).toHaveLength(2);

    const row = await prisma.cartDraft.findUnique({
      where: { userId_shopId: { userId: buyer.user.id, shopId: shopA.id } },
    });
    expect(row).toBeTruthy();
    expect(JSON.parse(row.payload)).toHaveLength(2);
  });

  test('second PUT with new payload replaces the prior one', async () => {
    const res = await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({
        payload: [
          { productId: prodA1.id, quantity: 5, modifiers: [] },
        ],
        couponCode: 'welcome',
        loyaltyPoints: 100,
      });
    expect(res.status).toBe(200);
    expect(res.body.draft.payload).toHaveLength(1);
    expect(res.body.draft.payload[0].quantity).toBe(5);
    expect(res.body.draft.couponCode).toBe('WELCOME');
    expect(res.body.draft.loyaltyPoints).toBe(100);
  });

  test('rejects products from a different shop with 400', async () => {
    const res = await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({
        payload: [
          { productId: prodA1.id, quantity: 1, modifiers: [] },
          { productId: prodB1.id, quantity: 1, modifiers: [] }, // wrong shop
        ],
      });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/does not belong/i);
  });

  test('rejects payload > 50 lines with 400', async () => {
    const lines = Array.from({ length: 51 }, () => ({
      productId: prodA1.id, quantity: 1, modifiers: [],
    }));
    const res = await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({ payload: lines });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/exceeds/i);
  });

  test('accepts empty payload (buyer cleared cart but keeping draft slot)', async () => {
    const res = await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopB.id}`)
      .set('Authorization', buyer.auth)
      .send({ payload: [] });
    expect(res.status).toBe(200);
    expect(res.body.draft.payload).toEqual([]);
  });

  test('rejects when shop does not exist', async () => {
    const res = await request(ctx.app)
      .put('/api/cart-drafts/me/no-such-shop')
      .set('Authorization', buyer.auth)
      .send({ payload: [] });
    expect(res.status).toBe(404);
  });

  test('rejects malformed payload (not an array)', async () => {
    const res = await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({ payload: 'not-an-array' });
    expect(res.status).toBe(400);
  });

  test('rejects line with bad quantity', async () => {
    const res = await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({
        payload: [{ productId: prodA1.id, quantity: 0, modifiers: [] }],
      });
    expect(res.status).toBe(400);
  });

  test('requires auth', async () => {
    const res = await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .send({ payload: [] });
    expect(res.status).toBe(401);
  });
});

describe('GET /api/cart-drafts/me', () => {
  test('lists all drafts with computed itemCount + subtotal', async () => {
    // Reset state to known shape: shopA → 2x A1 + 1x A2; shopB → empty.
    await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({
        payload: [
          { productId: prodA1.id, quantity: 2, modifiers: [] },
          { productId: prodA2.id, quantity: 1, modifiers: [] },
        ],
      });
    await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopB.id}`)
      .set('Authorization', buyer.auth)
      .send({ payload: [{ productId: prodB1.id, quantity: 3, modifiers: [] }] });

    const res = await request(ctx.app)
      .get('/api/cart-drafts/me')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.drafts).toHaveLength(2);

    const a = res.body.drafts.find((d) => d.shopId === shopA.id);
    const b = res.body.drafts.find((d) => d.shopId === shopB.id);
    expect(a.itemCount).toBe(3);       // 2 + 1
    expect(a.subtotal).toBe(40000);    // 2*10000 + 1*20000
    expect(a.shopName).toBe(shopA.name);
    expect(a.shopCurrency).toBe('UZS');
    expect(a.staleItems).toBe(0);
    expect(b.itemCount).toBe(3);       // 3 of B1
    expect(b.subtotal).toBe(45000);    // 3*15000
  });

  test('GET /me/:shopId returns single draft with raw payload', async () => {
    const res = await request(ctx.app)
      .get(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.draft.shopId).toBe(shopA.id);
    expect(res.body.draft.payload).toHaveLength(2);
    expect(res.body.draft.itemCount).toBe(3);
  });

  test('GET /me/:shopId returns 404 when missing', async () => {
    const res = await request(ctx.app)
      .get('/api/cart-drafts/me/no-such-shop')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(404);
  });

  test('stale items are excluded from count and surfaced via staleItems', async () => {
    // Create a fresh shop+product, put it in the draft, then delete the product.
    const owner = await createUser(prisma, { isShop: true });
    const shopC = await createShopWithOwner(prisma, owner.user);
    const ephemeral = await createProduct(prisma, shopC.id, { name: 'gone', price: 9000 });
    const keep = await createProduct(prisma, shopC.id, { name: 'stay', price: 9000 });

    await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopC.id}`)
      .set('Authorization', buyer.auth)
      .send({
        payload: [
          { productId: ephemeral.id, quantity: 2, modifiers: [] },
          { productId: keep.id, quantity: 1, modifiers: [] },
        ],
      });
    await prisma.product.delete({ where: { id: ephemeral.id } });

    const res = await request(ctx.app)
      .get(`/api/cart-drafts/me/${shopC.id}`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.draft.staleItems).toBe(1);
    expect(res.body.draft.itemCount).toBe(1);
    expect(res.body.draft.subtotal).toBe(9000);

    // Cleanup so it doesn't pollute subsequent tests.
    await prisma.cartDraft.deleteMany({ where: { userId: buyer.user.id, shopId: shopC.id } });
  });
});

describe('DELETE /api/cart-drafts/me', () => {
  test('single-shop delete removes only that draft', async () => {
    // Ensure both A and B drafts exist.
    await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({ payload: [{ productId: prodA1.id, quantity: 1, modifiers: [] }] });
    await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopB.id}`)
      .set('Authorization', buyer.auth)
      .send({ payload: [{ productId: prodB1.id, quantity: 1, modifiers: [] }] });

    const del = await request(ctx.app)
      .delete(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth);
    expect(del.status).toBe(200);
    expect(del.body.deleted).toBe(true);

    const list = await request(ctx.app)
      .get('/api/cart-drafts/me')
      .set('Authorization', buyer.auth);
    const ids = list.body.drafts.map((d) => d.shopId);
    expect(ids).not.toContain(shopA.id);
    expect(ids).toContain(shopB.id);
  });

  test('DELETE single returns 404 when no draft exists', async () => {
    const res = await request(ctx.app)
      .delete(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(404);
  });

  test('DELETE /me clears all drafts', async () => {
    // Refill so the bulk delete has something to remove.
    await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({ payload: [{ productId: prodA1.id, quantity: 1, modifiers: [] }] });

    const res = await request(ctx.app)
      .delete('/api/cart-drafts/me')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.deleted).toBeGreaterThanOrEqual(1);

    const list = await request(ctx.app)
      .get('/api/cart-drafts/me')
      .set('Authorization', buyer.auth);
    expect(list.body.drafts).toEqual([]);
  });
});

describe('Cross-user isolation', () => {
  test('user A cannot read user B drafts via /me list', async () => {
    // Buyer creates a draft.
    await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({ payload: [{ productId: prodA1.id, quantity: 1, modifiers: [] }] });

    const otherList = await request(ctx.app)
      .get('/api/cart-drafts/me')
      .set('Authorization', otherBuyer.auth);
    expect(otherList.status).toBe(200);
    expect(otherList.body.drafts).toEqual([]);
  });

  test('user A gets 404 hitting GET /me/:shopId for a shop they have no draft in', async () => {
    const res = await request(ctx.app)
      .get(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', otherBuyer.auth);
    expect(res.status).toBe(404);
  });

  test('user A cannot DELETE user B draft via shopId', async () => {
    // Buyer still has a draft on shopA from above; otherBuyer tries to delete it.
    const del = await request(ctx.app)
      .delete(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', otherBuyer.auth);
    expect(del.status).toBe(404);

    // Original draft must still exist.
    const stillThere = await prisma.cartDraft.findUnique({
      where: { userId_shopId: { userId: buyer.user.id, shopId: shopA.id } },
    });
    expect(stillThere).toBeTruthy();
  });
});

describe('Draft cleared after order placement', () => {
  test('POST /api/orders deletes the buyer cart draft for that shop', async () => {
    // Seed a fresh draft.
    await request(ctx.app)
      .put(`/api/cart-drafts/me/${shopA.id}`)
      .set('Authorization', buyer.auth)
      .send({
        payload: [{ productId: prodA1.id, quantity: 2, modifiers: [] }],
      });

    const orderRes = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send({
        shopId: shopA.id,
        items: [{ productId: prodA1.id, quantity: 2, modifiers: [] }],
        deliveryAddress: '1 Test St',
        paymentMethod: 'cash',
      });
    expect(orderRes.status).toBe(201);

    const remaining = await prisma.cartDraft.findUnique({
      where: { userId_shopId: { userId: buyer.user.id, shopId: shopA.id } },
    });
    expect(remaining).toBeNull();
  });
});
