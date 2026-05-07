// In-memory presence + last known location for online couriers.
// (Lost on restart — for production move to Redis.)

const courierLocations = new Map(); // userId -> { lat, lng, ts }
const courierSockets = new Map();   // userId -> socketId

function setCourierLocation(userId, lat, lng) {
  courierLocations.set(userId, { lat: Number(lat), lng: Number(lng), ts: Date.now() });
}

function getCourierLocation(userId) {
  return courierLocations.get(userId);
}

function setCourierOnline(userId, socketId) {
  courierSockets.set(userId, socketId);
}

function setCourierOffline(userId) {
  courierSockets.delete(userId);
  courierLocations.delete(userId);
}

function listOnlineCouriers() {
  return Array.from(courierSockets.keys());
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

/** Return list of courier user ids whose last location is within radiusKm of point. */
function nearbyCourierIds(point, radiusKm = 5) {
  if (!point || point.lat == null || point.lng == null) {
    // No origin coords — fall back to all online couriers
    return listOnlineCouriers();
  }
  const ids = [];
  for (const [userId, loc] of courierLocations.entries()) {
    if (distanceKm(point, loc) <= radiusKm) ids.push(userId);
  }
  return ids;
}

module.exports = {
  setCourierLocation,
  getCourierLocation,
  setCourierOnline,
  setCourierOffline,
  listOnlineCouriers,
  distanceKm,
  nearbyCourierIds,
};
