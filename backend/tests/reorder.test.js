// Phase 7.3 — POST /api/orders/:id/reorder cart-draft helper.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let prisma;

beforeAll(async () => {
  ctx = await setupTestDb('reorder');
  prisma = ctx.prisma;
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makeScenario({ productAvailable = true, shopActive = true } = {}) {
  const owner = await createUser(prisma, { isShop: true });
  const buyer = await createUser(prisma);
  const stranger = await createUser(prisma);
  const shop = await createShopWithOwner(prisma, owner.user);
  if (!shopActive) {
    await prisma.shop.update({ where: { id: shop.id }, data: { isActive: false } });
  }
  const p1 = await createProduct(prisma, shop.id, { name: 'Burger', price: 30000 });
  const p2 = await createProduct(prisma, shop.id, { name: 'Fries', price: 10000 });

  const order = await prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'X', customerPhone: '+99800',
      shopId: shop.id,
      deliveryAddress: '1 Test', deliveryLat: 41.0, deliveryLng: 69.0,
      paymentMethod: 'cash',
      subtotal: 40000, total: 52000,
      status: 'delivered', deliveredAt: new Date(),
      items: {
        create: [
          { productId: p1.id, productName: p1.name, quantity: 2, price: 30000, total: 60000,
            modifiers: JSON.stringify([{ groupId: 'g1', optionId: 'o1', priceDelta: 0 }]) },
          { productId: p2.id, productName: p2.name, quantity: 1, price: 10000, total: 10000 },
        ],
      },
    },
    include: { items: true },
  });

  if (!productAvailable) {
    await prisma.product.update({ where: { id: p1.id }, data: { isAvailable: false } });
  }

  return { buyer, stranger, shop, order, p1, p2 };
}

describe('POST /api/orders/:id/reorder', () => {
  test('valid order → all items available, shopId + draft fields populated', async () => {
    const { buyer, order, shop } = await makeScenario();
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/reorder`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.shopId).toBe(shop.id);
    expect(res.body.items.length).toBe(2);
    expect(res.body.items.every((i) => i.available)).toBe(true);
    expect(res.body.couponCode).toBeNull();
    // The first item carries its modifier snapshot.
    const burger = res.body.items.find((i) => i.quantity === 2);
    expect(Array.isArray(burger.modifiers)).toBe(true);
    expect(burger.modifiers[0].optionId).toBe('o1');
  });

  test('product unavailable → marked with skipReason=out_of_stock', async () => {
    const { buyer, order, p1 } = await makeScenario({ productAvailable: false });
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/reorder`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    const it = res.body.items.find((i) => i.productId === p1.id);
    expect(it.available).toBe(false);
    expect(it.skipReason).toBe('out_of_stock');
  });

  test('product deleted (orphaned reference) → marked with skipReason=product_deleted', async () => {
    // FK constraints prevent us from actually deleting a referenced product.
    // We need to simulate an orphaned OrderItem.productId — the state seen in
    // production when an older row's product is removed via raw cleanup.
    //
    // On Postgres we drop the FK constraint for the duration of the test, do
    // the update, then re-add it. Quoted identifiers because Prisma generates
    // CamelCase table/column names.
    const { buyer, order } = await makeScenario();
    const fakeId = 'ghost-' + Math.random().toString(36).slice(2, 8);
    // Find and drop the FK constraint name dynamically — Prisma names them
    // unpredictably (e.g. OrderItem_productId_fkey).
    const fks = await prisma.$queryRawUnsafe(
      `SELECT conname FROM pg_constraint
         WHERE conrelid = '"OrderItem"'::regclass
           AND contype = 'f'
           AND conname LIKE '%productId%'`,
    );
    for (const { conname } of fks) {
      await prisma.$executeRawUnsafe(
        `ALTER TABLE "OrderItem" DROP CONSTRAINT "${conname}"`,
      );
    }
    await prisma.$executeRawUnsafe(
      `UPDATE "OrderItem" SET "productId" = $1 WHERE "orderId" = $2`,
      fakeId, order.id,
    );
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/reorder`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.items.every((i) => i.skipReason === 'product_deleted')).toBe(true);
  });

  test('shop inactive → all items marked with skipReason=shop_inactive', async () => {
    const { buyer, order } = await makeScenario({ shopActive: false });
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/reorder`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.items.every((i) => !i.available && i.skipReason === 'shop_inactive')).toBe(true);
  });

  test('cross-user → 403', async () => {
    const { stranger, order } = await makeScenario();
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/reorder`)
      .set('Authorization', stranger.auth);
    expect(res.status).toBe(403);
  });

  test('unknown order → 404', async () => {
    const buyer = await createUser(prisma);
    const res = await request(ctx.app)
      .post('/api/orders/no-such-order/reorder')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(404);
  });

  test('matches saved address by lat/lng', async () => {
    const { buyer, order } = await makeScenario();
    const addr = await prisma.address.create({
      data: {
        userId: buyer.user.id,
        label: 'Home',
        fullAddress: '1 Test',
        lat: 41.0,
        lng: 69.0,
        isDefault: true,
      },
    });
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/reorder`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.deliveryAddressId).toBe(addr.id);
  });
});
