// Phase 7.2 — membership routes (subscribe / cancel / reactivate / read).
//
// Endpoints (all require auth unless noted):
//   GET    /api/membership/me          → current membership + benefits + nextChargeAt
//   GET    /api/membership/pricing     → pricing matrix for the user's country
//   POST   /api/membership/subscribe   → body { tier, billingPeriod, paymentMethodId }
//   POST   /api/membership/cancel      → body { reason? }
//   POST   /api/membership/reactivate
//
// Admin (requireAdmin):
//   GET    /api/membership/admin       → list memberships with optional ?status= and ?tier=

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware, requireAdmin } = require('../middleware/auth');
const subscription = require('../services/subscription');

function sanitize(m) {
  if (!m) return null;
  return {
    id: m.id,
    userId: m.userId,
    tier: m.tier,
    status: m.status,
    currency: m.currency,
    periodAmount: m.periodAmount,
    billingPeriod: m.billingPeriod,
    startedAt: m.startedAt,
    currentPeriodEnd: m.currentPeriodEnd,
    cancelledAt: m.cancelledAt,
    autoRenew: m.autoRenew,
    failedRenewals: m.failedRenewals,
    paymentMethodId: m.paymentMethodId,
    lastChargeAt: m.lastChargeAt,
    lastChargeError: m.lastChargeError,
  };
}

// Map a thrown subscription-service error into a JSON response.
function sendError(res, err) {
  const status = err.status || 500;
  const body = { error: err.reason || err.message || 'error' };
  if (err.message && err.reason && err.reason !== err.message) body.message = err.message;
  return res.status(status).json(body);
}

// ─── GET /api/membership/me ─────────────────────────────────────────────────
router.get('/me', authMiddleware, async (req, res, next) => {
  try {
    const m = await prisma.membership.findUnique({ where: { userId: req.user.id } });
    if (!m) return res.json({ membership: null });
    const isActive = await subscription.hasActive(prisma, req.user.id, m.tier);
    res.json({
      membership: sanitize(m),
      isActive,
      benefits: subscription.benefitsFor(m.tier),
      nextChargeAt: m.autoRenew && m.status === 'active' ? m.currentPeriodEnd : null,
    });
  } catch (err) { next(err); }
});

// ─── GET /api/membership/pricing ────────────────────────────────────────────
router.get('/pricing', authMiddleware, async (req, res, next) => {
  try {
    const country = req.user.country || 'UZ';
    const matrix = subscription.PRICING[country] || null;
    res.json({
      country,
      pricing: matrix,
      benefits: { plus: subscription.benefitsFor('plus'), pro: subscription.benefitsFor('pro') },
      available: !!matrix,
    });
  } catch (err) { next(err); }
});

// ─── POST /api/membership/subscribe ─────────────────────────────────────────
router.post('/subscribe', authMiddleware, async (req, res, next) => {
  try {
    const { tier, billingPeriod, paymentMethodId } = req.body || {};
    const membership = await subscription.subscribe(prisma, {
      userId: req.user.id,
      tier,
      billingPeriod,
      paymentMethodId,
    });
    res.status(201).json({ membership: sanitize(membership) });
  } catch (err) {
    if (err && err.status) return sendError(res, err);
    next(err);
  }
});

// ─── POST /api/membership/cancel ────────────────────────────────────────────
router.post('/cancel', authMiddleware, async (req, res, next) => {
  try {
    const { reason } = req.body || {};
    const membership = await subscription.cancel(prisma, req.user.id, { reason });
    res.json({ membership: sanitize(membership) });
  } catch (err) {
    if (err && err.status) return sendError(res, err);
    next(err);
  }
});

// ─── POST /api/membership/reactivate ────────────────────────────────────────
router.post('/reactivate', authMiddleware, async (req, res, next) => {
  try {
    const membership = await subscription.reactivate(prisma, req.user.id);
    res.json({ membership: sanitize(membership) });
  } catch (err) {
    if (err && err.status) return sendError(res, err);
    next(err);
  }
});

// ─── GET /api/membership/admin ──────────────────────────────────────────────
router.get('/admin', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const where = {};
    if (req.query.status) where.status = String(req.query.status);
    if (req.query.tier) where.tier = String(req.query.tier);
    const [items, total] = await Promise.all([
      prisma.membership.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take: 200,
        include: { user: { select: { id: true, phone: true, name: true, country: true } } },
      }),
      prisma.membership.count({ where }),
    ]);
    res.json({ items: items.map((m) => ({ ...sanitize(m), user: m.user })), total });
  } catch (err) { next(err); }
});

module.exports = router;
