// Integration tests for /api/products/:productId/modifier-groups
// + /api/modifier-groups + /api/modifier-options.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let owner, outsider, admin;
let shop, product;

beforeAll(async () => {
  ctx = await setupTestDb('modifiers');
  owner = await createUser(ctx.prisma, { isShop: true });
  outsider = await createUser(ctx.prisma);
  admin = await createUser(ctx.prisma, { isAdmin: true });
  shop = await createShopWithOwner(ctx.prisma, owner.user);
  product = await createProduct(ctx.prisma, shop.id);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('Modifier groups CRUD', () => {
  test('non-member is rejected with 403', async () => {
    const res = await request(ctx.app)
      .post(`/api/products/${product.id}/modifier-groups`)
      .set('Authorization', outsider.auth)
      .send({ nameUz: 'Razmer', nameRu: 'Размер', minSelect: 1, maxSelect: 1 });
    expect(res.status).toBe(403);
  });

  test('owner can create a group with options', async () => {
    const res = await request(ctx.app)
      .post(`/api/products/${product.id}/modifier-groups`)
      .set('Authorization', owner.auth)
      .send({ nameUz: 'Razmer', nameRu: 'Размер', minSelect: 1, maxSelect: 1, sortOrder: 0 });
    expect(res.status).toBe(201);
    expect(res.body.group.nameRu).toBe('Размер');

    const groupId = res.body.group.id;

    // Add three options out of order — GET should sort them by sortOrder.
    const opts = [
      { nameUz: 'L', nameRu: 'Большая', priceDelta: 5000, sortOrder: 3 },
      { nameUz: 'S', nameRu: 'Маленькая', priceDelta: 0, sortOrder: 1 },
      { nameUz: 'M', nameRu: 'Средняя', priceDelta: 2000, sortOrder: 2 },
    ];
    for (const o of opts) {
      const r = await request(ctx.app)
        .post(`/api/modifier-groups/${groupId}/options`)
        .set('Authorization', owner.auth)
        .send(o);
      expect(r.status).toBe(201);
    }

    const list = await request(ctx.app)
      .get(`/api/products/${product.id}/modifier-groups`);
    expect(list.status).toBe(200);
    expect(list.body.groups).toHaveLength(1);
    const optionsOut = list.body.groups[0].options.map((o) => o.nameRu);
    expect(optionsOut).toEqual(['Маленькая', 'Средняя', 'Большая']);
  });

  test('admin can create groups even without membership', async () => {
    const res = await request(ctx.app)
      .post(`/api/products/${product.id}/modifier-groups`)
      .set('Authorization', admin.auth)
      .send({ nameUz: 'Sous', nameRu: 'Соус', minSelect: 0, maxSelect: 2 });
    expect(res.status).toBe(201);
  });

  test('rejects minSelect > maxSelect', async () => {
    const res = await request(ctx.app)
      .post(`/api/products/${product.id}/modifier-groups`)
      .set('Authorization', owner.auth)
      .send({ nameUz: 'Bad', nameRu: 'Плохая', minSelect: 3, maxSelect: 1 });
    expect(res.status).toBe(400);
  });

  test('DELETE group cascades options', async () => {
    const created = await request(ctx.app)
      .post(`/api/products/${product.id}/modifier-groups`)
      .set('Authorization', owner.auth)
      .send({ nameUz: 'Tmp', nameRu: 'Временная', minSelect: 0, maxSelect: 5 });
    const groupId = created.body.group.id;
    await request(ctx.app)
      .post(`/api/modifier-groups/${groupId}/options`)
      .set('Authorization', owner.auth)
      .send({ nameUz: 'X', nameRu: 'X' });
    await request(ctx.app)
      .post(`/api/modifier-groups/${groupId}/options`)
      .set('Authorization', owner.auth)
      .send({ nameUz: 'Y', nameRu: 'Y' });

    const before = await ctx.prisma.productModifierOption.count({ where: { groupId } });
    expect(before).toBe(2);

    const del = await request(ctx.app)
      .delete(`/api/modifier-groups/${groupId}`)
      .set('Authorization', owner.auth);
    expect(del.status).toBe(200);

    const after = await ctx.prisma.productModifierOption.count({ where: { groupId } });
    expect(after).toBe(0);
    const groupRow = await ctx.prisma.productModifierGroup.findUnique({ where: { id: groupId } });
    expect(groupRow).toBeNull();
  });

  test('PATCH group updates fields and validates min<=max', async () => {
    const created = await request(ctx.app)
      .post(`/api/products/${product.id}/modifier-groups`)
      .set('Authorization', owner.auth)
      .send({ nameUz: 'Edit', nameRu: 'Редактируй', minSelect: 0, maxSelect: 3 });
    const groupId = created.body.group.id;

    const okPatch = await request(ctx.app)
      .patch(`/api/modifier-groups/${groupId}`)
      .set('Authorization', owner.auth)
      .send({ nameRu: 'Изменено', maxSelect: 5 });
    expect(okPatch.status).toBe(200);
    expect(okPatch.body.group.nameRu).toBe('Изменено');
    expect(okPatch.body.group.maxSelect).toBe(5);

    const badPatch = await request(ctx.app)
      .patch(`/api/modifier-groups/${groupId}`)
      .set('Authorization', owner.auth)
      .send({ minSelect: 99 });
    expect(badPatch.status).toBe(400);
  });

  test('non-member cannot mutate options', async () => {
    const created = await request(ctx.app)
      .post(`/api/products/${product.id}/modifier-groups`)
      .set('Authorization', owner.auth)
      .send({ nameUz: 'A', nameRu: 'А' });
    const groupId = created.body.group.id;
    const opt = await request(ctx.app)
      .post(`/api/modifier-groups/${groupId}/options`)
      .set('Authorization', owner.auth)
      .send({ nameUz: 'O', nameRu: 'О' });

    const blocked = await request(ctx.app)
      .delete(`/api/modifier-options/${opt.body.option.id}`)
      .set('Authorization', outsider.auth);
    expect(blocked.status).toBe(403);
  });
});
