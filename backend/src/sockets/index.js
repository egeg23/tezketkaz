// Socket.IO setup with secure JWT auth (access tokens with Redis blacklist),
// optional Redis adapter for multi-instance pub/sub, throttled courier-location
// updates, and Redis-backed presence/location state.

const prisma = require('../db');
const env = require('../config/env');
const logger = require('../lib/logger');
const jwtLib = require('../lib/jwt');
const redis = require('../lib/redis');
const presence = require('../services/redis-state');

const LOCATION_MIN_INTERVAL_MS = 1000; // max 1 update / second per courier socket

function setupSockets(io) {
  // Expose the io instance to background workers (jobs/dispatch.js etc.).
  module.exports.io = io;
  // Optional Redis adapter for cross-instance pub/sub
  if (env.redisEnabled) {
    try {
      // Lazy require — not needed when Redis is disabled
      // eslint-disable-next-line global-require
      const { createAdapter } = require('@socket.io/redis-adapter');
      const pub = redis.getRedis();
      const sub = redis.getRedisSub();
      if (pub && sub) {
        io.adapter(createAdapter(pub, sub));
        logger.info('socket.io Redis adapter attached');
      }
    } catch (err) {
      logger.warn({ err: err.message }, 'failed to attach socket.io redis adapter');
    }
  }

  // Auth middleware for sockets
  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth?.token;
      if (!token) return next(new Error('No token'));

      let decoded;
      try {
        decoded = await jwtLib.verifyAccess(token);
      } catch (err) {
        logger.warn({ err: err.message }, 'socket access token rejected');
        return next(new Error('Auth failed'));
      }

      const user = await prisma.user.findUnique({
        where: { id: decoded.userId },
        include: { shopMemberships: true },
      });
      if (!user) return next(new Error('User not found'));

      socket.user = user;
      socket.tokenJti = decoded.jti;
      next();
    } catch (err) {
      logger.error({ err }, 'socket auth error');
      next(new Error('Auth failed'));
    }
  });

  // In-memory throttle map (per-socket; ok because it lives with the connection)
  const lastLocationTs = new Map(); // socketId → ms

  io.on('connection', async (socket) => {
    const user = socket.user;
    logger.info({ userId: user.id, phone: user.phone, socketId: socket.id }, 'socket connected');

    // Join personal rooms based on roles
    socket.join(`buyer:${user.id}`);

    if (user.isCourier) {
      socket.join('couriers');
      socket.join(`courier:${user.id}`);
      try {
        await presence.setCourierOnline(user.id, socket.id);
      } catch (err) {
        logger.error({ err }, 'setCourierOnline failed');
      }
    }

    if (user.isShop) {
      (user.shopMemberships || []).forEach((m) => {
        socket.join(`shop:${m.shopId}`);
      });
    }

    // Order tracking — buyer/courier subscribes to specific order
    socket.on('order:subscribe', (orderId) => {
      if (typeof orderId === 'string' && orderId) socket.join(`order:${orderId}`);
    });

    socket.on('order:unsubscribe', (orderId) => {
      if (typeof orderId === 'string' && orderId) socket.leave(`order:${orderId}`);
    });

    // Phase 3: chat join — validate participant before subscribing.
    socket.on('chat:join', async (payload = {}) => {
      const orderId = typeof payload === 'string' ? payload : payload.orderId;
      if (!orderId || typeof orderId !== 'string') return;
      try {
        const order = await prisma.order.findUnique({
          where: { id: orderId },
          select: { id: true, buyerId: true, courierId: true, shopId: true },
        });
        if (!order) return;
        let allowed = order.buyerId === user.id || order.courierId === user.id;
        if (!allowed) {
          const m = await prisma.shopMember.findUnique({
            where: { userId_shopId: { userId: user.id, shopId: order.shopId } },
          }).catch(() => null);
          allowed = !!m;
        }
        if (allowed) socket.join(`order:${orderId}`);
      } catch (err) {
        logger.warn({ err: err.message }, 'chat:join failed');
      }
    });

    // Phase 3: chat typing indicator — relay to room.
    socket.on('chat:typing', (payload = {}) => {
      const orderId = typeof payload === 'string' ? payload : payload.orderId;
      if (!orderId || typeof orderId !== 'string') return;
      const isTyping = payload.isTyping !== false;
      socket.to(`order:${orderId}`).emit('chat:typing', {
        orderId, userId: user.id, isTyping,
      });
    });

    // Courier location updates → broadcast + presence
    socket.on('courier:location', async ({ orderId, lat, lng } = {}) => {
      // Reject from non-courier or unapproved-courier sockets
      if (!user.isCourier || user.courierStatus !== 'approved') return;
      if (lat == null || lng == null) return;

      // Per-socket throttle: max 1 update / second
      const now = Date.now();
      const last = lastLocationTs.get(socket.id) || 0;
      if (now - last < LOCATION_MIN_INTERVAL_MS) return;
      lastLocationTs.set(socket.id, now);

      try {
        await presence.setCourierLocation(user.id, lat, lng);
      } catch (err) {
        logger.error({ err }, 'setCourierLocation failed');
        return;
      }

      // Per-order broadcast (buyer/shop subscribed to order:${id} room)
      if (orderId && typeof orderId === 'string') {
        try {
          const order = await prisma.order.findUnique({ where: { id: orderId } });
          if (order && order.courierId === user.id) {
            io.to(`order:${orderId}`).emit('courier:location', {
              orderId, courierId: user.id, lat, lng, ts: now,
            });
          }
        } catch (err) {
          logger.error({ err }, 'order broadcast failed');
        }
      }
    });

    // Phase 2: explicit online toggle (separate from shift bookkeeping).
    socket.on('courier:online', async (payload = {}) => {
      if (!user.isCourier) return;
      const isOnline = payload.isOnline !== false;
      try {
        await prisma.user.update({
          where: { id: user.id },
          data: { isOnline, lastSeenAt: new Date() },
        });
        if (isOnline) await presence.setCourierOnline(user.id, socket.id);
        else await presence.setCourierOffline(user.id);
      } catch (err) {
        logger.error({ err }, 'courier:online toggle failed');
      }
    });

    socket.on('disconnect', async () => {
      logger.info({ userId: user.id, phone: user.phone, socketId: socket.id }, 'socket disconnected');
      lastLocationTs.delete(socket.id);
      if (user.isCourier) {
        try {
          await presence.setCourierOffline(user.id);
        } catch (err) {
          logger.error({ err }, 'setCourierOffline failed');
        }
      }
    });
  });
}

module.exports = { setupSockets };
