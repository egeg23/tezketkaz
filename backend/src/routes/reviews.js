// Phase 3: polymorphic reviews. Targets: SHOP | COURIER | PRODUCT.
// Aggregate ratings: Shop.rating and User.rating (courier) recomputed on POST.
// PRODUCT has no aggregate field yet — that's intentional, skip silently.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const logger = require('../lib/logger');

const TARGET_TYPES = new Set(['SHOP', 'COURIER', 'PRODUCT']);
const EDIT_WINDOW_MS = 24 * 60 * 60 * 1000;

function clampRating(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const r = Math.round(n);
  if (r < 1 || r > 5) return null;
  return r;
}

async function recomputeAggregate(targetType, targetId) {
  try {
    if (targetType === 'SHOP') {
      const agg = await prisma.review.aggregate({
        where: { targetType: 'SHOP', targetId, isVisible: true },
        _avg: { rating: true },
      });
      const avg = agg._avg.rating ?? 5.0;
      await prisma.shop.update({ where: { id: targetId }, data: { rating: avg } });
    } else if (targetType === 'COURIER') {
      const agg = await prisma.review.aggregate({
        where: { targetType: 'COURIER', targetId, isVisible: true },
        _avg: { rating: true },
      });
      const avg = agg._avg.rating ?? 5.0;
      await prisma.user.update({ where: { id: targetId }, data: { rating: avg } });
    }
    // PRODUCT: no aggregate field on Product — skip.
  } catch (err) {
    logger.warn({ err: err.message, targetType, targetId }, 'review aggregate failed');
  }
}

// ─── POST /api/orders/:orderId/reviews ──────────────────────────────────────
router.post('/orders/:orderId/reviews', authMiddleware, async (req, res, next) => {
  try {
    const { orderId } = req.params;
    const { targetType, targetId, rating, text, photos } = req.body || {};

    if (!TARGET_TYPES.has(targetType)) {
      return res.status(400).json({ error: 'Invalid targetType' });
    }
    const r = clampRating(rating);
    if (r == null) return res.status(400).json({ error: 'rating must be 1..5' });
    if (!targetId || typeof targetId !== 'string') {
      return res.status(400).json({ error: 'targetId required' });
    }

    const order = await prisma.order.findUnique({
      where: { id: orderId },
      include: { items: true },
    });
    if (!order) return res.status(404).json({ error: 'Order not found' });
    if (order.status !== 'delivered') {
      return res.status(400).json({ error: 'Order is not delivered' });
    }

    // Only the buyer of this order may post reviews of SHOP/COURIER/PRODUCT.
    // (Courier→Buyer reviews skipped until schema supports BUYER targetType.)
    if (order.buyerId !== req.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    // Validate targetId vs order.
    if (targetType === 'SHOP' && targetId !== order.shopId) {
      return res.status(400).json({ error: 'targetId mismatch (SHOP)' });
    }
    if (targetType === 'COURIER') {
      if (!order.courierId) return res.status(400).json({ error: 'no courier on order' });
      if (targetId !== order.courierId) {
        return res.status(400).json({ error: 'targetId mismatch (COURIER)' });
      }
    }
    if (targetType === 'PRODUCT') {
      const found = order.items.some((it) => it.productId === targetId);
      if (!found) return res.status(400).json({ error: 'targetId not in order items' });
    }

    let photosJson = null;
    if (Array.isArray(photos)) {
      photosJson = JSON.stringify(photos.slice(0, 10).map(String));
    }

    let review;
    try {
      review = await prisma.review.create({
        data: {
          orderId, reviewerId: req.user.id,
          targetType, targetId,
          rating: r,
          text: text ? String(text).slice(0, 2000) : null,
          photos: photosJson,
        },
      });
    } catch (err) {
      if (err.code === 'P2002') {
        return res.status(409).json({ error: 'Already reviewed' });
      }
      throw err;
    }

    await recomputeAggregate(targetType, targetId);

    res.status(201).json({ review });
  } catch (err) { next(err); }
});

// ─── GET /api/reviews?targetType=&targetId=&cursor=&limit= ──────────────────
router.get('/reviews', async (req, res, next) => {
  try {
    const { targetType, targetId } = req.query;
    if (!TARGET_TYPES.has(targetType)) {
      return res.status(400).json({ error: 'targetType required' });
    }
    if (!targetId) return res.status(400).json({ error: 'targetId required' });

    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const cursor = req.query.cursor ? { id: String(req.query.cursor) } : undefined;

    const reviews = await prisma.review.findMany({
      where: { targetType, targetId, isVisible: true },
      orderBy: { createdAt: 'desc' },
      take: limit + 1,
      ...(cursor ? { cursor, skip: 1 } : {}),
      include: { reviewer: { select: { id: true, name: true, avatarUrl: true } } },
    });

    const hasMore = reviews.length > limit;
    const out = (hasMore ? reviews.slice(0, limit) : reviews).map((rv) => ({
      id: rv.id,
      orderId: rv.orderId,
      reviewerId: rv.reviewerId,
      reviewerName: rv.reviewer?.name || null,
      reviewerAvatar: rv.reviewer?.avatarUrl || null,
      targetType: rv.targetType,
      targetId: rv.targetId,
      rating: rv.rating,
      text: rv.text,
      photos: rv.photos ? safeJson(rv.photos) : [],
      createdAt: rv.createdAt,
    }));

    res.json({
      reviews: out,
      nextCursor: hasMore ? out[out.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// ─── GET /api/reviews/:id ───────────────────────────────────────────────────
router.get('/reviews/:id', async (req, res, next) => {
  try {
    const rv = await prisma.review.findUnique({
      where: { id: req.params.id },
      include: { reviewer: { select: { id: true, name: true, avatarUrl: true } } },
    });
    if (!rv || !rv.isVisible) return res.status(404).json({ error: 'Not found' });
    res.json({
      review: {
        id: rv.id,
        orderId: rv.orderId,
        reviewerId: rv.reviewerId,
        reviewerName: rv.reviewer?.name || null,
        reviewerAvatar: rv.reviewer?.avatarUrl || null,
        targetType: rv.targetType,
        targetId: rv.targetId,
        rating: rv.rating,
        text: rv.text,
        photos: rv.photos ? safeJson(rv.photos) : [],
        createdAt: rv.createdAt,
        updatedAt: rv.updatedAt,
      },
    });
  } catch (err) { next(err); }
});

// ─── PATCH /api/reviews/:id ─────────────────────────────────────────────────
router.patch('/reviews/:id', authMiddleware, async (req, res, next) => {
  try {
    const rv = await prisma.review.findUnique({ where: { id: req.params.id } });
    if (!rv) return res.status(404).json({ error: 'Not found' });
    if (rv.reviewerId !== req.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const ageMs = Date.now() - new Date(rv.createdAt).getTime();
    if (ageMs > EDIT_WINDOW_MS) {
      return res.status(400).json({ error: 'Edit window expired' });
    }

    const { text, photos, rating } = req.body || {};
    const data = {};
    if (rating !== undefined) {
      const r = clampRating(rating);
      if (r == null) return res.status(400).json({ error: 'rating must be 1..5' });
      data.rating = r;
    }
    if (text !== undefined) data.text = text == null ? null : String(text).slice(0, 2000);
    if (photos !== undefined) {
      if (Array.isArray(photos)) {
        data.photos = JSON.stringify(photos.slice(0, 10).map(String));
      } else if (photos == null) {
        data.photos = null;
      } else {
        return res.status(400).json({ error: 'photos must be array' });
      }
    }
    if (Object.keys(data).length === 0) {
      return res.status(400).json({ error: 'No editable fields' });
    }

    const updated = await prisma.review.update({ where: { id: rv.id }, data });
    if (data.rating !== undefined) {
      await recomputeAggregate(rv.targetType, rv.targetId);
    }
    res.json({ review: updated });
  } catch (err) { next(err); }
});

// ─── DELETE /api/reviews/:id ────────────────────────────────────────────────
router.delete('/reviews/:id', authMiddleware, async (req, res, next) => {
  try {
    const rv = await prisma.review.findUnique({ where: { id: req.params.id } });
    if (!rv) return res.status(404).json({ error: 'Not found' });
    if (rv.reviewerId !== req.user.id && !req.user.isAdmin) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    await prisma.review.delete({ where: { id: rv.id } });
    await recomputeAggregate(rv.targetType, rv.targetId);
    res.json({ success: true });
  } catch (err) { next(err); }
});

function safeJson(s) {
  try { return JSON.parse(s); } catch { return []; }
}

module.exports = router;
