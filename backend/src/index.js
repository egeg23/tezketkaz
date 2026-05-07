require('dotenv').config();

const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const path = require('path');
const http = require('http');
const { Server } = require('socket.io');

const authRoutes = require('./routes/auth');
const shopRoutes = require('./routes/shops');
const productRoutes = require('./routes/products');
const orderRoutes = require('./routes/orders');
const userRoutes = require('./routes/users');
const courierRoutes = require('./routes/couriers');
const paymentRoutes = require('./routes/payments');
const adminRoutes = require('./routes/admin');
const { setupSockets } = require('./sockets');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });
app.set('io', io);

// ─── Middleware ─────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(morgan('dev'));

// Health
app.get('/health', (req, res) => res.json({ ok: true, ts: Date.now() }));

// ─── API Routes ─────────────────────────────────────────────────────────────
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/shops', shopRoutes);
app.use('/api/products', productRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/couriers', courierRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/admin', adminRoutes);

// ─── User-uploaded product images ────────────────────────────────────────────
app.use('/uploads', express.static(path.join(__dirname, '../uploads'), {
  maxAge: '7d',
  setHeaders: (res) => res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin'),
}));

// ─── Static admin panel ─────────────────────────────────────────────────────
app.use('/admin', express.static(path.join(__dirname, '../../admin')));

// ─── Flutter web build (mount at /) ─────────────────────────────────────────
const webRoot = path.join(__dirname, '../../build/web');
app.use(express.static(webRoot, {
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('.html') || filePath.endsWith('.js') || filePath.endsWith('service_worker.js')) {
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    }
  },
}));
// SPA fallback — for any GET that's not /api or /admin, return index.html
app.get(/^\/(?!api|admin|uploads).*/, (req, res, next) => {
  if (req.method !== 'GET') return next();
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
  res.sendFile(path.join(webRoot, 'index.html'));
});

// ─── Error handler ──────────────────────────────────────────────────────────
app.use((err, req, res, next) => {
  console.error('🔥', err);
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

// ─── Sockets ────────────────────────────────────────────────────────────────
setupSockets(io);

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`🚀 TezKetKaz API running on :${PORT}`);
  console.log(`📡 Socket.IO ready`);
  console.log(`👨‍💼 Admin: http://localhost:${PORT}/admin`);
  console.log(`📚 Health: http://localhost:${PORT}/health`);
});
