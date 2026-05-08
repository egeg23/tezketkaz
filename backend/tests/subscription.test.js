// Phase 7.2 — subscription service + routes.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb, createUser,
} = require('./helpers/db');
const subscription = require('../src/services/subscription');

let ctx;
let prisma;
let buyer;
let buyerB;

beforeAll(async () => {
  ctx = await setupTestDb('subscription');
  prisma = ctx.prisma;
  buyer = await createUser(prisma);
  buyerB = await createUser(prisma);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function savePaymentMethodFor(auth) {
  const r = await request(ctx.app)
    .post('/api/payment-methods/me/confirm')
    .set('Authorization', auth)
    .send({
      provider: 'click',
      mockToken: 'mock_click_token',
      last4: '1111',
      brand: 'visa',
    });
  if (!r.body.method) throw new Error('failed to create payment method: ' + JSON.stringify(r.body));
  return r.body.method;
}

describe('subscription.subscribe', () => {
  test('UZ + plus monthly + valid pm → membership active for ~30 days', async () => {
    const u = await createUser(prisma);
    const pm = await savePaymentMethodFor(u.auth);
    const r = await request(ctx.app)
      .post('/api/membership/subscribe')
      .set('Authorization', u.auth)
      .send({ tier: 'plus', billingPeriod: 'monthly', paymentMethodId: pm.id });

    expect(r.status).toBe(201);
    expect(r.body.membership.tier).toBe('plus');
    expect(r.body.membership.status).toBe('active');
    expect(r.body.membership.periodAmount).toBe(30000);
    expect(r.body.membership.currency).toBe('UZS');
    expect(r.body.membership.autoRenew).toBe(true);
    const end = new Date(r.body.membership.currentPeriodEnd).getTime();
    const now = Date.now();
    // ~30 days out (give or take a few days for month length variance).
    expect(end).toBeGreaterThan(now + 27 * 24 * 60 * 60 * 1000);
    expect(end).toBeLessThan(now + 33 * 24 * 60 * 60 * 1000);
  });

  test('country without pricing → not_available_in_country', async () => {
    const u = await createUser(prisma);
    await prisma.user.update({ where: { id: u.user.id }, data: { country: 'RU' } });
    const pm = await savePaymentMethodFor(u.auth);
    const r = await request(ctx.app)
      .post('/api/membership/subscribe')
      .set('Authorization', u.auth)
      .send({ tier: 'plus', billingPeriod: 'monthly', paymentMethodId: pm.id });
    expect(r.status).toBe(400);
    expect(r.body.error).toBe('not_available_in_country');
  });

  test('using another user\'s payment method → 404', async () => {
    const pmA = await savePaymentMethodFor(buyer.auth);
    const r = await request(ctx.app)
      .post('/api/membership/subscribe')
      .set('Authorization', buyerB.auth)
      .send({ tier: 'plus', billingPeriod: 'monthly', paymentMethodId: pmA.id });
    expect(r.status).toBe(404);
    expect(r.body.error).toBe('payment_method_not_found');
  });
});

describe('subscription.cancel + reactivate', () => {
  test('cancel sets autoRenew=false, status stays active', async () => {
    const u = await createUser(prisma);
    const pm = await savePaymentMethodFor(u.auth);
    await request(ctx.app)
      .post('/api/membership/subscribe')
      .set('Authorization', u.auth)
      .send({ tier: 'plus', billingPeriod: 'monthly', paymentMethodId: pm.id });

    const r = await request(ctx.app)
      .post('/api/membership/cancel')
      .set('Authorization', u.auth)
      .send({ reason: 'testing' });
    expect(r.status).toBe(200);
    expect(r.body.membership.autoRenew).toBe(false);
    expect(r.body.membership.status).toBe('active');
    expect(r.body.membership.cancelledAt).toBeTruthy();
  });

  test('reactivate flips autoRenew back to true while still in period', async () => {
    const u = await createUser(prisma);
    const pm = await savePaymentMethodFor(u.auth);
    await request(ctx.app)
      .post('/api/membership/subscribe')
      .set('Authorization', u.auth)
      .send({ tier: 'pro', billingPeriod: 'monthly', paymentMethodId: pm.id });
    await request(ctx.app)
      .post('/api/membership/cancel')
      .set('Authorization', u.auth);

    const r = await request(ctx.app)
      .post('/api/membership/reactivate')
      .set('Authorization', u.auth);
    expect(r.status).toBe(200);
    expect(r.body.membership.autoRenew).toBe(true);
    expect(r.body.membership.cancelledAt).toBeNull();
  });
});

describe('subscription.renewDueMemberships', () => {
  test('extends an active membership about to expire and resets failedRenewals', async () => {
    const u = await createUser(prisma);
    const pm = await savePaymentMethodFor(u.auth);
    await request(ctx.app)
      .post('/api/membership/subscribe')
      .set('Authorization', u.auth)
      .send({ tier: 'plus', billingPeriod: 'monthly', paymentMethodId: pm.id });

    // Force expiry to within 24h, simulate one prior failure.
    const soon = new Date(Date.now() + 60 * 60 * 1000); // +1h
    await prisma.membership.update({
      where: { userId: u.user.id },
      data: { currentPeriodEnd: soon, failedRenewals: 1 },
    });

    const summary = await subscription.renewDueMemberships(prisma);
    expect(summary.renewed).toBeGreaterThanOrEqual(1);

    const m = await prisma.membership.findUnique({ where: { userId: u.user.id } });
    expect(m.status).toBe('active');
    expect(m.failedRenewals).toBe(0);
    // currentPeriodEnd extended by ~30 days from `soon`.
    expect(m.currentPeriodEnd.getTime()).toBeGreaterThan(soon.getTime() + 27 * 24 * 60 * 60 * 1000);
  });

  test('three failed renewals → status=cancelled', async () => {
    const u = await createUser(prisma);
    const pm = await savePaymentMethodFor(u.auth);
    await request(ctx.app)
      .post('/api/membership/subscribe')
      .set('Authorization', u.auth)
      .send({ tier: 'plus', billingPeriod: 'monthly', paymentMethodId: pm.id });

    // Detach the payment method so renewal will fail.
    await prisma.paymentMethod.update({ where: { id: pm.id }, data: { isActive: false } });
    const soon = new Date(Date.now() + 60 * 60 * 1000);
    await prisma.membership.update({
      where: { userId: u.user.id },
      data: { currentPeriodEnd: soon, failedRenewals: 0 },
    });

    // Three sweeps, each finds the same due membership and bumps the counter.
    await subscription.renewDueMemberships(prisma);
    let m = await prisma.membership.findUnique({ where: { userId: u.user.id } });
    expect(m.failedRenewals).toBe(1);
    expect(m.status).toBe('past_due');

    // Reset state to be due again so the next sweep picks it up. status='active'
    // with future end + autoRenew — the worker rolls past_due back to active on
    // success but on continued failure we need to keep it in the candidate set,
    // which means we manually bump it back to active to model the retry path.
    await prisma.membership.update({
      where: { userId: u.user.id },
      data: { status: 'active', currentPeriodEnd: soon },
    });
    await subscription.renewDueMemberships(prisma);
    m = await prisma.membership.findUnique({ where: { userId: u.user.id } });
    expect(m.failedRenewals).toBe(2);

    await prisma.membership.update({
      where: { userId: u.user.id },
      data: { status: 'active', currentPeriodEnd: soon },
    });
    await subscription.renewDueMemberships(prisma);
    m = await prisma.membership.findUnique({ where: { userId: u.user.id } });
    expect(m.failedRenewals).toBe(3);
    expect(m.status).toBe('cancelled');
  });
});

describe('subscription.hasActive', () => {
  test('expired membership → false', async () => {
    const u = await createUser(prisma);
    await prisma.membership.create({
      data: {
        userId: u.user.id,
        tier: 'plus',
        status: 'active',
        currency: 'UZS',
        periodAmount: 30000,
        billingPeriod: 'monthly',
        currentPeriodEnd: new Date(Date.now() - 24 * 60 * 60 * 1000),
      },
    });
    expect(await subscription.hasActive(prisma, u.user.id)).toBe(false);
  });

  test('cancelled membership (status) → false', async () => {
    const u = await createUser(prisma);
    await prisma.membership.create({
      data: {
        userId: u.user.id,
        tier: 'plus',
        status: 'cancelled',
        currency: 'UZS',
        periodAmount: 30000,
        billingPeriod: 'monthly',
        currentPeriodEnd: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000),
      },
    });
    expect(await subscription.hasActive(prisma, u.user.id)).toBe(false);
  });

  test('active pro covers requiredTier=plus', async () => {
    const u = await createUser(prisma);
    await prisma.membership.create({
      data: {
        userId: u.user.id,
        tier: 'pro',
        status: 'active',
        currency: 'UZS',
        periodAmount: 60000,
        billingPeriod: 'monthly',
        currentPeriodEnd: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000),
      },
    });
    expect(await subscription.hasActive(prisma, u.user.id, 'plus')).toBe(true);
    expect(await subscription.hasActive(prisma, u.user.id, 'pro')).toBe(true);
  });

  test('active plus does NOT cover requiredTier=pro', async () => {
    const u = await createUser(prisma);
    await prisma.membership.create({
      data: {
        userId: u.user.id,
        tier: 'plus',
        status: 'active',
        currency: 'UZS',
        periodAmount: 30000,
        billingPeriod: 'monthly',
        currentPeriodEnd: new Date(Date.now() + 5 * 24 * 60 * 60 * 1000),
      },
    });
    expect(await subscription.hasActive(prisma, u.user.id, 'plus')).toBe(true);
    expect(await subscription.hasActive(prisma, u.user.id, 'pro')).toBe(false);
  });
});
