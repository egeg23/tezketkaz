// Phase 10.3 — audience query compiler tests.

const {
  setupTestDb, teardownTestDb, createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let audienceQuery;

let uzRu, uzUz, kzRu, courier, ownerKz;
let shopKz;

async function makeOrder(prismaClient, buyerId, shopId, overrides = {}) {
  return prismaClient.order.create({
    data: {
      buyerId,
      customerName: 'X',
      customerPhone: '+998900000000',
      shopId,
      deliveryAddress: overrides.deliveryAddress || '1 Test, Tashkent',
      paymentMethod: 'cash',
      isPaid: false,
      subtotal: 30000,
      total: 30000,
      deliveryFee: 0,
      status: overrides.status || 'delivered',
      createdAt: overrides.createdAt || new Date(),
    },
  });
}

beforeAll(async () => {
  ctx = await setupTestDb('audience-query');
  audienceQuery = require('../src/services/audienceQuery');

  // UZ users.
  uzRu = await createUser(ctx.prisma);
  await ctx.prisma.user.update({
    where: { id: uzRu.user.id },
    data: { country: 'UZ', locale: 'ru' },
  });

  uzUz = await createUser(ctx.prisma);
  await ctx.prisma.user.update({
    where: { id: uzUz.user.id },
    data: { country: 'UZ', locale: 'uz' },
  });

  // KZ user.
  kzRu = await createUser(ctx.prisma);
  await ctx.prisma.user.update({
    where: { id: kzRu.user.id },
    data: { country: 'KZ', locale: 'ru' },
  });

  // Courier with no orders.
  courier = await createUser(ctx.prisma, { isCourier: true });
  await ctx.prisma.user.update({
    where: { id: courier.user.id },
    data: { isCourier: true, country: 'UZ' },
  });

  // Shop owner needed to create a Shop.
  ownerKz = await createUser(ctx.prisma, { isShop: true });
  shopKz = await createShopWithOwner(ctx.prisma, ownerKz.user);
  await ctx.prisma.shop.update({
    where: { id: shopKz.id },
    data: { vertical: 'restaurant' },
  });
  await createProduct(ctx.prisma, shopKz.id);

  // Recent order for uzRu.
  await makeOrder(ctx.prisma, uzRu.user.id, shopKz.id, { createdAt: new Date() });
  // Old order for uzUz (90 days ago).
  await makeOrder(ctx.prisma, uzUz.user.id, shopKz.id, {
    createdAt: new Date(Date.now() - 90 * 86400 * 1000),
  });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('audienceQuery', () => {
  test('country filter selects only matching country', async () => {
    const users = await audienceQuery.resolveAudience(ctx.prisma, { country: 'KZ' });
    const ids = users.map((u) => u.id);
    expect(ids).toContain(kzRu.user.id);
    expect(ids).not.toContain(uzRu.user.id);
    expect(ids).not.toContain(uzUz.user.id);
  });

  test('locale filter selects only matching locale', async () => {
    const users = await audienceQuery.resolveAudience(ctx.prisma, { locale: 'uz' });
    const ids = users.map((u) => u.id);
    expect(ids).toContain(uzUz.user.id);
    expect(ids).not.toContain(uzRu.user.id);
    expect(ids).not.toContain(kzRu.user.id);
  });

  test('hasOrders=true filter selects only buyers with orders', async () => {
    const users = await audienceQuery.resolveAudience(ctx.prisma, { hasOrders: true });
    const ids = users.map((u) => u.id);
    expect(ids).toContain(uzRu.user.id);
    expect(ids).toContain(uzUz.user.id);
    expect(ids).not.toContain(courier.user.id);
  });

  test('lastOrderWithinDays filter selects only recent buyers', async () => {
    const users = await audienceQuery.resolveAudience(ctx.prisma, { lastOrderWithinDays: 30 });
    const ids = users.map((u) => u.id);
    expect(ids).toContain(uzRu.user.id);   // recent
    expect(ids).not.toContain(uzUz.user.id); // 90 days old
    expect(ids).not.toContain(courier.user.id);
  });

  test('combined filters narrow correctly', async () => {
    const users = await audienceQuery.resolveAudience(ctx.prisma, {
      country: 'UZ',
      locale: 'ru',
      hasOrders: true,
    });
    const ids = users.map((u) => u.id);
    expect(ids).toContain(uzRu.user.id);
    expect(ids).not.toContain(uzUz.user.id);
    expect(ids).not.toContain(kzRu.user.id);
    expect(ids).not.toContain(courier.user.id);
  });

  test('empty spec returns all (non-deleted) users', async () => {
    const users = await audienceQuery.resolveAudience(ctx.prisma, {});
    const ids = users.map((u) => u.id);
    expect(ids).toContain(uzRu.user.id);
    expect(ids).toContain(uzUz.user.id);
    expect(ids).toContain(kzRu.user.id);
    expect(ids).toContain(courier.user.id);
    expect(ids).toContain(ownerKz.user.id);
  });
});
