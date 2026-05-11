// Phase 13.3.9 — Soliq.uz fiscal receipt integration tests.
//
// Exercises:
//   • Mock-mode issueReceipt happy path.
//   • Eligibility skips (soliqEnabled=false, missing INN, non-UZ buyer).
//   • Idempotency (re-running the job is a no-op).
//   • Failure path that increments fiscalFailureCount + emits a notification.
//   • Admin re-trigger endpoint.
//   • Buyer can fetch their receipt; another user cannot.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const soliq = require('../src/services/soliq');
const fiscalJob = require('../src/jobs/fiscal-receipt');

let ctx;
let prisma;
let app;

async function makeOrder({
  shopId,
  buyerId,
  total = 250000,
  subtotal = 250000,
  paymentMethod = 'click',
  currency = 'UZS',
  isPaid = true,
  status = 'confirmed',
}) {
  const order = await prisma.order.create({
    data: {
      buyerId,
      customerName: 'Buyer',
      customerPhone: '+998900000000',
      shopId,
      deliveryAddress: '1 Test St',
      paymentMethod,
      isPaid,
      subtotal,
      total,
      currency,
      status,
      items: {
        create: [
          {
            productId: (await ensureProduct(shopId)).id,
            productName: 'Apple',
            quantity: 1,
            price: subtotal,
            total: subtotal,
          },
        ],
      },
    },
    include: { items: true, shop: true, buyer: true },
  });
  return order;
}

let _productCache = {};
async function ensureProduct(shopId) {
  if (_productCache[shopId]) return _productCache[shopId];
  const p = await prisma.product.create({
    data: {
      shopId,
      name: 'Apple',
      nameUz: 'Olma',
      price: 250000,
      unit: 'шт',
      category: 'grocery',
      imageUrl: 'https://x/y.jpg',
    },
  });
  _productCache[shopId] = p;
  return p;
}

beforeAll(async () => {
  ctx = await setupTestDb('fiscal_receipt');
  prisma = ctx.prisma;
  app = ctx.app;
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

beforeEach(async () => {
  // Tests are independent; wipe orders and side rows between cases.
  await prisma.notification.deleteMany({});
  await prisma.auditLog.deleteMany({});
  await prisma.orderItem.deleteMany({});
  await prisma.order.deleteMany({});
  await prisma.product.deleteMany({});
  await prisma.shopMember.deleteMany({});
  await prisma.shop.deleteMany({});
  _productCache = {};
  soliq._resetForTests();
});

describe('soliq.issueReceipt (mock mode)', () => {
  test('returns ok + synthetic receipt id for eligible UZ shop', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.shop.update({
      where: { id: shop.id },
      data: { soliqEnabled: true, soliqInn: '300000001' },
    });
    const buyer = await createUser(prisma);
    const refreshed = await prisma.shop.findUnique({ where: { id: shop.id } });
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const result = await soliq.issueReceipt(order, refreshed);
    expect(result.ok).toBe(true);
    expect(result.receiptId).toBe(`mock-${order.id}`);
    expect(result.receiptUrl).toContain('soliq.uz/mock-receipt/');
  });

  test('isShopEligible returns false when soliqEnabled=false', () => {
    expect(soliq.isShopEligible({ soliqEnabled: false, soliqInn: '300000001' })).toBe(false);
  });

  test('isShopEligible returns false when soliqInn is missing', () => {
    expect(soliq.isShopEligible({ soliqEnabled: true, soliqInn: null })).toBe(false);
  });
});

describe('fiscal-receipt job', () => {
  test('writes fiscalReceiptId on the order when the shop is eligible', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.shop.update({
      where: { id: shop.id },
      data: { soliqEnabled: true, soliqInn: '300000001' },
    });
    const buyer = await createUser(prisma);
    await prisma.user.update({ where: { id: buyer.user.id }, data: { country: 'UZ' } });
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const result = await fiscalJob.processFiscalReceipt({ orderId: order.id });
    expect(result.ok).toBe(true);
    const updated = await prisma.order.findUnique({ where: { id: order.id } });
    expect(updated.fiscalReceiptId).toBe(`mock-${order.id}`);
    expect(updated.fiscalReceiptUrl).toContain('soliq.uz/mock-receipt/');
    expect(updated.fiscalIssuedAt).not.toBeNull();
  });

  test('skips when shop has soliqEnabled=false', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    // soliqEnabled left default (false)
    const buyer = await createUser(prisma);
    await prisma.user.update({ where: { id: buyer.user.id }, data: { country: 'UZ' } });
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const result = await fiscalJob.processFiscalReceipt({ orderId: order.id });
    expect(result.skipped).toBe('shop_not_eligible');
    const updated = await prisma.order.findUnique({ where: { id: order.id } });
    expect(updated.fiscalReceiptId).toBeNull();
  });

  test('skips when shop has no soliqInn', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.shop.update({
      where: { id: shop.id },
      data: { soliqEnabled: true, soliqInn: null },
    });
    const buyer = await createUser(prisma);
    await prisma.user.update({ where: { id: buyer.user.id }, data: { country: 'UZ' } });
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const result = await fiscalJob.processFiscalReceipt({ orderId: order.id });
    expect(result.skipped).toBe('shop_not_eligible');
  });

  test('skips when buyer country !== UZ and currency !== UZS', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.shop.update({
      where: { id: shop.id },
      data: { soliqEnabled: true, soliqInn: '300000001' },
    });
    const buyer = await createUser(prisma);
    await prisma.user.update({ where: { id: buyer.user.id }, data: { country: 'KZ' } });
    const order = await makeOrder({
      shopId: shop.id,
      buyerId: buyer.user.id,
      currency: 'KZT',
    });

    const result = await fiscalJob.processFiscalReceipt({ orderId: order.id });
    expect(result.skipped).toBe('not_uz');
  });

  test('is idempotent — second call is a no-op', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.shop.update({
      where: { id: shop.id },
      data: { soliqEnabled: true, soliqInn: '300000001' },
    });
    const buyer = await createUser(prisma);
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const first = await fiscalJob.processFiscalReceipt({ orderId: order.id });
    expect(first.ok).toBe(true);
    const updatedAfterFirst = await prisma.order.findUnique({ where: { id: order.id } });
    const issuedAt = updatedAfterFirst.fiscalIssuedAt;

    const second = await fiscalJob.processFiscalReceipt({ orderId: order.id });
    expect(second.skipped).toBe('already_issued');
    expect(second.receiptId).toBe(`mock-${order.id}`);

    // fiscalIssuedAt should not change on the no-op call.
    const updatedAfterSecond = await prisma.order.findUnique({ where: { id: order.id } });
    expect(updatedAfterSecond.fiscalIssuedAt.getTime()).toBe(issuedAt.getTime());
  });

  test('records failure + admin notification when soliq returns a 5xx', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.shop.update({
      where: { id: shop.id },
      data: { soliqEnabled: true, soliqInn: '300000001' },
    });
    const admin = await createUser(prisma, { isAdmin: true });
    const buyer = await createUser(prisma);
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    // Force the mock to throw the way a 5xx would in production.
    const original = soliq.issueReceipt;
    soliq.issueReceipt = async () => { throw new Error('soliq_5xx_502'); };
    try {
      await expect(
        fiscalJob.processFiscalReceipt({ orderId: order.id }, { isFinalAttempt: true }),
      ).rejects.toThrow('soliq_5xx_502');
    } finally {
      soliq.issueReceipt = original;
    }

    const updated = await prisma.order.findUnique({ where: { id: order.id } });
    expect(updated.fiscalFailureCount).toBe(1);
    expect(updated.fiscalLastError).toContain('soliq_5xx_502');

    const adminNotes = await prisma.notification.findMany({
      where: { userId: admin.user.id, type: 'fiscal_failure' },
    });
    expect(adminNotes.length).toBe(1);
  });
});

describe('fiscal routes', () => {
  test('buyer can fetch their receipt URL', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.shop.update({
      where: { id: shop.id },
      data: { soliqEnabled: true, soliqInn: '300000001' },
    });
    const buyer = await createUser(prisma);
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });
    await fiscalJob.processFiscalReceipt({ orderId: order.id });

    const res = await request(app)
      .get(`/api/orders/${order.id}/fiscal-receipt`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.receiptId).toBe(`mock-${order.id}`);
    expect(res.body.receiptUrl).toContain('soliq.uz/mock-receipt/');
  });

  test('another user cannot see the receipt (403)', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.shop.update({
      where: { id: shop.id },
      data: { soliqEnabled: true, soliqInn: '300000001' },
    });
    const buyer = await createUser(prisma);
    const stranger = await createUser(prisma);
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });
    await fiscalJob.processFiscalReceipt({ orderId: order.id });

    const res = await request(app)
      .get(`/api/orders/${order.id}/fiscal-receipt`)
      .set('Authorization', stranger.auth);
    expect(res.status).toBe(403);
  });

  test('admin can re-trigger fiscal issue via POST /admin/orders/:id/fiscal-retry', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    await prisma.shop.update({
      where: { id: shop.id },
      data: { soliqEnabled: true, soliqInn: '300000001' },
    });
    const admin = await createUser(prisma, { isAdmin: true });
    const buyer = await createUser(prisma);
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const res = await request(app)
      .post(`/api/admin/orders/${order.id}/fiscal-retry`)
      .set('Authorization', admin.auth)
      .send({});
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    // Inline run should have populated the receipt.
    const updated = await prisma.order.findUnique({ where: { id: order.id } });
    expect(updated.fiscalReceiptId).toBe(`mock-${order.id}`);
  });
});
