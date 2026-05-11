// Test helper: creates an isolated Postgres SCHEMA per test file by running
// migrations against a unique schema, then returns a PrismaClient bound to it.
// Schemas are wiped on teardown.
//
// Requires DATABASE_URL pointing to a reachable Postgres server. The schema
// name in the URL is overridden per test file. CI workflow and local
// docker-compose both provide such a server.
//
// Usage in a test file:
//   const { setupTestDb, teardownTestDb } = require('./helpers/db');
//   let ctx;
//   beforeAll(async () => { ctx = await setupTestDb('modifiers'); });
//   afterAll(async () => { await teardownTestDb(ctx); });
//
// `ctx.app` is a fresh Express app with the routes mounted. Each call wires
// `prisma` to the per-file schema by setting DATABASE_URL before requiring
// modules.

const path = require('path');
const { execSync } = require('child_process');

// Build a per-test-file schema name. Postgres schema names are limited to
// 63 chars, must start with a letter, and are case-sensitive when quoted.
function makeSchemaName(slug) {
  const safe = String(slug).toLowerCase().replace(/[^a-z0-9_]/g, '_').slice(0, 32);
  return `test_${safe}_${process.pid}`;
}

// Replace (or insert) the `schema=...` query param in DATABASE_URL.
function urlWithSchema(baseUrl, schema) {
  const u = new URL(baseUrl);
  u.searchParams.set('schema', schema);
  return u.toString();
}

function baseDatabaseUrl() {
  return (
    process.env.TEST_DATABASE_URL ||
    process.env.DATABASE_URL ||
    'postgresql://postgres:postgres@localhost:5432/tezketkaz_test'
  );
}

async function setupTestDb(slug) {
  const schema = makeSchemaName(slug);
  const dbUrl = urlWithSchema(baseDatabaseUrl(), schema);
  // Set the URL BEFORE requiring prisma client so it picks it up.
  process.env.DATABASE_URL = dbUrl;
  process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-min-eight-chars';

  // Apply migrations to the new schema. `prisma migrate deploy` creates the
  // schema implicitly when targeting a fresh one.
  execSync('npx prisma migrate deploy', {
    cwd: path.resolve(__dirname, '..', '..'),
    env: { ...process.env, DATABASE_URL: dbUrl },
    stdio: 'pipe',
  });

  // Reset module cache so PrismaClient picks up the new DATABASE_URL.
  for (const k of Object.keys(require.cache)) {
    if (k.includes('/src/') || k.includes('/@prisma/client/')) {
      delete require.cache[k];
    }
  }

  const prisma = require('../../src/db');
  const express = require('express');
  const app = express();
  app.use(express.json());
  // Inject request id for downstream loggers.
  app.use((req, res, next) => { req.id = 'test'; next(); });

  // Mount only the routes we test — keeps boot fast and avoids side effects
  // (rate limiting, sockets, static serving).
  app.use('/api/users', require('../../src/routes/users'));
  app.use('/api/shops', require('../../src/routes/shops'));
  app.use('/api/products', require('../../src/routes/products'));
  // Phase 11 — cart drafts.
  try { app.use('/api/cart-drafts', require('../../src/routes/cart-drafts')); } catch { /* noop */ }
  app.use('/api/categories', require('../../src/routes/categories'));
  app.use('/api', require('../../src/routes/modifiers'));
  app.use('/api', require('../../src/routes/zones'));
  app.use('/api/admin/pricing-rules', require('../../src/routes/pricing-rules'));
  app.use('/api/orders', require('../../src/routes/orders'));
  // Phase 3 routes (reviews, chat) — routers declare absolute paths.
  try { app.use('/api', require('../../src/routes/reviews')); } catch { /* missing in unrelated tests */ }
  try { app.use('/api', require('../../src/routes/chat')); } catch { /* missing in unrelated tests */ }
  // Phase 4 — admin + buyer disputes.
  try { app.use('/api/admin', require('../../src/routes/admin')); } catch { /* noop */ }
  try { app.use('/api', require('../../src/routes/buyer-disputes')); } catch { /* noop */ }
  // Phase 6.5 — KYC verification (declares absolute paths under /verification
  // and /admin/verification).
  try { app.use('/api', require('../../src/routes/verification')); } catch { /* noop */ }
  // Phase 6.4 — working hours (declares absolute /api/shops/:id/working-hours).
  try { app.use('/api', require('../../src/routes/working-hours')); } catch { /* noop */ }
  // Phase 6.1 — saved tokenized payment methods.
  try { app.use('/api/payment-methods', require('../../src/routes/payment-methods')); } catch { /* noop */ }
  // Phase 7.2 — Wolt+/Yandex Plus membership.
  try { app.use('/api/membership', require('../../src/routes/membership')); } catch { /* noop */ }
  // Phase 7.3 — banners + favorites.
  try { app.use('/api', require('../../src/routes/banners')); } catch { /* noop */ }
  try { app.use('/api/favorites', require('../../src/routes/favorites')); } catch { /* noop */ }
  // Phase 8.3 — courier performance breakdown.
  try { app.use('/api/couriers', require('../../src/routes/courier-performance')); } catch { /* noop */ }
  // Phase 8.4 — courier demand heatmap.
  try { app.use('/api/couriers', require('../../src/routes/heatmap')); } catch { /* noop */ }
  // Phase 2 — courier shifts + dispatch accept/decline.
  try { app.use('/api', require('../../src/routes/courier-shifts')); } catch { /* noop */ }
  // Phase 8.5 — instant payout (declares absolute /couriers and /admin paths).
  try { app.use('/api', require('../../src/routes/instant-payout')); } catch { /* noop */ }
  // Phase 9.1/9.2 — GDPR (data export + account deletion).
  try { app.use('/api/users', require('../../src/routes/gdpr')); } catch { /* noop */ }
  // Phase 9.3 — auth (OAuth endpoints + OTP). Some test files exercise this.
  try { app.use('/api/auth', require('../../src/routes/auth')); } catch { /* noop */ }
  // Phase 10.2 — customer support inbox.
  try {
    const supportRoutes = require('../../src/routes/support');
    app.use('/api/support', supportRoutes);
    app.use('/api/admin/support', supportRoutes.adminRouter);
  } catch { /* noop */ }
  // Phase 10.3 — push notification campaigns.
  try {
    const pushCampaignRoutes = require('../../src/routes/push-campaigns');
    app.use('/api/admin/push-campaigns', pushCampaignRoutes.adminRouter);
    app.use('/api/push-campaigns', pushCampaignRoutes.userRouter);
  } catch { /* noop */ }
  // Phase 12 — legal documents (privacy + terms).
  try { app.use('/api/legal', require('../../src/routes/legal')); } catch { /* noop */ }
  // Stub the io getter — orders.js uses `req.app.get('io')`.
  const noopIo = { to: () => ({ emit: () => {} }), emit: () => {} };
  app.set('io', noopIo);
  // Error handler so failures surface as JSON (not HTML). Set
  // `TEST_DEBUG_ERRORS=1` to also print stack traces for 5xx errors — handy
  // when triaging broken routes locally.
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, _next) => {
    const status = err.status || err.statusCode || 500;
    if (status >= 500 && process.env.TEST_DEBUG_ERRORS === '1') {
      // eslint-disable-next-line no-console
      console.error('[test-route-error]', err && (err.stack || err.message));
    }
    res.status(status).json({ error: err.message || 'Server error' });
  });

  return { prisma, app, schema, dbUrl };
}

async function teardownTestDb(ctx) {
  if (!ctx) return;
  // Drop the per-test schema so subsequent runs are clean. Use a fresh
  // PrismaClient pointed at the public schema so the DROP isn't blocked by
  // open transactions or by being inside the schema we're deleting.
  if (ctx.schema && ctx.dbUrl) {
    try {
      const cleanupUrl = urlWithSchema(ctx.dbUrl, 'public');
      const { PrismaClient } = require('@prisma/client');
      const cleanup = new PrismaClient({
        datasources: { db: { url: cleanupUrl } },
      });
      await cleanup.$executeRawUnsafe(
        `DROP SCHEMA IF EXISTS "${ctx.schema}" CASCADE`
      );
      await cleanup.$disconnect();
    } catch {
      // Non-fatal; the next run will reuse or recreate the schema.
    }
  }
  try { await ctx.prisma.$disconnect(); } catch { /* noop */ }
}

// Create a user + return { user, token } using JWT helpers.
async function createUser(prisma, overrides = {}) {
  const jwtLib = require('../../src/lib/jwt');
  const phone = overrides.phone || `+9989${Math.floor(Math.random() * 100000000).toString().padStart(8, '0')}`;
  const user = await prisma.user.create({
    data: {
      phone,
      name: overrides.name || 'Test User',
      isBuyer: overrides.isBuyer ?? true,
      isShop: overrides.isShop ?? false,
      isAdmin: overrides.isAdmin ?? false,
      isCourier: overrides.isCourier ?? false,
      courierStatus: overrides.courierStatus ?? 'none',
    },
  });
  const { token } = jwtLib.signAccess(user.id);
  return { user, token, auth: `Bearer ${token}` };
}

async function createShopWithOwner(prisma, owner) {
  const shop = await prisma.shop.create({
    data: {
      name: 'Test Shop',
      address: '1 Test St',
      lat: 41.0,
      lng: 69.0,
    },
  });
  await prisma.shopMember.create({
    data: { userId: owner.id, shopId: shop.id, role: 'owner' },
  });
  return shop;
}

async function createProduct(prisma, shopId, overrides = {}) {
  return prisma.product.create({
    data: {
      shopId,
      name: overrides.name || 'Burger',
      nameUz: overrides.nameUz || 'Burger',
      price: overrides.price ?? 30000,
      discountPrice: overrides.discountPrice ?? null,
      unit: 'шт',
      category: 'food',
      imageUrl: 'https://example.com/x.jpg',
      isAvailable: overrides.isAvailable ?? true,
    },
  });
}

module.exports = {
  setupTestDb,
  teardownTestDb,
  createUser,
  createShopWithOwner,
  createProduct,
};
