// Phase 8.2 — Wolt-tier transparency: estimate the buyer's expected tip in
// UZS at the moment a dispatcher offer fires, so couriers can decide whether
// to accept based on the *full* expected reward (delivery fee + tip).
//
// Heuristic two-tier lookup:
//   1. Buyer history — average tip on the last 5 delivered+tipPaidAt orders.
//      If at least 3 such orders exist, use that mean.
//   2. Shop fallback — average tip across last 100 delivered orders for that
//      shop. We apply a 50% confidence cap (multiply by 0.5) so we don't
//      over-promise on couriers betting against an unknown buyer.
//   3. Otherwise return 0.

const TIP_PAID_LIMIT = 5;
const SHOP_LIMIT = 100;
const MIN_BUYER_TIPS = 3;
const SHOP_CONFIDENCE = 0.5;

function avg(arr) {
  if (!arr.length) return 0;
  return arr.reduce((s, v) => s + Number(v || 0), 0) / arr.length;
}

// Round to nearest 100 UZS so we don't surface noisy decimals to the courier.
function round100(n) {
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.round(n / 100) * 100;
}

async function buyerHistoryMean(prisma, buyerId) {
  if (!buyerId) return null;
  const rows = await prisma.order.findMany({
    where: {
      buyerId,
      status: { in: ['delivered', 'confirmedByBuyer'] },
      tipPaidAt: { not: null },
      tipAmount: { gt: 0 },
    },
    orderBy: { tipPaidAt: 'desc' },
    take: TIP_PAID_LIMIT,
    select: { tipAmount: true },
  });
  if (rows.length < MIN_BUYER_TIPS) return null;
  return avg(rows.map((r) => r.tipAmount));
}

async function shopHistoryMean(prisma, shopId) {
  if (!shopId) return null;
  const rows = await prisma.order.findMany({
    where: {
      shopId,
      status: { in: ['delivered', 'confirmedByBuyer'] },
    },
    orderBy: { deliveredAt: 'desc' },
    take: SHOP_LIMIT,
    select: { tipAmount: true },
  });
  if (rows.length === 0) return null;
  // Mean over ALL delivered orders, not only tipped ones — this reflects the
  // realistic chance + size of a tip on this shop.
  const mean = avg(rows.map((r) => r.tipAmount));
  if (mean <= 0) return null;
  return mean * SHOP_CONFIDENCE;
}

async function estimateForOrder(prisma, orderId) {
  if (!orderId) return 0;
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    select: { id: true, buyerId: true, shopId: true },
  });
  if (!order) return 0;

  const buyerMean = await buyerHistoryMean(prisma, order.buyerId);
  if (buyerMean !== null) return round100(buyerMean);

  const shopMean = await shopHistoryMean(prisma, order.shopId);
  if (shopMean !== null) return round100(shopMean);

  return 0;
}

// Cheap variant for batches — averages individual order estimates.
async function estimateForBatch(prisma, orderIds) {
  if (!Array.isArray(orderIds) || orderIds.length === 0) return 0;
  const values = await Promise.all(orderIds.map((id) => estimateForOrder(prisma, id)));
  return round100(avg(values));
}

module.exports = {
  estimateForOrder,
  estimateForBatch,
  // exported for tests
  _buyerHistoryMean: buyerHistoryMean,
  _shopHistoryMean: shopHistoryMean,
  _round100: round100,
  TIP_PAID_LIMIT,
  SHOP_LIMIT,
  MIN_BUYER_TIPS,
  SHOP_CONFIDENCE,
};
