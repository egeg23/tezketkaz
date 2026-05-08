// Phase 3: order chat (buyer ↔ courier ↔ shop). Messages live on ChatMessage.
// Read access: buyer | courier | any shop member of the order's shop.
// Realtime: emits `chat:message` to room `order:{id}` via req.app.get('io').
// Push: triggers notifications.sendChat to receiver.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const notifications = require('../services/notifications');
const logger = require('../lib/logger');

async function loadOrderForChat(orderId) {
  return prisma.order.findUnique({
    where: { id: orderId },
    select: { id: true, buyerId: true, courierId: true, shopId: true },
  });
}

async function isShopMember(userId, shopId) {
  if (!userId || !shopId) return false;
  const m = await prisma.shopMember.findUnique({
    where: { userId_shopId: { userId, shopId } },
  });
  return !!m;
}

async function canAccessChat(user, order) {
  if (!user || !order) return false;
  if (user.id === order.buyerId) return true;
  if (user.id === order.courierId) return true;
  if (user.isAdmin) return true;
  return isShopMember(user.id, order.shopId);
}

// Pick the receiver for a new chat message. Buyer → courier (fallback shop owner);
// courier → buyer; shop member → buyer.
async function pickReceiverId(senderUserId, order) {
  if (senderUserId === order.buyerId) {
    if (order.courierId) return order.courierId;
    // fallback: first shop member
    const sm = await prisma.shopMember.findFirst({
      where: { shopId: order.shopId },
      orderBy: { id: 'asc' },
    });
    return sm?.userId || null;
  }
  if (senderUserId === order.courierId) return order.buyerId;
  // shop member → buyer
  if (await isShopMember(senderUserId, order.shopId)) return order.buyerId;
  return null;
}

// ─── GET /api/orders/:orderId/chat ──────────────────────────────────────────
router.get('/orders/:orderId/chat', authMiddleware, async (req, res, next) => {
  try {
    const order = await loadOrderForChat(req.params.orderId);
    if (!order) return res.status(404).json({ error: 'Order not found' });
    if (!(await canAccessChat(req.user, order))) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const cursor = req.query.cursor ? { id: String(req.query.cursor) } : undefined;

    const messages = await prisma.chatMessage.findMany({
      where: { orderId: order.id },
      orderBy: { createdAt: 'asc' },
      take: limit + 1,
      ...(cursor ? { cursor, skip: 1 } : {}),
    });

    const hasMore = messages.length > limit;
    const out = hasMore ? messages.slice(0, limit) : messages;

    res.json({
      messages: out,
      nextCursor: hasMore ? out[out.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:orderId/chat ─────────────────────────────────────────
router.post('/orders/:orderId/chat', authMiddleware, async (req, res, next) => {
  try {
    const order = await loadOrderForChat(req.params.orderId);
    if (!order) return res.status(404).json({ error: 'Order not found' });
    if (!(await canAccessChat(req.user, order))) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const { text, imageUrl } = req.body || {};
    const cleanText = text != null ? String(text).slice(0, 4000) : null;
    const cleanImage = imageUrl ? String(imageUrl).slice(0, 1000) : null;
    if (!cleanText && !cleanImage) {
      return res.status(400).json({ error: 'text or imageUrl required' });
    }

    const receiverId = await pickReceiverId(req.user.id, order);
    if (!receiverId) {
      return res.status(400).json({ error: 'No receiver available' });
    }

    const msg = await prisma.chatMessage.create({
      data: {
        orderId: order.id,
        senderId: req.user.id,
        receiverId,
        text: cleanText,
        imageUrl: cleanImage,
      },
    });

    // Realtime fan-out to order room.
    try {
      const io = req.app.get('io');
      if (io && typeof io.to === 'function') {
        io.to(`order:${order.id}`).emit('chat:message', msg);
      }
    } catch (err) {
      logger.warn({ err: err.message }, 'chat socket emit failed');
    }

    // Push to receiver.
    try {
      const io = req.app.get('io');
      await notifications.sendChat(prisma, io, {
        senderName: req.user.name || '',
        receiverId,
        orderId: order.id,
        text: cleanText,
      });
    } catch (err) {
      logger.warn({ err: err.message }, 'chat push failed');
    }

    res.status(201).json({ message: msg });
  } catch (err) { next(err); }
});

// ─── POST /api/orders/:orderId/chat/read ────────────────────────────────────
router.post('/orders/:orderId/chat/read', authMiddleware, async (req, res, next) => {
  try {
    const order = await loadOrderForChat(req.params.orderId);
    if (!order) return res.status(404).json({ error: 'Order not found' });
    if (!(await canAccessChat(req.user, order))) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const result = await prisma.chatMessage.updateMany({
      where: {
        orderId: order.id,
        receiverId: req.user.id,
        isRead: false,
      },
      data: { isRead: true, readAt: new Date() },
    });

    res.json({ updated: result.count });
  } catch (err) { next(err); }
});

module.exports = router;
