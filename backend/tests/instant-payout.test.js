// Phase 8.5 — instant payout: balance computation, request flow, admin
// approve/reject, and weekly-payout interaction.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner,
} = require('./helpers/db');
const instantPayout = require('../src/services/instantPayout');
const payoutsSvc = require('../src/services/payouts');

let ctx;
let prisma;
let admin;
let owner;
let shop;
let buyer;

beforeAll(async () => {
  ctx = await setupTestDb('instant-payout');
  prisma = ctx.prisma;
  admin = await createUser(prisma, { isAdmin: true });
  owner = await createUser(prisma, { isShop: true });
  shop = await createShopWithOwner(prisma, owner.user);
  buyer = await createUser(prisma);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makeCourier() {
  return createUser(prisma, { isCourier: true, courierStatus: 'approved' });
}

async function makeDeliveredOrder({
  courierId, courierReward = 30000, tipAmount = 0, deliveredAt = new Date(),
}) {
  return prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'X', customerPhone: '+99800',
      shopId: shop.id, courierId,
      deliveryAddress: 'addr', paymentMethod: 'cash',
      subtotal: 100000, total: 100000, courierReward,
      tipAmount, tipPaidAt: tipAmount > 0 ? deliveredAt : null,
      status: 'delivered', deliveredAt,
    },
  });
}

describe('instantPayout.availableBalance', () => {
  test('aggregates rewards + tips minus committed payouts', async () => {
    const courier = await makeCourier();
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 30000, tipAmount: 5000 });
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 30000, tipAmount: 0 });
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 40000, tipAmount: 2000 });
    // 30+5+30+0+40+2 = 107000
    const balance1 = await instantPayout.availableBalance(prisma, courier.user.id);
    expect(balance1).toBe(107000);

    // Simulate a previously-paid weekly payout of 50000 — balance drops.
    await prisma.payout.create({
      data: {
        recipientType: 'courier', recipientId: courier.user.id,
        periodStart: new Date('2025-01-06T00:00:00Z'),
        periodEnd: new Date('2025-01-13T00:00:00Z'),
        grossAmount: 50000, netAmount: 50000, ordersCount: 2,
        status: 'paid', source: 'weekly',
      },
    });
    const balance2 = await instantPayout.availableBalance(prisma, courier.user.id);
    expect(balance2).toBe(57000);

    // A 'pending' (not paid/requested) row does not count as committed.
    await prisma.payout.create({
      data: {
        recipientType: 'courier', recipientId: courier.user.id,
        periodStart: new Date('2025-01-13T00:00:00Z'),
        periodEnd: new Date('2025-01-20T00:00:00Z'),
        grossAmount: 7000, netAmount: 7000, ordersCount: 1,
        status: 'pending', source: 'weekly',
      },
    });
    const balance3 = await instantPayout.availableBalance(prisma, courier.user.id);
    expect(balance3).toBe(57000);
  });
});

describe('POST /api/couriers/me/payout/request', () => {
  test('rejects when balance below minimum', async () => {
    const courier = await makeCourier();
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 10000 });
    const res = await request(ctx.app)
      .post('/api/couriers/me/payout/request')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(400);
    expect(res.body.reason).toBe('below_min');
  });

  test('creates a Payout(status=requested,source=instant) on success', async () => {
    const courier = await makeCourier();
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 60000 });
    const res = await request(ctx.app)
      .post('/api/couriers/me/payout/request')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(res.body.payout).toBeTruthy();
    expect(res.body.payout.status).toBe('requested');
    expect(res.body.payout.source).toBe('instant');
    expect(res.body.payout.netAmount).toBe(60000);
  });

  test('rejects when a pending instant payout already exists', async () => {
    const courier = await makeCourier();
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 60000 });
    const r1 = await request(ctx.app)
      .post('/api/couriers/me/payout/request')
      .set('Authorization', courier.auth);
    expect(r1.status).toBe(200);
    // A second order's reward should not enable a second concurrent request.
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 80000 });
    const r2 = await request(ctx.app)
      .post('/api/couriers/me/payout/request')
      .set('Authorization', courier.auth);
    expect(r2.status).toBe(400);
    expect(r2.body.reason).toBe('pending_exists');
  });
});

describe('GET /api/couriers/me/balance', () => {
  test('returns availableBalance + minPayout + hasPending', async () => {
    const courier = await makeCourier();
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 40000 });
    const res = await request(ctx.app)
      .get('/api/couriers/me/balance')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(res.body.availableBalance).toBe(40000);
    expect(res.body.minPayout).toBe(50000);
    expect(res.body.currency).toBe('UZS');
    expect(res.body.hasPending).toBe(false);
  });
});

describe('admin approve/reject', () => {
  test('approve transitions requested → paid with txnRef', async () => {
    const courier = await makeCourier();
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 60000 });
    const reqRes = await request(ctx.app)
      .post('/api/couriers/me/payout/request')
      .set('Authorization', courier.auth);
    const payoutId = reqRes.body.payout.id;

    const res = await request(ctx.app)
      .post(`/api/admin/payouts/${payoutId}/approve`)
      .set('Authorization', admin.auth)
      .send({ txnRef: 'TX-123', notes: 'Click transfer' });
    expect(res.status).toBe(200);
    expect(res.body.payout.status).toBe('paid');
    expect(res.body.payout.txnRef).toBe('TX-123');
    expect(res.body.payout.paidAt).toBeTruthy();
  });

  test('reject transitions requested → cancelled with notes', async () => {
    const courier = await makeCourier();
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 60000 });
    const reqRes = await request(ctx.app)
      .post('/api/couriers/me/payout/request')
      .set('Authorization', courier.auth);
    const payoutId = reqRes.body.payout.id;

    const res = await request(ctx.app)
      .post(`/api/admin/payouts/${payoutId}/reject`)
      .set('Authorization', admin.auth)
      .send({ notes: 'Suspicious activity' });
    expect(res.status).toBe(200);
    expect(res.body.payout.status).toBe('cancelled');
    expect(res.body.payout.notes).toBe('Suspicious activity');
  });

  test('approve refuses on non-instant payouts', async () => {
    const weekly = await prisma.payout.create({
      data: {
        recipientType: 'courier', recipientId: admin.user.id, // any id
        periodStart: new Date('2025-02-03T00:00:00Z'),
        periodEnd: new Date('2025-02-10T00:00:00Z'),
        grossAmount: 1000, netAmount: 1000, ordersCount: 1,
        status: 'pending', source: 'weekly',
      },
    });
    const res = await request(ctx.app)
      .post(`/api/admin/payouts/${weekly.id}/approve`)
      .set('Authorization', admin.auth)
      .send({ txnRef: 'X' });
    expect(res.status).toBe(400);
    expect(res.body.reason).toBe('not_instant');
  });
});

describe('GET /api/admin/payouts/instant', () => {
  test('lists only source=instant rows', async () => {
    const res = await request(ctx.app)
      .get('/api/admin/payouts/instant')
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.payouts)).toBe(true);
    for (const p of res.body.payouts) {
      expect(p.source).toBe('instant');
    }
  });
});

describe('weekly payout subtracts instant payouts in window', () => {
  test('weekly netAmount excludes already-paid instant amount', async () => {
    const courier = await makeCourier();

    // Pick a week deterministically — Monday 2026-06-01.
    const weekStart = new Date('2026-06-01T00:00:00.000Z');
    const inWeek = new Date('2026-06-03T12:00:00.000Z');

    // Courier earns 200k that week.
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 100000, deliveredAt: inWeek });
    await makeDeliveredOrder({ courierId: courier.user.id, courierReward: 100000, deliveredAt: inWeek });

    // Mid-week, courier withdraws 100k via instant payout (status: paid).
    await prisma.payout.create({
      data: {
        recipientType: 'courier', recipientId: courier.user.id,
        periodStart: inWeek, periodEnd: inWeek,
        grossAmount: 100000, netAmount: 100000, ordersCount: 0,
        status: 'paid', source: 'instant',
        requestedAt: inWeek, paidAt: inWeek,
        createdAt: inWeek,
      },
    });

    await payoutsSvc.generateWeeklyPayouts(prisma, { weekStart });

    const weekly = await prisma.payout.findFirst({
      where: {
        recipientType: 'courier', recipientId: courier.user.id,
        periodStart: weekStart, source: 'weekly',
      },
    });
    expect(weekly).not.toBeNull();
    // 200k earned - 100k already paid out = 100k weekly net.
    expect(weekly.netAmount).toBe(100000);
    expect(weekly.grossAmount).toBe(200000);
    const notes = JSON.parse(weekly.notes || '{}');
    expect(notes.instantTotal).toBe(100000);
  });
});
