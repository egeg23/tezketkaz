// Phase 14 — B2B integration endpoints for shops.
//
// Two surfaces:
//
//   1. Owner-facing (under /api/shops/me/integration/…) — accessed by the
//      shop manager from the Flutter Integration screen, gated by their
//      session JWT. Used to mint/rotate the API key, register the webhook,
//      and inspect the sync log.
//
//   2. Public B2B (under /api/v1/…) — uses the `tz_live_…` API key in the
//      Authorization header (`Bearer <apiKey>`). POS systems (iiko, 1С,
//      Poster, R-Keeper, custom backends) hit these to push their menu.
//
// Security:
//   - API key is generated cryptographically, returned to the user exactly
//     once (after that we keep only its SHA-256 hash).
//   - Webhook secret is similar: returned on first generation, then hashed.
//   - Every API request appends a row to ShopSyncEvent so the shop can see
//     what their integration sent (and we can debug).

const router = require('express').Router();
const crypto = require('crypto');
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const registry = require('../integrations/registry');
const cryptoBox = require('../lib/integration-crypto');

// ─── helpers ────────────────────────────────────────────────────────────────

function sha256(s) {
  return crypto.createHash('sha256').update(s, 'utf8').digest('hex');
}

function mintApiKey() {
  // tz_live_<24 url-safe chars>. Total length 32 → easy to copy/paste.
  const rand = crypto.randomBytes(18).toString('base64url'); // 24 chars
  return `tz_live_${rand}`;
}

function mintWebhookSecret() {
  return `whsec_${crypto.randomBytes(24).toString('base64url')}`;
}

async function assertShopManager(req, shopId) {
  if (!req.user) return false;
  const m = await prisma.shopMember.findUnique({
    where: { userId_shopId: { userId: req.user.id, shopId } },
  });
  return Boolean(m);
}

async function findUserShopId(req) {
  // Owner-facing endpoints operate on "your shop" — pick the first membership.
  // Reality: a manager works in one shop at a time; UI can pass an explicit
  // shopId later if we ever support multi-shop owners.
  // ShopMember has no createdAt — order by primary key for determinism.
  const m = await prisma.shopMember.findFirst({
    where: { userId: req.user.id },
    orderBy: { id: 'asc' },
  });
  return m?.shopId || null;
}

async function logEvent(shopId, kind, { ok, message, meta } = {}) {
  await prisma.shopSyncEvent.create({
    data: {
      shopId, kind,
      ok: ok ?? true,
      message: message ?? null,
      meta: meta ? JSON.stringify(meta) : null,
    },
  });
  // Cap log at 200 newest rows per shop.
  const total = await prisma.shopSyncEvent.count({ where: { shopId } });
  if (total > 200) {
    const cutoff = await prisma.shopSyncEvent.findMany({
      where: { shopId },
      orderBy: { createdAt: 'desc' },
      skip: 200,
      take: 1,
      select: { createdAt: true },
    });
    if (cutoff[0]) {
      await prisma.shopSyncEvent.deleteMany({
        where: { shopId, createdAt: { lt: cutoff[0].createdAt } },
      });
    }
  }
}

// Auth helper for the public B2B routes — accepts `Bearer tz_live_…`.
async function apiKeyMiddleware(req, res, next) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'missing_api_key' });
  }
  const key = header.substring(7).trim();
  if (!key.startsWith('tz_live_')) {
    return res.status(401).json({ error: 'invalid_api_key_format' });
  }
  const prefix = key.substring(0, 12);
  const hash = sha256(key);
  const shop = await prisma.shop.findFirst({
    where: { apiKeyPrefix: prefix, apiKeyHash: hash, isActive: true },
  });
  if (!shop) return res.status(401).json({ error: 'invalid_api_key' });
  req.shop = shop;
  next();
}

// ─── OWNER-FACING ───────────────────────────────────────────────────────────

// GET /api/shops/me/integration → returns current state (no secrets)
router.get('/me/integration', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }
    const shop = await prisma.shop.findUnique({ where: { id: shopId } });
    res.json({
      shopId,
      apiKeyPrefix: shop.apiKeyPrefix,            // e.g. "tz_live_aB3z"
      apiKeyCreatedAt: shop.apiKeyCreatedAt,
      hasApiKey: Boolean(shop.apiKeyHash),
      hasWebhook: Boolean(shop.webhookUrl),
      webhookUrl: shop.webhookUrl || null,
      webhookEvents: shop.webhookEvents || '*',
      lastSyncAt: shop.lastSyncAt,
      // Public endpoint roots the integrator should use:
      apiBase: `${req.protocol}://${req.get('host')}/api/v1`,
      docsUrl: '/docs/api', // static md page can be added later
    });
  } catch (err) { next(err); }
});

// POST /api/shops/me/integration/api-key/rotate
// Returns the plaintext key ONCE. Subsequent GETs only show the prefix.
router.post('/me/integration/api-key/rotate', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }

    const apiKey = mintApiKey();
    const prefix = apiKey.substring(0, 12);
    const hash = sha256(apiKey);

    await prisma.shop.update({
      where: { id: shopId },
      data: {
        apiKeyHash: hash,
        apiKeyPrefix: prefix,
        apiKeyCreatedAt: new Date(),
      },
    });
    await logEvent(shopId, 'credentials.rotated',
      { ok: true, message: 'API key rotated' });

    res.json({
      apiKey,              // shown once — UI must surface "Save this key now"
      apiKeyPrefix: prefix,
      apiKeyCreatedAt: new Date().toISOString(),
    });
  } catch (err) { next(err); }
});

// POST /api/shops/me/integration/webhook
// Body: { url: "https://…", events?: "*" | "order.created,order.completed" }
// Returns the secret ONCE.
router.post('/me/integration/webhook', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }

    const { url, events = '*' } = req.body || {};
    if (!url || typeof url !== 'string' || !/^https?:\/\//.test(url)) {
      return res.status(400).json({ error: 'invalid_url' });
    }

    const secret = mintWebhookSecret();
    await prisma.shop.update({
      where: { id: shopId },
      data: {
        webhookUrl: url,
        webhookSecret: sha256(secret),
        webhookEvents: String(events).slice(0, 200),
      },
    });
    await logEvent(shopId, 'webhook.configured', {
      ok: true, message: `webhook set: ${url}`, meta: { events },
    });

    res.json({
      webhookUrl: url,
      webhookSecret: secret,   // shown once
      webhookEvents: events,
    });
  } catch (err) { next(err); }
});

// DELETE /api/shops/me/integration/webhook — remove webhook
router.delete('/me/integration/webhook', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }
    await prisma.shop.update({
      where: { id: shopId },
      data: { webhookUrl: null, webhookSecret: null, webhookEvents: null },
    });
    await logEvent(shopId, 'webhook.removed', { ok: true, message: 'webhook removed' });
    res.json({ ok: true });
  } catch (err) { next(err); }
});

// GET /api/shops/me/integration/log?limit=50
router.get('/me/integration/log', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }
    const limit = Math.min(200, parseInt(req.query.limit, 10) || 50);
    const events = await prisma.shopSyncEvent.findMany({
      where: { shopId },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    res.json({ events });
  } catch (err) { next(err); }
});

// ─── PUBLIC B2B v1 ──────────────────────────────────────────────────────────

// GET /api/v1/me — auth ping for integrators ("does my key work?")
router.get('/v1/me', apiKeyMiddleware, async (req, res) => {
  res.json({
    shop: {
      id: req.shop.id,
      name: req.shop.name,
      vertical: req.shop.vertical,
      currency: req.shop.currency,
      isActive: req.shop.isActive,
    },
  });
});

// POST /api/v1/products/upsert
// Body: { items: [{ externalId, name, nameUz?, price, discountPrice?, unit,
//                   category, imageUrl?, stock?, isAvailable?, description?,
//                   ingredients? }, …] }
// Idempotent by (shopId, externalId). Pure insert/update — no delete.
router.post('/v1/products/upsert', apiKeyMiddleware, async (req, res, next) => {
  try {
    const items = Array.isArray(req.body?.items) ? req.body.items : [];
    if (items.length === 0) {
      return res.status(400).json({ error: 'items_required' });
    }
    if (items.length > 1000) {
      return res.status(400).json({ error: 'batch_too_large', max: 1000 });
    }

    const results = [];
    let inserted = 0, updated = 0, failed = 0;

    for (const raw of items) {
      try {
        const externalId = String(raw.externalId || '').trim();
        if (!externalId) {
          failed++;
          results.push({ externalId: null, ok: false, error: 'externalId_required' });
          continue;
        }
        const data = {
          name: String(raw.name || '').slice(0, 200).trim(),
          nameUz: String(raw.nameUz || raw.name || '').slice(0, 200).trim(),
          description: raw.description ? String(raw.description).slice(0, 2000) : null,
          ingredients: raw.ingredients ? String(raw.ingredients).slice(0, 1000) : null,
          price: Math.max(0, Number(raw.price) || 0),
          discountPrice: raw.discountPrice == null
            ? null
            : Math.max(0, Number(raw.discountPrice)),
          unit: String(raw.unit || 'шт').slice(0, 16),
          category: String(raw.category || 'grocery').slice(0, 32),
          imageUrl: String(raw.imageUrl || '').slice(0, 500),
          stock: Math.max(0, Math.floor(Number(raw.stock ?? 100))),
          isAvailable: raw.isAvailable !== false,
        };
        if (!data.name || !data.price) {
          failed++;
          results.push({ externalId, ok: false, error: 'name_or_price_missing' });
          continue;
        }
        const existing = await prisma.product.findUnique({
          where: { shopId_externalId: { shopId: req.shop.id, externalId } },
        });
        if (existing) {
          await prisma.product.update({
            where: { id: existing.id },
            data: { ...data, searchText: (data.name + ' ' + data.nameUz).toLowerCase() },
          });
          updated++;
          results.push({ externalId, ok: true, id: existing.id, action: 'updated' });
        } else {
          const created = await prisma.product.create({
            data: {
              shopId: req.shop.id,
              externalId,
              ...data,
              searchText: (data.name + ' ' + data.nameUz).toLowerCase(),
            },
          });
          inserted++;
          results.push({ externalId, ok: true, id: created.id, action: 'inserted' });
        }
      } catch (e) {
        failed++;
        results.push({ externalId: raw.externalId, ok: false, error: e.message });
      }
    }

    await prisma.shop.update({
      where: { id: req.shop.id },
      data: { lastSyncAt: new Date() },
    });

    await logEvent(req.shop.id, 'products.upsert', {
      ok: failed === 0,
      message: `${inserted} inserted, ${updated} updated, ${failed} failed`,
      meta: { inserted, updated, failed, total: items.length },
    });

    res.json({ inserted, updated, failed, total: items.length, results });
  } catch (err) {
    if (req.shop) {
      await logEvent(req.shop.id, 'products.upsert',
        { ok: false, message: err.message }).catch(() => {});
    }
    next(err);
  }
});

// POST /api/v1/products/delete  Body: { externalIds: ["sku-1","sku-2"] }
// Soft delete — flips isAvailable=false. We never hard-delete because that
// would break order history snapshots.
router.post('/v1/products/delete', apiKeyMiddleware, async (req, res, next) => {
  try {
    const ids = Array.isArray(req.body?.externalIds) ? req.body.externalIds : [];
    if (ids.length === 0) return res.status(400).json({ error: 'externalIds_required' });

    const r = await prisma.product.updateMany({
      where: { shopId: req.shop.id, externalId: { in: ids } },
      data: { isAvailable: false },
    });

    await logEvent(req.shop.id, 'products.delete', {
      ok: true,
      message: `${r.count}/${ids.length} marked unavailable`,
      meta: { count: r.count, requested: ids.length },
    });

    res.json({ disabled: r.count, requested: ids.length });
  } catch (err) {
    if (req.shop) {
      await logEvent(req.shop.id, 'products.delete',
        { ok: false, message: err.message }).catch(() => {});
    }
    next(err);
  }
});

// ─── PROVIDER CONNECTORS (Phase 14 wave 2) ──────────────────────────────────
//
// CRUD over ShopIntegration rows + test/sync actions. Sits alongside the
// existing "raw API key" surface so a shop can have both: a tz_live_… for
// their own devs AND one or more connected POS adapters at the same time.

// GET /api/shops/me/integrations/providers — registry of supported POS
router.get('/me/integrations/providers', authMiddleware, async (req, res) => {
  res.json({ providers: registry.listProviders() });
});

// GET /api/shops/me/integrations — list installed adapters
router.get('/me/integrations', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }
    const rows = await prisma.shopIntegration.findMany({
      where: { shopId },
      orderBy: { createdAt: 'asc' },
    });
    const integrations = rows.map((r) => ({
      id: r.id,
      provider: r.provider,
      providerLabel: registry.getAdapter(r.provider)?.label || r.provider,
      publicMeta: r.publicMeta ? JSON.parse(r.publicMeta) : {},
      syncMenu: r.syncMenu,
      syncStock: r.syncStock,
      syncOrders: r.syncOrders,
      lastSyncAt: r.lastSyncAt,
      lastSyncError: r.lastSyncError,
      lastTestedAt: r.lastTestedAt,
      lastTestOk: r.lastTestOk,
      isActive: r.isActive,
      createdAt: r.createdAt,
    }));
    res.json({ integrations });
  } catch (err) { next(err); }
});

// POST /api/shops/me/integrations — connect a new provider
//   Body: { provider: "custom_rest" | "iiko" | "poster", creds: {...} }
router.post('/me/integrations', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }

    const { provider, creds } = req.body || {};
    const adapter = registry.getAdapter(provider);
    if (!adapter) {
      return res.status(400).json({ error: 'unknown_provider' });
    }

    let sanitized;
    try {
      sanitized = registry.validateCreds(provider, creds);
    } catch (err) {
      return res.status(400).json({
        error: err.code || 'invalid_creds',
        field: err.field,
      });
    }

    // Run a connection test before persisting — fail-fast so the user knows
    // they typed something wrong while their fingers are still on the keys.
    const probe = await adapter.testConnection(sanitized);

    const publicMeta = registry.publicMetaFrom(provider, sanitized);
    const credsCipher = cryptoBox.encrypt(sanitized);

    const row = await prisma.shopIntegration.upsert({
      where: { shopId_provider: { shopId, provider } },
      create: {
        shopId, provider,
        credsCipher,
        publicMeta: JSON.stringify(publicMeta),
        lastTestedAt: new Date(),
        lastTestOk: probe.ok,
        lastSyncError: probe.ok ? null : probe.message,
      },
      update: {
        credsCipher,
        publicMeta: JSON.stringify(publicMeta),
        lastTestedAt: new Date(),
        lastTestOk: probe.ok,
        lastSyncError: probe.ok ? null : probe.message,
        isActive: true,
        // Re-connecting a provider re-enables the default sync flags. Without
        // this, a user who toggled off syncMenu and then re-entered credentials
        // would still be stuck "off" with no obvious way to flip it back on
        // beyond clicking the toggle in the active-integrations card.
        syncMenu: true,
        syncStock: true,
        syncOrders: true,
      },
    });

    await logEvent(shopId, 'integration.connected', {
      ok: probe.ok,
      message: `${provider}: ${probe.message}`,
      meta: { provider, integrationId: row.id },
    });

    res.json({
      integration: {
        id: row.id,
        provider: row.provider,
        providerLabel: adapter.label,
        publicMeta,
        lastTestOk: row.lastTestOk,
        lastTestedAt: row.lastTestedAt,
      },
      test: probe,
    });
  } catch (err) { next(err); }
});

// POST /api/shops/me/integrations/:id/test — re-run connection test
router.post('/me/integrations/:id/test', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }
    const row = await prisma.shopIntegration.findFirst({
      where: { id: req.params.id, shopId },
    });
    if (!row) return res.status(404).json({ error: 'not_found' });

    const adapter = registry.getAdapter(row.provider);
    if (!adapter) return res.status(400).json({ error: 'unknown_provider' });

    const creds = cryptoBox.decrypt(row.credsCipher);
    const probe = await adapter.testConnection(creds);

    await prisma.shopIntegration.update({
      where: { id: row.id },
      data: {
        lastTestedAt: new Date(),
        lastTestOk: probe.ok,
        lastSyncError: probe.ok ? null : probe.message,
      },
    });
    await logEvent(shopId, 'integration.test', {
      ok: probe.ok,
      message: `${row.provider}: ${probe.message}`,
      meta: { provider: row.provider },
    });

    res.json({ test: probe });
  } catch (err) { next(err); }
});

// POST /api/shops/me/integrations/:id/sync-now — trigger immediate menu pull
router.post('/me/integrations/:id/sync-now', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }
    const row = await prisma.shopIntegration.findFirst({
      where: { id: req.params.id, shopId },
    });
    if (!row) return res.status(404).json({ error: 'not_found' });
    if (!row.syncMenu) {
      return res.status(400).json({ error: 'menu_sync_disabled' });
    }

    const adapter = registry.getAdapter(row.provider);
    const creds = cryptoBox.decrypt(row.credsCipher);

    let result;
    try {
      result = await adapter.pullMenu(creds, shopId);
      await prisma.shopIntegration.update({
        where: { id: row.id },
        data: { lastSyncAt: new Date(), lastSyncError: null },
      });
      await logEvent(shopId, `${row.provider}.menu.synced`, {
        ok: true,
        message: result.message,
        meta: result,
      });
    } catch (err) {
      await prisma.shopIntegration.update({
        where: { id: row.id },
        data: { lastSyncError: err.message },
      });
      await logEvent(shopId, `${row.provider}.menu.sync_failed`, {
        ok: false, message: err.message,
      });
      return res.status(500).json({ error: err.message });
    }

    res.json({ result });
  } catch (err) { next(err); }
});

// PATCH /api/shops/me/integrations/:id — toggle syncMenu/syncStock/syncOrders
router.patch('/me/integrations/:id', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }
    const row = await prisma.shopIntegration.findFirst({
      where: { id: req.params.id, shopId },
    });
    if (!row) return res.status(404).json({ error: 'not_found' });

    const { syncMenu, syncStock, syncOrders, isActive } = req.body || {};
    const updated = await prisma.shopIntegration.update({
      where: { id: row.id },
      data: {
        ...(typeof syncMenu === 'boolean' && { syncMenu }),
        ...(typeof syncStock === 'boolean' && { syncStock }),
        ...(typeof syncOrders === 'boolean' && { syncOrders }),
        ...(typeof isActive === 'boolean' && { isActive }),
      },
    });
    res.json({
      integration: {
        id: updated.id,
        provider: updated.provider,
        syncMenu: updated.syncMenu,
        syncStock: updated.syncStock,
        syncOrders: updated.syncOrders,
        isActive: updated.isActive,
      },
    });
  } catch (err) { next(err); }
});

// DELETE /api/shops/me/integrations/:id — disconnect
router.delete('/me/integrations/:id', authMiddleware, async (req, res, next) => {
  try {
    const shopId = await findUserShopId(req);
    if (!shopId) return res.status(404).json({ error: 'no_shop' });
    if (!(await assertShopManager(req, shopId))) {
      return res.status(403).json({ error: 'not_a_member' });
    }
    const row = await prisma.shopIntegration.findFirst({
      where: { id: req.params.id, shopId },
    });
    if (!row) return res.status(404).json({ error: 'not_found' });

    await prisma.shopIntegration.delete({ where: { id: row.id } });
    await logEvent(shopId, 'integration.disconnected', {
      ok: true, message: row.provider,
    });

    res.json({ ok: true });
  } catch (err) { next(err); }
});

module.exports = router;
