// Bootstrap environment validation FIRST — fails fast on missing config.
const env = require('./config/env');

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const pinoHttp = require('pino-http');
const path = require('path');
const http = require('http');
const { randomUUID } = require('crypto');
const { Server } = require('socket.io');

const logger = require('./lib/logger');
const redisLib = require('./lib/redis');

const authRoutes = require('./routes/auth');
const shopRoutes = require('./routes/shops');
const productRoutes = require('./routes/products');
const categoryRoutes = require('./routes/categories');
const orderRoutes = require('./routes/orders');
const userRoutes = require('./routes/users');
const courierRoutes = require('./routes/couriers');
const paymentRoutes = require('./routes/payments');
const adminRoutes = require('./routes/admin');
const modifierRoutes = require('./routes/modifiers');
const { setupSockets } = require('./sockets');

const app = express();
app.set('trust proxy', 1);                    // we sit behind Render/Railway/Cloudflare
app.disable('x-powered-by');

const server = http.createServer(app);

// ─── Security headers ───────────────────────────────────────────────────────
app.use(helmet({
  // Disable strict CSP because we serve a Flutter web bundle that needs inline
  // bootstrapping and remote fonts. Re-tune once we move to a separate frontend
  // origin.
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
  crossOriginResourcePolicy: { policy: 'cross-origin' },
}));

// ─── CORS ───────────────────────────────────────────────────────────────────
const corsOrigins = (env.FRONTEND_URL || '*').split(',').map((s) => s.trim());
app.use(cors({
  origin: corsOrigins.includes('*') ? true : corsOrigins,
  credentials: true,
}));

// ─── Body parsing ───────────────────────────────────────────────────────────
// Uzum callback needs raw bytes for HMAC verification — leave body as Buffer
// for that path and let the route handler parse it. Everything else gets the
// global JSON parser.
const RAW_PATHS = ['/api/payments/uzum/callback'];
app.use((req, res, next) => {
  if (RAW_PATHS.includes(req.path)) {
    return express.raw({ type: '*/*', limit: '256kb' })(req, res, next);
  }
  return express.json({ limit: '5mb' })(req, res, next);
});
app.use(express.urlencoded({ extended: true, limit: '5mb' }));

// ─── Request id + structured logging ────────────────────────────────────────
app.use((req, res, next) => {
  req.id = req.headers['x-request-id'] || randomUUID();
  res.setHeader('X-Request-Id', req.id);
  next();
});
app.use(pinoHttp({
  logger,
  genReqId: (req) => req.id,
  customLogLevel: (req, res, err) => {
    if (err || res.statusCode >= 500) return 'error';
    if (res.statusCode >= 400) return 'warn';
    return 'info';
  },
  serializers: {
    req: (req) => ({ id: req.id, method: req.method, url: req.url, ip: req.remoteAddress }),
    res: (res) => ({ statusCode: res.statusCode }),
  },
}));

// ─── Rate limiting ──────────────────────────────────────────────────────────
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: env.isProd ? 600 : 5000,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Too many requests' },
});
app.use('/api', globalLimiter);

const otpSendLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 3,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Too many OTP requests, wait a minute' },
});
const otpVerifyLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Too many verify attempts' },
});
const refreshLimiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  max: 30,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Too many refresh attempts' },
});
app.use('/api/auth/send-otp', otpSendLimiter);
app.use('/api/auth/verify-otp', otpVerifyLimiter);
app.use('/api/auth/refresh', refreshLimiter);

// ─── Socket.IO ──────────────────────────────────────────────────────────────
const io = new Server(server, {
  cors: { origin: corsOrigins.includes('*') ? '*' : corsOrigins, credentials: true },
});
app.set('io', io);

// ─── Health ─────────────────────────────────────────────────────────────────
app.get('/health', (req, res) => res.json({ ok: true, ts: Date.now() }));
app.get('/ready', async (req, res) => {
  const checks = { db: 'unknown', redis: 'unknown' };
  try {
    const prisma = require('./db');
    await prisma.$queryRaw`SELECT 1`;
    checks.db = 'ok';
  } catch (err) { checks.db = `error: ${err.message}`; }
  try {
    const r = redisLib.getRedis();
    if (!r) checks.redis = 'disabled';
    else { await r.ping(); checks.redis = 'ok'; }
  } catch (err) { checks.redis = `error: ${err.message}`; }
  const ok = checks.db === 'ok' && checks.redis !== 'error';
  res.status(ok ? 200 : 503).json({ ok, checks });
});

// ─── API Routes ─────────────────────────────────────────────────────────────
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/shops', shopRoutes);
app.use('/api/products', productRoutes);
app.use('/api/categories', categoryRoutes);
app.use('/api', modifierRoutes); // modifier groups/options use absolute paths
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

// ─── 404 ────────────────────────────────────────────────────────────────────
app.use('/api', (req, res) => res.status(404).json({ error: 'Not found' }));

// ─── Error handler ──────────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, _next) => {
  const status = err.status || err.statusCode || 500;
  if (status >= 500) {
    logger.error({ err, reqId: req.id, url: req.url }, 'unhandled');
  } else {
    logger.warn({ err: err.message, reqId: req.id, url: req.url }, 'request error');
  }
  const message = status >= 500 && env.isProd ? 'Internal server error' : (err.message || 'Internal server error');
  res.status(status).json({ error: message, requestId: req.id });
});

// ─── Sockets ────────────────────────────────────────────────────────────────
setupSockets(io).catch((err) => {
  logger.error({ err }, 'sockets bootstrap failed');
});

// ─── Graceful shutdown ──────────────────────────────────────────────────────
async function shutdown(signal) {
  logger.info({ signal }, 'shutting down');
  server.close(() => logger.info('http server closed'));
  io.close();
  await redisLib.close();
  setTimeout(() => process.exit(0), 1500).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// ─── Listen ─────────────────────────────────────────────────────────────────
server.listen(env.PORT, () => {
  logger.info({ port: env.PORT, env: env.NODE_ENV, redis: env.redisEnabled, fcm: env.fcmEnabled },
    'TezKetKaz API ready');
});

module.exports = { app, server };
