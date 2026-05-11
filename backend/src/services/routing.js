// Real driving-distance + ETA via Yandex Routing API, with safe fallback.
//
// Currently we use straight-line haversine + a 25 km/h heuristic everywhere.
// In production we want road-aware ETAs (one-way streets, traffic, river
// crossings, etc.). This wrapper calls Yandex Routing when YANDEX_ROUTING_KEY
// is configured, otherwise it falls back to the pure-JS estimator from
// src/lib/geo so dev / test / fork-CI continue to work.
//
// The cache is in-memory and per-process; it dedupes repeat calls within the
// same minute (e.g. /api/orders/estimate retries) so we don't burn quota.

const env = require('../config/env');
const logger = require('../lib/logger');
const geo = require('../lib/geo');

const ENDPOINT = 'https://api.routing.yandex.net/v2/route';

// Key by rounded (origin, dest) tuple at 5-decimal precision (~1m), so
// effectively-identical points reuse the cached result.
const _cache = new Map();
const CACHE_TTL_MS = 60 * 1000;
// Bound the cache so high-cardinality (origin,dest) traffic can't grow it
// without limit. Map.keys() preserves insertion order so deleting the first
// key drops the oldest entry — cheap LRU-ish eviction.
const CACHE_MAX_ENTRIES = 5000;

function _cacheSet(key, value) {
  if (_cache.size >= CACHE_MAX_ENTRIES) {
    const oldest = _cache.keys().next().value;
    if (oldest !== undefined) _cache.delete(oldest);
  }
  _cache.set(key, { value, fetchedAt: Date.now() });
}

function _key(lat1, lng1, lat2, lng2) {
  const r = (n) => Math.round(n * 1e5) / 1e5;
  return `${r(lat1)},${r(lng1)}->${r(lat2)},${r(lng2)}`;
}

// Exposed for tests that need to assert cache miss/hit behaviour.
function _clearCache() {
  _cache.clear();
}

// Returns { distanceKm, etaMinutes, source: 'yandex'|'fallback' }.
// Falls back to haversine + eta_minutes when key missing or API fails.
async function route(origin, destination, opts = {}) {
  const fb = () => {
    const dKm = geo.distanceKm(origin.lat, origin.lng, destination.lat, destination.lng);
    return {
      distanceKm: Number.isFinite(dKm) ? dKm : 0,
      etaMinutes: geo.eta_minutes(
        Number.isFinite(dKm) ? dKm : 0,
        opts.avgSpeedKmh,
      ),
      source: 'fallback',
    };
  };
  if (!env.YANDEX_ROUTING_KEY) return fb();

  const k = _key(origin.lat, origin.lng, destination.lat, destination.lng);
  const cached = _cache.get(k);
  if (cached && cached.fetchedAt + CACHE_TTL_MS > Date.now()) {
    return { ...cached.value, source: 'yandex' };
  }

  try {
    const url = `${ENDPOINT}?apikey=${env.YANDEX_ROUTING_KEY}` +
      `&waypoints=${origin.lat},${origin.lng}|${destination.lat},${destination.lng}` +
      `&mode=driving`;
    const res = await fetch(url, { signal: AbortSignal.timeout(3000) });
    if (!res.ok) throw new Error(`Yandex Routing HTTP ${res.status}`);
    const body = await res.json();
    const distance = body?.route?.distance?.value; // meters
    const duration = body?.route?.duration?.value; // seconds
    if (!Number.isFinite(distance) || !Number.isFinite(duration)) {
      throw new Error('Yandex Routing response missing distance/duration');
    }
    const value = {
      distanceKm: distance / 1000,
      etaMinutes: Math.ceil(duration / 60),
    };
    _cacheSet(k, value);
    return { ...value, source: 'yandex' };
  } catch (err) {
    logger.warn({ err: err.message }, 'Yandex Routing failed, falling back to haversine');
    return fb();
  }
}

module.exports = { route, _clearCache };
