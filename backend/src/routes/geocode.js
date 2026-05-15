// Server-side proxy to Yandex HTTP Geocoder.
//
// Why proxy: the Flutter web client could hit Yandex directly, but doing it
// server-side gives us
//   • a single place to swap providers (2GIS → Yandex → Google) without
//     touching the app,
//   • caching (LRU on the same query string for 24h),
//   • cost control (one place to add per-user rate limits later),
//   • the API key never has to ship with the front-end bundle.
//
// Environment:
//   YANDEX_MAPKIT_API_KEY — the MapKit / JS API / HTTP Geocoder key from
//                           https://developer.tech.yandex.ru
//
// Endpoints:
//   GET /api/geocode?q=Чиланзар 19      — forward geocode (address → coords)
//   GET /api/geocode/reverse?lat=&lng=  — reverse geocode (coords → address)
//   GET /api/geocode/suggest?q=…&lat&lng — autocomplete suggestions

const router = require('express').Router();

const KEY = process.env.YANDEX_MAPKIT_API_KEY || '';
const BASE = 'https://geocode-maps.yandex.ru/1.x/';

// Tiny in-process LRU. For prod-multi-instance, swap to Redis.
const CACHE_TTL_MS = 24 * 3600_000;
const CACHE_MAX = 1024;
const cache = new Map();

function cacheGet(key) {
  const hit = cache.get(key);
  if (!hit) return null;
  if (Date.now() - hit.at > CACHE_TTL_MS) {
    cache.delete(key);
    return null;
  }
  // LRU touch
  cache.delete(key);
  cache.set(key, hit);
  return hit.body;
}

function cacheSet(key, body) {
  if (cache.size >= CACHE_MAX) {
    // delete oldest
    const oldest = cache.keys().next().value;
    if (oldest) cache.delete(oldest);
  }
  cache.set(key, { at: Date.now(), body });
}

async function yandex(params) {
  if (!KEY) {
    throw Object.assign(new Error('yandex_not_configured'), { status: 503 });
  }
  const url = new URL(BASE);
  url.searchParams.set('apikey', KEY);
  url.searchParams.set('format', 'json');
  url.searchParams.set('lang', 'ru_RU');
  for (const [k, v] of Object.entries(params)) {
    if (v != null && v !== '') url.searchParams.set(k, v);
  }
  const cacheKey = url.search;
  const hit = cacheGet(cacheKey);
  if (hit) return hit;
  const r = await fetch(url.toString(), {
    signal: AbortSignal.timeout(8000),
  });
  if (!r.ok) {
    throw Object.assign(new Error(`yandex_${r.status}`), { status: 502 });
  }
  const j = await r.json();
  cacheSet(cacheKey, j);
  return j;
}

// Reshape Yandex's nested GeoObject into a flatter, friendlier object that
// the Flutter side actually wants.
function flattenObject(go) {
  const meta = go?.metaDataProperty?.GeocoderMetaData;
  const addr = meta?.Address;
  const components = addr?.Components || [];
  const point = go?.Point?.pos?.split(' ').map(Number) || [];
  return {
    name: go?.name || meta?.text || '',
    description: go?.description || addr?.formatted || '',
    kind: meta?.kind || null,         // "house" | "street" | "locality" | …
    precision: meta?.precision || null, // "exact" | "near" | …
    country: components.find((c) => c.kind === 'country')?.name || null,
    locality: components.find((c) => c.kind === 'locality')?.name || null,
    street: components.find((c) => c.kind === 'street')?.name || null,
    house: components.find((c) => c.kind === 'house')?.name || null,
    lat: point[1] ?? null,
    lng: point[0] ?? null,
    full: addr?.formatted || '',
  };
}

function pickObjects(body, limit = 5) {
  const feats = body?.response?.GeoObjectCollection?.featureMember || [];
  return feats.slice(0, limit).map((f) => flattenObject(f.GeoObject));
}

// ─── GET /api/geocode ───────────────────────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const q = String(req.query.q || '').trim();
    if (!q) return res.status(400).json({ error: 'q_required' });
    const body = await yandex({ geocode: q, results: 5 });
    res.json({ results: pickObjects(body, 5) });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

// ─── GET /api/geocode/reverse ───────────────────────────────────────────────
router.get('/reverse', async (req, res) => {
  try {
    const lat = Number(req.query.lat);
    const lng = Number(req.query.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return res.status(400).json({ error: 'lat_lng_required' });
    }
    // Note Yandex expects "lng lat", not "lat lng" — easy to fumble.
    const body = await yandex({ geocode: `${lng},${lat}`, kind: 'house', results: 1 });
    const arr = pickObjects(body, 1);
    res.json({ result: arr[0] || null });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

// ─── GET /api/geocode/suggest ───────────────────────────────────────────────
//
// Yandex doesn't expose a public suggest endpoint on the free HTTP tier
// (Search API is paid). For the buyer's address picker we get good-enough
// behaviour by treating the same /geocode forward call as a suggester —
// it returns up to 5 ranked matches. If we move to paid Search API later,
// only this handler changes; the front-end contract stays.
router.get('/suggest', async (req, res) => {
  try {
    const q = String(req.query.q || '').trim();
    if (q.length < 2) return res.json({ suggestions: [] });

    // Optional bias to the user's current location for better ranking.
    const lat = Number(req.query.lat);
    const lng = Number(req.query.lng);
    const params = { geocode: q, results: 8 };
    if (Number.isFinite(lat) && Number.isFinite(lng)) {
      // Yandex uses ll=lng,lat&spn=lng_span,lat_span&rspn=1 for biasing.
      params.ll = `${lng},${lat}`;
      params.spn = '0.4,0.4';
    }
    const body = await yandex(params);
    res.json({ suggestions: pickObjects(body, 8) });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

module.exports = router;
