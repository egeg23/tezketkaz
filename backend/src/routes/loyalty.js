// Loyalty endpoints — buyer wallet + referral.

const router = require('express').Router();
const crypto = require('crypto');
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const loyalty = require('../services/loyalty');

function generateReferralCode() {
  // 8-char base36 code from 5 random bytes (40 bits → ≤ 8 chars in base36).
  const n = parseInt(crypto.randomBytes(5).toString('hex'), 16);
  return n.toString(36).toUpperCase().padStart(8, '0').slice(-8);
}

// ─── GET /api/loyalty/me ─────────────────────────────────────────────────────
router.get('/me', authMiddleware, async (req, res, next) => {
  try {
    const account = await loyalty.getOrCreateAccount(prisma, req.user.id);
    const transactions = await prisma.loyaltyTransaction.findMany({
      where: { userId: req.user.id },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    res.json({
      tier: account.tier,
      points: account.points,
      cashback: account.cashback,
      lifetimeSpent: account.lifetimeSpent,
      transactions,
    });
  } catch (err) { next(err); }
});

// ─── GET /api/loyalty/me/referral-code ───────────────────────────────────────
router.get('/me/referral-code', authMiddleware, async (req, res, next) => {
  try {
    let user = await prisma.user.findUnique({ where: { id: req.user.id } });
    if (!user.referralCode) {
      // Try a few times in case of unique collision.
      for (let i = 0; i < 5; i++) {
        const candidate = generateReferralCode();
        try {
          user = await prisma.user.update({
            where: { id: req.user.id },
            data: { referralCode: candidate },
          });
          break;
        } catch (err) {
          if (i === 4) throw err;
        }
      }
    }
    res.json({ referralCode: user.referralCode });
  } catch (err) { next(err); }
});

// ─── POST /api/loyalty/me/use-referral ───────────────────────────────────────
router.post('/me/use-referral', authMiddleware, async (req, res, next) => {
  try {
    const { code } = req.body || {};
    if (!code || typeof code !== 'string') return res.status(400).json({ error: 'code required' });
    const cleaned = code.trim().toUpperCase();

    const me = await prisma.user.findUnique({ where: { id: req.user.id } });
    if (me.referredById) return res.status(400).json({ error: 'Already used a referral code' });
    if (me.referralCode === cleaned) return res.status(400).json({ error: 'Cannot use your own code' });

    const ordersCount = await prisma.order.count({ where: { buyerId: me.id } });
    if (ordersCount > 0) return res.status(400).json({ error: 'Referral codes are first-order only' });

    const referrer = await prisma.user.findUnique({ where: { referralCode: cleaned } });
    if (!referrer || referrer.id === me.id) {
      return res.status(404).json({ error: 'Referral code not found' });
    }

    await prisma.user.update({
      where: { id: me.id },
      data: { referredById: referrer.id },
    });

    res.json({ ok: true, referrerId: referrer.id });
  } catch (err) { next(err); }
});

module.exports = router;
module.exports.generateReferralCode = generateReferralCode;
