// Liveness / readiness / version endpoints.
// Mount BEFORE rate limiters and auth so health probes never get 429'd.
//
//   GET /health   — liveness (always 200 if process is up)
//   GET /healthz  — operator-friendly aggregated check (DB + Redis + queues)
//   GET /ready    — readiness (DB + Redis check, 503 on degraded)
//   GET /version  — build metadata for sanity checks
//
// `/healthz` is documented in `docs/runbooks/monitoring-setup.md` and is the
// endpoint UptimeRobot / BetterUptime should poll. Returns 200 when all
// subsystems are healthy, 503 otherwise. Format is stable — alerting rules
// downstream parse `status` and the per-subsystem fields.

const router = require('express').Router();
const path = require('path');

const redisLib = require('../lib/redis');

let pkg = { version: '0.0.0' };
try {
  // eslint-disable-next-line global-require
  pkg = require(path.join(__dirname, '..', '..', 'package.json'));
} catch { /* noop — fallback above */ }

const startedAt = new Date().toISOString();

router.get('/health', (req, res) => {
  res.json({ ok: true, ts: Date.now() });
});

// Resolve a promise with a timeout to avoid hanging readiness probes when DB
// or Redis is wedged.
function withTimeout(promise, ms, label) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`${label} timeout after ${ms}ms`)), ms);
    promise.then(
      (v) => { clearTimeout(t); resolve(v); },
      (err) => { clearTimeout(t); reject(err); },
    );
  });
}

router.get('/ready', async (req, res) => {
  const out = { ok: true, db: 'unknown', redis: 'disabled' };

  // ─── Postgres / SQLite ────────────────────────────────────────────────────
  try {
    // eslint-disable-next-line global-require
    const prisma = require('../db');
    await withTimeout(prisma.$queryRaw`SELECT 1`, 2000, 'db');
    out.db = 'ok';
  } catch (err) {
    out.ok = false;
    out.db = `error: ${err.message}`;
  }

  // ─── Redis (optional) ─────────────────────────────────────────────────────
  try {
    const r = redisLib.getRedis();
    if (!r) {
      out.redis = 'disabled';
    } else {
      await withTimeout(r.ping(), 2000, 'redis');
      out.redis = 'ok';
    }
  } catch (err) {
    out.ok = false;
    out.redis = `error: ${err.message}`;
  }

  res.status(out.ok ? 200 : 503).json(out);
});

// `/healthz` — operator-facing aggregated health. Same checks as `/ready`
// plus a queues subsystem indicator. Stable response shape:
//   { status: 'ok'|'degraded', db, redis, queues }
// 200 OK when status === 'ok', 503 otherwise. Safe to poll every 5 min from
// UptimeRobot / BetterUptime.
router.get('/healthz', async (req, res) => {
  const out = { status: 'ok', db: 'unknown', redis: 'disabled', queues: 'disabled' };

  // ─── Postgres ─────────────────────────────────────────────────────────────
  try {
    // eslint-disable-next-line global-require
    const prisma = require('../db');
    await withTimeout(prisma.$queryRaw`SELECT 1`, 2000, 'db');
    out.db = 'connected';
  } catch (err) {
    out.status = 'degraded';
    out.db = `error: ${err.message}`;
  }

  // ─── Redis (optional in dev/test) ─────────────────────────────────────────
  try {
    const r = redisLib.getRedis();
    if (!r) {
      out.redis = 'disabled';
    } else {
      await withTimeout(r.ping(), 2000, 'redis');
      out.redis = 'connected';
    }
  } catch (err) {
    out.status = 'degraded';
    out.redis = `error: ${err.message}`;
  }

  // ─── BullMQ queues (best-effort — `isEnabled` mirrors Redis state) ────────
  try {
    // eslint-disable-next-line global-require
    const queuesLib = require('../lib/queues');
    out.queues = queuesLib.isEnabled && queuesLib.isEnabled() ? 'running' : 'disabled';
  } catch (err) {
    // Don't flip the whole healthcheck to degraded just because the queues
    // module failed to load — log it and report as 'unknown'. DB + Redis are
    // the load-bearing dependencies.
    out.queues = `error: ${err.message}`;
  }

  res.status(out.status === 'ok' ? 200 : 503).json(out);
});

router.get('/version', (req, res) => {
  res.json({
    commit: process.env.GIT_COMMIT || 'dev',
    version: pkg.version || '0.0.0',
    startedAt,
  });
});

module.exports = router;
