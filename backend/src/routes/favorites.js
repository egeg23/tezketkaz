// Phase 7.3 — buyer favorites (products + shops).
//
// All endpoints require the user to be authenticated; favorites are strictly
// user-scoped. Adds are idempotent so the UI can call POST without checking
// state first.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const logger = require('../lib/logger');

// ─── GET /api/favorites/me — full list with embedded info ───────────────────
router.get('/me', authMiddleware, async (req, res, next) => {
  try {
    const rows = await prisma.favorite.findMany({
      where: { userId: req.user.id },
      orderBy: { createdAt: 'desc' },
    });

    const productIds = rows.filter((f) => f.productId).map((f) => f.productId);
    const shopIds = rows.filter((f) => f.shopId).map((f) => f.shopId);

    const [products, shops] = await Promise.all([
      productIds.length
        ? prisma.product.findMany({
            where: { id: { in: productIds } },
            include: { shop: { select: { id: true, name: true, vertical: true, isActive: true } } },
          })
        : [],
      shopIds.length
        ? prisma.shop.findMany({
            where: { id: { in: shopIds } },
            select: { id: true, name: true, logoUrl: true, vertical: true, isActive: true, rating: true },
          })
        : [],
    ]);
    const productMap = new Map(products.map((p) => [p.id, p]));
    const shopMap = new Map(shops.map((s) => [s.id, s]));

    const favorites = rows.map((f) => ({
      id: f.id,
      productId: f.productId,
      shopId: f.shopId,
      createdAt: f.createdAt,
      product: f.productId ? productMap.get(f.productId) || null : null,
      shop: f.shopId ? shopMap.get(f.shopId) || null : null,
    }));
    res.json({ favorites });
  } catch (err) { next(err); }
});

// ─── POST /api/favorites/me/products/:productId ─────────────────────────────
router.post('/me/products/:productId', authMiddleware, async (req, res, next) => {
  try {
    const product = await prisma.product.findUnique({ where: { id: req.params.productId } });
    if (!product) return res.status(404).json({ error: 'Product not found' });

    const existing = await prisma.favorite.findUnique({
      where: { userId_productId: { userId: req.user.id, productId: product.id } },
    });
    if (existing) {
      return res.json({ favorite: existing, alreadyExists: true });
    }
    const favorite = await prisma.favorite.create({
      data: { userId: req.user.id, productId: product.id },
    });
    res.status(201).json({ favorite });
  } catch (err) {
    // Race-condition fallback: unique constraint violation → idempotent 200.
    if (err && err.code === 'P2002') {
      const fav = await prisma.favorite.findUnique({
        where: { userId_productId: { userId: req.user.id, productId: req.params.productId } },
      });
      return res.json({ favorite: fav, alreadyExists: true });
    }
    next(err);
  }
});

// ─── DELETE /api/favorites/me/products/:productId ───────────────────────────
router.delete('/me/products/:productId', authMiddleware, async (req, res, next) => {
  try {
    const fav = await prisma.favorite.findUnique({
      where: { userId_productId: { userId: req.user.id, productId: req.params.productId } },
    });
    if (!fav) return res.status(404).json({ error: 'Not favorited' });
    await prisma.favorite.delete({ where: { id: fav.id } });
    res.json({ deleted: true });
  } catch (err) { next(err); }
});

// ─── POST /api/favorites/me/shops/:shopId ───────────────────────────────────
router.post('/me/shops/:shopId', authMiddleware, async (req, res, next) => {
  try {
    const shop = await prisma.shop.findUnique({ where: { id: req.params.shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });

    const existing = await prisma.favorite.findUnique({
      where: { userId_shopId: { userId: req.user.id, shopId: shop.id } },
    });
    if (existing) {
      return res.json({ favorite: existing, alreadyExists: true });
    }
    const favorite = await prisma.favorite.create({
      data: { userId: req.user.id, shopId: shop.id },
    });
    res.status(201).json({ favorite });
  } catch (err) {
    if (err && err.code === 'P2002') {
      const fav = await prisma.favorite.findUnique({
        where: { userId_shopId: { userId: req.user.id, shopId: req.params.shopId } },
      });
      return res.json({ favorite: fav, alreadyExists: true });
    }
    next(err);
  }
});

// ─── DELETE /api/favorites/me/shops/:shopId ─────────────────────────────────
router.delete('/me/shops/:shopId', authMiddleware, async (req, res, next) => {
  try {
    const fav = await prisma.favorite.findUnique({
      where: { userId_shopId: { userId: req.user.id, shopId: req.params.shopId } },
    });
    if (!fav) return res.status(404).json({ error: 'Not favorited' });
    await prisma.favorite.delete({ where: { id: fav.id } });
    res.json({ deleted: true });
  } catch (err) { next(err); }
});

// ─── GET /api/favorites/me/check?productId=&shopId= ─────────────────────────
router.get('/me/check', authMiddleware, async (req, res, next) => {
  try {
    const { productId, shopId } = req.query;
    if (!productId && !shopId) {
      return res.status(400).json({ error: 'productId or shopId required' });
    }
    let fav = null;
    if (productId) {
      fav = await prisma.favorite.findUnique({
        where: { userId_productId: { userId: req.user.id, productId: String(productId) } },
      });
    } else if (shopId) {
      fav = await prisma.favorite.findUnique({
        where: { userId_shopId: { userId: req.user.id, shopId: String(shopId) } },
      });
    }
    res.json({ isFavorite: !!fav });
  } catch (err) { next(err); }
});

module.exports = router;
