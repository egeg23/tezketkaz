// Loyalty service — points + tiers + referrals.
//
// Earn rate: 1 point per 1000 UZS spent, multiplied by tier.
// Redeem rate: 1 point = 100 UZS discount at checkout.
//
// Tier promotion thresholds (lifetimeSpent UZS):
//   silver  500_000
//   gold    2_000_000
//   platinum 10_000_000

const TIER_MULT = { bronze: 1.0, silver: 1.2, gold: 1.5, platinum: 2.0 };

const TIER_THRESHOLDS = [
  { tier: 'platinum', min: 10_000_000 },
  { tier: 'gold', min: 2_000_000 },
  { tier: 'silver', min: 500_000 },
  { tier: 'bronze', min: 0 },
];

const POINT_RATE_UZS = 1000;     // 1 point per 1000 UZS
const SPEND_VALUE_UZS = 100;     // 1 point = 100 UZS discount
const REFERRAL_BONUS_POINTS = 500;

function tierForSpend(lifetimeSpent) {
  const v = Number(lifetimeSpent) || 0;
  for (const t of TIER_THRESHOLDS) {
    if (v >= t.min) return t.tier;
  }
  return 'bronze';
}

async function getOrCreateAccount(prisma, userId) {
  let account = await prisma.loyaltyAccount.findUnique({ where: { userId } });
  if (!account) {
    account = await prisma.loyaltyAccount.create({
      data: { userId, tier: 'bronze', points: 0, cashback: 0, lifetimeSpent: 0 },
    });
  }
  return account;
}

function pointsForOrder(account, orderTotal) {
  const total = Math.max(0, Number(orderTotal) || 0);
  const tier = (account && account.tier) || 'bronze';
  const mult = TIER_MULT[tier] ?? 1.0;
  return Math.floor((total / POINT_RATE_UZS) * mult);
}

async function creditOrder(prisma, userId, orderId, orderTotal) {
  if (!userId || !orderId) return { pointsAdded: 0, newTier: 'bronze' };
  const account = await getOrCreateAccount(prisma, userId);

  // Idempotency: if we already credited this order, skip.
  const existing = await prisma.loyaltyTransaction.findFirst({
    where: { userId, orderId, reason: 'earn_order' },
  });
  if (existing) {
    return { pointsAdded: 0, newTier: account.tier, alreadyCredited: true };
  }

  const pointsAdded = pointsForOrder(account, orderTotal);
  const newLifetime = (account.lifetimeSpent || 0) + (Number(orderTotal) || 0);
  const newTier = tierForSpend(newLifetime);

  await prisma.loyaltyAccount.update({
    where: { userId },
    data: {
      points: { increment: pointsAdded },
      lifetimeSpent: newLifetime,
      tier: newTier,
    },
  });
  await prisma.loyaltyTransaction.create({
    data: {
      userId,
      reason: 'earn_order',
      delta: pointsAdded,
      orderId,
    },
  });
  return { pointsAdded, newTier };
}

async function spendPoints(prisma, userId, amount, orderId) {
  const points = Math.max(0, Math.floor(Number(amount) || 0));
  if (points === 0) return { discount: 0, points: 0 };
  const account = await getOrCreateAccount(prisma, userId);
  if (account.points < points) {
    throw Object.assign(new Error('Insufficient loyalty points'), { status: 400, code: 'insufficient_points' });
  }
  await prisma.loyaltyAccount.update({
    where: { userId },
    data: { points: { decrement: points } },
  });
  await prisma.loyaltyTransaction.create({
    data: {
      userId,
      reason: 'spend_order',
      delta: -points,
      orderId: orderId || null,
    },
  });
  return { discount: points * SPEND_VALUE_UZS, points };
}

async function refundOrder(prisma, userId, orderId) {
  if (!userId || !orderId) return { reversed: 0 };
  const txs = await prisma.loyaltyTransaction.findMany({
    where: { userId, orderId, reason: { in: ['earn_order', 'spend_order'] } },
  });
  if (txs.length === 0) return { reversed: 0 };

  let netDelta = 0;
  for (const tx of txs) {
    netDelta += tx.delta;
  }
  // Reverse: subtract earned, refund spent.
  // earn_order had delta>0 → reverse means -delta
  // spend_order had delta<0 → reverse means -delta (i.e., +points back)
  const reversal = -netDelta;

  await prisma.loyaltyAccount.update({
    where: { userId },
    data: { points: { increment: reversal } },
  });
  await prisma.loyaltyTransaction.create({
    data: {
      userId,
      reason: 'refund',
      delta: reversal,
      orderId,
    },
  });
  return { reversed: reversal };
}

async function bonusReferral(prisma, refereeUserId) {
  if (!refereeUserId) return { credited: false };
  const user = await prisma.user.findUnique({ where: { id: refereeUserId } });
  if (!user || !user.referredById) return { credited: false };

  // Idempotency: only credit once per referee.
  const existing = await prisma.loyaltyTransaction.findFirst({
    where: { userId: refereeUserId, reason: 'bonus_referral' },
  });
  if (existing) return { credited: false, alreadyCredited: true };

  // Only on first delivered order.
  const deliveredCount = await prisma.order.count({
    where: { buyerId: refereeUserId, status: { in: ['delivered', 'confirmedByBuyer'] } },
  });
  if (deliveredCount === 0) return { credited: false };
  // First order only (we want to credit once, on the first delivered).
  if (deliveredCount > 1) return { credited: false };

  await getOrCreateAccount(prisma, refereeUserId);
  await getOrCreateAccount(prisma, user.referredById);

  await prisma.loyaltyAccount.update({
    where: { userId: refereeUserId },
    data: { points: { increment: REFERRAL_BONUS_POINTS } },
  });
  await prisma.loyaltyAccount.update({
    where: { userId: user.referredById },
    data: { points: { increment: REFERRAL_BONUS_POINTS } },
  });
  await prisma.loyaltyTransaction.createMany({
    data: [
      {
        userId: refereeUserId,
        reason: 'bonus_referral',
        delta: REFERRAL_BONUS_POINTS,
        metadata: JSON.stringify({ role: 'referee', referrerId: user.referredById }),
      },
      {
        userId: user.referredById,
        reason: 'bonus_referral',
        delta: REFERRAL_BONUS_POINTS,
        metadata: JSON.stringify({ role: 'referrer', refereeId: refereeUserId }),
      },
    ],
  });
  return { credited: true, points: REFERRAL_BONUS_POINTS };
}

module.exports = {
  TIER_MULT,
  POINT_RATE_UZS,
  SPEND_VALUE_UZS,
  REFERRAL_BONUS_POINTS,
  tierForSpend,
  getOrCreateAccount,
  pointsForOrder,
  creditOrder,
  spendPoints,
  refundOrder,
  bonusReferral,
};
