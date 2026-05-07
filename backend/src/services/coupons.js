// Coupon validation + discount computation. The validateCoupon entry point
// returns a structured `{ valid, discount, reason?, coupon }` shape so
// callers (orders, /api/coupons/validate) can branch without throwing.
//
// Coupon types:
//   PERCENT        — value is 1..100, optional maxDiscount cap.
//   FIXED          — value is UZS amount, capped by subtotal.
//   FREE_DELIVERY  — discount equals the deliveryFee for the order.

const VALID_TYPES = ['PERCENT', 'FIXED', 'FREE_DELIVERY'];

const REASONS = {
  NOT_FOUND: 'not_found',
  INACTIVE: 'inactive',
  EXPIRED: 'expired',
  NOT_STARTED: 'not_started',
  USAGE_LIMIT: 'usage_limit',
  USER_LIMIT: 'user_limit',
  MIN_ORDER: 'min_order',
  WRONG_VERTICAL: 'wrong_vertical',
  WRONG_SHOP: 'wrong_shop',
  FIRST_ORDER_ONLY: 'first_order_only',
};

function fail(reason, coupon = null) {
  return { valid: false, discount: 0, reason, coupon };
}

function computeDiscount(coupon, { subtotal = 0, deliveryFee = 0 } = {}) {
  if (!coupon) return 0;
  const sub = Math.max(0, Number(subtotal) || 0);
  const fee = Math.max(0, Number(deliveryFee) || 0);
  const value = Number(coupon.value) || 0;

  if (coupon.type === 'PERCENT') {
    let d = Math.round((sub * value) / 100);
    if (coupon.maxDiscount != null) d = Math.min(d, Number(coupon.maxDiscount));
    return Math.max(0, Math.min(d, sub));
  }
  if (coupon.type === 'FIXED') {
    return Math.max(0, Math.min(value, sub));
  }
  if (coupon.type === 'FREE_DELIVERY') {
    return fee;
  }
  return 0;
}

async function validateCoupon(prisma, { code, userId, vertical, shopId, subtotal, deliveryFee = 0 } = {}) {
  if (!code || typeof code !== 'string') {
    return fail(REASONS.NOT_FOUND);
  }
  const coupon = await prisma.coupon.findUnique({ where: { code } });
  if (!coupon) return fail(REASONS.NOT_FOUND);
  if (!coupon.isActive) return fail(REASONS.INACTIVE, coupon);

  const now = new Date();
  if (coupon.validFrom && now < new Date(coupon.validFrom)) return fail(REASONS.NOT_STARTED, coupon);
  if (coupon.validUntil && now > new Date(coupon.validUntil)) return fail(REASONS.EXPIRED, coupon);

  if (coupon.usageLimit != null && coupon.usedCount >= coupon.usageLimit) {
    return fail(REASONS.USAGE_LIMIT, coupon);
  }

  if (userId && coupon.usagePerUser != null) {
    const userUses = await prisma.couponRedemption.count({
      where: { couponCode: coupon.code, userId },
    });
    if (userUses >= coupon.usagePerUser) return fail(REASONS.USER_LIMIT, coupon);
  }

  if (coupon.minOrder != null && Number(subtotal || 0) < Number(coupon.minOrder)) {
    return fail(REASONS.MIN_ORDER, coupon);
  }

  if (coupon.vertical && vertical && coupon.vertical !== vertical) {
    return fail(REASONS.WRONG_VERTICAL, coupon);
  }
  if (coupon.shopId && shopId && coupon.shopId !== shopId) {
    return fail(REASONS.WRONG_SHOP, coupon);
  }
  // If coupon is scoped to a shop/vertical and caller didn't provide that
  // context, treat as wrong scope (defensive).
  if (coupon.shopId && !shopId) return fail(REASONS.WRONG_SHOP, coupon);
  if (coupon.vertical && !vertical) return fail(REASONS.WRONG_VERTICAL, coupon);

  if (coupon.firstOrderOnly && userId) {
    const prior = await prisma.order.count({
      where: { buyerId: userId, status: { not: 'cancelled' } },
    });
    if (prior > 0) return fail(REASONS.FIRST_ORDER_ONLY, coupon);
  }

  const discount = computeDiscount(coupon, { subtotal, deliveryFee });
  return { valid: true, discount, coupon };
}

module.exports = {
  validateCoupon,
  computeDiscount,
  VALID_TYPES,
  REASONS,
};
