const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');

// ─── GET /api/shops ──────────────────────────────────────────────────────────
router.get('/', async (req, res, next) => {
  try {
    const shops = await prisma.shop.findMany({
      where: { isActive: true },
      orderBy: { rating: 'desc' },
    });
    res.json({ shops });
  } catch (err) { next(err); }
});

// ─── GET /api/shops/:id ──────────────────────────────────────────────────────
router.get('/:id', async (req, res, next) => {
  try {
    const shop = await prisma.shop.findUnique({
      where: { id: req.params.id },
      include: { products: { where: { isAvailable: true } } },
    });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });
    res.json({ shop });
  } catch (err) { next(err); }
});

// ─── POST /api/shops/connect ─────────────────────────────────────────────────
// Прототип — в реальности магазин подключается через invite-код
router.post('/connect', authMiddleware, async (req, res, next) => {
  try {
    const { shopId } = req.body;
    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });

    await prisma.shopMember.upsert({
      where: { userId_shopId: { userId: req.user.id, shopId } },
      update: {},
      create: { userId: req.user.id, shopId, role: 'manager' },
    });

    await prisma.user.update({
      where: { id: req.user.id },
      data: { isShop: true },
    });

    res.json({ success: true });
  } catch (err) { next(err); }
});

module.exports = router;
