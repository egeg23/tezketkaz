// Pure geometry helpers — no Prisma / IO. SQLite has no geo types so we do
// distance + point-in-polygon in JS. Polygons are arrays of [lat,lng] pairs.

const EARTH_RADIUS_KM = 6371;

function toRad(deg) {
  return (deg * Math.PI) / 180;
}

// Haversine great-circle distance between two lat/lng points, in kilometres.
function distanceKm(lat1, lng1, lat2, lng2) {
  if (
    !Number.isFinite(lat1) || !Number.isFinite(lng1) ||
    !Number.isFinite(lat2) || !Number.isFinite(lng2)
  ) {
    return NaN;
  }
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_KM * c;
}

// Ray-casting point-in-polygon. Polygon is an array of [lat,lng] pairs.
// Treats polygon as closed; the last vertex doesn't have to repeat the first.
// Returns false if the polygon has fewer than 3 distinct vertices or any
// coordinates are non-numeric.
function pointInPolygon(lat, lng, polygon) {
  if (!Array.isArray(polygon) || polygon.length < 3) return false;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;

  let inside = false;
  const n = polygon.length;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const pi = polygon[i];
    const pj = polygon[j];
    if (!Array.isArray(pi) || !Array.isArray(pj)) return false;
    const yi = pi[0]; // lat
    const xi = pi[1]; // lng
    const yj = pj[0];
    const xj = pj[1];
    if (
      !Number.isFinite(yi) || !Number.isFinite(xi) ||
      !Number.isFinite(yj) || !Number.isFinite(xj)
    ) {
      return false;
    }
    const intersects =
      ((yi > lat) !== (yj > lat)) &&
      (lng < ((xj - xi) * (lat - yi)) / ((yj - yi) || Number.EPSILON) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

// Simple driving-time estimate. 25 km/h reflects busy urban Tashkent traffic.
// Returns minutes, rounded to nearest integer; minimum 1 minute for any
// non-zero positive distance.
function eta_minutes(distanceKm, avgSpeedKmh = 25) {
  if (!Number.isFinite(distanceKm) || distanceKm < 0) return 0;
  if (!Number.isFinite(avgSpeedKmh) || avgSpeedKmh <= 0) return 0;
  const minutes = (distanceKm / avgSpeedKmh) * 60;
  return Math.max(distanceKm > 0 ? 1 : 0, Math.round(minutes));
}

module.exports = { distanceKm, pointInPolygon, eta_minutes };
