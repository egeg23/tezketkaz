// Delivery pricing service.
//
// Combines: shop location, polygon-based delivery zones (with optional
// per-zone fee/freeKm/minOrder overrides), shop-level overrides, env defaults,
// and time-bounded PricingRule surge factors.
//
// Pure read of DB state — never mutates. Returns null/zoneId:null when the
// destination is outside every active zone for the shop.

const { distanceKm, pointInPolygon, eta_minutes } = require('../lib/geo');

// Env defaults are read at call time so tests can override via process.env.
function envDefaults() {
  return {
    baseFee: Number(process.env.DELIVERY_BASE_FEE ?? 12000),
    perKmFee: Number(process.env.DELIVERY_PER_KM ?? 2000),
    freeKm: Number(process.env.DELIVERY_FREE_KM ?? 2),
  };
}

function parsePolygon(raw) {
  if (!raw) return null;
  if (Array.isArray(raw)) return raw;
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

// Picks the zone whose polygon contains the destination, preferring the
// lowest sortOrder when multiple match. Inactive zones are skipped.
function pickZone(zones, lat, lng) {
  let best = null;
  for (const z of zones) {
    if (!z.isActive) continue;
    const poly = parsePolygon(z.polygon);
    if (!poly) continue;
    if (!pointInPolygon(lat, lng, poly)) continue;
    if (best === null || (z.sortOrder ?? 0) < (best.sortOrder ?? 0)) {
      best = z;
    }
  }
  return best;
}

// Fetch the *highest* surge factor among active rules matching the shop's
// vertical (or global rules with vertical=null) at `now`. zoneId-scoped rules
// match only if `zoneId` argument matches.
async function pickSurgeRule(prisma, { vertical, zoneId, now = new Date() }) {
  const rules = await prisma.pricingRule.findMany({
    where: {
      isActive: true,
      validFrom: { lte: now },
      validUntil: { gte: now },
      OR: [
        { vertical },
        { vertical: null },
      ],
    },
  });
  let best = null;
  for (const r of rules) {
    if (r.zoneId && r.zoneId !== zoneId) continue;
    if (best === null || r.surgeFactor > best.surgeFactor) best = r;
  }
  return best;
}

// Compute deliveryFee, ETA, surge, zone for a destination served by `shopId`.
// Returns:
//   { zoneId, distanceKm, baseFee, perKmFee, freeKm, surgeFactor,
//     surgeReason, eta, deliveryFee, minOrder, outOfZone,
//     membershipDiscount, freeDeliveryReason }
// `outOfZone:true` means caller should reject the order — zoneId will be null.
//
// Phase 7.2 — when `userId` is provided and that user has an active membership
// the deliveryFee is reduced (or zeroed) accordingly:
//   • tier='pro'  → deliveryFee=0, freeDeliveryReason='membership_pro'
//   • tier='plus' → deliveryFee halved, freeDeliveryReason='membership_plus_half'
//
// Phase 7 — `country` is accepted for forward-compat (per-country surge / fee
// rules) but currently doesn't change the math; the shop's own currency drives
// the units. Tax (VAT) is applied separately in services/tax.js.
async function computeDelivery(prisma, { shopId, destLat, destLng, userId, country } = {}) {
  void country;
  if (!shopId) throw Object.assign(new Error('shopId required'), { status: 400 });
  if (!Number.isFinite(destLat) || !Number.isFinite(destLng)) {
    throw Object.assign(new Error('destLat/destLng required'), { status: 400 });
  }

  const shop = await prisma.shop.findUnique({ where: { id: shopId } });
  if (!shop) throw Object.assign(new Error('Shop not found'), { status: 404 });

  const zones = await prisma.deliveryZone.findMany({
    where: { shopId, isActive: true },
    orderBy: { sortOrder: 'asc' },
  });

  const zone = pickZone(zones, destLat, destLng);
  const defaults = envDefaults();

  const dKm = (shop.lat != null && shop.lng != null)
    ? distanceKm(shop.lat, shop.lng, destLat, destLng)
    : 0;

  if (!zone) {
    return {
      zoneId: null,
      distanceKm: Number.isFinite(dKm) ? Number(dKm.toFixed(3)) : 0,
      baseFee: defaults.baseFee,
      perKmFee: defaults.perKmFee,
      freeKm: defaults.freeKm,
      surgeFactor: 1.0,
      surgeReason: null,
      eta: 0,
      deliveryFee: 0,
      minOrder: shop.minOrderAmount ?? 0,
      outOfZone: true,
    };
  }

  // Resolve effective fee parameters: zone → shop → env default.
  const baseFee = zone.baseFee ?? shop.deliveryBaseFee ?? defaults.baseFee;
  const perKmFee = zone.perKmFee ?? shop.deliveryPerKm ?? defaults.perKmFee;
  const freeKm = zone.freeKm ?? shop.freeDeliveryKm ?? defaults.freeKm;
  const minOrder = Math.max(zone.minOrder || 0, shop.minOrderAmount || 0, 0);

  // Surge lookup.
  const rule = await pickSurgeRule(prisma, {
    vertical: shop.vertical,
    zoneId: zone.id,
  });
  const surgeFactor = rule?.surgeFactor ?? 1.0;
  const surgeReason = rule?.reason ?? null;

  const billableKm = Math.max(0, dKm - freeKm);
  const rawFee = baseFee + billableKm * perKmFee;
  let deliveryFee = Math.round(rawFee * surgeFactor);

  let eta = eta_minutes(dKm) + 15; // 15-min prep buffer
  if (shop.vertical === 'restaurant') eta += 5;

  // Phase 7.2 — apply membership perk on top of the surge-adjusted fee.
  let membershipDiscount = 0;
  let freeDeliveryReason = null;
  if (userId) {
    try {
      const membership = await prisma.membership.findUnique({ where: { userId } });
      if (
        membership &&
        membership.status === 'active' &&
        membership.currentPeriodEnd &&
        membership.currentPeriodEnd.getTime() > Date.now()
      ) {
        if (membership.tier === 'pro') {
          membershipDiscount = deliveryFee;
          deliveryFee = 0;
          freeDeliveryReason = 'membership_pro';
        } else if (membership.tier === 'plus') {
          const halved = Math.round(deliveryFee / 2);
          membershipDiscount = deliveryFee - halved;
          deliveryFee = halved;
          freeDeliveryReason = 'membership_plus_half';
        }
      }
    } catch {
      // Membership lookup must never break checkout.
    }
  }

  return {
    zoneId: zone.id,
    distanceKm: Number(dKm.toFixed(3)),
    baseFee,
    perKmFee,
    freeKm,
    surgeFactor,
    surgeReason,
    eta,
    deliveryFee,
    minOrder,
    outOfZone: false,
    membershipDiscount,
    freeDeliveryReason,
  };
}

module.exports = { computeDelivery };
