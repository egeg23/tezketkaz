// Unit tests for the payouts service. Verifies weekly aggregation, idempotent
// upsert, status transitions, and CSV export.

const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const payoutsSvc = require('../src/services/payouts');

let ctx;
let prisma;
let buyer;
let courier;
let owner;
let shop;

beforeAll(async () => {
  ctx = await setupTestDb('payouts');
  prisma = ctx.prisma;
  buyer = await createUser(prisma);
  courier = await createUser(prisma);
  owner = await createUser(prisma, { isShop: true });
  shop = await createShopWithOwner(prisma, owner.user);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

// Build an order delivered at a specific time within a known week.
async function makeDeliveredOrder({ deliveredAt, subtotal = 100000, total = 112000, courierReward = 12000, refundedAmount = 0 }) {
  return prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'X', customerPhone: '+99800',
      shopId: shop.id, courierId: courier.user.id,
      deliveryAddress: 'addr', paymentMethod: 'cash',
      subtotal, total, courierReward, refundedAmount,
      status: 'delivered',
      deliveredAt,
    },
  });
}

describe('payouts.getWeekRange', () => {
  test('returns Monday 00:00 UTC for any day in the week', () => {
    // 2026-05-07 is Thursday → Monday is 2026-05-04.
    const { weekStart, weekEnd } = payoutsSvc.getWeekRange(new Date('2026-05-07T12:34:56Z'));
    expect(weekStart.toISOString()).toBe('2026-05-04T00:00:00.000Z');
    expect(weekEnd.toISOString()).toBe('2026-05-11T00:00:00.000Z');
  });
  test('Sunday rolls back to previous Monday', () => {
    const { weekStart } = payoutsSvc.getWeekRange(new Date('2026-05-10T23:59:00Z')); // Sunday
    expect(weekStart.toISOString()).toBe('2026-05-04T00:00:00.000Z');
  });
});

describe('payouts.generateWeeklyPayouts', () => {
  // Fix the week to avoid clashing with other tests.
  const weekStart = new Date('2026-04-06T00:00:00.000Z'); // a Monday
  const inWeek = new Date('2026-04-08T15:00:00.000Z');

  test('aggregates courier and shop rows', async () => {
    await makeDeliveredOrder({ deliveredAt: inWeek, subtotal: 100000, total: 112000, courierReward: 12000 });
    await makeDeliveredOrder({ deliveredAt: inWeek, subtotal: 200000, total: 212000, courierReward: 12000, refundedAmount: 50000 });

    const out = await payoutsSvc.generateWeeklyPayouts(prisma, { weekStart });
    expect(out.length).toBeGreaterThanOrEqual(2);

    const courierPayout = await prisma.payout.findFirst({
      where: { recipientType: 'courier', recipientId: courier.user.id, periodStart: weekStart },
    });
    expect(courierPayout).not.toBeNull();
    expect(courierPayout.grossAmount).toBe(24000);
    expect(courierPayout.netAmount).toBe(24000);
    expect(courierPayout.ordersCount).toBe(2);

    const shopPayout = await prisma.payout.findFirst({
      where: { recipientType: 'shop', recipientId: shop.id, periodStart: weekStart },
    });
    expect(shopPayout).not.toBeNull();
    expect(shopPayout.grossAmount).toBe(300000);
    expect(shopPayout.commission).toBeCloseTo(300000 * 0.15, 5);
    expect(shopPayout.refundsTotal).toBe(50000);
    expect(shopPayout.netAmount).toBeCloseTo(300000 - (300000 * 0.15) - 50000, 5);
  });

  test('re-running the same week is idempotent (upserts)', async () => {
    const out1 = await payoutsSvc.generateWeeklyPayouts(prisma, { weekStart });
    const before = await prisma.payout.count({ where: { periodStart: weekStart } });
    const out2 = await payoutsSvc.generateWeeklyPayouts(prisma, { weekStart });
    const after = await prisma.payout.count({ where: { periodStart: weekStart } });
    expect(after).toBe(before);
    expect(out2.length).toBe(out1.length);
  });
});

describe('payouts.markPayoutPaid', () => {
  test('flips status, sets paidAt + txnRef', async () => {
    const row = await prisma.payout.create({
      data: {
        recipientType: 'courier', recipientId: courier.user.id,
        periodStart: new Date('2026-03-30T00:00:00.000Z'),
        periodEnd: new Date('2026-04-06T00:00:00.000Z'),
        grossAmount: 50000, commission: 0, refundsTotal: 0, netAmount: 50000,
        ordersCount: 3, status: 'pending',
      },
    });
    const updated = await payoutsSvc.markPayoutPaid(prisma, row.id, { txnRef: 'TX-999', notes: 'manual' });
    expect(updated.status).toBe('paid');
    expect(updated.paidAt).not.toBeNull();
    expect(updated.txnRef).toBe('TX-999');
  });
});

describe('payouts.exportPayoutsCsv', () => {
  test('returns header + rows with expected columns', () => {
    const csv = payoutsSvc.exportPayoutsCsv([
      {
        recipientType: 'courier', recipientId: 'c1', recipientName: 'Ali',
        periodStart: new Date('2026-04-06T00:00:00.000Z'),
        periodEnd: new Date('2026-04-13T00:00:00.000Z'),
        grossAmount: 24000, commission: 0, refundsTotal: 0, netAmount: 24000,
        ordersCount: 2, status: 'pending', paidAt: null, txnRef: null,
      },
    ]);
    const lines = csv.split('\n');
    expect(lines[0]).toContain('recipientType,recipientId,recipientName');
    expect(lines[0]).toContain('netAmount');
    expect(lines[0]).toContain('txnRef');
    expect(lines.length).toBe(2);
    expect(lines[1]).toContain('courier');
    expect(lines[1]).toContain('Ali');
    expect(lines[1]).toContain('24000');
  });
  test('escapes commas/quotes', () => {
    const csv = payoutsSvc.exportPayoutsCsv([
      {
        recipientType: 'shop', recipientId: 's1', recipientName: 'My, "Best" Shop',
        periodStart: new Date('2026-04-06T00:00:00.000Z'),
        periodEnd: new Date('2026-04-13T00:00:00.000Z'),
        grossAmount: 0, commission: 0, refundsTotal: 0, netAmount: 0,
        ordersCount: 0, status: 'pending',
      },
    ]);
    expect(csv).toContain('"My, ""Best"" Shop"');
  });
});
