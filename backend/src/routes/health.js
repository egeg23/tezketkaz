// Liveness / readiness / version endpoints.
// Mount BEFORE rate limiters and auth so health probes never get 429'd.
//
//   GET /health   — liveness (always 200 if process is up)
//   GET /ready    — readiness (DB + Redis check, 503 on degraded)
//   GET /version  — build metadata for sanity checks

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

router.get('/version', (req, res) => {
  res.json({
    commit: process.env.GIT_COMMIT || 'dev',
    version: pkg.version || '0.0.0',
    startedAt,
  });
});

module.exports = router;
