const router = require('express').Router();
const jwt = require('jsonwebtoken');
const prisma = require('../db');
const { sendOtp } = require('../services/sms');
const { authMiddleware } = require('../middleware/auth');

function genCode() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function normalizePhone(phone) {
  // Always +998XXXXXXXXX
  const digits = phone.replace(/\D/g, '');
  return '+' + digits;
}

// ─── POST /api/auth/send-otp ─────────────────────────────────────────────────
router.post('/send-otp', async (req, res, next) => {
  try {
    const phone = normalizePhone(req.body.phone || '');
    if (!phone.match(/^\+998\d{9}$/)) {
      return res.status(400).json({ error: 'Invalid Uzbek phone number' });
    }

    // Limit: 1 OTP per minute
    const recent = await prisma.otpCode.findFirst({
      where: { phone, createdAt: { gt: new Date(Date.now() - 60_000) } },
    });
    if (recent) {
      return res.status(429).json({ error: 'Too many requests, wait 60s' });
    }

    // In dev: always 123456 for testing
    const code = process.env.NODE_ENV === 'production' ? genCode() : '123456';

    await prisma.otpCode.create({
      data: {
        phone, code,
        expiresAt: new Date(Date.now() + 5 * 60_000), // 5 min
      },
    });

    await sendOtp(phone, code);
    res.json({ success: true, devCode: process.env.NODE_ENV !== 'production' ? code : undefined });
  } catch (err) { next(err); }
});

// ─── POST /api/auth/verify-otp ───────────────────────────────────────────────
router.post('/verify-otp', async (req, res, next) => {
  try {
    const phone = normalizePhone(req.body.phone || '');
    const { code } = req.body;

    const otp = await prisma.otpCode.findFirst({
      where: { phone, code, used: false, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });

    if (!otp) {
      return res.status(400).json({ error: 'Invalid or expired code' });
    }

    await prisma.otpCode.update({ where: { id: otp.id }, data: { used: true } });

    // Find or create user
    let user = await prisma.user.findUnique({
      where: { phone },
      include: { shopMemberships: { include: { shop: true } } },
    });
    if (!user) {
      user = await prisma.user.create({
        data: { phone },
        include: { shopMemberships: { include: { shop: true } } },
      });
    }

    const token = jwt.sign(
      { userId: user.id },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '30d' },
    );

    res.json({ token, user: serializeUser(user) });
  } catch (err) { next(err); }
});

// ─── GET /api/auth/me ────────────────────────────────────────────────────────
router.get('/me', authMiddleware, async (req, res) => {
  res.json({ user: serializeUser(req.user) });
});

// ─── PATCH /api/auth/me ──────────────────────────────────────────────────────
router.patch('/me', authMiddleware, async (req, res, next) => {
  try {
    const { name } = req.body;
    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: { name },
      include: { shopMemberships: { include: { shop: true } } },
    });
    res.json({ user: serializeUser(user) });
  } catch (err) { next(err); }
});

function serializeUser(user) {
  return {
    id: user.id,
    phone: user.phone,
    name: user.name,
    avatarUrl: user.avatarUrl,
    isBuyer: user.isBuyer,
    isCourier: user.isCourier,
    isShop: user.isShop,
    courierStatus: user.courierStatus,
    rating: user.rating,
    ordersCount: user.ordersCount,
    shops: user.shopMemberships?.map(m => ({
      id: m.shop.id,
      name: m.shop.name,
      role: m.role,
    })) || [],
  };
}

module.exports = router;
