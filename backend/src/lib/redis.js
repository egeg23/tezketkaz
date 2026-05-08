// Redis client with graceful degradation: when REDIS_ENABLED=false, all helpers
// fall back to safe in-memory equivalents. Production MUST enable Redis to scale
// sockets and JWT-blacklist across multiple instances.

const Redis = require('ioredis');
const env = require('../config/env');
const logger = require('./logger');

let pub = null;
let sub = null;

function getRedis() {
  if (!env.redisEnabled) return null;
  if (!pub) {
    pub = new Redis(env.REDIS_URL, {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
      lazyConnect: false,
    });
    pub.on('error', (e) => logger.error({ err: e }, 'redis pub error'));
    pub.on('connect', () => logger.info('redis pub connected'));
  }
  return pub;
}

function getRedisSub() {
  if (!env.redisEnabled) return null;
  if (!sub) {
    sub = new Redis(env.REDIS_URL, { maxRetriesPerRequest: null });
    sub.on('error', (e) => logger.error({ err: e }, 'redis sub error'));
  }
  return sub;
}

// ─── In-memory fallback (single-process) ─────────────────────────────────────
const memStore = new Map();      // key → value
const memExpiry = new Map();     // key → expiresAtMs

function memCleanup(key) {
  const e = memExpiry.get(key);
  if (e && e <= Date.now()) {
    memStore.delete(key);
    memExpiry.delete(key);
    return true;
  }
  return false;
}

// ─── Public API (Redis with fallback) ────────────────────────────────────────

async function setEx(key, value, ttlSeconds) {
  const r = getRedis();
  if (r) {
    await r.set(key, value, 'EX', ttlSeconds);
    return;
  }
  memStore.set(key, value);
  memExpiry.set(key, Date.now() + ttlSeconds * 1000);
}

async function get(key) {
  const r = getRedis();
  if (r) return r.get(key);
  if (memCleanup(key)) return null;
  return memStore.get(key) ?? null;
}

async function del(key) {
  const r = getRedis();
  if (r) {
    await r.del(key);
    return;
  }
  memStore.delete(key);
  memExpiry.delete(key);
}

async function exists(key) {
  return (await get(key)) !== null;
}

// Hash-set per-courier location (single-source structure for fallback / Redis)
async function hsetWithTtl(key, field, value, ttlSeconds) {
  const r = getRedis();
  if (r) {
    await r.hset(key, field, JSON.stringify(value));
    await r.expire(key, ttlSeconds);
    return;
  }
  let bucket = memStore.get(key);
  if (!bucket || typeof bucket !== 'object') {
    bucket = {};
    memStore.set(key, bucket);
  }
  bucket[field] = { value, expiresAt: Date.now() + ttlSeconds * 1000 };
}

async function hget(key, field) {
  const r = getRedis();
  if (r) {
    const raw = await r.hget(key, field);
    return raw ? JSON.parse(raw) : null;
  }
  const bucket = memStore.get(key);
  if (!bucket) return null;
  const entry = bucket[field];
  if (!entry) return null;
  if (entry.expiresAt && entry.expiresAt <= Date.now()) {
    delete bucket[field];
    return null;
  }
  return entry.value;
}

async function hdel(key, field) {
  const r = getRedis();
  if (r) {
    await r.hdel(key, field);
    return;
  }
  const bucket = memStore.get(key);
  if (bucket) delete bucket[field];
}

async function hgetAll(key) {
  const r = getRedis();
  if (r) {
    const raw = await r.hgetall(key);
    const out = {};
    for (const [k, v] of Object.entries(raw || {})) {
      try { out[k] = JSON.parse(v); } catch { out[k] = v; }
    }
    return out;
  }
  const bucket = memStore.get(key) || {};
  const now = Date.now();
  const out = {};
  for (const [k, entry] of Object.entries(bucket)) {
    if (entry.expiresAt && entry.expiresAt <= now) continue;
    out[k] = entry.value;
  }
  return out;
}

// ─── JWT blacklist helpers ───────────────────────────────────────────────────

async function blacklistJti(jti, ttlSeconds) {
  await setEx(`jwt:blacklist:${jti}`, '1', Math.max(1, ttlSeconds));
}

async function isJtiBlacklisted(jti) {
  return exists(`jwt:blacklist:${jti}`);
}

// ─── Rate-limit helpers (custom keyed flows like OTP) ────────────────────────

async function incrWithTtl(key, ttlSeconds) {
  const r = getRedis();
  if (r) {
    const v = await r.incr(key);
    if (v === 1) await r.expire(key, ttlSeconds);
    return v;
  }
  if (memCleanup(key)) {
    memStore.set(key, 1);
    memExpiry.set(key, Date.now() + ttlSeconds * 1000);
    return 1;
  }
  const cur = (memStore.get(key) || 0) + 1;
  memStore.set(key, cur);
  if (cur === 1) memExpiry.set(key, Date.now() + ttlSeconds * 1000);
  return cur;
}

async function close() {
  if (pub) { await pub.quit().catch(() => {}); pub = null; }
  if (sub) { await sub.quit().catch(() => {}); sub = null; }
}

module.exports = {
  getRedis,
  getRedisSub,
  setEx, get, del, exists,
  hsetWithTtl, hget, hdel, hgetAll,
  blacklistJti, isJtiBlacklisted,
  incrWithTtl,
  close,
};
