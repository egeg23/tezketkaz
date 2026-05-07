const router = require('express').Router();
const prisma = require('../db');
const state = require('../state');
const { authMiddleware, requireRole } = require('../middleware/auth');

// Order status flow
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

const COURIER_RADIUS_KM = Number(process.env.COURIER_RADIUS_KM || 5);

// Notify nearby online couriers (within radius of the shop) about an available order
function notifyNearbyCouriers(req, order) {
  const io = req.app.get('io');
  const shopPoint = (order.shop?.lat != null && order.shop?.lng != null)
    ? { lat: order.shop.lat, lng: order.shop.lng }
    : null;
  const ids = state.nearbyCourierIds(shopPoint, COURIER_RADIUS_KM);
  if (ids.length === 0) {
    // Fallback to broadcast — keep flow working in dev / when no GPS yet
    io.to('couriers').emit('order:available', order);
    return;
  }
  ids.forEach((uid) => io.to(`courier:${uid}`).emit('order:available', order));
}

// Helper: get io from app and emit
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
  const num = parseInt(last.orderNumber.split('-')[1] || '99') + 1;
  return `K-${num}`;
}

// ─── POST /api/orders — buyer places order ───────────────────────────────────
router.post('/', authMiddleware, async (req, res, next) => {
  try {
    const {
      shopId,
      items, // [{ productId, quantity }]
      deliveryAddress,
      deliveryLat,
      deliveryLng,
      customerComment,
      paymentMethod,
    } = req.body;

    if (!shopId || !items?.length || !deliveryAddress || !paymentMethod) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Fetch product data
    const productIds = items.map(i => i.productId);
    const products = await prisma.product.findMany({
      where: { id: { in: productIds } },
    });
    const productMap = Object.fromEntries(products.map(p => [p.id, p]));

    let subtotal = 0;
    const orderItemsData = items.map(i => {
      const p = productMap[i.productId];
      if (!p) throw new Error(`Product ${i.productId} not found`);
      const price = p.discountPrice || p.price;
      const total = price * i.quantity;
      subtotal += total;
      return {
        productId: p.id,
        productName: p.name,
        quantity: i.quantity,
        price,
        total,
      };
    });

    const deliveryFee = subtotal >= 100000 ? 0 : 12000;
    const total = subtotal + deliveryFee;
    const isPaid = paymentMethod !== 'cash';

    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    if (!shop) return res.status(404).json({ error: 'Shop not found' });

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

    res.status(201).json({ order });
  } catch (err) { next(err); }
});

// ─── GET /api/orders/mine — buyer's orders ───────────────────────────────────
router.get('/mine', authMiddleware, async (req, res, next) => {
  try {
    const orders = await prisma.order.findMany({
      where: { buyerId: req.user.id },
      orderBy: { createdAt: 'desc' },
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
    res.json({ order });
  } catch (err) { next(err); }
});

// ─── GET /api/orders/shop/:shopId ────────────────────────────────────────────
router.get('/shop/:shopId', authMiddleware, async (req, res, next) => {
  try {
    // Check membership
    const isMember = await prisma.shopMember.findUnique({
      where: { userId_shopId: { userId: req.user.id, shopId: req.params.shopId } },
    });
    if (!isMember) return res.status(403).json({ error: 'Not a shop member' });

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
        status: { in: [STATUS.COURIER_ASSIGNED, STATUS.PICKED_UP, STATUS.IN_DELIVERY] },
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
    if (order.status !== STATUS.PENDING) {
      return res.status(400).json({ error: 'Order is not pending' });
    }

    // Check shop membership
    const isMember = await prisma.shopMember.findUnique({
      where: { userId_shopId: { userId: req.user.id, shopId: order.shopId } },
    });
    if (!isMember) return res.status(403).json({ error: 'Not a shop member' });

    const orderNumber = await nextOrderNumber(order.shopId);
    const updated = await prisma.order.update({
      where: { id: order.id },
      data: {
        status: STATUS.COLLECTING,
        orderNumber,
        acceptedAt: new Date(),
      },
      include: { items: true, shop: true, courier: true },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    // Pre-dispatch — let nearby couriers grab it while shop is collecting
    notifyNearbyCouriers(req, updated);

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

    const isMember = await prisma.shopMember.findUnique({
      where: { userId_shopId: { userId: req.user.id, shopId: order.shopId } },
    });
    if (!isMember) return res.status(403).json({ error: 'Not a shop member' });

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { status: STATUS.READY_FOR_PICKUP, readyAt: new Date() },
      include: { items: true, shop: true, courier: true },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    // If courier still not assigned, re-notify nearby couriers (now urgent)
    if (!updated.courierId) notifyNearbyCouriers(req, updated);

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/shop/cancel ────────────────────────────────────────
router.post('/:id/shop/cancel', authMiddleware, async (req, res, next) => {
  try {
    const { reason } = req.body;
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) return res.status(404).json({ error: 'Not found' });

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { status: STATUS.CANCELLED, cancelledAt: new Date(), cancelReason: reason },
      include: { items: true, shop: true },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);

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

    // If shop already finished assembly — go straight to courierAssigned;
    // otherwise keep collecting so shop UI doesn't get out of sync.
    const newStatus = order.status === STATUS.READY_FOR_PICKUP
      ? STATUS.COURIER_ASSIGNED
      : STATUS.COLLECTING;
    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { courierId: req.user.id, status: newStatus },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });

    emit(req, `order:${order.id}`, 'order:updated', updated);
    emit(req, `buyer:${order.buyerId}`, 'order:updated', updated);
    emit(req, `shop:${order.shopId}`, 'order:updated', updated);
    emit(req, `couriers`, 'order:taken', { orderId: order.id });

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/courier/pickup ─────────────────────────────────────
// Курьер вводит номер заказа от магазина
router.post('/:id/courier/pickup', authMiddleware, requireRole('courier'), async (req, res, next) => {
  try {
    const { orderNumber } = req.body;
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (order.courierId !== req.user.id) {
      return res.status(403).json({ error: 'Not your order' });
    }
    if (order.orderNumber?.toLowerCase() !== orderNumber?.toLowerCase().trim()) {
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

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/courier/arrived ────────────────────────────────────
// Courier reached the customer's address — waiting at the door
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
    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/courier/complete ───────────────────────────────────
// Courier handed the order over to customer
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

    res.json({ order: updated });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:id/buyer/confirm ──────────────────────────────────────
// Customer confirms they received the order (final step in the chain)
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
    const { rating, review } = req.body;
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) return res.status(404).json({ error: 'Not found' });
    if (order.buyerId !== req.user.id) return res.status(403).json({ error: 'Not your order' });

    await prisma.order.update({
      where: { id: order.id },
      data: { buyerRating: rating, buyerReview: review },
    });
    res.json({ success: true });
  } catch (err) { next(err); }
});

module.exports = router;
