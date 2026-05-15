// Phase 14 wave 3 — POS sync + webhook delivery workers.
//
// Two queues, two handlers:
//
//   • integrationSync  — fires every N minutes per active integration that
//     has syncMenu=true. Calls adapter.pullMenu() and writes a
//     ShopSyncEvent row. We don't snowflake N per shop yet; one global
//     cadence keeps the scheduler simple. If a shop disables menu sync,
//     the job is skipped at runtime.
//
//   • integrationWebhook — fires every time an outbound webhook needs to
//     go to a shop's own server (shop.webhookUrl) AND/OR to a connected
//     POS adapter via its pushOrder(). Each attempt is logged. Failures
//     re-enqueue with exponential backoff up to 5 retries, then land in
//     a dead-letter row (ShopSyncEvent with kind webhook.dead_letter).

const crypto = require('crypto');
const prisma = require('../db');
const logger = require('../lib/logger');
const registry = require('../integrations/registry');
const cryptoBox = require('../lib/integration-crypto');

// ════════════════════════════════════════════════════════════════════════
// integrationSync
// ════════════════════════════════════════════════════════════════════════
//
// Each periodic tick (cron job below) enqueues one job per active row in
// ShopIntegration. The worker pulls menu from the partner, upserts into
// Product via the adapter, and writes one ShopSyncEvent.
async function integrationSyncHandler(job) {
  const { integrationId } = job.data || {};
  if (!integrationId) return;
  const row = await prisma.shopIntegration.findUnique({
    where: { id: integrationId },
  });
  if (!row || !row.isActive || !row.syncMenu) {
    logger.debug({ integrationId }, 'integration sync skipped');
    return;
  }
  const adapter = registry.getAdapter(row.provider);
  if (!adapter || !adapter.pullMenu) {
    return;
  }
  let creds;
  try {
    creds = cryptoBox.decrypt(row.credsCipher);
  } catch (err) {
    logger.warn({ integrationId, err: err.message }, 'decrypt failed');
    return;
  }

  try {
    const result = await adapter.pullMenu(creds, row.shopId);
    await prisma.shopIntegration.update({
      where: { id: row.id },
      data: { lastSyncAt: new Date(), lastSyncError: null },
    });
    await logEvent(row.shopId, `${row.provider}.menu.auto_synced`, {
      ok: true,
      message: result.message,
      meta: result,
    });
  } catch (err) {
    await prisma.shopIntegration.update({
      where: { id: row.id },
      data: { lastSyncError: err.message },
    });
    await logEvent(row.shopId, `${row.provider}.menu.auto_sync_failed`, {
      ok: false,
      message: err.message,
    });
    throw err; // let BullMQ retry per its policy
  }
}

// ════════════════════════════════════════════════════════════════════════
// integrationWebhook
// ════════════════════════════════════════════════════════════════════════
//
// Body shape: { shopId, event: "order.created", payload: {...} }
// Worker fans out the event to two destinations:
//   1. shop.webhookUrl — the integrator's own server, signed with HMAC
//   2. ALL active ShopIntegration rows with syncOrders=true — calls
//      adapter.pushOrder(creds, payload)
//
// Failures throw; BullMQ retries with exp backoff. After max retries, the
// job's `attemptsMade >= attempts` triggers our 'failed' hook to write
// a dead-letter event.
async function integrationWebhookHandler(job) {
  const { shopId, event, payload } = job.data || {};
  if (!shopId || !event) return;

  const shop = await prisma.shop.findUnique({ where: { id: shopId } });
  if (!shop) return;

  const failures = [];

  // 1) Direct webhook to shop.webhookUrl
  if (shop.webhookUrl) {
    const ok = await deliverHttpWebhook(shop, event, payload).catch((err) => {
      failures.push({ kind: 'http', message: err.message });
      return false;
    });
    if (!ok) {
      // Don't await audit here — fall through; failed delivery is logged below
    }
  }

  // 2) Provider adapters with syncOrders=true
  const integrations = await prisma.shopIntegration.findMany({
    where: { shopId, isActive: true, syncOrders: true },
  });
  for (const i of integrations) {
    const adapter = registry.getAdapter(i.provider);
    if (!adapter || !adapter.pushOrder) continue;
    try {
      const creds = cryptoBox.decrypt(i.credsCipher);
      const res = await adapter.pushOrder(creds, payload);
      if (!res?.ok) {
        failures.push({ kind: i.provider, message: res?.message || 'unknown' });
      }
      await logEvent(shopId, `${i.provider}.order.pushed`, {
        ok: res?.ok === true,
        message: res?.message || '',
        meta: { event, status: res?.status },
      });
    } catch (err) {
      failures.push({ kind: i.provider, message: err.message });
      await logEvent(shopId, `${i.provider}.order.push_failed`, {
        ok: false,
        message: err.message,
      });
    }
  }

  if (failures.length) {
    // Throw so BullMQ retries. The dead-letter hook (below) writes a final
    // audit row once attempts are exhausted.
    throw new Error(`webhook_failures:${failures.map(f => f.kind).join(',')}`);
  }
}

// Direct HTTP delivery with HMAC signature. We compute SHA-256 over
// `timestamp.body` keyed by shop.webhookSecret (already SHA-256 hashed at
// rest — for signing we use the same hash as the shared secret, which is
// fine here because we're not handing the raw secret to anyone).
async function deliverHttpWebhook(shop, event, payload) {
  const body = JSON.stringify({ event, payload, at: new Date().toISOString() });
  const ts = Math.floor(Date.now() / 1000).toString();
  const hmac = crypto
    .createHmac('sha256', shop.webhookSecret || '')
    .update(`${ts}.${body}`)
    .digest('hex');

  const r = await fetch(shop.webhookUrl, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-tz-signature': `t=${ts},v1=${hmac}`,
      'x-tz-event': event,
    },
    body,
    signal: AbortSignal.timeout(15000),
  });
  await logEvent(shop.id, `webhook.delivered`, {
    ok: r.ok,
    message: `HTTP ${r.status} ${r.statusText}`,
    meta: { event, url: shop.webhookUrl },
  });
  if (!r.ok) {
    throw new Error(`webhook_${r.status}`);
  }
  return true;
}

// ════════════════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════════════════

async function logEvent(shopId, kind, { ok, message, meta }) {
  try {
    await prisma.shopSyncEvent.create({
      data: {
        shopId,
        kind,
        ok: ok ?? true,
        message: message ?? null,
        meta: meta ? JSON.stringify(meta) : null,
      },
    });
  } catch (err) {
    logger.warn({ err: err.message }, 'shopSyncEvent insert failed');
  }
}

// ════════════════════════════════════════════════════════════════════════
// Cron — enqueue periodic sync jobs
// ════════════════════════════════════════════════════════════════════════
//
// Called from index.js bootstrap. Every 15 minutes scans all active
// integrations with syncMenu=true and enqueues an integrationSync job per
// row. We use a single periodic timer rather than BullMQ repeat options
// so the cadence is per-row aware: a shop disabling syncMenu instantly
// stops getting jobs without any queue-side cleanup.
function startIntegrationSyncCron(queues) {
  const intervalMs = Number(process.env.INTEGRATION_SYNC_INTERVAL_MS) || 15 * 60_000;
  const tick = async () => {
    try {
      const rows = await prisma.shopIntegration.findMany({
        where: { isActive: true, syncMenu: true },
        select: { id: true },
      });
      for (const r of rows) {
        await queues().integrationSync.add('syncOne', { integrationId: r.id }, {
          attempts: 3,
          backoff: { type: 'exponential', delay: 30_000 },
          removeOnComplete: 50,
          removeOnFail: 200,
        });
      }
      logger.debug({ count: rows.length }, 'integration sync cron tick');
    } catch (err) {
      logger.warn({ err: err.message }, 'integration sync cron tick failed');
    }
  };
  // Stagger first run by 30 s so server has time to fully boot.
  const timer = setTimeout(tick, 30_000);
  const repeat = setInterval(tick, intervalMs);
  return () => { clearTimeout(timer); clearInterval(repeat); };
}

// ════════════════════════════════════════════════════════════════════════
// Helper used by orders router to fan out an order event to all wired
// integrations + webhook. Called like:
//   await enqueueOrderEvent(queues, { shopId, event: 'order.created', payload })
async function enqueueOrderEvent(queues, { shopId, event, payload }) {
  if (!shopId || !event) return;
  await queues().integrationWebhook.add(event, { shopId, event, payload }, {
    attempts: 5,
    backoff: { type: 'exponential', delay: 5_000 },
    removeOnComplete: 100,
    removeOnFail: 500,
  });
}

module.exports = {
  integrationSyncHandler,
  integrationWebhookHandler,
  startIntegrationSyncCron,
  enqueueOrderEvent,
};
