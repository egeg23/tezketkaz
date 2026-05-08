// Weekly payouts service — aggregates delivered orders into per-recipient
// (courier or shop) Payout rows. Idempotent via composite unique
// (recipientType, recipientId, periodStart). CSV export for admin downloads.

const { audit } = require('../lib/audit');

const COMMISSION_RATE = parseFloat(process.env.SHOP_COMMISSION || '0.15');

// Returns { weekStart, weekEnd } where weekStart is the most recent Monday
// 00:00 UTC at-or-before `forDate`, and weekEnd is +7 days.
function getWeekRange(forDate = new Date()) {
  const d = new Date(forDate);
  // Compute UTC components.
  const day = d.getUTCDay(); // 0=Sun..6=Sat; we want Monday=1
  const diff = (day + 6) % 7; // 0 for Mon, 1 for Tue, ..., 6 for Sun
  const start = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - diff, 0, 0, 0, 0));
  const end = new Date(start.getTime() + 7 * 24 * 60 * 60 * 1000);
  return { weekStart: start, weekEnd: end };
}

// Returns the Monday 00:00 UTC for the week immediately preceding `now`.
function getLastMonday(now = new Date()) {
  const { weekStart } = getWeekRange(now);
  return new Date(weekStart.getTime() - 7 * 24 * 60 * 60 * 1000);
}

async function generateWeeklyPayouts(prisma, { weekStart } = {}) {
  if (!weekStart) {
    weekStart = getLastMonday();
  }
  const start = new Date(weekStart);
  const end = new Date(start.getTime() + 7 * 24 * 60 * 60 * 1000);

  // Pull delivered orders within the window once.
  const orders = await prisma.order.findMany({
    where: {
      status: { in: ['delivered', 'confirmedByBuyer', 'refunded'] },
      deliveredAt: { gte: start, lt: end },
    },
    select: {
      id: true, shopId: true, courierId: true,
      subtotal: true, total: true, courierReward: true, refundedAmount: true,
    },
  });

  // ── Couriers: aggregate by courierId ──────────────────────────────────────
  const byCourier = new Map();
  for (const o of orders) {
    if (!o.courierId) continue;
    const e = byCourier.get(o.courierId) || { gross: 0, count: 0 };
    e.gross += Number(o.courierReward || 0);
    e.count += 1;
    byCourier.set(o.courierId, e);
  }

  // ── Shops: aggregate by shopId ────────────────────────────────────────────
  const byShop = new Map();
  for (const o of orders) {
    if (!o.shopId) continue;
    const e = byShop.get(o.shopId) || { gross: 0, refunds: 0, count: 0 };
    e.gross += Number(o.subtotal || 0);
    e.refunds += Number(o.refundedAmount || 0);
    e.count += 1;
    byShop.set(o.shopId, e);
  }

  const results = [];

  // Upsert courier payouts. Couriers don't bear refund cost.
  for (const [courierId, agg] of byCourier.entries()) {
    const grossAmount = agg.gross;
    const commission = 0;
    const refundsTotal = 0;
    const netAmount = grossAmount;
    const row = await prisma.payout.upsert({
      where: {
        recipientType_recipientId_periodStart: {
          recipientType: 'courier', recipientId: courierId, periodStart: start,
        },
      },
      create: {
        recipientType: 'courier',
        recipientId: courierId,
        periodStart: start,
        periodEnd: end,
        grossAmount, commission, refundsTotal, netAmount,
        ordersCount: agg.count,
        status: 'pending',
      },
      update: {
        periodEnd: end,
        grossAmount, commission, refundsTotal, netAmount,
        ordersCount: agg.count,
      },
    });
    results.push({
      recipientType: 'courier',
      recipientId: courierId,
      netAmount: row.netAmount,
      ordersCount: row.ordersCount,
      payoutId: row.id,
    });
  }

  // Upsert shop payouts. net = gross - commission - refunds.
  for (const [shopId, agg] of byShop.entries()) {
    const grossAmount = agg.gross;
    const commission = grossAmount * COMMISSION_RATE;
    const refundsTotal = agg.refunds;
    const netAmount = grossAmount - commission - refundsTotal;
    const row = await prisma.payout.upsert({
      where: {
        recipientType_recipientId_periodStart: {
          recipientType: 'shop', recipientId: shopId, periodStart: start,
        },
      },
      create: {
        recipientType: 'shop',
        recipientId: shopId,
        periodStart: start,
        periodEnd: end,
        grossAmount, commission, refundsTotal, netAmount,
        ordersCount: agg.count,
        status: 'pending',
      },
      update: {
        periodEnd: end,
        grossAmount, commission, refundsTotal, netAmount,
        ordersCount: agg.count,
      },
    });
    results.push({
      recipientType: 'shop',
      recipientId: shopId,
      netAmount: row.netAmount,
      ordersCount: row.ordersCount,
      payoutId: row.id,
    });
  }

  return results;
}

async function markPayoutPaid(prisma, payoutId, { txnRef, notes, actorId, ipAddress } = {}) {
  if (!payoutId) {
    throw Object.assign(new Error('payoutId required'), { status: 400 });
  }
  const existing = await prisma.payout.findUnique({ where: { id: payoutId } });
  if (!existing) {
    throw Object.assign(new Error('Payout not found'), { status: 404 });
  }
  if (existing.status === 'paid') {
    return existing;
  }
  const updated = await prisma.payout.update({
    where: { id: payoutId },
    data: {
      status: 'paid',
      paidAt: new Date(),
      txnRef: txnRef || existing.txnRef || null,
      notes: notes || existing.notes || null,
    },
  });
  await audit({
    actorId: actorId || null,
    action: 'payout.pay',
    targetType: 'Payout',
    targetId: updated.id,
    metadata: { txnRef, notes, netAmount: updated.netAmount, recipientType: updated.recipientType },
    ipAddress: ipAddress || null,
  });
  return updated;
}

function escapeCsvField(v) {
  if (v === null || v === undefined) return '';
  const s = String(v);
  if (/[",\n\r]/.test(s)) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

const CSV_COLUMNS = [
  'recipientType', 'recipientId', 'recipientName',
  'periodStart', 'periodEnd',
  'grossAmount', 'commission', 'refundsTotal', 'netAmount',
  'ordersCount', 'status', 'paidAt', 'txnRef',
];

// payouts: array of payout-like objects, each may have `recipientName` already
// resolved; otherwise blank.
function exportPayoutsCsv(payouts) {
  const rows = [CSV_COLUMNS.join(',')];
  for (const p of payouts || []) {
    const periodStart = p.periodStart ? new Date(p.periodStart).toISOString() : '';
    const periodEnd = p.periodEnd ? new Date(p.periodEnd).toISOString() : '';
    const paidAt = p.paidAt ? new Date(p.paidAt).toISOString() : '';
    const cells = [
      p.recipientType,
      p.recipientId,
      p.recipientName || '',
      periodStart,
      periodEnd,
      p.grossAmount,
      p.commission,
      p.refundsTotal,
      p.netAmount,
      p.ordersCount,
      p.status,
      paidAt,
      p.txnRef || '',
    ].map(escapeCsvField);
    rows.push(cells.join(','));
  }
  return rows.join('\n');
}

module.exports = {
  COMMISSION_RATE,
  getWeekRange,
  getLastMonday,
  generateWeeklyPayouts,
  markPayoutPaid,
  exportPayoutsCsv,
  CSV_COLUMNS,
};
