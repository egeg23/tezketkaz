// Integration tests for POST /api/orders with modifier selections.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let buyer;
let shop, productWithGroups, plainProduct;
let sizeGroup, sizeS, sizeL;
let toppingGroup, topCheese, topBacon, topMushroom;

beforeAll(async () => {
  ctx = await setupTestDb('orders-modifiers');
  const owner = await createUser(ctx.prisma, { isShop: true });
  buyer = await createUser(ctx.prisma);
  shop = await createShopWithOwner(ctx.prisma, owner.user);

  productWithGroups = await createProduct(ctx.prisma, shop.id, { name: 'Burger', price: 30000 });
  plainProduct = await createProduct(ctx.prisma, shop.id, { name: 'Coke', price: 10000 });

  // Required size group (min=1 max=1).
  sizeGroup = await ctx.prisma.productModifierGroup.create({
    data: {
      productId: productWithGroups.id,
      nameUz: 'Razmer', nameRu: 'Размер',
      minSelect: 1, maxSelect: 1, sortOrder: 1,
    },
  });
  sizeS = await ctx.prisma.productModifierOption.create({
    data: { groupId: sizeGroup.id, nameUz: 'S', nameRu: 'Малый', priceDelta: 0 },
  });
  sizeL = await ctx.prisma.productModifierOption.create({
    data: { groupId: sizeGroup.id, nameUz: 'L', nameRu: 'Большой', priceDelta: 5000 },
  });

  // Optional toppings group (min=0 max=2).
  toppingGroup = await ctx.prisma.productModifierGroup.create({
    data: {
      productId: productWithGroups.id,
      nameUz: 'Sous', nameRu: 'Топпинги',
      minSelect: 0, maxSelect: 2, sortOrder: 2,
    },
  });
  topCheese = await ctx.prisma.productModifierOption.create({
    data: { groupId: toppingGroup.id, nameUz: 'Pishloq', nameRu: 'Сыр', priceDelta: 2000 },
  });
  topBacon = await ctx.prisma.productModifierOption.create({
    data: { groupId: toppingGroup.id, nameUz: 'Bekon', nameRu: 'Бекон', priceDelta: 4000 },
  });
  topMushroom = await ctx.prisma.productModifierOption.create({
    data: { groupId: toppingGroup.id, nameUz: 'Qoziqorin', nameRu: 'Грибы', priceDelta: 3000 },
  });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

function basePayload(items) {
  return {
    shopId: shop.id,
    items,
    deliveryAddress: 'Test Address 1',
    paymentMethod: 'cash',
  };
}

describe('POST /api/orders with modifiers', () => {
  test('snapshots modifiers and computes correct unitPrice', async () => {
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send(basePayload([
        {
          productId: productWithGroups.id,
          quantity: 2,
          modifiers: [
            { groupId: sizeGroup.id, optionIds: [sizeL.id] },
            { groupId: toppingGroup.id, optionIds: [topCheese.id, topBacon.id] },
          ],
        },
      ]));

    expect(res.status).toBe(201);
    const order = res.body.order;
    // base 30000 + L 5000 + cheese 2000 + bacon 4000 = 41000 per unit.
    const item = order.items[0];
    expect(item.basePrice).toBe(30000);
    expect(item.price).toBe(41000);
    expect(item.quantity).toBe(2);
    expect(item.total).toBe(82000);
    expect(order.subtotal).toBe(82000);

    const snap = JSON.parse(item.modifiers);
    expect(snap).toHaveLength(3);
    const optNames = snap.map((s) => s.optionName);
    expect(optNames).toContain('Большой');
    expect(optNames).toContain('Бекон');
    expect(optNames).toContain('Сыр');
    const totalDelta = snap.reduce((s, m) => s + m.priceDelta, 0);
    expect(totalDelta).toBe(11000);
    for (const s of snap) {
      expect(s.groupId).toBeDefined();
      expect(s.optionId).toBeDefined();
      expect(typeof s.priceDelta).toBe('number');
    }
  });

  test('selecting maxSelect+1 options returns 400', async () => {
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send(basePayload([
        {
          productId: productWithGroups.id,
          quantity: 1,
          modifiers: [
            { groupId: sizeGroup.id, optionIds: [sizeS.id] },
            { groupId: toppingGroup.id, optionIds: [topCheese.id, topBacon.id, topMushroom.id] },
          ],
        },
      ]));
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/at most 2/i);
  });

  test('missing required group returns 400', async () => {
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send(basePayload([
        {
          productId: productWithGroups.id,
          quantity: 1,
          modifiers: [
            { groupId: toppingGroup.id, optionIds: [topCheese.id] },
          ],
        },
      ]));
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/required/i);
  });

  test('order without modifiers when product has no groups still works', async () => {
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send(basePayload([
        { productId: plainProduct.id, quantity: 3 },
      ]));
    expect(res.status).toBe(201);
    const item = res.body.order.items[0];
    expect(item.basePrice).toBe(10000);
    expect(item.price).toBe(10000);
    expect(item.total).toBe(30000);
    expect(item.modifiers).toBeNull();
  });

  test('option not belonging to group returns 400', async () => {
    const res = await request(ctx.app)
      .post('/api/orders')
      .set('Authorization', buyer.auth)
      .send(basePayload([
        {
          productId: productWithGroups.id,
          quantity: 1,
          modifiers: [
            // Wrong: pass topping option id under size group.
            { groupId: sizeGroup.id, optionIds: [topCheese.id] },
          ],
        },
      ]));
    expect(res.status).toBe(400);
  });
});
