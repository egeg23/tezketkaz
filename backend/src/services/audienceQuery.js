// Phase 10.3 — push notification campaign audience compiler.
//
// Translates a saved JSON spec into a Prisma `where` clause for User.findMany.
// Supported keys:
//   country, locale, isCourier, isShop      → direct User columns
//   hasOrders                               → Order relation (exists / none)
//   lastOrderWithinDays                     → most-recent Order in window
//   noOrdersInDays                          → no Orders in window
//   vertical                                → has any Order with shop.vertical=X
//   cityName                                → best-effort substring match against
//                                             address fullAddress / order
//                                             deliveryAddress.

function parseSpec(spec) {
  if (!spec) return {};
  if (typeof spec === 'string') {
    try { return JSON.parse(spec) || {}; } catch { return {}; }
  }
  if (typeof spec === 'object') return spec;
  return {};
}

function compile(rawSpec) {
  const spec = parseSpec(rawSpec);
  const where = {};

  if (spec.country) where.country = String(spec.country);
  if (spec.locale)  where.locale  = String(spec.locale);

  if (typeof spec.isCourier === 'boolean') where.isCourier = spec.isCourier;
  if (typeof spec.isShop === 'boolean')    where.isShop    = spec.isShop;

  // Always exclude soft-deleted users from campaigns.
  where.deletedAt = null;

  // Build up `some` and `none` predicates for `buyerOrders` separately so a
  // later-evaluated branch can't overwrite an earlier one (e.g.,
  // lastOrderWithinDays + vertical previously dropped the date constraint).
  // Each branch merges into the local `someParts`/`nonePart` and we assemble
  // `where.buyerOrders` once at the end.
  const someParts = [];
  let nonePart = null;

  // hasOrders=true   → at least one Order. hasOrders=false → no orders.
  if (spec.hasOrders === true) {
    someParts.push({});
  } else if (spec.hasOrders === false) {
    nonePart = {};
  }

  // lastOrderWithinDays=N — at least one order created within N days.
  if (Number.isFinite(Number(spec.lastOrderWithinDays))) {
    const days = Number(spec.lastOrderWithinDays);
    if (days > 0) {
      const cutoff = new Date(Date.now() - days * 86400 * 1000);
      someParts.push({ createdAt: { gte: cutoff } });
    }
  }

  // noOrdersInDays=N — no order in last N days.
  if (Number.isFinite(Number(spec.noOrdersInDays))) {
    const days = Number(spec.noOrdersInDays);
    if (days > 0) {
      const cutoff = new Date(Date.now() - days * 86400 * 1000);
      nonePart = { createdAt: { gte: cutoff } };
    }
  }

  // vertical filter — any order in shop with vertical=X.
  if (spec.vertical) {
    someParts.push({ shop: { vertical: String(spec.vertical) } });
  }

  if (someParts.length || nonePart !== null) {
    where.buyerOrders = {};
    if (someParts.length === 1) {
      where.buyerOrders.some = someParts[0];
    } else if (someParts.length > 1) {
      // Multi-`some` predicates require at least one matching Order PER
      // predicate. Merge into a single object that ANDs the conditions so
      // the same row must satisfy all of them.
      where.buyerOrders.some = Object.assign({}, ...someParts);
    }
    if (nonePart !== null) where.buyerOrders.none = nonePart;
  }

  // City filter — best-effort substring against addresses.fullAddress or
  // any past order's deliveryAddress.
  if (spec.cityName) {
    const needle = String(spec.cityName);
    where.OR = [
      { addresses: { some: { fullAddress: { contains: needle } } } },
      { buyerOrders: { some: { deliveryAddress: { contains: needle } } } },
    ];
  }

  return where;
}

async function resolveAudience(prisma, spec, opts = {}) {
  const limit = Math.max(1, Math.min(opts.limit || 100000, 200000));
  const where = compile(spec);
  const users = await prisma.user.findMany({
    where,
    select: {
      id: true,
      locale: true,
      country: true,
      notificationPrefs: true,
    },
    take: limit,
  });
  return users;
}

async function countAudience(prisma, spec) {
  const where = compile(spec);
  return prisma.user.count({ where });
}

module.exports = {
  compile,
  parseSpec,
  resolveAudience,
  countAudience,
};
