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

  // hasOrders=true   → at least one Order. hasOrders=false → no orders.
  if (spec.hasOrders === true) {
    where.buyerOrders = { some: {} };
  } else if (spec.hasOrders === false) {
    where.buyerOrders = { none: {} };
  }

  // lastOrderWithinDays=N — at least one order created within N days.
  if (Number.isFinite(Number(spec.lastOrderWithinDays))) {
    const days = Number(spec.lastOrderWithinDays);
    if (days > 0) {
      const cutoff = new Date(Date.now() - days * 86400 * 1000);
      where.buyerOrders = {
        ...(where.buyerOrders || {}),
        some: { createdAt: { gte: cutoff } },
      };
    }
  }

  // noOrdersInDays=N — no order in last N days. (Combines with hasOrders if set.)
  if (Number.isFinite(Number(spec.noOrdersInDays))) {
    const days = Number(spec.noOrdersInDays);
    if (days > 0) {
      const cutoff = new Date(Date.now() - days * 86400 * 1000);
      // Prisma's `none` accepts a filter; a user matches if no Order with
      // createdAt >= cutoff exists.
      where.buyerOrders = {
        ...(where.buyerOrders || {}),
        none: { createdAt: { gte: cutoff } },
      };
    }
  }

  // vertical filter — any order in shop with vertical=X.
  if (spec.vertical) {
    where.buyerOrders = {
      ...(where.buyerOrders || {}),
      some: { shop: { vertical: String(spec.vertical) } },
    };
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
