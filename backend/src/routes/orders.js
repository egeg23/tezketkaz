const router = require('express').Router();
const prisma = require('../db');
const env = require('../config/env');
const state = require('../services/redis-state');
const push = require('../services/push');
const { authMiddleware, requireRole } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const logger = require('../lib/logger');

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

// ─── POST /api/orders — buyer places order ───────────────────────────────────
router.post('/', authMiddleware, async (req, res, next) => {
  try {
    const {
      shopId, items, deliveryAddress, deliveryLat, deliveryLng,
      customerComment, paymentMethod,
    } = req.body || {};

    if (!shopId || !items?.length || !deliveryAddress || !paymentMethod) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    if (!['click', 'payme', 'uzumpay', 'cash'].includes(paymentMethod)) {
      return res.status(400).json({ error: 'Invalid payment method' });
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

    const deliveryFee = subtotal >= 100000 ? 0 : 12000;
    const total = subtotal + deliveryFee;
    const isPaid = paymentMethod === 'cash' ? false : false; // online → wait for webhook

    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });
    if (!shop.isActive) return res.status(400).json({ error: 'Shop is not active' });

    const order = await prisma.order.create({
      data: {
        buyerId: req.user.id,
        customerName: req.user.name || 'Xaridor',
        customerPhone: req.user.phone,
        shopId,
        deliveryAddress, deliveryLat, deliveryLng,
        customerComment,
        paymentMethod, isPaid,
        subtotal, deliveryFee, total,
        status: STATUS.PENDING,
        items: { create: orderItemsData },
      },
      include: { items: true, shop: true, courier: true },
    });

    // Notify shop in real time
    emit(req, `shop:${shopId}`, 'order:new', order);
    // Push to shop members
    try {
      const members = await prisma.shopMember.findMany({ where: { shopId } });
      push.notifyShopNewOrder(order, members).catch(() => {});
    } catch (err) {
      logger.warn({ err: err.message }, 'shop push failed');
    }

    res.status(201).json({ order });
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
    res.json({ orders });
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
    res.json({ order });
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

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);
    push.notifyBuyerStatusUpdate(updated).catch(() => {});
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

    const updated = await prisma.order.findUnique({
      where: { id: order.id },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);
    emit(req, 'couriers', 'order:taken', { orderId: order.id });
    push.notifyBuyerStatusUpdate(updated).catch(() => {});

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

    await prisma.user.update({
      where: { id: req.user.id },
      data: { ordersCount: { increment: 1 } },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);
    push.notifyBuyerStatusUpdate(updated).catch(() => {});

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

module.exports = router;
module.exports.priceItem = priceItem;
