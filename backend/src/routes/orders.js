const router = require('express').Router();
const prisma = require('../db');
const env = require('../config/env');
const state = require('../services/redis-state');
const push = require('../services/push');
const { computeDelivery } = require('../services/pricing');
const { authMiddleware, requireRole } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const logger = require('../lib/logger');
const { queues } = require('../lib/queues');
const { validateCoupon, computeDiscount } = require('../services/coupons');
const loyalty = require('../services/loyalty');
const scheduling = require('../services/scheduling');
const notifications = require('../services/notifications');
const shopHours = require('../services/shopHours');
const click = require('../services/click');
const payme = require('../services/payme');
const money = require('../lib/money');
// Phase 7 — multi-country VAT + country-aware estimate.
const tax = require('../services/tax');
const country = require('../services/country');

// Phase 6 — backwards-compatible Money envelope. We keep the raw Float fields
// (subtotal, total, etc.) AND emit a sibling `*_money` object so the Flutter
// Money model can parse either shape. `currency` defaults to UZS.
function attachMoneyEnvelope(order) {
  if (!order) return order;
  const cur = order.currency || 'UZS';
  const wrap = (n) => money.toJson(money.money(Number(n) || 0, cur));
  const out = { ...order };
  out.currency = cur;
  out.subtotalMoney = wrap(order.subtotal);
  out.deliveryFeeMoney = wrap(order.deliveryFee);
  out.discountMoney = wrap(order.discount);
  out.tipAmountMoney = wrap(order.tipAmount);
  out.totalMoney = wrap(order.total);
  out.refundedAmountMoney = wrap(order.refundedAmount);
  return out;
}

// Phase 3: fire DB Notification + FCM + socket emit for an order transition.
// Best-effort; never throw out of a state-change handler.
async function notifyOrder(req, order, type) {
  if (!order || !type) return;
  try {
    const io = req.app.get('io');
    await notifications.sendOrderEvent(prisma, io, {
      userId: order.buyerId,
      type,
      orderId: order.id,
      data: { status: order.status, shopId: order.shopId },
    });
  } catch (err) {
    logger.warn({ err: err.message, orderId: order.id, type }, 'notifyOrder failed');
  }
}

// Order status flow:
// pending → confirmed → collecting → readyForPickup → courierAssigned →
// pickedUp → inDelivery → arrivedAtCustomer → delivered → confirmedByBuyer
const STATUS = {
  PENDING: 'pending',
  CONFIRMED: 'confirmed',
  COLLECTING: 'collecting',
  READY_FOR_PICKUP: 'readyForPickup',
  COURIER_ASSIGNED: 'courierAssigned',
  PICKED_UP: 'pickedUp',
  IN_DELIVERY: 'inDelivery',
  ARRIVED_AT_CUSTOMER: 'arrivedAtCustomer',
  DELIVERED: 'delivered',
  CONFIRMED_BY_BUYER: 'confirmedByBuyer',
  CANCELLED: 'cancelled',
};

const COURIER_RADIUS_KM = env.COURIER_RADIUS_KM;

// ─── Authorization helpers ──────────────────────────────────────────────────

async function isShopMember(userId, shopId) {
  if (!userId || !shopId) return false;
  const m = await prisma.shopMember.findUnique({
    where: { userId_shopId: { userId, shopId } },
  });
  return !!m;
}

async function canViewOrder(user, order) {
  if (!user || !order) return false;
  if (order.buyerId === user.id) return true;
  if (order.courierId === user.id) return true;
  if (user.isAdmin) return true;
  return isShopMember(user.id, order.shopId);
}

// Notify nearby online couriers about an available order
async function notifyNearbyCouriers(req, order) {
  const io = req.app.get('io');
  const shopPoint = (order.shop?.lat != null && order.shop?.lng != null)
    ? { lat: order.shop.lat, lng: order.shop.lng }
    : null;
  const ids = await state.nearbyCourierIds(shopPoint, COURIER_RADIUS_KM);
  if (ids.length === 0) {
    // Fallback to broadcast — keep flow working in dev / when no GPS yet
    io.to('couriers').emit('order:available', order);
    push.notifyCouriersNewOrder(order, []).catch(() => {});
    return;
  }
  ids.forEach((uid) => io.to(`courier:${uid}`).emit('order:available', order));
  push.notifyCouriersNewOrder(order, ids).catch(() => {});
}

function emit(req, room, event, data) {
  const io = req.app.get('io');
  io.to(room).emit(event, data);
}

// Auto-generate next order number per shop (e.g. K-247)
async function nextOrderNumber(shopId) {
  const last = await prisma.order.findFirst({
    where: { shopId, orderNumber: { not: null } },
    orderBy: { createdAt: 'desc' },
  });
  if (!last?.orderNumber) return 'K-100';
  const num = parseInt(last.orderNumber.split('-')[1] || '99', 10) + 1;
  return `K-${num}`;
}

// Compute per-unit price for an item with modifiers.
// Validates min/max selections per group; throws { status: 400 } on violation.
//
// Returns { basePrice, unitPrice, modifiersSnapshot }.
async function priceItem(prismaClient, productId, modifierSelections) {
  const product = await prismaClient.product.findUnique({
    where: { id: productId },
    include: { modifierGroups: { include: { options: true } } },
  });
  if (!product) {
    throw Object.assign(new Error(`Product ${productId} not found`), { status: 400 });
  }
  if (!product.isAvailable) {
    throw Object.assign(new Error(`${product.name} is not available`), { status: 400 });
  }

  const basePrice = product.discountPrice ?? product.price;

  // Backwards compat: no groups → no modifiers.
  if (!product.modifierGroups || product.modifierGroups.length === 0) {
    return { product, basePrice, unitPrice: basePrice, modifiersSnapshot: [] };
  }

  const selections = Array.isArray(modifierSelections) ? modifierSelections : [];
  const selectionsByGroup = new Map();
  for (const sel of selections) {
    if (!sel || !sel.groupId) continue;
    selectionsByGroup.set(sel.groupId, Array.isArray(sel.optionIds) ? sel.optionIds : []);
  }

  // Validate every selection refers to a real group on this product, and that
  // optionIds are unique + belong to that group.
  const groupById = new Map(product.modifierGroups.map((g) => [g.id, g]));
  for (const [gid, optIds] of selectionsByGroup) {
    const group = groupById.get(gid);
    if (!group) {
      throw Object.assign(new Error(`Modifier group ${gid} does not belong to product`), { status: 400 });
    }
    const uniq = new Set(optIds);
    if (uniq.size !== optIds.length) {
      throw Object.assign(new Error(`Duplicate options in group ${group.nameRu}`), { status: 400 });
    }
    if (uniq.size < group.minSelect) {
      throw Object.assign(new Error(`Group "${group.nameRu}" requires at least ${group.minSelect} option(s)`), { status: 400 });
    }
    if (uniq.size > group.maxSelect) {
      throw Object.assign(new Error(`Group "${group.nameRu}" allows at most ${group.maxSelect} option(s)`), { status: 400 });
    }
    const validIds = new Set(group.options.map((o) => o.id));
    for (const oid of optIds) {
      if (!validIds.has(oid)) {
        throw Object.assign(new Error(`Option ${oid} not in group ${group.nameRu}`), { status: 400 });
      }
      const opt = group.options.find((o) => o.id === oid);
      if (!opt.isAvailable) {
        throw Object.assign(new Error(`Option "${opt.nameRu}" is not available`), { status: 400 });
      }
    }
  }

  // Reject if any required group (minSelect > 0) wasn't selected.
  for (const group of product.modifierGroups) {
    if (group.minSelect > 0 && !selectionsByGroup.has(group.id)) {
      throw Object.assign(new Error(`Group "${group.nameRu}" is required`), { status: 400 });
    }
  }

  // Build snapshot + sum deltas.
  let delta = 0;
  const modifiersSnapshot = [];
  for (const group of product.modifierGroups) {
    const optIds = selectionsByGroup.get(group.id) || [];
    for (const oid of optIds) {
      const opt = group.options.find((o) => o.id === oid);
      delta += opt.priceDelta || 0;
      modifiersSnapshot.push({
        groupId: group.id,
        groupName: group.nameRu,
        optionId: opt.id,
        optionName: opt.nameRu,
        priceDelta: opt.priceDelta || 0,
      });
    }
  }

  return {
    product,
    basePrice,
    unitPrice: basePrice + delta,
    modifiersSnapshot,
  };
}

// ─── POST /api/orders/estimate — preview pricing without creating an order ──
// Buyer-facing checkout call; computes subtotal + delivery + ETA. NO DB write.
router.post('/estimate', authMiddleware, async (req, res, next) => {
  try {
    const { shopId, address, items, couponCode, loyaltyPoints } = req.body || {};
    if (!shopId) return res.status(400).json({ error: 'shopId required' });
    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'items required' });
    }
    if (!address || !Number.isFinite(Number(address.lat)) || !Number.isFinite(Number(address.lng))) {
      return res.status(400).json({ error: 'address.lat / address.lng required' });
    }

    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });

    // Phase 6.4 — closed-shop hint. We don't reject /estimate (it's a preview),
    // but we expose the flag so the UI can warn the user.
    const workingHours = await prisma.shopWorkingHours.findMany({
      where: { shopId: shop.id },
      orderBy: [{ dayOfWeek: 'asc' }, { startsAt: 'asc' }],
    });
    const shopOpen = shopHours.isOpenNow({ ...shop, workingHours });
    const opensAt = shopOpen
      ? null
      : (() => {
        const next = shopHours.nextOpenAt({ ...shop, workingHours });
        return next ? next.toISOString() : null;
      })();

    let subtotal = 0;
    const itemsBreakdown = [];
    for (const i of items) {
      const qty = Math.max(1, Math.min(99, Number(i.quantity) || 1));
      const { product, unitPrice } = await priceItem(prisma, i.productId, i.modifiers);
      const total = unitPrice * qty;
      subtotal += total;
      itemsBreakdown.push({
        productId: product.id,
        productName: product.name,
        quantity: qty,
        unitPrice,
        total,
      });
    }

    const delivery = await computeDelivery(prisma, {
      shopId,
      destLat: Number(address.lat),
      destLng: Number(address.lng),
      userId: req.user.id,
    });

    if (delivery.outOfZone) {
      return res.status(400).json({ error: 'out_of_zone' });
    }

    const minOrderMet = subtotal >= delivery.minOrder;

    // Phase 3 — preview coupon + loyalty discount.
    let couponDiscount = 0;
    let couponReason = null;
    let couponInfo = null;
    if (couponCode) {
      const r = await validateCoupon(prisma, {
        code: String(couponCode).trim().toUpperCase(),
        userId: req.user.id,
        vertical: shop.vertical,
        shopId,
        subtotal,
        deliveryFee: delivery.deliveryFee,
      });
      if (!r.valid) {
        couponReason = r.reason;
      } else {
        couponDiscount = r.discount;
        couponInfo = { code: r.coupon.code, type: r.coupon.type, value: r.coupon.value };
      }
    }

    let loyaltyDiscount = 0;
    let loyaltyPointsApplied = 0;
    if (loyaltyPoints) {
      const requested = Math.max(0, Math.floor(Number(loyaltyPoints) || 0));
      if (requested > 0) {
        const account = await loyalty.getOrCreateAccount(prisma, req.user.id);
        loyaltyPointsApplied = Math.min(requested, account.points);
        loyaltyDiscount = loyaltyPointsApplied * loyalty.SPEND_VALUE_UZS;
      }
    }

    const discount = couponDiscount + loyaltyDiscount;

    // Phase 7 — VAT applies to (subtotal - discount) clamped at 0. Country
    // comes from the user; defaults to UZ for legacy accounts without one.
    const userCountry = req.user.country || country.fromPhone(req.user.phone) || 'UZ';
    const taxBase = Math.max(0, subtotal - discount);
    const { taxRate, taxAmount } = tax.compute({
      subtotal: taxBase,
      deliveryFee: delivery.deliveryFee,
      country: userCountry,
    });

    const total = Math.max(0, subtotal + delivery.deliveryFee - discount + taxAmount);

    res.json({
      subtotal,
      deliveryFee: delivery.deliveryFee,
      discount,
      couponDiscount,
      couponReason,
      coupon: couponInfo,
      loyaltyDiscount,
      loyaltyPointsApplied,
      taxRate,
      taxAmount,
      total,
      minOrder: delivery.minOrder,
      minOrderMet,
      distanceKm: delivery.distanceKm,
      etaMinutes: delivery.eta,
      surgeFactor: delivery.surgeFactor,
      surgeReason: delivery.surgeReason,
      zoneId: delivery.zoneId,
      items: itemsBreakdown,
      currency: shop.currency || 'UZS',
      country: userCountry,
      shopOpen,
      opensAt,
    });
  } catch (err) { next(err); }
});

// ─── POST /api/orders — buyer places order ───────────────────────────────────
router.post('/', authMiddleware, async (req, res, next) => {
  try {
    const {
      shopId, items, deliveryAddress, deliveryLat, deliveryLng,
      customerComment, paymentMethod, paymentMethodId,
      couponCode, loyaltyPoints, scheduledFor,
    } = req.body || {};

    if (!shopId || !items?.length || !deliveryAddress || !paymentMethod) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    if (!['click', 'payme', 'uzumpay', 'cash'].includes(paymentMethod)) {
      return res.status(400).json({ error: 'Invalid payment method' });
    }

    // Phase 6.1 — if paymentMethodId provided, verify ownership upfront. We
    // 404 (not 403) so callers can't use this endpoint to enumerate other
    // users' methods.
    let savedMethod = null;
    if (paymentMethodId) {
      savedMethod = await prisma.paymentMethod.findUnique({
        where: { id: paymentMethodId },
      });
      if (!savedMethod || savedMethod.userId !== req.user.id || !savedMethod.isActive) {
        return res.status(404).json({ error: 'payment_method_not_found' });
      }
    }

    let subtotal = 0;
    const orderItemsData = [];
    for (const i of items) {
      const qty = Math.max(1, Math.min(99, Number(i.quantity) || 1));
      const { product, basePrice, unitPrice, modifiersSnapshot } =
        await priceItem(prisma, i.productId, i.modifiers);
      const total = unitPrice * qty;
      subtotal += total;
      orderItemsData.push({
        productId: product.id,
        productName: product.name,
        quantity: qty,
        price: unitPrice,
        basePrice,
        total,
        modifiers: modifiersSnapshot.length ? JSON.stringify(modifiersSnapshot) : null,
      });
    }

    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });
    if (!shop.isActive) return res.status(400).json({ error: 'Shop is not active' });

    // Phase 6.4 — closed-shop guard. Require either an open shop *now* or a
    // scheduledFor that the buyer explicitly set. Front-end picks a slot from
    // GET /working-hours; we trust scheduledFor here (validated for past/range
    // below) — a future enhancement could also require scheduledFor to fall
    // inside an open window.
    {
      const workingHours = await prisma.shopWorkingHours.findMany({
        where: { shopId: shop.id },
        orderBy: [{ dayOfWeek: 'asc' }, { startsAt: 'asc' }],
      });
      const openNow = shopHours.isOpenNow({ ...shop, workingHours });
      if (!openNow && !scheduledFor) {
        const next = shopHours.nextOpenAt({ ...shop, workingHours });
        return res.status(400).json({
          error: 'shop_closed',
          code: 'shop_closed',
          opensAt: next ? next.toISOString() : null,
        });
      }
    }

    // Compute server-side delivery fee — never trust the client.
    let deliveryFee = 0;
    if (Number.isFinite(Number(deliveryLat)) && Number.isFinite(Number(deliveryLng))) {
      const delivery = await computeDelivery(prisma, {
        shopId,
        destLat: Number(deliveryLat),
        destLng: Number(deliveryLng),
        userId: req.user.id,
      });
      if (delivery.outOfZone) {
        return res.status(400).json({ error: 'out_of_zone' });
      }
      if (subtotal < delivery.minOrder) {
        return res.status(400).json({ error: 'min_order_not_met', minOrder: delivery.minOrder });
      }
      deliveryFee = delivery.deliveryFee;
    } else {
      // Legacy fallback when client didn't send coords yet — keep old behaviour.
      deliveryFee = subtotal >= 100000 ? 0 : 12000;
    }

    // Phase 3 — coupon validation (before save, no DB writes yet).
    let couponDiscount = 0;
    let validatedCoupon = null;
    const normalizedCode = couponCode ? String(couponCode).trim().toUpperCase() : null;
    if (normalizedCode) {
      const r = await validateCoupon(prisma, {
        code: normalizedCode,
        userId: req.user.id,
        vertical: shop.vertical,
        shopId,
        subtotal,
        deliveryFee,
      });
      if (!r.valid) {
        return res.status(400).json({ error: 'coupon_invalid', reason: r.reason });
      }
      couponDiscount = r.discount;
      validatedCoupon = r.coupon;
    }

    // Phase 3 — loyalty points spend (validate balance before save).
    const requestedPoints = Math.max(0, Math.floor(Number(loyaltyPoints) || 0));
    let loyaltyDiscount = 0;
    if (requestedPoints > 0) {
      const account = await loyalty.getOrCreateAccount(prisma, req.user.id);
      if (account.points < requestedPoints) {
        return res.status(400).json({ error: 'insufficient_points' });
      }
      loyaltyDiscount = requestedPoints * loyalty.SPEND_VALUE_UZS;
    }

    const discount = couponDiscount + loyaltyDiscount;

    // Phase 7 — VAT applied to (subtotal - discount) clamped at 0; delivery
    // fee is the courier reward and is not taxed in our model. Country comes
    // from the buyer (User.country); falls back to phone-prefix detection.
    const userCountry = req.user.country || country.fromPhone(req.user.phone) || 'UZ';
    const taxBase = Math.max(0, subtotal - discount);
    const { taxRate, taxAmount } = tax.compute({
      subtotal: taxBase,
      deliveryFee,
      country: userCountry,
    });

    const total = Math.max(0, subtotal + deliveryFee - discount + taxAmount);
    // Default false; the saved-method charge below or the provider webhook
    // flips it to true. Cash is "paid on delivery" so still starts at false.
    let isPaid = false;
    let paymentRef = null;

    // Phase 6.1 — saved-method charge happens BEFORE order creation so we can
    // reflect the result on the row we insert. On failure we still create the
    // order (isPaid=false) so the buyer can retry from the order screen, but
    // we audit the failure for support visibility.
    let chargeResult = null;
    if (savedMethod && paymentMethod !== 'cash') {
      const provider = savedMethod.provider;
      try {
        if (provider === 'click') {
          chargeResult = await click.chargeWithToken(
            savedMethod.providerId, total, undefined, shop.currency || 'UZS',
          );
        } else if (provider === 'payme') {
          chargeResult = await payme.chargeWithToken(
            savedMethod.providerId, total, undefined, shop.currency || 'UZS',
          );
        } else {
          chargeResult = { ok: false, externalId: null, message: 'provider_not_chargeable' };
        }
      } catch (err) {
        logger.warn({ err: err.message, provider }, 'saved-method charge failed');
        chargeResult = { ok: false, externalId: null, message: err.message };
      }
      if (chargeResult && chargeResult.ok) {
        isPaid = true;
        paymentRef = chargeResult.externalId;
      }
    }

    // Phase 3 — validate scheduledFor up front so we don't write a row we'll reject.
    let scheduledAt = null;
    if (scheduledFor) {
      const when = new Date(scheduledFor);
      if (Number.isNaN(when.getTime())) {
        return res.status(400).json({ error: 'invalid_scheduled_for' });
      }
      const now = Date.now();
      if (when.getTime() <= now) {
        return res.status(400).json({ error: 'scheduled_in_past' });
      }
      if (when.getTime() > now + scheduling.MAX_SCHEDULE_DAYS * 24 * 60 * 60 * 1000) {
        return res.status(400).json({ error: 'scheduled_too_far' });
      }
      scheduledAt = when;
    }

    const order = await prisma.order.create({
      data: {
        buyerId: req.user.id,
        customerName: req.user.name || 'Xaridor',
        customerPhone: req.user.phone,
        shopId,
        deliveryAddress, deliveryLat, deliveryLng,
        customerComment,
        paymentMethod, isPaid,
        paymentRef,
        paymentMethodId: savedMethod ? savedMethod.id : null,
        currency: shop.currency || 'UZS',
        subtotal, deliveryFee, total,
        // Phase 7 — VAT snapshot.
        taxRate, taxAmount,
        couponCode: validatedCoupon ? validatedCoupon.code : null,
        discount,
        loyaltySpent: requestedPoints,
        scheduledFor: scheduledAt,
        status: STATUS.PENDING,
        items: { create: orderItemsData },
      },
      include: { items: true, shop: true, courier: true },
    });

    if (savedMethod) {
      audit({
        actorId: req.user.id,
        action: chargeResult && chargeResult.ok ? 'order.paid_saved_method' : 'order.charge_failed',
        targetType: 'Order',
        targetId: order.id,
        metadata: {
          paymentMethodId: savedMethod.id,
          provider: savedMethod.provider,
          ok: !!(chargeResult && chargeResult.ok),
          message: chargeResult ? chargeResult.message : null,
        },
      });
    }

    // Phase 3 — record coupon redemption + bump usage counter.
    if (validatedCoupon) {
      try {
        await prisma.coupon.update({
          where: { code: validatedCoupon.code },
          data: { usedCount: { increment: 1 } },
        });
        await prisma.couponRedemption.create({
          data: {
            couponCode: validatedCoupon.code,
            userId: req.user.id,
            orderId: order.id,
            discount: couponDiscount,
          },
        });
      } catch (err) {
        logger.warn({ err: err.message, orderId: order.id }, 'coupon redemption failed');
      }
    }

    // Phase 3 — debit loyalty points (DB-only, balance already validated).
    if (requestedPoints > 0) {
      try {
        await loyalty.spendPoints(prisma, req.user.id, requestedPoints, order.id);
      } catch (err) {
        logger.warn({ err: err.message, orderId: order.id }, 'loyalty spend failed');
      }
    }

    // Notify shop in real time
    emit(req, `shop:${shopId}`, 'order:new', order);
    // Push to shop members
    try {
      const members = await prisma.shopMember.findMany({ where: { shopId } });
      push.notifyShopNewOrder(order, members).catch(() => {});
    } catch (err) {
      logger.warn({ err: err.message }, 'shop push failed');
    }

    // Phase 3 — scheduled vs immediate dispatch.
    if (scheduledAt) {
      try {
        await scheduling.scheduleOrder(prisma, queues, { orderId: order.id, scheduledFor: scheduledAt });
      } catch (err) {
        logger.warn({ err: err.message, orderId: order.id }, 'scheduleOrder failed');
      }
    } else {
      // Phase 2: enqueue dispatch + auto-cancel (no-ops when Redis disabled).
      try {
        await queues().dispatch.add('startDispatch', { type: 'startDispatch', orderId: order.id });
        await queues().autoCancel.add(
          'autoCancel',
          { orderId: order.id, expectedStatus: order.status },
          { delay: 10 * 60 * 1000 },
        );
      } catch (err) {
        logger.warn({ err: err.message, orderId: order.id }, 'dispatch enqueue failed');
      }
    }

    res.status(201).json({ order: attachMoneyEnvelope(order) });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/tip — buyer adds a tip on a delivered order ───────
// 100% of the tip goes to the courier (aggregated in the next weekly payout).
// Validation:
//   • Buyer-only (the order's buyer).
//   • Order must be `delivered` (so we know who the courier was).
//   • Amount must be > 0 and ≤ 50% of order.total (anti-abuse cap).
//   • Buyer must have a saved payment method (either order.paymentMethodId or
//     a fresh paymentMethodId in the body). Cash tips are out of scope here.
router.post('/:id/tip', authMiddleware, async (req, res, next) => {
  try {
    const { amount, paymentMethodId: bodyPmId } = req.body || {};
    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      include: { shop: true },
    });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (order.buyerId !== req.user.id) return res.status(403).json({ error: 'Not your order' });
    if (order.status !== STATUS.DELIVERED) {
      return res.status(400).json({ error: 'order_not_delivered' });
    }

    const tip = Number(amount);
    if (!Number.isFinite(tip) || tip <= 0) {
      return res.status(400).json({ error: 'invalid_amount' });
    }
    if (tip >= order.total * 0.5) {
      return res.status(400).json({ error: 'tip_too_large', maxTip: order.total * 0.5 });
    }

    // Resolve which saved method to charge: prefer the order's, fall back to
    // the body. Cash-only orders have neither — surface a friendly error.
    const pmId = order.paymentMethodId || bodyPmId;
    if (!pmId) {
      return res.status(400).json({ error: 'payment_method_required' });
    }
    const method = await prisma.paymentMethod.findUnique({ where: { id: pmId } });
    if (!method || method.userId !== req.user.id || !method.isActive) {
      return res.status(404).json({ error: 'payment_method_not_found' });
    }

    let result;
    if (method.provider === 'click') {
      result = await click.chargeWithToken(method.providerId, tip, order.id, order.currency || 'UZS');
    } else if (method.provider === 'payme') {
      result = await payme.chargeWithToken(method.providerId, tip, order.id, order.currency || 'UZS');
    } else {
      return res.status(400).json({ error: 'provider_not_chargeable' });
    }

    if (!result || !result.ok) {
      audit({
        actorId: req.user.id,
        action: 'order.tip_failed',
        targetType: 'Order',
        targetId: order.id,
        metadata: { amount: tip, message: result ? result.message : 'unknown' },
      });
      return res.status(402).json({ error: 'charge_failed', message: result ? result.message : 'unknown' });
    }

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: {
        tipAmount: { increment: tip },
        tipPaidAt: new Date(),
      },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });
    audit({
      actorId: req.user.id,
      action: 'order.tip',
      targetType: 'Order',
      targetId: order.id,
      metadata: { amount: tip, courierId: order.courierId, externalId: result.externalId },
    });
    res.json({ order: attachMoneyEnvelope(updated) });
  } catch (err) { next(err); }
});

// ─── GET /api/orders/mine — buyer's orders ───────────────────────────────────
router.get('/mine', authMiddleware, async (req, res, next) => {
  try {
    const orders = await prisma.order.findMany({
      where: { buyerId: req.user.id },
      orderBy: { createdAt: 'desc' },
      take: 100,
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true, rating: true } } },
    });
    res.json({ orders: orders.map(attachMoneyEnvelope) });
  } catch (err) { next(err); }
});

// ─── GET /api/orders/:id ─────────────────────────────────────────────────────
router.get('/:id', authMiddleware, async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true, rating: true } } },
    });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (!(await canViewOrder(req.user, order))) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    res.json({ order: attachMoneyEnvelope(order) });
  } catch (err) { next(err); }
});

// ─── GET /api/orders/shop/:shopId ────────────────────────────────────────────
router.get('/shop/:shopId', authMiddleware, async (req, res, next) => {
  try {
    if (!(await isShopMember(req.user.id, req.params.shopId)) && !req.user.isAdmin) {
      return res.status(403).json({ error: 'Not a shop member' });
    }
    const orders = await prisma.order.findMany({
      where: { shopId: req.params.shopId },
      orderBy: { createdAt: 'desc' },
      include: { items: true, courier: { select: { id: true, name: true, phone: true } } },
      take: 100,
    });
    res.json({ orders });
  } catch (err) { next(err); }
});

// ─── GET /api/orders/courier/available ───────────────────────────────────────
router.get('/courier/available', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const orders = await prisma.order.findMany({
      where: { status: STATUS.READY_FOR_PICKUP, courierId: null },
      orderBy: { createdAt: 'asc' },
      include: { items: true, shop: true },
      take: 20,
    });
    res.json({ orders });
  } catch (err) { next(err); }
});

// ─── GET /api/orders/courier/active ──────────────────────────────────────────
router.get('/courier/active', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const order = await prisma.order.findFirst({
      where: {
        courierId: req.user.id,
        status: { in: [STATUS.COURIER_ASSIGNED, STATUS.PICKED_UP, STATUS.IN_DELIVERY, STATUS.ARRIVED_AT_CUSTOMER] },
      },
      include: { items: true, shop: true },
    });
    res.json({ order });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/shop/accept ────────────────────────────────────────
router.post('/:id/shop/accept', authMiddleware, async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (order.status !== STATUS.PENDING) return res.status(400).json({ error: 'Order is not pending' });
    if (!(await isShopMember(req.user.id, order.shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }

    const orderNumber = await nextOrderNumber(order.shopId);
    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { status: STATUS.COLLECTING, orderNumber, acceptedAt: new Date() },
      include: { items: true, shop: true, courier: true },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    notifyNearbyCouriers(req, updated).catch(() => {});
    push.notifyBuyerStatusUpdate(updated).catch(() => {});
    notifyOrder(req, updated, 'order_confirmed').catch(() => {});

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/shop/ready ─────────────────────────────────────────
router.post('/:id/shop/ready', authMiddleware, async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (order.status !== STATUS.COLLECTING) {
      return res.status(400).json({ error: 'Order is not being collected' });
    }
    if (!(await isShopMember(req.user.id, order.shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { status: STATUS.READY_FOR_PICKUP, readyAt: new Date() },
      include: { items: true, shop: true, courier: true },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    if (!updated.courierId) notifyNearbyCouriers(req, updated).catch(() => {});
    push.notifyBuyerStatusUpdate(updated).catch(() => {});
    notifyOrder(req, updated, 'order_confirmed').catch(() => {});

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/shop/cancel ────────────────────────────────────────
router.post('/:id/shop/cancel', authMiddleware, async (req, res, next) => {
  try {
    const { reason } = req.body || {};
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (!(await isShopMember(req.user.id, order.shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }
    if ([STATUS.DELIVERED, STATUS.CONFIRMED_BY_BUYER, STATUS.CANCELLED].includes(order.status)) {
      return res.status(400).json({ error: 'Order is finalized' });
    }

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { status: STATUS.CANCELLED, cancelledAt: new Date(), cancelReason: reason || 'shop' },
      include: { items: true, shop: true },
    });

    // Free the courier (if any was assigned) so dispatcher can offer new orders.
    if (order.courierId) {
      await prisma.user.updateMany({
        where: { id: order.courierId, activeOrderId: order.id },
        data: { activeOrderId: null },
      });
    }

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);
    push.notifyBuyerStatusUpdate(updated).catch(() => {});
    notifyOrder(req, updated, 'order_cancelled').catch(() => {});
    audit({ actorId: req.user.id, action: 'order.cancel_by_shop', targetType: 'Order', targetId: order.id, metadata: { reason } });

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/courier/accept ─────────────────────────────────────
router.post('/:id/courier/accept', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (![STATUS.COLLECTING, STATUS.READY_FOR_PICKUP].includes(order.status) || order.courierId) {
      return res.status(400).json({ error: 'Order is not available' });
    }

    const newStatus = order.status === STATUS.READY_FOR_PICKUP
      ? STATUS.COURIER_ASSIGNED
      : STATUS.COLLECTING;

    // Atomic claim — only succeeds if courierId is still null.
    const claim = await prisma.order.updateMany({
      where: { id: order.id, courierId: null },
      data: { courierId: req.user.id, status: newStatus },
    });
    if (claim.count === 0) {
      return res.status(409).json({ error: 'Order already taken' });
    }

    // Mark courier busy so the dispatcher excludes them from new offers
    // until this order completes/cancels (parity with dispatcher.acceptOffer).
    await prisma.user.update({
      where: { id: req.user.id },
      data: { activeOrderId: order.id },
    });

    const updated = await prisma.order.findUnique({
      where: { id: order.id },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);
    emit(req, 'couriers', 'order:taken', { orderId: order.id });
    push.notifyBuyerStatusUpdate(updated).catch(() => {});
    notifyOrder(req, updated, 'order_dispatched').catch(() => {});

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/courier/pickup ─────────────────────────────────────
router.post('/:id/courier/pickup', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const { orderNumber } = req.body || {};
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (order.courierId !== req.user.id) {
      return res.status(403).json({ error: 'Not your order' });
    }
    if (order.orderNumber?.toLowerCase() !== orderNumber?.toLowerCase()?.trim()) {
      return res.status(400).json({ error: 'Wrong order number' });
    }

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { status: STATUS.PICKED_UP, pickedUpAt: new Date() },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);
    push.notifyBuyerStatusUpdate(updated).catch(() => {});
    notifyOrder(req, updated, 'order_picked_up').catch(() => {});

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/courier/start ──────────────────────────────────────
router.post('/:id/courier/start', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order || order.courierId !== req.user.id) {
      return res.status(404).json({ error: 'Not found' });
    }

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { status: STATUS.IN_DELIVERY },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    push.notifyBuyerStatusUpdate(updated).catch(() => {});
    notifyOrder(req, updated, 'order_in_delivery').catch(() => {});

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/courier/arrived ────────────────────────────────────
router.post('/:id/courier/arrived', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order || order.courierId !== req.user.id) {
      return res.status(404).json({ error: 'Not found' });
    }
    if (![STATUS.PICKED_UP, STATUS.IN_DELIVERY].includes(order.status)) {
      return res.status(400).json({ error: 'Wrong status' });
    }
    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { status: STATUS.ARRIVED_AT_CUSTOMER },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });
    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);
    push.notifyBuyerStatusUpdate(updated).catch(() => {});
    notifyOrder(req, updated, 'order_in_delivery').catch(() => {});
    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/courier/complete ───────────────────────────────────
router.post('/:id/courier/complete', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order || order.courierId !== req.user.id) {
      return res.status(404).json({ error: 'Not found' });
    }

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { status: STATUS.DELIVERED, deliveredAt: new Date() },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });

    // Phase 8.1 — if this order is part of a batch, advance the batch's
    // progress counter and either advance the courier to the next order in
    // the sequence, or close the batch when all members are delivered.
    let nextActiveOrderId = null;
    if (order.batchId) {
      const batch = await prisma.orderBatch.update({
        where: { id: order.batchId },
        data: { deliveriesCompleted: { increment: 1 } },
      });
      if (batch.deliveriesCompleted >= batch.totalDeliveries) {
        await prisma.orderBatch.update({
          where: { id: batch.id },
          data: { status: 'completed', completedAt: new Date() },
        });
      } else {
        // Find the next undelivered member by sequence.
        const next = await prisma.order.findFirst({
          where: {
            batchId: batch.id,
            id: { not: order.id },
            status: { not: STATUS.DELIVERED },
          },
          orderBy: { batchSequence: 'asc' },
        });
        if (next) nextActiveOrderId = next.id;
      }
    }

    await prisma.user.update({
      where: { id: req.user.id },
      data: {
        ordersCount: { increment: 1 },
        // Free the courier (or advance to next batch member) so the
        // dispatcher can offer them new orders.
        activeOrderId: nextActiveOrderId,
      },
    });

    // Phase 3: credit loyalty points + referral bonus on delivery.
    try {
      const credit = await loyalty.creditOrder(prisma, updated.buyerId, updated.id, updated.total);
      if (credit && credit.pointsAdded) {
        await prisma.order.update({
          where: { id: updated.id },
          data: { loyaltyEarned: credit.pointsAdded },
        });
      }
    } catch (err) {
      logger.warn({ err: err.message, orderId: updated.id }, 'loyalty credit failed');
    }
    try {
      await loyalty.bonusReferral(prisma, updated.buyerId);
    } catch (err) {
      logger.warn({ err: err.message, orderId: updated.id }, 'referral bonus failed');
    }

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);
    push.notifyBuyerStatusUpdate(updated).catch(() => {});
    notifyOrder(req, updated, 'order_delivered').catch(() => {});

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/buyer/confirm ──────────────────────────────────────
router.post('/:id/buyer/confirm', authMiddleware, async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (order.buyerId !== req.user.id) return res.status(403).json({ error: 'Not your order' });
    if (order.status !== STATUS.DELIVERED) {
      return res.status(400).json({ error: 'Order is not delivered yet' });
    }
    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { status: STATUS.CONFIRMED_BY_BUYER },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });
    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);
    if (order.courierId) emit(req, `courier:${order.courierId}`, 'order:updated', updated);
    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/rate ───────────────────────────────────────────────
router.post('/:id/rate', authMiddleware, async (req, res, next) => {
  try {
    const { rating, review, courierRating, shopRating } = req.body || {};
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (order.buyerId !== req.user.id) return res.status(403).json({ error: 'Not your order' });
    if (![STATUS.DELIVERED, STATUS.CONFIRMED_BY_BUYER].includes(order.status)) {
      return res.status(400).json({ error: 'Order not deliverable yet' });
    }

    const data = {};
    if (rating != null) data.buyerRating = Math.max(1, Math.min(5, Number(rating)));
    if (review) data.buyerReview = String(review).slice(0, 1000);
    if (courierRating != null) data.courierRating = Math.max(1, Math.min(5, Number(courierRating)));
    if (shopRating != null) data.shopRating = Math.max(1, Math.min(5, Number(shopRating)));

    await prisma.order.update({ where: { id: order.id }, data });
    res.json({ success: true });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/reorder — buyer-only cart draft helper ─────────────
// Phase 7.3 — produce a CartDraft from a previous order. We DO NOT create a
// new Order — that's the buyer's choice on the next checkout. We surface
// per-item availability so the UI can warn before saving the cart.
router.post('/:id/reorder', authMiddleware, async (req, res, next) => {
  try {
    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      include: { items: true, shop: true },
    });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (order.buyerId !== req.user.id) return res.status(403).json({ error: 'Not your order' });

    const productIds = order.items.map((i) => i.productId);
    const products = productIds.length
      ? await prisma.product.findMany({ where: { id: { in: productIds } } })
      : [];
    const productMap = new Map(products.map((p) => [p.id, p]));

    const shopActive = !!order.shop?.isActive;

    const items = order.items.map((it) => {
      const product = productMap.get(it.productId);
      let modifiers = [];
      if (it.modifiers) {
        try {
          modifiers = JSON.parse(it.modifiers) || [];
        } catch {
          modifiers = [];
        }
      }
      let available = true;
      let skipReason = null;
      if (!product) {
        available = false;
        skipReason = 'product_deleted';
      } else if (!product.isAvailable) {
        available = false;
        skipReason = 'out_of_stock';
      } else if (product.shopId !== order.shopId) {
        // Shop relocation/migration — refuse cross-shop reorder.
        available = false;
        skipReason = 'product_moved';
      } else if (!shopActive) {
        available = false;
        skipReason = 'shop_inactive';
      }
      return {
        productId: it.productId,
        productName: it.productName,
        quantity: it.quantity,
        unitPrice: it.price,
        modifiers,
        available,
        skipReason,
        // Embed enough product info so the UI can render the line without
        // a second roundtrip. Null when product was deleted.
        product: product ? {
          id: product.id,
          name: product.name,
          nameUz: product.nameUz,
          price: product.price,
          discountPrice: product.discountPrice,
          unit: product.unit,
          category: product.category,
          imageUrl: product.imageUrl,
          shopId: product.shopId,
        } : null,
      };
    });

    // Resolve a saved Address that matches the original order's coords. Best
    // effort — if nothing matches, returns null and the buyer picks again.
    let deliveryAddressId = null;
    if (order.deliveryLat != null && order.deliveryLng != null) {
      const matches = await prisma.address.findMany({
        where: { userId: req.user.id },
      });
      const same = matches.find((a) => (
        a.lat != null && a.lng != null
        && Math.abs(a.lat - order.deliveryLat) < 0.0001
        && Math.abs(a.lng - order.deliveryLng) < 0.0001
      ));
      if (same) deliveryAddressId = same.id;
    }

    res.json({
      shopId: order.shopId,
      items,
      couponCode: null,
      deliveryAddressId,
    });
  } catch (err) { next(err); }
});

// ─── GET /api/orders/courier/active ──────────────────────────────────────────
// Phase 8 — returns the courier's currently active order (whatever
// User.activeOrderId points at). The Flutter active-order screen polls this
// after each batch leg completes so it can advance to the next member of
// the batch automatically.
router.get('/courier/active', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const me = await prisma.user.findUnique({
      where: { id: req.user.id },
      select: { activeOrderId: true },
    });
    if (!me?.activeOrderId) return res.json({ order: null });
    const order = await prisma.order.findUnique({
      where: { id: me.activeOrderId },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });
    if (!order || order.courierId !== req.user.id) {
      return res.json({ order: null });
    }
    res.json({ order });
  } catch (err) { next(err); }
});

// ─── GET /api/orders/courier/batch/:batchId ──────────────────────────────────
// Phase 8 — returns all orders in a batch the courier is handling, sorted
// by batchSequence. Used by the active-order screen to render the upcoming
// pickups list and the batch overview map.
router.get('/courier/batch/:batchId', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const orders = await prisma.order.findMany({
      where: { batchId: req.params.batchId, courierId: req.user.id },
      include: { items: true, shop: true },
      orderBy: { batchSequence: 'asc' },
    });
    if (!orders.length) return res.status(404).json({ error: 'Not found' });
    const batch = await prisma.orderBatch.findUnique({ where: { id: req.params.batchId } });
    res.json({ batch, orders });
  } catch (err) { next(err); }
});

module.exports = router;
module.exports.priceItem = priceItem;
