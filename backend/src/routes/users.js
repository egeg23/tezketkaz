const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');

// ─── GET /api/users/me/stats — buyer stats ───────────────────────────────────
router.get('/me/stats', authMiddleware, async (req, res, next) => {
  try {
    const total = await prisma.order.count({ where: { buyerId: req.user.id } });
    const active = await prisma.order.count({
      where: { buyerId: req.user.id, status: { notIn: ['delivered', 'cancelled'] } },
    });
    const delivered = await prisma.order.count({
      where: { buyerId: req.user.id, status: 'delivered' },
    });
    res.json({ total, active, delivered });
  } catch (err) { next(err); }
});

// ─── GET /api/users/addresses ────────────────────────────────────────────────
router.get('/addresses', authMiddleware, async (req, res, next) => {
  try {
    const addresses = await prisma.address.findMany({
      where: { userId: req.user.id },
      orderBy: { isDefault: 'desc' },
    });
    res.json({ addresses });
  } catch (err) { next(err); }
});

// ─── POST /api/users/addresses ───────────────────────────────────────────────
router.post('/addresses', authMiddleware, async (req, res, next) => {
  try {
    const { label, fullAddress, lat, lng, comment, isDefault } = req.body;
    if (isDefault) {
      await prisma.address.updateMany({
        where: { userId: req.user.id }, data: { isDefault: false },
      });
    }
    const address = await prisma.address.create({
      data: { userId: req.user.id, label, fullAddress, lat, lng, comment, isDefault },
    });
    res.status(201).json({ address });
  } catch (err) { next(err); }
});

module.exports = router;
