// Integration tests for the Phase-1 Category CRUD routes.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser } = require('./helpers/db');

let ctx;
let admin;
let regular;

beforeAll(async () => {
  ctx = await setupTestDb('categories');
  admin = await createUser(ctx.prisma, { isAdmin: true, name: 'Admin' });
  regular = await createUser(ctx.prisma, { name: 'Regular' });
});

afterAll(async () => {
  await teardownTestDb(ctx);
});

describe('GET /api/categories/tree', () => {
  let rootId;
  let childId;

  beforeAll(async () => {
    const root = await ctx.prisma.category.create({
      data: { vertical: 'grocery', slug: 'tree-root', nameUz: 'Root', nameRu: 'Корень', sortOrder: 1 },
    });
    rootId = root.id;
    const child = await ctx.prisma.category.create({
      data: {
        vertical: 'grocery', slug: 'tree-child', nameUz: 'Child', nameRu: 'Дитя',
        parentId: rootId, sortOrder: 1,
      },
    });
    childId = child.id;
  });

  test('returns nested tree filtered by vertical', async () => {
    const res = await request(ctx.app).get('/api/categories/tree?vertical=grocery');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.tree)).toBe(true);
    const root = res.body.tree.find((n) => n.id === rootId);
    expect(root).toBeTruthy();
    expect(root.children).toHaveLength(1);
    expect(root.children[0].id).toBe(childId);
    expect(root.children[0]).toHaveProperty('productCount');
  });

  test('vertical filter excludes other verticals', async () => {
    const res = await request(ctx.app).get('/api/categories/tree?vertical=pharmacy');
    expect(res.status).toBe(200);
    const root = res.body.tree.find((n) => n.id === rootId);
    expect(root).toBeFalsy();
  });
});

describe('admin-only mutations', () => {
  test('non-admin cannot POST', async () => {
    const res = await request(ctx.app)
      .post('/api/categories')
      .set('Authorization', regular.auth)
      .send({ vertical: 'grocery', slug: 'forbidden', nameUz: 'X', nameRu: 'X' });
    expect(res.status).toBe(403);
  });

  test('admin can POST, PATCH, DELETE', async () => {
    const created = await request(ctx.app)
      .post('/api/categories')
      .set('Authorization', admin.auth)
      .send({ vertical: 'grocery', slug: 'admin-only', nameUz: 'AO', nameRu: 'AO', sortOrder: 7 });
    expect(created.status).toBe(201);
    expect(created.body.category.slug).toBe('admin-only');

    const id = created.body.category.id;
    const patched = await request(ctx.app)
      .patch(`/api/categories/${id}`)
      .set('Authorization', admin.auth)
      .send({ nameRu: 'Renamed' });
    expect(patched.status).toBe(200);
    expect(patched.body.category.nameRu).toBe('Renamed');

    const del = await request(ctx.app)
      .delete(`/api/categories/${id}`)
      .set('Authorization', admin.auth);
    expect(del.status).toBe(200);
    expect(del.body.deleted).toBe(true);
  });

  test('duplicate slug returns 409', async () => {
    await request(ctx.app)
      .post('/api/categories')
      .set('Authorization', admin.auth)
      .send({ vertical: 'grocery', slug: 'dupe', nameUz: 'X', nameRu: 'X' });
    const res = await request(ctx.app)
      .post('/api/categories')
      .set('Authorization', admin.auth)
      .send({ vertical: 'grocery', slug: 'dupe', nameUz: 'Y', nameRu: 'Y' });
    expect(res.status).toBe(409);
  });
});

describe('DELETE refuses when category has children/products', () => {
  test('blocked when category has children', async () => {
    const parent = await ctx.prisma.category.create({
      data: { vertical: 'grocery', slug: 'has-kids', nameUz: 'P', nameRu: 'P' },
    });
    await ctx.prisma.category.create({
      data: { vertical: 'grocery', slug: 'is-kid', nameUz: 'C', nameRu: 'C', parentId: parent.id },
    });

    const res = await request(ctx.app)
      .delete(`/api/categories/${parent.id}`)
      .set('Authorization', admin.auth);
    expect(res.status).toBe(409);
    expect(res.body.reason).toBe('has_children');
  });

  test('blocked when category has products', async () => {
    const cat = await ctx.prisma.category.create({
      data: { vertical: 'grocery', slug: 'has-products', nameUz: 'P', nameRu: 'P' },
    });
    const owner = await createUser(ctx.prisma, { isShop: true });
    const shop = await ctx.prisma.shop.create({
      data: { name: 'S1', address: '1 St', lat: 41.0, lng: 69.0 },
    });
    await ctx.prisma.shopMember.create({
      data: { userId: owner.user.id, shopId: shop.id, role: 'owner' },
    });
    await ctx.prisma.product.create({
      data: {
        shopId: shop.id, name: 'P', nameUz: 'P', price: 1000, unit: 'шт',
        category: 'food', imageUrl: 'x', categoryId: cat.id,
      },
    });

    const res = await request(ctx.app)
      .delete(`/api/categories/${cat.id}`)
      .set('Authorization', admin.auth);
    expect(res.status).toBe(409);
    expect(res.body.reason).toBe('has_products');
  });
});
