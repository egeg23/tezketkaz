// Phase 9.1 — GDPR data export tests.

const request = require('supertest');
const fs = require('fs');
const path = require('path');
const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const dataExport = require('../src/services/dataExport');

let ctx;
let prisma;
let buyer;
let buyer2;
let owner;
let shop;

beforeAll(async () => {
  ctx = await setupTestDb('data-export');
  prisma = ctx.prisma;
  buyer = await createUser(prisma, { name: 'Alice' });
  buyer2 = await createUser(prisma, { name: 'Bob' });
  owner = await createUser(prisma, { isShop: true });
  shop = await createShopWithOwner(prisma, owner.user);

  // Seed the buyer with some data: address + order + OTP code + refresh token.
  await prisma.address.create({
    data: { userId: buyer.user.id, label: 'Home', fullAddress: '1 A St' },
  });
  await prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'Alice', customerPhone: buyer.user.phone,
      shopId: shop.id,
      deliveryAddress: '1 A St', paymentMethod: 'cash',
      subtotal: 50000, total: 62000, courierReward: 12000,
      status: 'delivered',
    },
  });
  await prisma.otpCode.create({
    data: {
      phone: buyer.user.phone, code: '123456',
      expiresAt: new Date(Date.now() + 60_000),
    },
  });
  await prisma.refreshToken.create({
    data: {
      userId: buyer.user.id, jti: 'export-test-jti',
      expiresAt: new Date(Date.now() + 24 * 60 * 60_000),
    },
  });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('dataExport.buildExport', () => {
  test('returns user profile + orders + addresses; excludes OTPs and refresh tokens', async () => {
    const data = await dataExport.buildExport(prisma, buyer.user.id);
    expect(data.user.id).toBe(buyer.user.id);
    expect(data.user.name).toBe('Alice');
    expect(data.addresses.length).toBe(1);
    expect(data.orders.length).toBe(1);
    expect(data.orders[0].subtotal).toBe(50000);

    // Security: nothing OTP/refresh related leaks into the export blob.
    const flat = JSON.stringify(data);
    expect(flat).not.toContain('123456');
    expect(flat).not.toContain('export-test-jti');
  });
});

describe('dataExport.renderToFile', () => {
  test('creates a DataExport row with status=ready and fileUrl set', async () => {
    const row = await dataExport.renderToFile(prisma, buyer.user.id);
    expect(row.status).toBe('ready');
    expect(row.fileUrl).toBeTruthy();
    expect(row.expiresAt).toBeTruthy();

    // The local-fallback URL points at /uploads/exports/<user>/<id>.json
    // — confirm the file actually exists on disk.
    if (row.fileUrl.startsWith('/uploads/')) {
      const localPath = path.resolve(__dirname, '..', row.fileUrl.replace(/^\//, ''));
      expect(fs.existsSync(localPath)).toBe(true);
    }
  });
});

describe('GET /api/users/me/exports/:id', () => {
  test('returns 410 for expired exports', async () => {
    const expired = await prisma.dataExport.create({
      data: {
        userId: buyer.user.id,
        status: 'ready',
        fileUrl: '/uploads/exports/x/expired.json',
        expiresAt: new Date(Date.now() - 60_000),
      },
    });
    const res = await request(ctx.app)
      .get(`/api/users/me/exports/${expired.id}`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(410);
  });

  test('cross-user: user A cannot see user B exports', async () => {
    const bExport = await prisma.dataExport.create({
      data: {
        userId: buyer2.user.id,
        status: 'ready',
        fileUrl: '/uploads/exports/b/x.json',
        expiresAt: new Date(Date.now() + 60_000),
      },
    });
    const res = await request(ctx.app)
      .get(`/api/users/me/exports/${bExport.id}`)
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(404);
  });
});

describe('POST /api/users/me/export-data', () => {
  test('kicks off an export and returns 202 with exportId', async () => {
    const res = await request(ctx.app)
      .post('/api/users/me/export-data')
      .set('Authorization', buyer.auth)
      .send({});
    expect(res.status).toBe(202);
    expect(res.body.exportId).toBeTruthy();
    expect(['pending', 'ready']).toContain(res.body.status);
  });
});
