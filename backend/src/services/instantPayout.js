// Phase 8.5 — Instant payout. Couriers can request their accumulated
// earnings be paid out off-cycle (rather than waiting for the weekly
// aggregate). The flow is:
//
//   1. Courier hits POST /api/couriers/me/payout/request.
//   2. We compute their earned-but-not-yet-paid balance and refuse if it's
//      below MIN_PAYOUT_UZS or there's already a pending instant payout.
//   3. We create a Payout(status='requested', source='instant').
//   4. Admin reviews + approves (-> 'paid' with txnRef) or rejects (-> 'cancelled').
//   5. The weekly cron subtracts already-paid instant amounts so couriers
//      aren't paid twice for the same earnings.

const { audit } = require('../lib/audit');

const MIN_PAYOUT_UZS = 50000;

// Statuses we treat as "money is committed/already paid out for this courier".
// 'requested' is in the pipeline (admin pending), 'paid' is settled.
const COMMITTED_STATUSES = ['requested', 'paid'];

// Sum of (courierReward + tipAmount) across delivered orders for this courier.
async function totalEarned(prisma, courierId) {
  const agg = await prisma.order.aggregate({
    where: {
      courierId,
      status: { in: ['delivered', 'confirmedByBuyer'] },
    },
    _sum: { courierReward: true, tipAmount: true },
  });
  const reward = Number(agg._sum.courierReward || 0);
  const tips = Number(agg._sum.tipAmount || 0);
  return reward + tips;
}

// Sum of every Payout already paid or requested for this courier (instant or
// weekly). This is what we subtract from totalEarned to get the available
// balance.
async function totalCommittedPayouts(prisma, courierId) {
  const agg = await prisma.payout.aggregate({
    where: {
      recipientType: 'courier',
      recipientId: courierId,
      status: { in: COMMITTED_STATUSES },
    },
    _sum: { netAmount: true },
  });
  return Number(agg._sum.netAmount || 0);
}

async function availableBalance(prisma, courierId) {
  const earned = await totalEarned(prisma, courierId);
  const committed = await totalCommittedPayouts(prisma, courierId);
  const balance = earned - committed;
  return balance > 0 ? balance : 0;
}

async function hasPendingInstant(prisma, courierId) {
  const row = await prisma.payout.findFirst({
    where: {
      recipientType: 'courier',
      recipientId: courierId,
      source: 'instant',
      status: 'requested',
    },
    select: { id: true },
  });
  return !!row;
}

// Buyer-triggered instant payout request. Returns the created Payout row, or
// throws an Error with a `code` and HTTP `status` for known failure cases.
async function request(prisma, courierId, opts = {}) {
  if (!courierId) {
    throw Object.assign(new Error('courierId required'), { status: 400, code: 'invalid' });
  }

  if (await hasPendingInstant(prisma, courierId)) {
    throw Object.assign(new Error('A pending instant payout already exists'), {
      status: 400, code: 'pending_exists',
    });
  }

  const balance = await availableBalance(prisma, courierId);
  if (balance < MIN_PAYOUT_UZS) {
    throw Object.assign(new Error(`Balance below minimum (${MIN_PAYOUT_UZS} UZS)`), {
      status: 400, code: 'below_min', balance, minPayout: MIN_PAYOUT_UZS,
    });
  }

  const now = new Date();
  // Each instant payout is a unique row keyed on (courier, periodStart). We
  // use the request timestamp as periodStart to keep each instant payout
  // distinct from weekly rows. periodEnd = same instant.
  const row = await prisma.payout.create({
    data: {
      recipientType: 'courier',
      recipientId: courierId,
      periodStart: now,
      periodEnd: now,
      grossAmount: balance,
      commission: 0,
      refundsTotal: 0,
      netAmount: balance,
      ordersCount: 0,
      status: 'requested',
      source: 'instant',
      requestedAt: now,
    },
  });

  await audit({
    actorId: courierId,
    action: 'payout.instant_request',
    targetType: 'Payout',
    targetId: row.id,
    metadata: { netAmount: balance, source: 'instant' },
    ipAddress: opts.ipAddress || null,
  });

  return row;
}

// Admin transitions an instant Payout row to 'paid'. Reuses the same status
// shape as the weekly markPayoutPaid but enforces source='instant' so admins
// don't accidentally mis-route a weekly row through this endpoint.
async function approve(prisma, payoutId, { txnRef, notes, actorId, ipAddress } = {}) {
  if (!payoutId) {
    throw Object.assign(new Error('payoutId required'), { status: 400 });
  }
  const existing = await prisma.payout.findUnique({ where: { id: payoutId } });
  if (!existing) {
    throw Object.assign(new Error('Payout not found'), { status: 404 });
  }
  if (existing.source !== 'instant') {
    throw Object.assign(new Error('Not an instant payout'), { status: 400, code: 'not_instant' });
  }
  if (existing.status === 'paid') {
    return existing;
  }
  if (existing.status !== 'requested') {
    throw Object.assign(new Error(`Cannot approve from status ${existing.status}`), {
      status: 400, code: 'invalid_state',
    });
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
    action: 'payout.instant_approve',
    targetType: 'Payout',
    targetId: updated.id,
    metadata: { txnRef, notes, netAmount: updated.netAmount },
    ipAddress: ipAddress || null,
  });
  return updated;
}

// Admin rejects an instant payout. Sets status='cancelled' with notes.
async function reject(prisma, payoutId, { notes, actorId, ipAddress } = {}) {
  if (!payoutId) {
    throw Object.assign(new Error('payoutId required'), { status: 400 });
  }
  const existing = await prisma.payout.findUnique({ where: { id: payoutId } });
  if (!existing) {
    throw Object.assign(new Error('Payout not found'), { status: 404 });
  }
  if (existing.source !== 'instant') {
    throw Object.assign(new Error('Not an instant payout'), { status: 400, code: 'not_instant' });
  }
  if (existing.status === 'cancelled') {
    return existing;
  }
  if (existing.status !== 'requested') {
    throw Object.assign(new Error(`Cannot reject from status ${existing.status}`), {
      status: 400, code: 'invalid_state',
    });
  }
  const updated = await prisma.payout.update({
    where: { id: payoutId },
    data: {
      status: 'cancelled',
      notes: notes || existing.notes || null,
    },
  });
  await audit({
    actorId: actorId || null,
    action: 'payout.instant_reject',
    targetType: 'Payout',
    targetId: updated.id,
    metadata: { notes },
    ipAddress: ipAddress || null,
  });
  return updated;
}

module.exports = {
  MIN_PAYOUT_UZS,
  availableBalance,
  hasPendingInstant,
  request,
  approve,
  reject,
  // exposed for tests
  _totalEarned: totalEarned,
  _totalCommittedPayouts: totalCommittedPayouts,
};
