// Phase 11 — multi-shop cart drafts.
// Each (userId, shopId) pair has at most one draft (enforced by Prisma
// @@unique). The payload mirrors `CartProvider.toApiPayload()` on the Flutter
// side: an array of `{productId, quantity, modifiers}`. We compute itemCount
// and subtotal server-side by joining each line against its product so the
// list view doesn't have to trust client-side prices. Products that have been
// deleted since the draft was written are excluded from the count and
// surfaced via the `staleItems` field so the UI can warn the buyer.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const logger = require('../lib/logger');

const MAX_LINES = 50;

// Parse the stored payload string into an array; returns [] if anything is off
// (so a corrupt row never blows up a list response).
function parsePayload(raw) {
  if (!raw) return [];
  try {
    const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

// Validate the shape of a single line. Returns null on success, error message
// otherwise. We don't dictate the modifiers shape here — order placement is
// the canonical validator. The draft just needs to round-trip.
function validateLineShape(line, idx) {
  if (!line || typeof line !== 'object') return `item ${idx}: not an object`;
  if (typeof line.productId !== 'string' || !line.productId.trim()) {
    return `item ${idx}: productId required`;
  }
  const qty = Number(line.quantity);
  if (!Number.isFinite(qty) || qty < 1 || qty > 99) {
    return `item ${idx}: quantity must be 1..99`;
  }
  if (line.modifiers !== undefined && line.modifiers !== null && !Array.isArray(line.modifiers)) {
    return `item ${idx}: modifiers must be an array`;
  }
  return null;
}

// Given a payload + product map, compute itemCount + subtotal + staleItems.
// Uses discountPrice when set, mirroring orders.js priceItem(). Modifier
// price deltas are intentionally NOT included — the draft is a hint, the
// final price is recomputed at order time.
function summarisePayload(payload, productMap) {
  let itemCount = 0;
  let subtotal = 0;
  let staleItems = 0;
  for (const line of payload) {
    const product = productMap.get(line.productId);
    const qty = Math.max(1, Math.min(99, Number(line.quantity) || 1));
    if (!product || !product.isAvailable) {
      staleItems += 1;
      continue;
    }
    const unit = product.discountPrice ?? product.price;
    itemCount += qty;
    subtotal += unit * qty;
  }
  return { itemCount, subtotal, staleItems };
}

// ─── GET /api/cart-drafts/me ────────────────────────────────────────────────
// List all drafts owned by the current user, one per shop, with derived
// itemCount + subtotal joined from the underlying products. Most-recent first.
router.get('/me', authMiddleware, async (req, res, next) => {
  try {
    const drafts = await prisma.cartDraft.findMany({
      where: { userId: req.user.id },
      orderBy: { updatedAt: 'desc' },
    });

    if (drafts.length === 0) {
      return res.json({ drafts: [] });
    }

    const shopIds = [...new Set(drafts.map((d) => d.shopId))];
    const shops = await prisma.shop.findMany({
      where: { id: { in: shopIds } },
      select: { id: true, name: true, logoUrl: true, vertical: true, currency: true },
    });
    const shopMap = new Map(shops.map((s) => [s.id, s]));

    // Gather every productId across every draft so we can fetch them in one query.
    const allProductIds = new Set();
    const parsedByDraft = new Map();
    for (const d of drafts) {
      const payload = parsePayload(d.payload);
      parsedByDraft.set(d.id, payload);
      for (const line of payload) {
        if (line && typeof line.productId === 'string') allProductIds.add(line.productId);
      }
    }
    const products = allProductIds.size > 0
      ? await prisma.product.findMany({
          where: { id: { in: [...allProductIds] } },
          select: { id: true, price: true, discountPrice: true, isAvailable: true, shopId: true },
        })
      : [];
    const productMap = new Map(products.map((p) => [p.id, p]));

    const out = drafts.map((d) => {
      const shop = shopMap.get(d.shopId);
      const { itemCount, subtotal, staleItems } = summarisePayload(parsedByDraft.get(d.id), productMap);
      return {
        shopId: d.shopId,
        shopName: shop?.name || null,
        shopLogoUrl: shop?.logoUrl || null,
        shopVertical: shop?.vertical || null,
        shopCurrency: shop?.currency || 'UZS',
        itemCount,
        subtotal,
        staleItems,
        couponCode: d.couponCode,
        loyaltyPoints: d.loyaltyPoints,
        scheduledFor: d.scheduledFor,
        updatedAt: d.updatedAt,
      };
    });

    res.json({ drafts: out });
  } catch (err) { next(err); }
});

// ─── GET /api/cart-drafts/me/:shopId ────────────────────────────────────────
// Single-shop view — includes the raw payload so the Flutter cart screen can
// hydrate itself line-by-line.
router.get('/me/:shopId', authMiddleware, async (req, res, next) => {
  try {
    const { shopId } = req.params;
    const draft = await prisma.cartDraft.findUnique({
      where: { userId_shopId: { userId: req.user.id, shopId } },
    });
    if (!draft) return res.status(404).json({ error: 'Draft not found' });

    const payload = parsePayload(draft.payload);
    const productIds = payload
      .map((l) => l && l.productId)
      .filter((id) => typeof id === 'string');
    const [shop, products] = await Promise.all([
      prisma.shop.findUnique({
        where: { id: shopId },
        select: { id: true, name: true, logoUrl: true, vertical: true, currency: true },
      }),
      productIds.length
        ? prisma.product.findMany({
            where: { id: { in: productIds } },
            select: { id: true, price: true, discountPrice: true, isAvailable: true, shopId: true },
          })
        : [],
    ]);
    const productMap = new Map(products.map((p) => [p.id, p]));
    const { itemCount, subtotal, staleItems } = summarisePayload(payload, productMap);

    res.json({
      draft: {
        shopId: draft.shopId,
        shopName: shop?.name || null,
        shopLogoUrl: shop?.logoUrl || null,
        shopVertical: shop?.vertical || null,
        shopCurrency: shop?.currency || 'UZS',
        payload,
        itemCount,
        subtotal,
        staleItems,
        couponCode: draft.couponCode,
        loyaltyPoints: draft.loyaltyPoints,
        scheduledFor: draft.scheduledFor,
        updatedAt: draft.updatedAt,
      },
    });
  } catch (err) { next(err); }
});

// ─── PUT /api/cart-drafts/me/:shopId ────────────────────────────────────────
// Upsert the draft for (current user, shopId). The payload is validated for
// shape + cross-shop contamination (every product must belong to shopId and
// be available). Empty payloads are accepted so the buyer can "park" an
// intent to come back without us aggressively deleting the row.
router.put('/me/:shopId', authMiddleware, async (req, res, next) => {
  try {
    const { shopId } = req.params;
    const { payload, couponCode, loyaltyPoints, scheduledFor } = req.body || {};

    if (!Array.isArray(payload)) {
      return res.status(400).json({ error: 'payload must be an array' });
    }
    if (payload.length > MAX_LINES) {
      return res.status(400).json({ error: `payload exceeds ${MAX_LINES} lines` });
    }

    const shop = await prisma.shop.findUnique({
      where: { id: shopId },
      select: { id: true },
    });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });

    // Per-line shape validation.
    for (let i = 0; i < payload.length; i++) {
      const err = validateLineShape(payload[i], i);
      if (err) return res.status(400).json({ error: err });
    }

    // Cross-shop guard: every product must belong to shopId and be available.
    if (payload.length > 0) {
      const productIds = [...new Set(payload.map((l) => l.productId))];
      const products = await prisma.product.findMany({
        where: { id: { in: productIds } },
        select: { id: true, shopId: true, isAvailable: true },
      });
      const byId = new Map(products.map((p) => [p.id, p]));
      for (const id of productIds) {
        const p = byId.get(id);
        if (!p) return res.status(400).json({ error: `product ${id} not found` });
        if (p.shopId !== shopId) {
          return res.status(400).json({ error: `product ${id} does not belong to shop ${shopId}` });
        }
        if (!p.isAvailable) {
          return res.status(400).json({ error: `product ${id} is not available` });
        }
      }
    }

    let scheduledAt = null;
    if (scheduledFor !== undefined && scheduledFor !== null) {
      const when = new Date(scheduledFor);
      if (Number.isNaN(when.getTime())) {
        return res.status(400).json({ error: 'invalid scheduledFor' });
      }
      scheduledAt = when;
    }

    const points = Math.max(0, Math.floor(Number(loyaltyPoints) || 0));
    const code = couponCode == null ? null : String(couponCode).trim().toUpperCase() || null;

    const data = {
      payload: JSON.stringify(payload),
      couponCode: code,
      loyaltyPoints: points,
      scheduledFor: scheduledAt,
      // `updatedAt` is bumped automatically by @updatedAt, but be explicit so
      // it's obvious in the audit trail. Prisma will still rewrite it.
      updatedAt: new Date(),
    };

    const draft = await prisma.cartDraft.upsert({
      where: { userId_shopId: { userId: req.user.id, shopId } },
      create: { userId: req.user.id, shopId, ...data },
      update: data,
    });

    res.json({
      draft: {
        shopId: draft.shopId,
        payload: parsePayload(draft.payload),
        couponCode: draft.couponCode,
        loyaltyPoints: draft.loyaltyPoints,
        scheduledFor: draft.scheduledFor,
        updatedAt: draft.updatedAt,
      },
    });
  } catch (err) { next(err); }
});

// ─── DELETE /api/cart-drafts/me/:shopId ─────────────────────────────────────
// Drop a single draft. Returns 404 if there is no draft to drop, so callers
// can distinguish a no-op from a successful clear.
router.delete('/me/:shopId', authMiddleware, async (req, res, next) => {
  try {
    const { shopId } = req.params;
    const result = await prisma.cartDraft.deleteMany({
      where: { userId: req.user.id, shopId },
    });
    if (result.count === 0) return res.status(404).json({ error: 'Draft not found' });
    res.json({ deleted: true });
  } catch (err) { next(err); }
});

// ─── DELETE /api/cart-drafts/me ─────────────────────────────────────────────
// Bulk clear — invoked on logout / "empty cart" actions.
router.delete('/me', authMiddleware, async (req, res, next) => {
  try {
    const result = await prisma.cartDraft.deleteMany({
      where: { userId: req.user.id },
    });
    res.json({ deleted: result.count });
  } catch (err) { next(err); }
});

// Best-effort helper used by orders.js after a successful POST /api/orders.
// Returns true on success, false on failure (caller swallows the failure).
async function clearDraftAfterOrder(userId, shopId) {
  try {
    await prisma.cartDraft.deleteMany({ where: { userId, shopId } });
    return true;
  } catch (err) {
    logger.warn({ err: err.message, userId, shopId }, 'cart-draft cleanup failed');
    return false;
  }
}

module.exports = router;
module.exports.clearDraftAfterOrder = clearDraftAfterOrder;
