// Phase 7.3 — buyer favorites CRUD.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let prisma;
let buyer;
let other;
let shop;
let product;

beforeAll(async () => {
  ctx = await setupTestDb('favorites');
  prisma = ctx.prisma;
  const owner = await createUser(prisma, { isShop: true });
  buyer = await createUser(prisma);
  other = await createUser(prisma);
  shop = await createShopWithOwner(prisma, owner.user);
  product = await createProduct(prisma, shop.id);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('Product favorites', () => {
  test('add + idempotency: second add returns existing favorite', async () => {
    const r1 = await request(ctx.app)
      .post(`/api/favorites/me/products/${product.id}`)
      .set('Authorization', buyer.auth);
    expect(r1.status).toBe(201);
    expect(r1.body.favorite.productId).toBe(product.id);

    const r2 = await request(ctx.app)
      .post(`/api/favorites/me/products/${product.id}`)
      .set('Authorization', buyer.auth);
    expect(r2.status).toBe(200);
    expect(r2.body.alreadyExists).toBe(true);
  });

  test('list shows the favorite with embedded product', async () => {
    const res = await request(ctx.app)
      .get('/api/favorites/me')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    const fav = res.body.favorites.find((f) => f.productId === product.id);
    expect(fav).toBeTruthy();
    expect(fav.product?.id).toBe(product.id);
    expect(fav.product?.shop?.id).toBe(shop.id);
  });

  test('check returns isFavorite true', async () => {
    const res = await request(ctx.app)
      .get(`/api/favorites/me/check?productId=${product.id}`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.isFavorite).toBe(true);
  });

  test('cross-user isolation: other user sees no favorite for that product', async () => {
    const res = await request(ctx.app)
      .get(`/api/favorites/me/check?productId=${product.id}`)
      .set('Authorization', other.auth);
    expect(res.status).toBe(200);
    expect(res.body.isFavorite).toBe(false);

    const list = await request(ctx.app)
      .get('/api/favorites/me')
      .set('Authorization', other.auth);
    expect(list.body.favorites.length).toBe(0);
  });

  test('remove favorite returns deleted; second remove → 404', async () => {
    const r1 = await request(ctx.app)
      .delete(`/api/favorites/me/products/${product.id}`)
      .set('Authorization', buyer.auth);
    expect(r1.status).toBe(200);
    expect(r1.body.deleted).toBe(true);

    const r2 = await request(ctx.app)
      .delete(`/api/favorites/me/products/${product.id}`)
      .set('Authorization', buyer.auth);
    expect(r2.status).toBe(404);
  });

  test('add favorite for unknown product → 404', async () => {
    const res = await request(ctx.app)
      .post('/api/favorites/me/products/no-such-id')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(404);
  });
});

describe('Shop favorites', () => {
  test('add shop favorite + check + remove', async () => {
    const add = await request(ctx.app)
      .post(`/api/favorites/me/shops/${shop.id}`)
      .set('Authorization', buyer.auth);
    expect(add.status).toBe(201);
    expect(add.body.favorite.shopId).toBe(shop.id);

    const check = await request(ctx.app)
      .get(`/api/favorites/me/check?shopId=${shop.id}`)
      .set('Authorization', buyer.auth);
    expect(check.body.isFavorite).toBe(true);

    const dup = await request(ctx.app)
      .post(`/api/favorites/me/shops/${shop.id}`)
      .set('Authorization', buyer.auth);
    expect(dup.status).toBe(200);
    expect(dup.body.alreadyExists).toBe(true);

    const del = await request(ctx.app)
      .delete(`/api/favorites/me/shops/${shop.id}`)
      .set('Authorization', buyer.auth);
    expect(del.status).toBe(200);
  });
});

describe('Auth', () => {
  test('list requires auth', async () => {
    const res = await request(ctx.app).get('/api/favorites/me');
    expect(res.status).toBe(401);
  });
  test('check requires productId or shopId', async () => {
    const res = await request(ctx.app)
      .get('/api/favorites/me/check')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(400);
  });
});
