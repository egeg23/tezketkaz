// Phase 8.3 — courier performance breakdown.
// Aggregates over the last N days (default 30):
//   acceptanceRate = accepted / (accepted + declined + timed_out)
//   completionRate = delivered / accepted
//   onTimeRate     = delivered within ETA / delivered
//   avgRating      = mean(Review.rating where target=COURIER)
//   ratingsBreakdown { '5': n, '4': n, ... }
//   totalEarnings  = sum(courierReward) over delivered orders
//   tipsTotal      = sum(tipAmount where tipPaidAt set)
//   totalOrders    = delivered count
//   byDay          = per-day { day, orders, earnings, rating }
//
// Mounted at /api/couriers; this router declares /me/performance so it can
// stack alongside the existing courier router without overwriting routes.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware, requireRole } = require('../middleware/auth');
const logger = require('../lib/logger');

// On-time threshold: a delivery is considered on-time when deliveredAt is at
// or before scheduledFor (when set), or within ON_TIME_BUFFER_MS of the
// "expected" timestamp derived from acceptedAt + ETA. With no scheduledFor
// and no recorded ETA, we fall back to (acceptedAt + 60min).
const DEFAULT_DELIVERY_BUDGET_MIN = 60;

function dayKey(d) {
  if (!d) return null;
  const x = (d instanceof Date) ? d : new Date(d);
  if (Number.isNaN(x.getTime())) return null;
  return x.toISOString().slice(0, 10); // YYYY-MM-DD
}

function isOnTime(order) {
  if (!order.deliveredAt) return false;
  if (order.scheduledFor) {
    return new Date(order.deliveredAt) <= new Date(order.scheduledFor);
  }
  // Fallback: budget after acceptedAt (or createdAt) plus the default.
  const start = order.acceptedAt || order.createdAt;
  if (!start) return true; // not enough data — treat as on-time
  const budget = DEFAULT_DELIVERY_BUDGET_MIN * 60 * 1000;
  return new Date(order.deliveredAt).getTime() <= new Date(start).getTime() + budget;
}

router.get('/me/performance', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const days = Math.min(365, Math.max(1, parseInt(req.query.days, 10) || 30));
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    const userId = req.user.id;

    // ── Dispatch offers (acceptance) ─────────────────────────────────────────
    const offers = await prisma.dispatchOffer.findMany({
      where: {
        courierId: userId,
        offeredAt: { gte: since },
        status: { in: ['accepted', 'declined', 'timed_out'] },
      },
      select: { status: true },
    });
    const accepted = offers.filter((o) => o.status === 'accepted').length;
    const declined = offers.filter((o) => o.status === 'declined').length;
    const timedOut = offers.filter((o) => o.status === 'timed_out').length;
    const offerDenom = accepted + declined + timedOut;
    const acceptanceRate = offerDenom > 0 ? accepted / offerDenom : 0;

    // ── Orders (delivery + earnings + ETA) ───────────────────────────────────
    const orders = await prisma.order.findMany({
      where: {
        courierId: userId,
        OR: [
          { deliveredAt: { gte: since } },
          { acceptedAt: { gte: since } },
        ],
      },
      select: {
        id: true,
        status: true,
        deliveredAt: true,
        acceptedAt: true,
        scheduledFor: true,
        createdAt: true,
        courierReward: true,
        tipAmount: true,
        tipPaidAt: true,
      },
    });

    const delivered = orders.filter((o) => o.status === 'delivered' || o.status === 'confirmedByBuyer');
    const totalOrders = delivered.length;
    const totalEarnings = delivered.reduce((s, o) => s + Number(o.courierReward || 0), 0);
    const tipsTotal = delivered
      .filter((o) => o.tipPaidAt)
      .reduce((s, o) => s + Number(o.tipAmount || 0), 0);
    const onTimeCount = delivered.filter(isOnTime).length;
    const onTimeRate = totalOrders > 0 ? onTimeCount / totalOrders : 0;

    // completionRate: delivered / accepted (within window).
    const completionRate = accepted > 0 ? Math.min(1, totalOrders / accepted) : 0;

    // ── Reviews (ratings) ────────────────────────────────────────────────────
    const reviews = await prisma.review.findMany({
      where: {
        targetType: 'COURIER',
        targetId: userId,
        isVisible: true,
        createdAt: { gte: since },
      },
      select: { rating: true },
    });
    const ratingsBreakdown = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
    let ratingSum = 0;
    for (const r of reviews) {
      const v = Math.max(1, Math.min(5, Math.round(r.rating)));
      ratingsBreakdown[v] += 1;
      ratingSum += v;
    }
    const avgRating = reviews.length ? ratingSum / reviews.length : 0;

    // ── byDay aggregation ────────────────────────────────────────────────────
    const dayMap = new Map();
    for (const o of delivered) {
      const key = dayKey(o.deliveredAt);
      if (!key) continue;
      let row = dayMap.get(key);
      if (!row) {
        row = { day: key, orders: 0, earnings: 0, _ratingSum: 0, _ratingCount: 0 };
        dayMap.set(key, row);
      }
      row.orders += 1;
      row.earnings += Number(o.courierReward || 0);
    }
    // Distribute ratings by createdAt date.
    const reviewsWithDate = await prisma.review.findMany({
      where: {
        targetType: 'COURIER',
        targetId: userId,
        isVisible: true,
        createdAt: { gte: since },
      },
      select: { rating: true, createdAt: true },
    });
    for (const r of reviewsWithDate) {
      const key = dayKey(r.createdAt);
      if (!key) continue;
      let row = dayMap.get(key);
      if (!row) {
        row = { day: key, orders: 0, earnings: 0, _ratingSum: 0, _ratingCount: 0 };
        dayMap.set(key, row);
      }
      row._ratingSum += Number(r.rating || 0);
      row._ratingCount += 1;
    }
    const byDay = [...dayMap.values()]
      .map((row) => ({
        day: row.day,
        orders: row.orders,
        earnings: row.earnings,
        rating: row._ratingCount > 0
          ? Number((row._ratingSum / row._ratingCount).toFixed(2))
          : null,
      }))
      .sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0));

    res.json({
      acceptanceRate: Number(acceptanceRate.toFixed(4)),
      completionRate: Number(completionRate.toFixed(4)),
      onTimeRate: Number(onTimeRate.toFixed(4)),
      avgRating: Number(avgRating.toFixed(2)),
      ratingsBreakdown,
      totalEarnings,
      totalOrders,
      tipsTotal,
      byDay,
      windowDays: days,
    });
  } catch (err) {
    logger.warn({ err: err.message, userId: req.user?.id }, 'courier performance failed');
    next(err);
  }
});

module.exports = router;
