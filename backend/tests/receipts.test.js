// Phase 13.3.3 — PDF receipts tests.
//
// Exercises:
//   • generateReceipt() returns a non-empty Buffer with a PDF magic header.
//   • GET /api/orders/:id/receipt returns 200 + application/pdf + the
//     correct Content-Disposition filename.
//   • Order owner (buyer) can download; assigned courier can download;
//     shop member can download; admin can download; an unrelated user
//     gets 403.
//   • An order with fiscal receipt data embeds the receipt URL string in
//     the generated PDF; an order without does not.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const receipts = require('../src/services/receipts');

let ctx;
let prisma;
let app;

let _productCache = {};
async function ensureProduct(shopId) {
  if (_productCache[shopId]) return _productCache[shopId];
  const p = await prisma.product.create({
    data: {
      shopId,
      name: 'Apple',
      nameUz: 'Olma',
      price: 25000,
      unit: 'шт',
      category: 'grocery',
      imageUrl: 'https://example.com/apple.jpg',
    },
  });
  _productCache[shopId] = p;
  return p;
}

async function makeOrder({
  shopId,
  buyerId,
  total = 50000,
  subtotal = 45000,
  deliveryFee = 5000,
  paymentMethod = 'click',
  currency = 'UZS',
  isPaid = true,
  status = 'delivered',
  itemQty = 2,
  itemPrice = 22500,
  withFiscal = false,
  taxRate = 0,
  taxAmount = 0,
  discount = 0,
}) {
  const product = await ensureProduct(shopId);
  const data = {
    buyerId,
    customerName: 'Алиса Тестовая',
    customerPhone: '+998901234567',
    shopId,
    deliveryAddress: 'ул. Бабура, 7, Ташкент',
    paymentMethod,
    isPaid,
    subtotal,
    total,
    deliveryFee,
    discount,
    taxRate,
    taxAmount,
    currency,
    status,
    orderNumber: `K-${Math.floor(Math.random() * 9000 + 1000)}`,
    items: {
      create: [
        {
          productId: product.id,
          productName: 'Apple',
          quantity: itemQty,
          price: itemPrice,
          total: itemQty * itemPrice,
        },
      ],
    },
  };
  if (withFiscal) {
    data.fiscalReceiptId = 'mock-fiscal-1';
    data.fiscalReceiptUrl = 'https://soliq.uz/mock-receipt/mock-fiscal-1';
    data.fiscalIssuedAt = new Date();
  }
  return prisma.order.create({
    data,
    include: { items: true, shop: true, buyer: true },
  });
}

beforeAll(async () => {
  ctx = await setupTestDb('receipts');
  prisma = ctx.prisma;
  app = ctx.app;
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

beforeEach(async () => {
  await prisma.notification.deleteMany({});
  await prisma.auditLog.deleteMany({});
  await prisma.orderItem.deleteMany({});
  await prisma.order.deleteMany({});
  await prisma.product.deleteMany({});
  await prisma.shopMember.deleteMany({});
  await prisma.shop.deleteMany({});
  _productCache = {};
});

describe('receipts.generateReceipt', () => {
  test('returns a non-empty Buffer with the PDF magic header', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    const buyer = await createUser(prisma);
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const buf = await receipts.generateReceipt(order.id);
    expect(Buffer.isBuffer(buf)).toBe(true);
    expect(buf.length).toBeGreaterThan(500);
    // PDF files start with "%PDF-".
    expect(buf.slice(0, 5).toString('utf8')).toBe('%PDF-');
  });

  test('throws when order does not exist', async () => {
    await expect(
      receipts.generateReceipt('00000000-0000-0000-0000-000000000000'),
    ).rejects.toThrow(/order_not_found/);
  });

  test('PDF for order with fiscal receipt embeds the receipt URL', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    const buyer = await createUser(prisma);
    const order = await makeOrder({
      shopId: shop.id,
      buyerId: buyer.user.id,
      withFiscal: true,
    });

    const buf = await receipts.generateReceipt(order.id);
    // PDF text is encoded but the URL appears as a plain string for the
    // annotation/link target — searching the raw bytes finds it.
    expect(buf.includes(Buffer.from('soliq.uz/mock-receipt/mock-fiscal-1'))).toBe(true);
  });

  test('PDF for order without fiscal receipt does NOT embed the soliq URL', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    const buyer = await createUser(prisma);
    const order = await makeOrder({
      shopId: shop.id,
      buyerId: buyer.user.id,
      withFiscal: false,
    });

    const buf = await receipts.generateReceipt(order.id);
    expect(buf.includes(Buffer.from('soliq.uz/mock-receipt/'))).toBe(false);
  });
});

describe('GET /api/orders/:id/receipt', () => {
  test('order owner (buyer) can download — 200 + application/pdf', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    const buyer = await createUser(prisma);
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const res = await request(app)
      .get(`/api/orders/${order.id}/receipt`)
      .set('Authorization', buyer.auth)
      .buffer(true)
      .parse((response, cb) => {
        const chunks = [];
        response.on('data', (c) => chunks.push(c));
        response.on('end', () => cb(null, Buffer.concat(chunks)));
      });
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toBe('application/pdf');
    expect(res.headers['content-disposition']).toMatch(
      /attachment; filename="tezketkaz-order-.+\.pdf"/,
    );
    expect(Buffer.isBuffer(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThan(500);
    expect(res.body.slice(0, 5).toString('utf8')).toBe('%PDF-');
  });

  test('shop member can download', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    const buyer = await createUser(prisma);
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const res = await request(app)
      .get(`/api/orders/${order.id}/receipt`)
      .set('Authorization', owner.auth);
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toBe('application/pdf');
  });

  test('assigned courier can download', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    const buyer = await createUser(prisma);
    const courier = await createUser(prisma, {
      isCourier: true,
      courierStatus: 'approved',
    });
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });
    await prisma.order.update({
      where: { id: order.id },
      data: { courierId: courier.user.id },
    });

    const res = await request(app)
      .get(`/api/orders/${order.id}/receipt`)
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
  });

  test('admin can download', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    const buyer = await createUser(prisma);
    const admin = await createUser(prisma, { isAdmin: true });
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const res = await request(app)
      .get(`/api/orders/${order.id}/receipt`)
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
  });

  test('unrelated user gets 403', async () => {
    const owner = await createUser(prisma, { isShop: true });
    const shop = await createShopWithOwner(prisma, owner.user);
    const buyer = await createUser(prisma);
    const stranger = await createUser(prisma);
    const order = await makeOrder({ shopId: shop.id, buyerId: buyer.user.id });

    const res = await request(app)
      .get(`/api/orders/${order.id}/receipt`)
      .set('Authorization', stranger.auth);
    expect(res.status).toBe(403);
  });

  test('unknown order id returns 404', async () => {
    const buyer = await createUser(prisma);
    const res = await request(app)
      .get('/api/orders/00000000-0000-0000-0000-000000000000/receipt')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(404);
  });
});
