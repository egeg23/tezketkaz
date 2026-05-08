// Test helper: creates an isolated SQLite DB per test file by running migrations
// against a unique file, then returns a PrismaClient bound to it.
//
// Usage in a test file:
//   const { setupTestDb, teardownTestDb } = require('./helpers/db');
//   let ctx;
//   beforeAll(async () => { ctx = await setupTestDb('modifiers'); });
//   afterAll(async () => { await teardownTestDb(ctx); });
//
// `ctx.app` is a fresh Express app with the routes mounted. Each call wires
// `prisma` to the per-file DB by setting DATABASE_URL before requiring modules.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

function makeDbPath(slug) {
  const dir = path.resolve(__dirname, '..', '..', 'prisma');
  const file = path.join(dir, `test-${slug}-${process.pid}.db`);
  // Wipe any leftover from a crashed previous run.
  try { fs.unlinkSync(file); } catch { /* noop */ }
  try { fs.unlinkSync(file + '-journal'); } catch { /* noop */ }
  return file;
}

async function setupTestDb(slug) {
  const dbFile = makeDbPath(slug);
  // Set the URL BEFORE requiring prisma client so it picks it up.
  process.env.DATABASE_URL = `file:./prisma/${path.basename(dbFile)}`;
  process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-min-eight-chars';

  // Apply migrations to the new file.
  execSync('npx prisma migrate deploy', {
    cwd: path.resolve(__dirname, '..', '..'),
    env: { ...process.env, DATABASE_URL: process.env.DATABASE_URL },
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
  // Stub the io getter — orders.js uses `req.app.get('io')`.
  const noopIo = { to: () => ({ emit: () => {} }), emit: () => {} };
  app.set('io', noopIo);
  // Error handler so failures surface as JSON (not HTML).
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, _next) => {
    const status = err.status || err.statusCode || 500;
    res.status(status).json({ error: err.message || 'Server error' });
  });

  return { prisma, app, dbFile };
}

async function teardownTestDb(ctx) {
  if (!ctx) return;
  try { await ctx.prisma.$disconnect(); } catch { /* noop */ }
  try { fs.unlinkSync(ctx.dbFile); } catch { /* noop */ }
  try { fs.unlinkSync(ctx.dbFile + '-journal'); } catch { /* noop */ }
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
