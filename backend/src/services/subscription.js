// Phase 7.2 — Wolt+ / Yandex Plus style membership service.
//
// Pricing per (country, tier, billingPeriod). UZ-only at launch; other
// country keys are populated by Phase 7.1 (multi-country) and stay empty
// here. When a country has no pricing entry, callers receive a
// `not_available_in_country` reason rather than a silent fallback.
//
// Renewal flow:
//   • A daily worker (jobs/membership.js) calls `renewDueMemberships` at
//     04:00 UTC.
//   • Memberships with `currentPeriodEnd` within the next 24h that are still
//     `active` and have `autoRenew=true` are charged via the saved payment
//     method's provider (`click` or `payme`) using `chargeWithToken`.
//   • Success → extend `currentPeriodEnd` by one billing period and reset
//     `failedRenewals=0`.
//   • Failure → increment `failedRenewals`, status becomes `past_due`. After
//     3 consecutive failures the membership is `cancelled`.
//   • Memberships that have already passed `currentPeriodEnd` and are still
//     `active` (e.g. renewal worker missed them, or autoRenew=false) are
//     marked `expired`.

const { audit } = require('../lib/audit');
const click = require('./click');
const payme = require('./payme');
const logger = require('../lib/logger');

// Pricing table — keyed by ISO country, then tier, then billingPeriod.
// Amounts are in major currency units (UZS sums, not tiyin).
const PRICING = {
  UZ: {
    plus: {
      monthly: { amount: 30000, currency: 'UZS' },
      yearly: { amount: 300000, currency: 'UZS' },
    },
    pro: {
      monthly: { amount: 60000, currency: 'UZS' },
      yearly: { amount: 600000, currency: 'UZS' },
    },
  },
  // KZ / KG / RU populated by Phase 7.1 (Agent B, multi-country).
};

// ─── Helpers ────────────────────────────────────────────────────────────────

const TIER_RANK = { plus: 1, pro: 2 };

function pricingFor(country, tier, billingPeriod) {
  const c = PRICING[country];
  if (!c) return null;
  const t = c[tier];
  if (!t) return null;
  return t[billingPeriod] || null;
}

function addPeriod(from, billingPeriod) {
  const d = new Date(from);
  if (billingPeriod === 'yearly') {
    d.setUTCFullYear(d.getUTCFullYear() + 1);
  } else {
    // monthly default
    d.setUTCMonth(d.getUTCMonth() + 1);
  }
  return d;
}

async function getProvider(provider) {
  if (provider === 'click') return click;
  if (provider === 'payme') return payme;
  return null;
}

// ─── Public API ─────────────────────────────────────────────────────────────

// True if user currently has an active membership at `requiredTier` or higher.
// Status === 'active' AND currentPeriodEnd in the future. Cancelled-but-still-
// in-period memberships count as active until they expire.
async function hasActive(prisma, userId, requiredTier = 'plus') {
  if (!userId) return false;
  const m = await prisma.membership.findUnique({ where: { userId } });
  if (!m) return false;
  if (m.status !== 'active') return false;
  if (!m.currentPeriodEnd || m.currentPeriodEnd.getTime() <= Date.now()) return false;
  const userRank = TIER_RANK[m.tier] || 0;
  const needRank = TIER_RANK[requiredTier] || 1;
  return userRank >= needRank;
}

// Subscribe (create or upgrade). Charges via saved payment method.
//
// Throws:
//   { status: 400, reason: 'not_available_in_country' }
//   { status: 400, reason: 'invalid_tier' | 'invalid_billing_period' }
//   { status: 404, reason: 'payment_method_not_found' }
//   { status: 402, reason: 'charge_failed', message }
async function subscribe(prisma, { userId, tier, billingPeriod, paymentMethodId }) {
  if (!userId) throw Object.assign(new Error('userId required'), { status: 400, reason: 'invalid_request' });
  if (!['plus', 'pro'].includes(tier)) {
    throw Object.assign(new Error('invalid tier'), { status: 400, reason: 'invalid_tier' });
  }
  if (!['monthly', 'yearly'].includes(billingPeriod)) {
    throw Object.assign(new Error('invalid billingPeriod'), { status: 400, reason: 'invalid_billing_period' });
  }

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) {
    throw Object.assign(new Error('user not found'), { status: 404, reason: 'user_not_found' });
  }

  const country = user.country || 'UZ';
  const price = pricingFor(country, tier, billingPeriod);
  if (!price) {
    throw Object.assign(new Error('subscription not available in country'), {
      status: 400,
      reason: 'not_available_in_country',
    });
  }

  // Verify payment method ownership + active.
  if (!paymentMethodId) {
    throw Object.assign(new Error('paymentMethodId required'), {
      status: 400,
      reason: 'payment_method_required',
    });
  }
  const method = await prisma.paymentMethod.findUnique({ where: { id: paymentMethodId } });
  if (!method || method.userId !== userId || !method.isActive) {
    throw Object.assign(new Error('payment method not found'), {
      status: 404,
      reason: 'payment_method_not_found',
    });
  }

  // Charge.
  const provider = await getProvider(method.provider);
  if (!provider) {
    throw Object.assign(new Error('provider_not_chargeable'), {
      status: 400,
      reason: 'provider_not_chargeable',
    });
  }
  const orderRef = `membership_${userId}_${Date.now()}`;
  const charge = await provider.chargeWithToken(
    method.providerId,
    price.amount,
    orderRef,
    price.currency,
  );
  if (!charge || !charge.ok) {
    audit({
      actorId: userId,
      action: 'membership.charge_failed',
      targetType: 'Membership',
      targetId: userId,
      metadata: {
        provider: method.provider,
        amount: price.amount,
        currency: price.currency,
        message: charge ? charge.message : 'unknown',
      },
    });
    throw Object.assign(new Error(charge ? charge.message : 'charge failed'), {
      status: 402,
      reason: 'charge_failed',
      message: charge ? charge.message : 'unknown',
    });
  }

  const now = new Date();
  const currentPeriodEnd = addPeriod(now, billingPeriod);

  const data = {
    tier,
    status: 'active',
    currency: price.currency,
    periodAmount: price.amount,
    billingPeriod,
    startedAt: now,
    currentPeriodEnd,
    cancelledAt: null,
    failedRenewals: 0,
    lastChargeAt: now,
    lastChargeError: null,
    autoRenew: true,
    paymentMethodId: method.id,
  };

  const membership = await prisma.membership.upsert({
    where: { userId },
    update: data,
    create: { userId, ...data },
  });

  audit({
    actorId: userId,
    action: 'membership.subscribe',
    targetType: 'Membership',
    targetId: membership.id,
    metadata: {
      tier,
      billingPeriod,
      amount: price.amount,
      currency: price.currency,
      provider: method.provider,
      externalId: charge.externalId,
    },
  });

  return membership;
}

// Cancel autorenew. The membership stays `active` until currentPeriodEnd is
// reached; the renewal worker then transitions it to `expired`. Idempotent —
// cancelling an already-cancelled (autoRenew=false) membership is a no-op.
async function cancel(prisma, userId, { reason } = {}) {
  const membership = await prisma.membership.findUnique({ where: { userId } });
  if (!membership) {
    throw Object.assign(new Error('membership not found'), { status: 404, reason: 'not_found' });
  }
  const updated = await prisma.membership.update({
    where: { userId },
    data: {
      autoRenew: false,
      cancelledAt: new Date(),
    },
  });
  audit({
    actorId: userId,
    action: 'membership.cancel',
    targetType: 'Membership',
    targetId: membership.id,
    metadata: { reason: reason || null },
  });
  return updated;
}

// Reactivate an autoRenew=false membership while still inside the active
// period. After currentPeriodEnd we require a fresh subscribe() call to
// re-charge — at that point the membership is `expired`.
async function reactivate(prisma, userId) {
  const membership = await prisma.membership.findUnique({ where: { userId } });
  if (!membership) {
    throw Object.assign(new Error('membership not found'), { status: 404, reason: 'not_found' });
  }
  if (membership.status !== 'active') {
    throw Object.assign(new Error('cannot reactivate non-active membership'), {
      status: 400,
      reason: 'not_active',
    });
  }
  if (!membership.currentPeriodEnd || membership.currentPeriodEnd.getTime() <= Date.now()) {
    throw Object.assign(new Error('period already ended'), { status: 400, reason: 'period_ended' });
  }
  const updated = await prisma.membership.update({
    where: { userId },
    data: {
      autoRenew: true,
      cancelledAt: null,
    },
  });
  audit({
    actorId: userId,
    action: 'membership.reactivate',
    targetType: 'Membership',
    targetId: membership.id,
  });
  return updated;
}

// Renewal worker — runs daily. Charges memberships about to expire and
// transitions stale rows. Returns a summary so the cron can log progress.
async function renewDueMemberships(prisma, now = new Date()) {
  const summary = { renewed: 0, failed: 0, expired: 0, cancelled: 0 };

  const horizon = new Date(now.getTime() + 24 * 60 * 60 * 1000); // +24h

  // 1) Mark already-expired active memberships (no autoRenew or missed window).
  const stale = await prisma.membership.findMany({
    where: {
      status: 'active',
      currentPeriodEnd: { lt: now },
    },
  });
  for (const m of stale) {
    await prisma.membership.update({
      where: { id: m.id },
      data: { status: 'expired' },
    });
    audit({
      actorId: m.userId,
      action: 'membership.expired',
      targetType: 'Membership',
      targetId: m.id,
    });
    summary.expired += 1;
  }

  // 2) Renew memberships about to expire and on autoRenew.
  const due = await prisma.membership.findMany({
    where: {
      status: 'active',
      autoRenew: true,
      currentPeriodEnd: { gte: now, lte: horizon },
    },
  });
  for (const m of due) {
    try {
      await renewOne(prisma, m, summary);
    } catch (err) {
      logger.warn({ err: err.message, membershipId: m.id }, 'renewal worker error');
    }
  }

  return summary;
}

async function renewOne(prisma, membership, summary) {
  if (!membership.paymentMethodId) {
    // Cannot charge without a method — bump failure counter.
    return markRenewalFailure(prisma, membership, 'no_payment_method', summary);
  }
  const method = await prisma.paymentMethod.findUnique({
    where: { id: membership.paymentMethodId },
  });
  if (!method || !method.isActive) {
    return markRenewalFailure(prisma, membership, 'method_inactive', summary);
  }
  const provider = await getProvider(method.provider);
  if (!provider) {
    return markRenewalFailure(prisma, membership, 'provider_not_chargeable', summary);
  }

  const orderRef = `membership_renew_${membership.userId}_${Date.now()}`;
  const charge = await provider.chargeWithToken(
    method.providerId,
    membership.periodAmount,
    orderRef,
    membership.currency,
  );

  if (!charge || !charge.ok) {
    return markRenewalFailure(
      prisma,
      membership,
      charge ? charge.message : 'unknown',
      summary,
    );
  }

  const now = new Date();
  const currentPeriodEnd = addPeriod(membership.currentPeriodEnd, membership.billingPeriod);
  await prisma.membership.update({
    where: { id: membership.id },
    data: {
      currentPeriodEnd,
      failedRenewals: 0,
      lastChargeAt: now,
      lastChargeError: null,
      status: 'active',
    },
  });
  audit({
    actorId: membership.userId,
    action: 'membership.renew',
    targetType: 'Membership',
    targetId: membership.id,
    metadata: {
      amount: membership.periodAmount,
      currency: membership.currency,
      externalId: charge.externalId,
      provider: method.provider,
    },
  });
  summary.renewed += 1;
}

async function markRenewalFailure(prisma, membership, message, summary) {
  const failures = (membership.failedRenewals || 0) + 1;
  const exhausted = failures >= 3;
  await prisma.membership.update({
    where: { id: membership.id },
    data: {
      failedRenewals: failures,
      lastChargeError: String(message || 'unknown').slice(0, 500),
      status: exhausted ? 'cancelled' : 'past_due',
      cancelledAt: exhausted ? new Date() : membership.cancelledAt,
    },
  });
  audit({
    actorId: membership.userId,
    action: exhausted ? 'membership.renew_exhausted' : 'membership.renew_failed',
    targetType: 'Membership',
    targetId: membership.id,
    metadata: { message, failures },
  });
  if (exhausted) summary.cancelled += 1;
  else summary.failed += 1;
}

// ─── Benefits ───────────────────────────────────────────────────────────────

// Static description of the perks each tier unlocks. The Flutter UI consumes
// this to render the benefits matrix without hard-coding strings.
const BENEFITS = {
  plus: [
    { code: 'half_delivery', label: '50% off delivery' },
    { code: 'loyalty_1_5x', label: '1.5x loyalty points' },
  ],
  pro: [
    { code: 'free_delivery', label: 'Free delivery on every order' },
    { code: 'loyalty_2x', label: '2x loyalty points' },
    { code: 'priority_support', label: 'Priority support' },
  ],
};

function benefitsFor(tier) {
  return BENEFITS[tier] || [];
}

module.exports = {
  PRICING,
  BENEFITS,
  pricingFor,
  benefitsFor,
  hasActive,
  subscribe,
  cancel,
  reactivate,
  renewDueMemberships,
  // exposed for tests
  _renewOne: renewOne,
  _addPeriod: addPeriod,
};
