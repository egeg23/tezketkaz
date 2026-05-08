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
const zoneRoutes = require('./routes/zones');
const pricingRuleRoutes = require('./routes/pricing-rules');
const courierShiftRoutes = require('./routes/courier-shifts');
const couponRoutes = require('./routes/coupons');
const loyaltyRoutes = require('./routes/loyalty');
const reviewRoutes = require('./routes/reviews');
const chatRoutes = require('./routes/chat');
const buyerDisputeRoutes = require('./routes/buyer-disputes');
const verificationRoutes = require('./routes/verification');
const paymentMethodRoutes = require('./routes/payment-methods');
const workingHoursRoutes = require('./routes/working-hours');
const membershipRoutes = require('./routes/membership');
const bannerRoutes = require('./routes/banners');
const favoriteRoutes = require('./routes/favorites');
const instantPayoutRoutes = require('./routes/instant-payout');
const courierPerformanceRoutes = require('./routes/courier-performance');
const heatmapRoutes = require('./routes/heatmap');
const gdprRoutes = require('./routes/gdpr');
const { setupSockets } = require('./sockets');

const app = express();
app.set('trust proxy', 1);                    // we sit behind Render/Railway/Cloudflare
app.disable('x-powered-by');

const server = http.createServer(app);

// ─── Sentry (must be FIRST middleware so it captures everything) ────────────
const sentry = require('./lib/sentry')(app, server);
app.use(sentry.requestHandler);
app.use(sentry.tracingHandler);
app.set('sentry', sentry);

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
// Phase 7 — Kaspi (KZ) also HMAC-signs raw bytes; same carve-out applies.
const RAW_PATHS = ['/api/payments/uzum/callback', '/api/payments/kaspi/callback'];
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
  customReceivedMessage: (req) => `→ ${req.method} ${req.url}`,
  customSuccessMessage: (req, res) => `← ${req.method} ${req.url} ${res.statusCode}`,
  customErrorMessage: (req, res) => `✗ ${req.method} ${req.url} ${res.statusCode}`,
  customProps: (req) => ({
    requestId: req.id,
    userId: req.user?.id,
  }),
  serializers: {
    req: (req) => ({ id: req.id, method: req.method, url: req.url, ip: req.remoteAddress }),
    res: (res) => ({ statusCode: res.statusCode }),
  },
}));

// ─── Health / readiness / version (mount BEFORE rate-limit + auth) ─────────
app.use('/', require('./routes/health'));

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
// Expose io to non-request contexts (BullMQ workers + the no-op queue's
// inline dispatcher fallback in lib/queues.js).
global.__tkk_io = io;

// ─── API Routes ─────────────────────────────────────────────────────────────
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
// Phase 9.1/9.2 — GDPR data export + account deletion. Mounted at /api/users
// so all endpoints are scoped under /api/users/me/*.
app.use('/api/users', gdprRoutes);
app.use('/api/shops', shopRoutes);
app.use('/api/products', productRoutes);
// Phase 7.3 — banners (public list + admin CRUD; declares absolute paths
// under /banners and /admin/banners).
app.use('/api', bannerRoutes);
// Phase 7.3 — buyer favorites (products + shops).
app.use('/api/favorites', favoriteRoutes);
// Phase 6.4 — working hours (declares absolute /api/shops/:id/working-hours).
app.use('/api', workingHoursRoutes);
// Phase 6.1 — saved tokenized payment methods.
app.use('/api/payment-methods', paymentMethodRoutes);
// Phase 6.5 — KYC verification (declares absolute paths under /verification
// /* and /admin/verification/*).
app.use('/api', verificationRoutes);
app.use('/api/coupons', couponRoutes);
app.use('/api/loyalty', loyaltyRoutes);
app.use('/api/categories', categoryRoutes);
app.use('/api', modifierRoutes); // modifier groups/options use absolute paths
app.use('/api', zoneRoutes); // zones routes use absolute /api/shops/:id/zones, /api/zones/:id
app.use('/api/orders', orderRoutes);
// Phase 7.2 — Wolt+/Yandex Plus membership.
app.use('/api/membership', membershipRoutes);
app.use('/api/couriers', courierRoutes);
// Phase 8.3 — courier performance breakdown (mounted alongside main courier
// router so /me/performance stacks with the existing /me/* sub-paths).
app.use('/api/couriers', courierPerformanceRoutes);
// Phase 8.4 — courier demand heatmap.
app.use('/api/couriers', heatmapRoutes);
// Phase 2 routes mounted at /api so they can declare absolute paths under
// /couriers/me/... and /orders/:id/dispatch/...
app.use('/api', courierShiftRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/admin/pricing-rules', pricingRuleRoutes);
// Phase 8.5 — instant payout (courier balance + admin review). Declares its
// own absolute paths under /couriers and /admin so it mounts at /api.
app.use('/api', instantPayoutRoutes);
app.use('/api/admin', adminRoutes);
// Phase 3: reviews + chat. Both routers declare absolute paths under /api/orders
// /:id/{reviews,chat} and /api/reviews/:id, so they mount at /api.
app.use('/api', reviewRoutes);
app.use('/api', chatRoutes);
// Phase 4 — buyer-facing dispute endpoints.
app.use('/api', buyerDisputeRoutes);

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

// ─── Sentry error handler (BEFORE app's 500 handler so it can capture) ─────
app.use(sentry.errorHandler);

// ─── Error handler ──────────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, _next) => {
  const status = err.status || err.statusCode || 500;
  if (status >= 500) {
    logger.error({ err, reqId: req.id, url: req.url }, 'unhandled');
    try { sentry.captureException(err); } catch { /* noop */ }
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

// ─── BullMQ workers (Phase 2 dispatch / auto-cancel) ────────────────────────
if (process.env.REDIS_URL || process.env.REDIS_HOST) {
  try {
    // eslint-disable-next-line global-require
    const { startWorkers, queues } = require('./lib/queues');
    // eslint-disable-next-line global-require
    const dispatchJobs = require('./jobs/dispatch');
    // eslint-disable-next-line global-require
    const scheduledJobs = require('./jobs/scheduled');
    // eslint-disable-next-line global-require
    const payoutJobs = require('./jobs/payouts');
    // eslint-disable-next-line global-require
    const membershipJobs = require('./jobs/membership');
    // eslint-disable-next-line global-require
    const accountDeletionJobs = require('./jobs/accountDeletion');
    // eslint-disable-next-line global-require
    const backupJobs = require('./jobs/backup');
    startWorkers({
      dispatch: dispatchJobs.dispatchHandler,
      autoCancel: dispatchJobs.autoCancelHandler,
      scheduled: scheduledJobs.scheduledHandler,
      payouts: payoutJobs.payoutsHandler,
      membership: membershipJobs.membershipHandler,
      accountDeletion: accountDeletionJobs.accountDeletionHandler,
      backup: backupJobs.backupHandler,
    });
    // Schedule weekly payouts: Mondays at 03:00 UTC.
    try {
      queues().payouts.add('weekly', {}, {
        repeat: { cron: '0 3 * * 1' },
        jobId: 'weekly-payouts-cron',
      });
    } catch (err) {
      logger.warn({ err: err.message }, 'failed to schedule weekly payouts cron');
    }
    // Phase 7.2 — daily membership renewal sweep at 04:00 UTC.
    try {
      queues().membership.add('renew', {}, {
        repeat: { cron: '0 4 * * *' },
        jobId: 'membership-renew-cron',
      });
    } catch (err) {
      logger.warn({ err: err.message }, 'failed to schedule membership renewal cron');
    }
    // Phase 9.2 — daily account-deletion purge at 05:00 UTC.
    try {
      queues().accountDeletion.add('purge', {}, {
        repeat: { cron: '0 5 * * *' },
        jobId: 'account-deletion-purge-cron',
      });
    } catch (err) {
      logger.warn({ err: err.message }, 'failed to schedule account deletion cron');
    }
    // Phase 9.4 — daily DB backup at 02:00 UTC.
    try {
      queues().backup.add('daily', {}, {
        repeat: { cron: '0 2 * * *' },
        jobId: 'daily-backup-cron',
      });
    } catch (err) {
      logger.warn({ err: err.message }, 'failed to schedule daily backup cron');
    }
    logger.info('BullMQ workers started');
  } catch (err) {
    logger.error({ err }, 'failed to start BullMQ workers');
  }
}

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
