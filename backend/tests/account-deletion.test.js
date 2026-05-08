// Phase 9.2 — account deletion lifecycle tests.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const accountDeletion = require('../src/services/accountDeletion');

let ctx;
let prisma;

beforeAll(async () => {
  ctx = await setupTestDb('account-deletion');
  prisma = ctx.prisma;
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function freshUser(name) {
  return createUser(prisma, { name });
}

describe('accountDeletion.request', () => {
  test('sets deletedAt + scheduledFor=+30d, revokes all refresh tokens', async () => {
    const u = await freshUser('Alice');
    await prisma.refreshToken.create({
      data: {
        userId: u.user.id, jti: 'jti-' + u.user.id,
        expiresAt: new Date(Date.now() + 24 * 60 * 60_000),
      },
    });

    const before = Date.now();
    const req = await accountDeletion.request(prisma, u.user.id, 'leaving the platform');
    expect(req.status).toBe('pending');
    expect(req.scheduledFor.getTime()).toBeGreaterThanOrEqual(before + accountDeletion.GRACE_MS - 5000);
    expect(req.scheduledFor.getTime()).toBeLessThanOrEqual(before + accountDeletion.GRACE_MS + 5000);

    const updated = await prisma.user.findUnique({ where: { id: u.user.id } });
    expect(updated.deletedAt).not.toBeNull();

    const tokens = await prisma.refreshToken.findMany({ where: { userId: u.user.id } });
    for (const t of tokens) expect(t.revokedAt).not.toBeNull();
  });

  test('repeat request returns the existing pending row (no new timer)', async () => {
    const u = await freshUser('Charlie');
    const r1 = await accountDeletion.request(prisma, u.user.id, null);
    const r2 = await accountDeletion.request(prisma, u.user.id, 'changed mind');
    expect(r1.id).toBe(r2.id);
  });
});

describe('accountDeletion.cancel', () => {
  test('within grace period restores deletedAt=null', async () => {
    const u = await freshUser('Dana');
    const req = await accountDeletion.request(prisma, u.user.id, null);

    const cancelled = await accountDeletion.cancel(prisma, req.id, u.user.id);
    expect(cancelled.status).toBe('cancelled');
    expect(cancelled.cancelledAt).not.toBeNull();

    const restored = await prisma.user.findUnique({ where: { id: u.user.id } });
    expect(restored.deletedAt).toBeNull();
  });

  test('already-cancelled request cannot be cancelled again', async () => {
    const u = await freshUser('Eve');
    const req = await accountDeletion.request(prisma, u.user.id, null);
    await accountDeletion.cancel(prisma, req.id, u.user.id);
    await expect(
      accountDeletion.cancel(prisma, req.id, u.user.id),
    ).rejects.toMatchObject({ status: 400 });
  });

  test('elapsed grace period rejects cancel', async () => {
    const u = await freshUser('Frank');
    const req = await prisma.accountDeletionRequest.create({
      data: {
        userId: u.user.id,
        status: 'pending',
        requestedAt: new Date(Date.now() - 31 * 24 * 60 * 60_000),
        scheduledFor: new Date(Date.now() - 60_000),
      },
    });
    await expect(
      accountDeletion.cancel(prisma, req.id, u.user.id),
    ).rejects.toMatchObject({ status: 400 });
  });
});

describe('accountDeletion.purgeDue', () => {
  test('anonymises phone/email/name; drops addresses + payment-methods + favorites; keeps orders intact', async () => {
    const u = await freshUser('Greta');
    const owner = await freshUser('Owner-' + Date.now());
    owner.user.isShop = true;
    const shop = await createShopWithOwner(prisma, owner.user);

    // Pre-seed dependent data.
    await prisma.user.update({
      where: { id: u.user.id },
      data: { email: 'greta@example.com' },
    });
    await prisma.address.create({
      data: { userId: u.user.id, label: 'Home', fullAddress: 'X' },
    });
    await prisma.paymentMethod.create({
      data: { userId: u.user.id, provider: 'click', last4: '4242' },
    });
    await prisma.fcmToken.create({
      data: { userId: u.user.id, token: 'fcm-' + u.user.id, platform: 'ios' },
    });
    const order = await prisma.order.create({
      data: {
        buyerId: u.user.id,
        customerName: 'Greta', customerPhone: u.user.phone,
        shopId: shop.id,
        deliveryAddress: 'X', paymentMethod: 'cash',
        subtotal: 10000, total: 22000, courierReward: 12000,
        status: 'delivered',
      },
    });

    // Schedule the request in the past so purgeDue picks it up.
    await prisma.accountDeletionRequest.create({
      data: {
        userId: u.user.id,
        status: 'pending',
        scheduledFor: new Date(Date.now() - 60_000),
      },
    });

    const summary = await accountDeletion.purgeDue(prisma);
    // At least one result; for our user it should be ok.
    const ours = summary.results.find((r) => r.userId === u.user.id);
    expect(ours).toBeDefined();
    expect(ours.ok).toBe(true);

    const after = await prisma.user.findUnique({ where: { id: u.user.id } });
    expect(after.name).toBeNull();
    expect(after.email).toBeNull();
    expect(after.phone.startsWith('DELETED_')).toBe(true);

    const addresses = await prisma.address.findMany({ where: { userId: u.user.id } });
    expect(addresses.length).toBe(0);

    const pms = await prisma.paymentMethod.findMany({ where: { userId: u.user.id } });
    expect(pms.length).toBe(0);

    const fcms = await prisma.fcmToken.findMany({ where: { userId: u.user.id } });
    expect(fcms.length).toBe(0);

    // Orders survive — accounting requires it.
    const stillOrder = await prisma.order.findUnique({ where: { id: order.id } });
    expect(stillOrder).not.toBeNull();
    expect(stillOrder.subtotal).toBe(10000);

    const finalReq = await prisma.accountDeletionRequest.findFirst({
      where: { userId: u.user.id, status: 'completed' },
    });
    expect(finalReq).not.toBeNull();
    expect(finalReq.completedAt).not.toBeNull();
  });
});

describe('GDPR endpoints', () => {
  test('POST /me/delete-account creates a request', async () => {
    const u = await freshUser('Hank');
    const res = await request(ctx.app)
      .post('/api/users/me/delete-account')
      .set('Authorization', u.auth)
      .send({ reason: 'no longer using' });
    expect(res.status).toBe(202);
    expect(res.body.request.status).toBe('pending');
    expect(res.body.gracePeriodDays).toBe(30);
  });

  test('GET /me/deletion-status returns the active request', async () => {
    const u = await freshUser('Iris');
    await accountDeletion.request(prisma, u.user.id, null);
    const res = await request(ctx.app)
      .get('/api/users/me/deletion-status')
      .set('Authorization', u.auth);
    expect(res.status).toBe(200);
    expect(res.body.request).not.toBeNull();
    expect(res.body.request.status).toBe('pending');
  });
});
