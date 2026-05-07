const jwt = require('jsonwebtoken');
const prisma = require('../db');
const state = require('../state');

function setupSockets(io) {
  // Auth middleware for sockets
  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth?.token;
      if (!token) return next(new Error('No token'));
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      const user = await prisma.user.findUnique({
        where: { id: decoded.userId },
        include: { shopMemberships: true },
      });
      if (!user) return next(new Error('User not found'));
      socket.user = user;
      next();
    } catch (err) {
      next(new Error('Auth failed'));
    }
  });

  io.on('connection', (socket) => {
    const user = socket.user;
    console.log(`✅ Socket connected: ${user.phone} (${socket.id})`);

    // Join personal rooms based on roles
    socket.join(`buyer:${user.id}`);

    if (user.isCourier) {
      socket.join('couriers');
      socket.join(`courier:${user.id}`);
      state.setCourierOnline(user.id, socket.id);
    }

    if (user.isShop) {
      user.shopMemberships.forEach(m => {
        socket.join(`shop:${m.shopId}`);
      });
    }

    // Order tracking — buyer/courier subscribes to specific order
    socket.on('order:subscribe', (orderId) => {
      socket.join(`order:${orderId}`);
    });

    socket.on('order:unsubscribe', (orderId) => {
      socket.leave(`order:${orderId}`);
    });

    // Courier location updates → broadcast to buyer and shop, also update presence
    socket.on('courier:location', async ({ orderId, lat, lng }) => {
      if (!user.isCourier || lat == null || lng == null) return;
      state.setCourierLocation(user.id, lat, lng);

      // Per-order broadcast (buyer/shop subscribed to order:${id} room)
      if (orderId) {
        const order = await prisma.order.findUnique({ where: { id: orderId } });
        if (order && order.courierId === user.id) {
          io.to(`order:${orderId}`).emit('courier:location', {
            orderId, courierId: user.id, lat, lng, ts: Date.now(),
          });
        }
      }
    });

    socket.on('disconnect', () => {
      console.log(`❌ Socket disconnected: ${user.phone}`);
      if (user.isCourier) state.setCourierOffline(user.id);
    });
  });
}

module.exports = { setupSockets };
