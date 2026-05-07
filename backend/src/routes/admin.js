const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');

// Admin authorization — пока проверяем по флагу `isAdmin`. В production добавить в User model.
function requireAdmin(req, res, next) {
  // TODO: добавить isAdmin поле в User модель и проверку здесь
  // Для прототипа: первый зарегистрированный пользователь = admin
  // ИЛИ настройка ADMIN_PHONES в .env
  const adminPhones = (process.env.ADMIN_PHONES || '').split(',').map(s => s.trim());
  if (adminPhones.length && !adminPhones.includes(req.user.phone)) {
    // Если ADMIN_PHONES задан — проверяем
    return res.status(403).json({ error: 'Admin only' });
  }
  next();
}

// ─── GET /api/admin/stats ────────────────────────────────────────────────────
router.get('/stats', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const [users, orders, couriers, pending, todayRevenue] = await Promise.all([
      prisma.user.count(),
      prisma.order.count(),
      prisma.user.count({ where: { isCourier: true, courierStatus: 'approved' } }),
      prisma.user.count({ where: { courierStatus: 'pending' } }),
      prisma.order.aggregate({
        where: {
          status: 'delivered',
          deliveredAt: { gte: new Date(new Date().setHours(0, 0, 0, 0)) },
        },
        _sum: { total: true },
      }),
    ]);
    res.json({
      users, orders, couriers, pending,
      revenue: todayRevenue._sum.total || 0,
    });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/couriers ─────────────────────────────────────────────────
router.get('/couriers', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const couriers = await prisma.user.findMany({
      where: { OR: [{ isCourier: true }, { courierStatus: { in: ['pending', 'rejected'] } }] },
      orderBy: [{ courierStatus: 'asc' }, { createdAt: 'desc' }],
    });
    res.json({ couriers });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/couriers/:id/approve ────────────────────────────────────
router.post('/couriers/:id/approve', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const user = await prisma.user.update({
      where: { id: req.params.id },
      data: { courierStatus: 'approved', isCourier: true },
    });
    res.json({ user });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/couriers/:id/reject ─────────────────────────────────────
router.post('/couriers/:id/reject', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const user = await prisma.user.update({
      where: { id: req.params.id },
      data: { courierStatus: 'rejected', isCourier: false },
    });
    res.json({ user });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/orders ───────────────────────────────────────────────────
router.get('/orders', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const orders = await prisma.order.findMany({
      orderBy: { createdAt: 'desc' },
      take: 100,
      include: { shop: true, courier: { select: { name: true, phone: true } } },
    });
    res.json({ orders });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/users ────────────────────────────────────────────────────
router.get('/users', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const users = await prisma.user.findMany({
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json({ users });
  } catch (err) { next(err); }
});

module.exports = router;
