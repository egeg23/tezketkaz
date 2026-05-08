// Integration tests for the upgraded GET /api/products handler:
// vertical join, q-search via searchText, cursor pagination, price filter.

const request = require('supertest');
const { setupTestDb, teardownTestDb } = require('./helpers/db');

let ctx;
let groceryShop;
let restaurantShop;

async function createProduct(overrides) {
  const data = {
    shopId: overrides.shopId,
    name: overrides.name,
    nameUz: overrides.nameUz || overrides.name,
    description: overrides.description || '',
    price: overrides.price ?? 10000,
    unit: 'шт',
    category: overrides.category || 'food',
    imageUrl: 'https://example.com/img.jpg',
    isAvailable: overrides.isAvailable ?? true,
    searchText: [overrides.name, overrides.nameUz, overrides.description]
      .filter(Boolean).join(' ').toLowerCase(),
  };
  if (overrides.createdAt) data.createdAt = overrides.createdAt;
  return ctx.prisma.product.create({ data });
}

beforeAll(async () => {
  ctx = await setupTestDb('products-search');

  groceryShop = await ctx.prisma.shop.create({
    data: { name: 'Grocer', address: '1 Apple St', vertical: 'grocery', lat: 41.0, lng: 69.0 },
  });
  restaurantShop = await ctx.prisma.shop.create({
    data: { name: 'Pizza Place', address: '2 Pie St', vertical: 'restaurant', lat: 41.1, lng: 69.1 },
  });

  // Seed products with controlled createdAt so cursor tests are deterministic.
  const base = Date.now();
  await createProduct({
    shopId: groceryShop.id, name: 'Tomato', nameUz: 'Pomidor',
    description: 'Fresh red tomato', price: 8500,
    createdAt: new Date(base - 4000),
  });
  await createProduct({
    shopId: groceryShop.id, name: 'Apple', nameUz: 'Olma',
    price: 12000, createdAt: new Date(base - 3000),
  });
  await createProduct({
    shopId: groceryShop.id, name: 'Bread', nameUz: 'Non',
    price: 4000, createdAt: new Date(base - 2000),
  });
  await createProduct({
    shopId: restaurantShop.id, name: 'Margherita Pizza', nameUz: 'Pitsa Margerita',
    price: 65000, createdAt: new Date(base - 1000),
  });
  await createProduct({
    shopId: restaurantShop.id, name: 'Cheeseburger', nameUz: 'Cheeseburger',
    price: 45000, createdAt: new Date(base - 500),
  });
});

afterAll(async () => {
  await teardownTestDb(ctx);
});

describe('GET /api/products vertical filter', () => {
  test('vertical=grocery returns only grocery shop products', async () => {
    const res = await request(ctx.app).get('/api/products?vertical=grocery&limit=50');
    expect(res.status).toBe(200);
    expect(res.body.items.length).toBe(3);
    for (const it of res.body.items) {
      expect(it.shopId).toBe(groceryShop.id);
    }
  });

  test('vertical=restaurant returns only restaurant products', async () => {
    const res = await request(ctx.app).get('/api/products?vertical=restaurant&limit=50');
    expect(res.status).toBe(200);
    expect(res.body.items.length).toBe(2);
    for (const it of res.body.items) {
      expect(it.shopId).toBe(restaurantShop.id);
    }
  });
});

describe('GET /api/products q search', () => {
  test('lowercased search matches via searchText', async () => {
    const res = await request(ctx.app).get('/api/products?q=PIZZA');
    expect(res.status).toBe(200);
    const names = res.body.items.map((i) => i.name);
    expect(names).toContain('Margherita Pizza');
  });

  test('search by Uzbek name works', async () => {
    const res = await request(ctx.app).get('/api/products?q=pomidor');
    expect(res.status).toBe(200);
    expect(res.body.items.length).toBeGreaterThanOrEqual(1);
    expect(res.body.items[0].name).toBe('Tomato');
  });
});

describe('GET /api/products price bounds', () => {
  test('priceMin filters low end', async () => {
    const res = await request(ctx.app).get('/api/products?priceMin=10000&limit=50');
    expect(res.status).toBe(200);
    for (const it of res.body.items) expect(it.price).toBeGreaterThanOrEqual(10000);
  });

  test('priceMin+priceMax bounds inclusive', async () => {
    const res = await request(ctx.app).get('/api/products?priceMin=5000&priceMax=20000&limit=50');
    expect(res.status).toBe(200);
    for (const it of res.body.items) {
      expect(it.price).toBeGreaterThanOrEqual(5000);
      expect(it.price).toBeLessThanOrEqual(20000);
    }
    // Tomato (8500) and Apple (12000) match; Bread (4000), Pizza, Burger don't.
    const names = res.body.items.map((i) => i.name).sort();
    expect(names).toEqual(['Apple', 'Tomato']);
  });
});

describe('GET /api/products cursor pagination', () => {
  test('cursor returns next page in createdAt-desc order', async () => {
    const first = await request(ctx.app).get('/api/products?limit=2');
    expect(first.status).toBe(200);
    expect(first.body.items.length).toBe(2);
    expect(first.body.nextCursor).toBeTruthy();

    const second = await request(ctx.app)
      .get(`/api/products?limit=2&cursor=${encodeURIComponent(first.body.nextCursor)}`);
    expect(second.status).toBe(200);
    expect(second.body.items.length).toBeGreaterThan(0);

    const firstIds = first.body.items.map((i) => i.id);
    const secondIds = second.body.items.map((i) => i.id);
    for (const id of secondIds) expect(firstIds).not.toContain(id);
  });

  test('createdAt is strictly non-increasing across pages', async () => {
    const first = await request(ctx.app).get('/api/products?limit=3');
    const second = await request(ctx.app)
      .get(`/api/products?limit=3&cursor=${encodeURIComponent(first.body.nextCursor)}`);

    const all = [...first.body.items, ...second.body.items];
    for (let i = 1; i < all.length; i++) {
      expect(new Date(all[i].createdAt).getTime())
        .toBeLessThanOrEqual(new Date(all[i - 1].createdAt).getTime());
    }
  });
});
