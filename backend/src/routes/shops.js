const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const shopHours = require('../services/shopHours');
const { audit } = require('../lib/audit');

// Phase 13.2.7 — fix vendor-next 403s by exposing owner-callable
// PATCH /api/shops/:id and GET /api/shops/:id/stats endpoints. The admin
// console keeps its existing /api/admin/shops/* surface; this one is scoped
// to the shop owner (or any owner/manager member) by walking ShopMember.
async function isShopOwnerOrAdmin(user, shopId) {
  if (!user) return false;
  if (user.isAdmin) return true;
  const m = await prisma.shopMember.findUnique({
    where: { userId_shopId: { userId: user.id, shopId } },
  });
  return !!m && (m.role === 'owner' || m.role === 'manager');
}
const disputesSvc = require('../services/disputes');

// Phase 13.2.6 — shop-owner endpoints (refunds, coupons, analytics) reuse the
// same ShopMember-based auth that products.js + orders.js use. Any member
// (including non-owner managers) may view; resolve/create operations are
// audited so abuse is traceable.
async function requireShopMember(req, shopId) {
  if (!shopId || !req.user) return false;
  if (req.user.isAdmin) return true;
  const m = await prisma.shopMember.findUnique({
    where: { userId_shopId: { userId: req.user.id, shopId } },
  });
  return !!m;
}

function normalizeCouponCode(c) {
  return String(c || '').trim().toUpperCase();
}

const COUPON_TYPES = ['PERCENT', 'FIXED', 'FREE_DELIVERY'];

function validateCouponBody(body, { partial = false } = {}) {
  const errors = [];
  if (!partial || body.type !== undefined) {
    if (!COUPON_TYPES.includes(body.type)) {
      errors.push('type must be PERCENT|FIXED|FREE_DELIVERY');
    }
  }
  if (!partial || body.value !== undefined) {
    const v = Number(body.value);
    if (!Number.isFinite(v) || v < 0) errors.push('value must be a non-negative number');
    if (body.type === 'PERCENT' && (v <= 0 || v > 100)) errors.push('PERCENT value must be 1..100');
  }
  if (!partial || body.validFrom !== undefined) {
    if (!body.validFrom || Number.isNaN(new Date(body.validFrom).getTime())) {
      errors.push('validFrom required (ISO date)');
    }
  }
  if (!partial || body.validUntil !== undefined) {
    if (!body.validUntil || Number.isNaN(new Date(body.validUntil).getTime())) {
      errors.push('validUntil required (ISO date)');
    }
  }
  if (body.validFrom && body.validUntil
      && new Date(body.validFrom) >= new Date(body.validUntil)) {
    errors.push('validUntil must be after validFrom');
  }
  if (body.usageLimit != null) {
    const n = Number(body.usageLimit);
    if (!Number.isInteger(n) || n < 0) errors.push('usageLimit must be a non-negative integer');
  }
  if (body.usagePerUser != null) {
    const n = Number(body.usagePerUser);
    if (!Number.isInteger(n) || n < 1) errors.push('usagePerUser must be >= 1');
  }
  return errors;
}

// Phase 6.4 — annotate a shop with currentlyOpen + opensAt + currency.
// Mutates a shallow copy and returns it.
async function enrichShop(shop, hoursById = null) {
  if (!shop) return shop;
  let workingHours;
  if (hoursById) {
    workingHours = hoursById.get(shop.id) || [];
  } else {
    workingHours = await prisma.shopWorkingHours.findMany({
      where: { shopId: shop.id },
      orderBy: [{ dayOfWeek: 'asc' }, { startsAt: 'asc' }],
    });
  }
  const isOpen = shopHours.isOpenNow({ ...shop, workingHours });
  const out = {
    ...shop,
    currency: shop.currency || 'UZS',
    workingHours,
    currentlyOpen: isOpen,
  };
  if (!isOpen) {
    const next = shopHours.nextOpenAt({ ...shop, workingHours });
    out.opensAt = next ? next.toISOString() : null;
  } else {
    out.opensAt = null;
  }
  return out;
}

// Great-circle distance in km using the haversine formula.
function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// ─── GET /api/shops ──────────────────────────────────────────────────────────
// Public list with optional geo filter.
//   vertical, isActive (default true), q (LIKE on name)
//   lat,lng,radiusKm — if all three provided, filters + sorts by distance ASC
//   limit (default 30, max 100)
router.get('/', async (req, res, next) => {
  try {
    const { vertical, q } = req.query;
    const limit = Math.min(parseInt(req.query.limit, 10) || 30, 100);

    const where = {};
    if (req.query.isActive === undefined) {
      where.isActive = true;
    } else {
      where.isActive = req.query.isActive === 'true' || req.query.isActive === '1';
    }
    if (vertical) where.vertical = vertical;
    if (q && String(q).trim()) {
      where.name = { contains: String(q) };
    }

    const lat = req.query.lat !== undefined ? Number(req.query.lat) : null;
    const lng = req.query.lng !== undefined ? Number(req.query.lng) : null;
    const radiusKm = req.query.radiusKm !== undefined ? Number(req.query.radiusKm) : null;
    const geo = Number.isFinite(lat) && Number.isFinite(lng) && Number.isFinite(radiusKm);

    let shops;
    if (geo) {
      // Fetch a reasonably wide pool (we have to compute distance in JS). Cap
      // the working set at 1000 to keep memory bounded.
      const pool = await prisma.shop.findMany({ where, take: 1000 });
      const withDist = [];
      for (const s of pool) {
        if (s.lat == null || s.lng == null) continue;
        const distanceKm = haversineKm(lat, lng, s.lat, s.lng);
        if (distanceKm <= radiusKm) withDist.push({ ...s, distanceKm });
      }
      withDist.sort((a, b) => a.distanceKm - b.distanceKm);
      shops = withDist.slice(0, limit);
    } else {
      shops = await prisma.shop.findMany({
        where,
        orderBy: { rating: 'desc' },
        take: limit,
      });
    }

    // Batch-load working hours for the result set so we don't do N queries.
    let hoursById = new Map();
    if (shops.length > 0) {
      const ids = shops.map((s) => s.id);
      const hours = await prisma.shopWorkingHours.findMany({
        where: { shopId: { in: ids } },
        orderBy: [{ dayOfWeek: 'asc' }, { startsAt: 'asc' }],
      });
      for (const h of hours) {
        const arr = hoursById.get(h.shopId) || [];
        arr.push(h);
        hoursById.set(h.shopId, arr);
      }
    }
    const enriched = await Promise.all(shops.map((s) => enrichShop(s, hoursById)));

    res.json({ items: enriched, shops: enriched, total: enriched.length });
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
    const enriched = await enrichShop(shop);
    res.json({ shop: enriched });
  } catch (err) { next(err); }
});

// ─── PATCH /api/shops/:id ────────────────────────────────────────────────────
// Phase 13.2.7 — owner/manager-callable. Lets a shop owner edit storefront
// details (name, description, address, phone, currency) and delivery economics
// (deliveryBaseFee, deliveryPerKm, freeDeliveryKm, minOrderAmount). Mirrors
// the admin PATCH but restricts the ALLOWED set: shop owners cannot flip
// isActive or change vertical — those remain admin-only.
router.patch('/:id', authMiddleware, async (req, res, next) => {
  try {
    const shopId = req.params.id;
    const exists = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!exists) return res.status(404).json({ error: 'Shop not found' });
    if (!(await isShopOwnerOrAdmin(req.user, shopId))) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const ALLOWED = [
      'name', 'description', 'address', 'phone', 'currency',
      'deliveryBaseFee', 'deliveryPerKm', 'freeDeliveryKm', 'minOrderAmount',
      'logoUrl',
    ];
    const data = {};
    for (const k of ALLOWED) {
      if (req.body && Object.prototype.hasOwnProperty.call(req.body, k)) {
        data[k] = req.body[k];
      }
    }
    for (const num of ['deliveryBaseFee', 'deliveryPerKm', 'freeDeliveryKm', 'minOrderAmount']) {
      if (data[num] === '' || data[num] === null) {
        data[num] = null;
      } else if (data[num] !== undefined) {
        const n = Number(data[num]);
        if (!Number.isFinite(n) || n < 0) {
          return res.status(400).json({ error: `${num} must be a non-negative number` });
        }
        data[num] = n;
      }
    }
    if (data.name !== undefined && (!data.name || !String(data.name).trim())) {
      return res.status(400).json({ error: 'name cannot be empty' });
    }

    const shop = await prisma.shop.update({ where: { id: shopId }, data });
    audit({
      actorId: req.user.id,
      action: 'shop.update_self',
      targetType: 'Shop', targetId: shop.id,
      metadata: data, ipAddress: req.ip,
    });
    const enriched = await enrichShop(shop);
    res.json({ shop: enriched });
  } catch (err) {
    if (err && err.code === 'P2025') return res.status(404).json({ error: 'Not found' });
    next(err);
  }
});

// ─── GET /api/shops/:id/stats?days=14 ───────────────────────────────────────
// Phase 13.2.7 — owner/manager-callable. Returns the dashboard KPIs the
// vendor-next dashboard expected to find at this path (instead of falling
// back to client-side aggregation against /api/orders/shop/:id).
router.get('/:id/stats', authMiddleware, async (req, res, next) => {
  try {
    const shopId = req.params.id;
    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });
    if (!(await isShopOwnerOrAdmin(req.user, shopId))) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    let days = parseInt(req.query.days, 10);
    if (!Number.isFinite(days) || days <= 0) days = 14;
    if (days > 90) days = 90;

    const now = new Date();
    const todayStart = new Date(now); todayStart.setHours(0, 0, 0, 0);
    const sinceWindow = new Date(now.getTime() - days * 86_400_000);

    const orders = await prisma.order.findMany({
      where: { shopId, createdAt: { gte: sinceWindow } },
      select: { status: true, total: true, createdAt: true },
    });

    const sales = new Map();
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(todayStart); d.setDate(d.getDate() - i);
      const key = d.toISOString().slice(0, 10);
      sales.set(key, { orders: 0, gmv: 0 });
    }

    let todayOrders = 0;
    let todayGmv = 0;
    let pendingOrders = 0;
    let delivered = 0;
    let cancelled = 0;
    for (const o of orders) {
      const t = new Date(o.createdAt);
      const key = t.toISOString().slice(0, 10);
      const bucket = sales.get(key);
      if (bucket) {
        bucket.orders += 1;
        bucket.gmv += o.total || 0;
      }
      if (t.getTime() >= todayStart.getTime()) {
        todayOrders += 1;
        todayGmv += o.total || 0;
      }
      const s = String(o.status || '').toLowerCase();
      if (s === 'pending') pendingOrders += 1;
      if (s === 'delivered' || s === 'confirmedbybuyer' || s === 'completed') delivered += 1;
      if (s === 'cancelled' || s === 'canceled') cancelled += 1;
    }

    // Lightweight reviews aggregate — kept best-effort so a missing table
    // doesn't blow up the dashboard.
    let rating = 0;
    let reviewsCount = 0;
    try {
      const agg = await prisma.review.aggregate({
        where: { targetType: 'SHOP', targetId: shopId },
        _avg: { rating: true },
        _count: { _all: true },
      });
      rating = Number(agg?._avg?.rating || 0);
      reviewsCount = Number(agg?._count?._all || 0);
    } catch {
      // schema may not yet expose Review.aggregate — fall back silently.
    }

    const finalised = delivered + cancelled;
    const salesByDay = Array.from(sales.entries()).map(([date, v]) => ({
      date, orders: v.orders, gmv: v.gmv,
    }));

    // Phase 13.2.6 — enrich response for the shop mobile analytics screen.
    // The original Phase 13.2.7 dashboard fields above are preserved; these
    // additional buckets give the mobile UI a today/week/month split, a
    // 30-day daily series and a top-selling product card.
    const dayMs = 86_400_000;
    const startOfDay = new Date(todayStart);
    const startOfWeek = new Date(startOfDay.getTime() - 6 * dayMs);
    const startOfMonth = new Date(startOfDay.getTime() - 29 * dayMs);
    const earnedStatuses = ['delivered', 'confirmedByBuyer'];

    async function bucket(since) {
      const rows = await prisma.order.findMany({
        where: { shopId, createdAt: { gte: since }, status: { in: earnedStatuses } },
        select: { total: true, refundedAmount: true },
      });
      const count = rows.length;
      const gross = rows.reduce((s, o) => s + Number(o.total || 0), 0);
      const refunded = rows.reduce((s, o) => s + Number(o.refundedAmount || 0), 0);
      const net = gross - refunded;
      return {
        orders: count,
        gross,
        refunded,
        net,
        avgTicket: count > 0 ? net / count : 0,
      };
    }

    const [today, week, month] = await Promise.all([
      bucket(startOfDay),
      bucket(startOfWeek),
      bucket(startOfMonth),
    ]);

    // 30-day daily series — independent from the parametric salesByDay above
    // (which honours ?days) so the mobile chart always sees the same window.
    const dailyOrders = await prisma.order.findMany({
      where: {
        shopId,
        createdAt: { gte: startOfMonth },
        status: { in: earnedStatuses },
      },
      select: { createdAt: true, total: true, refundedAmount: true },
    });
    const daily = [];
    for (let i = 29; i >= 0; i -= 1) {
      const ds = new Date(startOfDay.getTime() - i * dayMs);
      const de = new Date(ds.getTime() + dayMs);
      const inDay = dailyOrders.filter((o) => o.createdAt >= ds && o.createdAt < de);
      const rev = inDay.reduce((s, o) =>
        s + Number(o.total || 0) - Number(o.refundedAmount || 0), 0);
      daily.push({
        date: ds.toISOString().slice(0, 10),
        orders: inDay.length,
        revenue: rev,
      });
    }

    // Top product over the 30-day window.
    let topProduct = null;
    try {
      const topAgg = await prisma.orderItem.groupBy({
        by: ['productId'],
        where: {
          order: { is: { shopId, createdAt: { gte: startOfMonth }, status: { in: earnedStatuses } } },
        },
        _sum: { quantity: true },
        orderBy: { _sum: { quantity: 'desc' } },
        take: 1,
      });
      if (topAgg.length > 0 && topAgg[0].productId) {
        const p = await prisma.product.findUnique({
          where: { id: topAgg[0].productId },
          select: { id: true, name: true, nameUz: true },
        });
        if (p) {
          topProduct = {
            id: p.id,
            name: p.name,
            nameUz: p.nameUz,
            quantity: topAgg[0]._sum.quantity || 0,
          };
        }
      }
    } catch {
      // Defensive: schema differences shouldn't break the dashboard.
    }

    res.json({
      // 13.2.7 fields (vendor-next dashboard).
      todayOrders,
      todayGmv,
      pendingOrders,
      deliveredRate: finalised > 0 ? delivered / finalised : 0,
      rating,
      reviewsCount,
      salesByDay,
      // 13.2.6 fields (mobile shop analytics screen).
      today,
      week,
      month,
      daily,
      topProduct,
    });
  } catch (err) { next(err); }
});

// ─── GET /api/shops/:id/disputes ─────────────────────────────────────────────
// Phase 13.2.6 — shop owner lists disputes (refund requests) for their orders.
router.get('/:id/disputes', authMiddleware, async (req, res, next) => {
  try {
    const shopId = req.params.id;
    if (!(await requireShopMember(req, shopId))) {
      return res.status(403).json({ error: 'Shop role required' });
    }
    const { status } = req.query;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const where = { order: { is: { shopId } } };
    if (status) where.status = status;
    const rows = await prisma.dispute.findMany({
      where,
      orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
      take: limit,
      include: {
        order: {
          select: {
            id: true, orderNumber: true, total: true, refundedAmount: true,
            buyerId: true, shopId: true, status: true, deliveredAt: true,
            customerName: true, customerPhone: true,
          },
        },
      },
    });
    res.json({ disputes: rows });
  } catch (err) { next(err); }
});

// ─── POST /api/shops/:id/disputes/:disputeId/resolve ─────────────────────────
// Phase 13.2.6 — shop owner approves/rejects a refund request. Reuses the
// disputes service so the refund path is identical to the admin route.
router.post('/:id/disputes/:disputeId/resolve', authMiddleware, async (req, res, next) => {
  try {
    const shopId = req.params.id;
    if (!(await requireShopMember(req, shopId))) {
      return res.status(403).json({ error: 'Shop role required' });
    }
    const dispute = await prisma.dispute.findUnique({
      where: { id: req.params.disputeId },
      include: { order: { select: { shopId: true } } },
    });
    if (!dispute) return res.status(404).json({ error: 'Dispute not found' });
    if (dispute.order.shopId !== shopId) {
      return res.status(403).json({ error: 'Dispute does not belong to this shop' });
    }
    const { resolution, refundAmount, note } = req.body || {};
    try {
      const updated = await disputesSvc.resolveDispute(prisma, {
        disputeId: dispute.id,
        actorId: req.user.id,
        resolution,
        refundAmount,
        note,
        ipAddress: req.ip,
      });
      res.json({ dispute: updated });
    } catch (err) {
      if (err && err.status) return res.status(err.status).json({ error: err.message });
      throw err;
    }
  } catch (err) { next(err); }
});

// ─── GET /api/shops/:id/coupons ──────────────────────────────────────────────
router.get('/:id/coupons', authMiddleware, async (req, res, next) => {
  try {
    const shopId = req.params.id;
    if (!(await requireShopMember(req, shopId))) {
      return res.status(403).json({ error: 'Shop role required' });
    }
    const coupons = await prisma.coupon.findMany({
      where: { shopId },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    res.json({ coupons });
  } catch (err) { next(err); }
});

// ─── POST /api/shops/:id/coupons ─────────────────────────────────────────────
// Phase 13.2.6 — shop owner creates a coupon. shopId is forced from the URL so
// the body cannot widen scope to another shop or globally.
router.post('/:id/coupons', authMiddleware, async (req, res, next) => {
  try {
    const shopId = req.params.id;
    if (!(await requireShopMember(req, shopId))) {
      return res.status(403).json({ error: 'Shop role required' });
    }
    const body = req.body || {};
    const errs = validateCouponBody(body);
    if (errs.length) return res.status(400).json({ error: errs.join('; ') });
    const code = normalizeCouponCode(body.code);
    if (!code) return res.status(400).json({ error: 'code required' });

    const existing = await prisma.coupon.findUnique({ where: { code } });
    if (existing) return res.status(409).json({ error: 'Coupon already exists' });

    const coupon = await prisma.coupon.create({
      data: {
        code,
        type: body.type,
        value: Number(body.value) || 0,
        minOrder: body.minOrder != null ? Number(body.minOrder) : null,
        maxDiscount: body.maxDiscount != null ? Number(body.maxDiscount) : null,
        validFrom: new Date(body.validFrom),
        validUntil: new Date(body.validUntil),
        usageLimit: body.usageLimit != null ? Number(body.usageLimit) : null,
        usagePerUser: body.usagePerUser != null ? Number(body.usagePerUser) : 1,
        vertical: null,
        shopId, // force scope to this shop
        firstOrderOnly: !!body.firstOrderOnly,
        isActive: body.isActive == null ? true : !!body.isActive,
      },
    });
    audit({
      actorId: req.user.id,
      action: 'coupon.create',
      targetType: 'Coupon',
      targetId: code,
      metadata: { shopId },
    });
    res.status(201).json({ coupon });
  } catch (err) { next(err); }
});

// ─── PATCH /api/shops/:id/coupons/:code ──────────────────────────────────────
router.patch('/:id/coupons/:code', authMiddleware, async (req, res, next) => {
  try {
    const shopId = req.params.id;
    if (!(await requireShopMember(req, shopId))) {
      return res.status(403).json({ error: 'Shop role required' });
    }
    const code = normalizeCouponCode(req.params.code);
    const existing = await prisma.coupon.findUnique({ where: { code } });
    if (!existing) return res.status(404).json({ error: 'Not found' });
    if (existing.shopId !== shopId) {
      return res.status(403).json({ error: 'Coupon does not belong to this shop' });
    }

    const body = req.body || {};
    const errs = validateCouponBody(body, { partial: true });
    if (errs.length) return res.status(400).json({ error: errs.join('; ') });

    const data = {};
    const fields = ['type', 'value', 'minOrder', 'maxDiscount', 'usageLimit',
      'usagePerUser', 'firstOrderOnly', 'isActive'];
    for (const f of fields) {
      if (body[f] !== undefined) {
        if (['value', 'minOrder', 'maxDiscount', 'usageLimit', 'usagePerUser'].includes(f)) {
          data[f] = body[f] == null ? null : Number(body[f]);
        } else if (['firstOrderOnly', 'isActive'].includes(f)) {
          data[f] = !!body[f];
        } else {
          data[f] = body[f];
        }
      }
    }
    if (body.validFrom !== undefined) data.validFrom = new Date(body.validFrom);
    if (body.validUntil !== undefined) data.validUntil = new Date(body.validUntil);

    const coupon = await prisma.coupon.update({ where: { code }, data });
    audit({
      actorId: req.user.id,
      action: 'coupon.update',
      targetType: 'Coupon',
      targetId: code,
      metadata: { shopId },
    });
    res.json({ coupon });
  } catch (err) { next(err); }
});

// ─── DELETE /api/shops/:id/coupons/:code ─────────────────────────────────────
// Hard-delete only when no redemptions exist. Otherwise the client should
// PATCH `{isActive: false}` to deactivate.
router.delete('/:id/coupons/:code', authMiddleware, async (req, res, next) => {
  try {
    const shopId = req.params.id;
    if (!(await requireShopMember(req, shopId))) {
      return res.status(403).json({ error: 'Shop role required' });
    }
    const code = normalizeCouponCode(req.params.code);
    const existing = await prisma.coupon.findUnique({ where: { code } });
    if (!existing) return res.status(404).json({ error: 'Not found' });
    if (existing.shopId !== shopId) {
      return res.status(403).json({ error: 'Coupon does not belong to this shop' });
    }
    const used = await prisma.couponRedemption.count({ where: { couponCode: code } });
    if (used > 0) {
      return res.status(409).json({ error: 'Coupon has redemptions; deactivate instead' });
    }
    await prisma.coupon.delete({ where: { code } });
    audit({
      actorId: req.user.id,
      action: 'coupon.delete',
      targetType: 'Coupon',
      targetId: code,
      metadata: { shopId },
    });
    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ─── POST /api/shops/connect ─────────────────────────────────────────────────
// SECURITY: this endpoint previously let any authenticated user join ANY
// shop as a manager by guessing the shop id — a severe privilege escalation.
// Real onboarding goes through an admin-issued invite-code flow; until that
// exists, only admins may call this. Non-admins get a 403.
router.post('/connect', authMiddleware, async (req, res, next) => {
  try {
    if (!req.user.isAdmin) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const { shopId, userId } = req.body || {};
    if (!shopId) return res.status(400).json({ error: 'shopId required' });

    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });

    // Admin can attach themselves OR a target user by id (default: self).
    const targetUserId = (typeof userId === 'string' && userId) ? userId : req.user.id;
    const target = await prisma.user.findUnique({ where: { id: targetUserId } });
    if (!target) return res.status(404).json({ error: 'User not found' });

    await prisma.shopMember.upsert({
      where: { userId_shopId: { userId: targetUserId, shopId } },
      update: {},
      create: { userId: targetUserId, shopId, role: 'manager' },
    });

    await prisma.user.update({
      where: { id: targetUserId },
      data: { isShop: true },
    });

    audit({
      actorId: req.user.id,
      action: 'shop.member_add',
      targetType: 'Shop',
      targetId: shopId,
      metadata: { userId: targetUserId, role: 'manager' },
      ipAddress: req.ip,
    });

    res.json({ success: true });
  } catch (err) { next(err); }
});

module.exports = router;
