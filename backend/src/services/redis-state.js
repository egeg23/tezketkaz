// Replacement for the legacy in-memory `state.js`. Survives restarts and is
// shareable across multiple API instances when REDIS_ENABLED=true. When Redis
// is disabled, falls back to per-process memory (suitable for single-instance
// dev only).

const redis = require('../lib/redis');

const ONLINE_TTL_S = 15 * 60;        // courier presence sticky for 15 min
const LOCATION_TTL_S = 10 * 60;      // last known coords valid for 10 min

const ONLINE_KEY = 'couriers:online';      // hash userId → { socketId, since }
const LOCATIONS_KEY = 'couriers:locations'; // hash userId → { lat, lng, ts }

async function setCourierOnline(userId, socketId) {
  await redis.hsetWithTtl(ONLINE_KEY, userId, { socketId, since: Date.now() }, ONLINE_TTL_S);
}

async function setCourierOffline(userId) {
  await redis.hdel(ONLINE_KEY, userId);
  await redis.hdel(LOCATIONS_KEY, userId);
}

async function setCourierLocation(userId, lat, lng) {
  if (lat == null || lng == null) return;
  await redis.hsetWithTtl(
    LOCATIONS_KEY,
    userId,
    { lat: Number(lat), lng: Number(lng), ts: Date.now() },
    LOCATION_TTL_S,
  );
}

async function getCourierLocation(userId) {
  return redis.hget(LOCATIONS_KEY, userId);
}

async function listOnlineCouriers() {
  const all = await redis.hgetAll(ONLINE_KEY);
  return Object.keys(all);
}

// Haversine in km
function distanceKm(a, b) {
  if (a == null || b == null) return Infinity;
  const toRad = (d) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const x = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

async function nearbyCourierIds(point, radiusKm = 5) {
  const online = await listOnlineCouriers();
  if (!point || point.lat == null || point.lng == null) return online;
  const locations = await redis.hgetAll(LOCATIONS_KEY);
  const ids = [];
  for (const userId of online) {
    const loc = locations[userId];
    if (!loc) continue;
    if (distanceKm(point, loc) <= radiusKm) ids.push(userId);
  }
  return ids;
}

module.exports = {
  setCourierOnline,
  setCourierOffline,
  setCourierLocation,
  getCourierLocation,
  listOnlineCouriers,
  nearbyCourierIds,
  distanceKm,
};
