// Phase 2 dispatcher — picks N candidate couriers per offer batch, records
// DispatchOffer rows, schedules a BullMQ retry, and processes courier
// accept/decline transitions.
//
// Phase 8.1 — stacked dispatch. When several pending orders cluster in a
// shop or small radius within a tight pickup window we group them into an
// OrderBatch and offer that bundle to a single courier as one DispatchOffer.

const presence = require('./redis-state');
const logger = require('../lib/logger');
const { distanceKm: haversineKm } = require('../lib/geo');
const tipEstimate = require('./tipEstimate');

const STATUS_PENDING = 'pending';
const STATUS_ACCEPTED = 'accepted';
const STATUS_DECLINED = 'declined';
const STATUS_TIMED_OUT = 'timed_out';
const STATUS_SUPERSEDED = 'superseded';

// Statuses a pending order can be in before it's dispatched. We batch on
// these (paid/confirmed bookings ready for courier handoff).
const BATCHABLE_STATUSES = ['paid', 'confirmed', 'pending', 'collecting', 'readyForPickup'];

// Score a candidate courier vs. an order. Higher = better.
function scoreCourier(courier, order, distanceKm) {
  const safeDist = Number.isFinite(distanceKm) && distanceKm > 0 ? distanceKm : 0.5;
  const rating = Number(courier?.rating ?? 5);
  const ordersCount = Number(courier?.ordersCount ?? 0);
  // We don't track completionRate explicitly yet — derive a soft proxy from
  // ordersCount: more historical orders ≈ more reliable. Cap influence.
  const completionRate = Math.min(1, ordersCount / 50);
  const activeOrders = courier?.activeOrderId ? 1 : 0;

  const distScore = 1 / safeDist;
  return distScore + 0.3 * rating + 0.2 * completionRate - 0.1 * activeOrders;
}

// Internal: load candidate couriers (online + approved + free) NOT already
// offered for this order.
async function loadCandidates(prisma, orderId) {
  const offered = await prisma.dispatchOffer.findMany({
    where: { orderId },
    select: { courierId: true },
  });
  const excludeIds = offered.map((o) => o.courierId);
  return prisma.user.findMany({
    where: {
      isCourier: true,
      courierStatus: 'approved',
      isOnline: true,
      activeOrderId: null,
      id: excludeIds.length ? { notIn: excludeIds } : undefined,
    },
  });
}

function safeEmit(io, room, event, payload) {
  if (!io || typeof io.to !== 'function') return;
  try { io.to(room).emit(event, payload); } catch (err) {
    logger.warn({ err: err.message, room, event }, 'socket emit failed');
  }
}

// ─── Phase 8.1 stacked dispatch ─────────────────────────────────────────────

// Find pending orders that can be batched together with `seedOrderId`.
// Greedy: starts from the seed, looks for up to `batchCap-1` other unbatched
// orders that share the seed's shop OR sit within `radiusKm` of it AND were
// created within `windowMs`. Returns one candidate cluster (or null).
async function buildBatchCandidates(prisma, opts = {}) {
  const radiusKm = opts.radiusKm ?? 1;
  const windowMs = opts.windowMs ?? 5 * 60 * 1000;
  const batchCap = opts.batchCap ?? 3;
  const seedOrderId = opts.seedOrderId || null;

  // Pull all unbatched candidates up front (small set in practice).
  const orders = await prisma.order.findMany({
    where: {
      batchId: null,
      courierId: null,
      status: { in: BATCHABLE_STATUSES },
    },
    include: { shop: true },
    orderBy: { createdAt: 'asc' },
  });

  if (orders.length < 2) return [];

  const indexById = new Map(orders.map((o) => [o.id, o]));
  const used = new Set();
  const clusters = [];

  function shopPoint(o) {
    if (!o.shop) return null;
    if (o.shop.lat == null || o.shop.lng == null) return null;
    return { lat: o.shop.lat, lng: o.shop.lng };
  }

  function tryCluster(seed) {
    if (used.has(seed.id)) return null;
    const seedPt = shopPoint(seed);
    const seedTime = seed.createdAt instanceof Date ? seed.createdAt.getTime() : new Date(seed.createdAt).getTime();
    const members = [seed];
    const memberIds = new Set([seed.id]);

    for (const o of orders) {
      if (members.length >= batchCap) break;
      if (memberIds.has(o.id) || used.has(o.id)) continue;

      // Time window
      const oTime = o.createdAt instanceof Date ? o.createdAt.getTime() : new Date(o.createdAt).getTime();
      if (Math.abs(oTime - seedTime) > windowMs) continue;

      // Same shop OR within radius
      let groupable = false;
      if (o.shopId && o.shopId === seed.shopId) {
        groupable = true;
      } else {
        const oPt = shopPoint(o);
        if (seedPt && oPt) {
          const d = haversineKm(seedPt.lat, seedPt.lng, oPt.lat, oPt.lng);
          if (Number.isFinite(d) && d < radiusKm) groupable = true;
        }
      }
      if (!groupable) continue;

      members.push(o);
      memberIds.add(o.id);
    }

    if (members.length < 2) return null;
    return members;
  }

  if (seedOrderId) {
    const seed = indexById.get(seedOrderId);
    if (!seed) return [];
    const members = tryCluster(seed);
    if (!members) return [];
    members.forEach((m) => used.add(m.id));
    return [makeCandidate(members)];
  }

  for (const seed of orders) {
    if (used.has(seed.id)) continue;
    const members = tryCluster(seed);
    if (!members) continue;
    members.forEach((m) => used.add(m.id));
    clusters.push(makeCandidate(members));
  }
  return clusters;
}

function makeCandidate(members) {
  let totalReward = 0;
  for (const m of members) {
    totalReward += Number(m.courierReward || 0);
    totalReward += Number(m.tipAmount || 0);
  }
  return {
    seedOrderId: members[0].id,
    memberOrderIds: members.map((m) => m.id),
    totalReward,
  };
}

// Persist an OrderBatch row and link member orders by sequence. Returns the
// created OrderBatch row.
async function commitBatch(prisma, candidate) {
  const memberIds = candidate.memberOrderIds;
  if (!Array.isArray(memberIds) || memberIds.length < 2) {
    throw new Error('commitBatch requires >= 2 memberOrderIds');
  }
  // Resolve members to determine sequence by createdAt (asc).
  const members = await prisma.order.findMany({
    where: { id: { in: memberIds }, batchId: null },
    orderBy: { createdAt: 'asc' },
  });
  if (members.length !== memberIds.length) {
    throw Object.assign(new Error('Batch members already linked or missing'), { status: 409 });
  }

  const batch = await prisma.orderBatch.create({
    data: {
      totalDeliveries: members.length,
      estimatedReward: candidate.totalReward || 0,
      status: STATUS_PENDING,
    },
  });

  // Link orders with batchSequence in createdAt order.
  for (let i = 0; i < members.length; i += 1) {
    await prisma.order.update({
      where: { id: members[i].id },
      data: { batchId: batch.id, batchSequence: i },
    });
  }
  return batch;
}

async function offerNextBatch(prisma, io, orderId, opts = {}) {
  const {
    batchSize = 3,
    holdSeconds = 60,
    radiusKm = 15,
    maxBatches = 5,
    maxRadiusKm = 30,
    batchIndex = 0,
  } = opts;

  let order = await prisma.order.findUnique({
    where: { id: orderId },
    include: { shop: true, batch: true },
  });
  if (!order) return { offered: [], reason: 'not-found' };
  if (order.courierId) return { offered: [], reason: 'already-assigned' };

  // ── Phase 8.1: opportunistic batching ─────────────────────────────────────
  // If this order isn't already in a batch, see if we can group it with other
  // pending orders before dispatching. If so, the offer pays the batch reward
  // and references the OrderBatch row.
  let batch = order.batch || null;
  if (!batch && !opts.skipBatch) {
    try {
      const candidates = await buildBatchCandidates(prisma, {
        seedOrderId: orderId,
        radiusKm: opts.batchRadiusKm ?? 1,
        windowMs: opts.batchWindowMs ?? 5 * 60 * 1000,
        batchCap: opts.batchCap ?? 3,
      });
      if (candidates.length) {
        batch = await commitBatch(prisma, candidates[0]);
        // Reload the seed order so it reflects the new batchId.
        order = await prisma.order.findUnique({
          where: { id: orderId },
          include: { shop: true, batch: true },
        });
      }
    } catch (err) {
      logger.warn({ err: err.message, orderId }, 'buildBatchCandidates failed');
    }
  }

  // No-courier-found short-circuit
  if (batchIndex >= maxBatches || radiusKm > maxRadiusKm) {
    try {
      await prisma.order.update({
        where: { id: orderId },
        data: { status: 'no_courier_found' },
      });
    } catch (err) {
      logger.warn({ err: err.message, orderId }, 'mark no_courier_found failed');
    }
    safeEmit(io, `buyer:${order.buyerId}`, 'order:no_courier', { orderId });
    return { offered: [], reason: 'exhausted' };
  }

  const shopPoint = (order.shop?.lat != null && order.shop?.lng != null)
    ? { lat: order.shop.lat, lng: order.shop.lng }
    : null;

  const candidates = await loadCandidates(prisma, orderId);
  if (candidates.length === 0) {
    return scheduleRetry(orderId, holdSeconds, { ...opts, batchIndex: batchIndex + 1, radiusKm: radiusKm + 5 });
  }

  // Compute distance + score
  const scored = [];
  for (const c of candidates) {
    let distanceKm = 0;
    if (shopPoint) {
      const loc = await presence.getCourierLocation(c.id);
      if (!loc) continue; // skip couriers without location
      distanceKm = presence.distanceKm(shopPoint, loc);
      if (distanceKm > radiusKm) continue;
    }
    const score = scoreCourier(c, order, distanceKm);
    scored.push({ courier: c, distanceKm, score });
  }

  if (scored.length === 0) {
    return scheduleRetry(orderId, holdSeconds, { ...opts, batchIndex: batchIndex + 1, radiusKm: radiusKm + 5 });
  }

  scored.sort((a, b) => b.score - a.score);
  const picks = scored.slice(0, batchSize);

  const expiresAt = new Date(Date.now() + holdSeconds * 1000);
  const created = [];

  // Phase 8.2 — compute the tip estimate once per offer round so couriers see
  // the buyer's expected tip in the offer banner. For batched dispatch we
  // average the heuristic across member orders. Failures degrade to 0.
  let tipEst = 0;
  try {
    if (batch) {
      const memberOrders = await prisma.order.findMany({
        where: { batchId: batch.id },
        select: { id: true },
      });
      tipEst = await tipEstimate.estimateForBatch(prisma, memberOrders.map((m) => m.id));
    } else {
      tipEst = await tipEstimate.estimateForOrder(prisma, orderId);
    }
  } catch (err) {
    logger.warn({ err: err.message, orderId }, 'tipEstimate failed; using 0');
    tipEst = 0;
  }

  for (const p of picks) {
    try {
      const offer = await prisma.dispatchOffer.create({
        data: {
          orderId,
          courierId: p.courier.id,
          status: STATUS_PENDING,
          score: p.score,
          distanceKm: p.distanceKm || null,
          expiresAt,
          tipEstimate: tipEst,
          batchId: batch ? batch.id : null,
        },
      });
      created.push(offer);
      const payload = {
        orderId,
        offerId: offer.id,
        expiresAt: expiresAt.toISOString(),
        distanceKm: p.distanceKm,
        tipEstimate: tipEst,
      };
      if (batch) {
        payload.batchId = batch.id;
        payload.totalDeliveries = batch.totalDeliveries;
        payload.estimatedReward = batch.estimatedReward;
      }
      safeEmit(io, `courier:${p.courier.id}`, 'dispatch:offer', payload);
    } catch (err) {
      // Likely a race on UNIQUE(orderId, courierId) — ignore.
      logger.debug({ err: err.message, courierId: p.courier.id, orderId }, 'offer create skipped');
    }
  }

  await scheduleRetry(orderId, holdSeconds, { ...opts, batchIndex: batchIndex + 1, radiusKm: radiusKm + 5 });

  return { offered: created, reason: 'ok' };
}

async function scheduleRetry(orderId, holdSeconds, nextOpts) {
  // Lazy-require to avoid circular load with index.js wiring.
  // eslint-disable-next-line global-require
  const { queues } = require('../lib/queues');
  try {
    await queues().dispatch.add(
      'retry',
      { type: 'retry', orderId, opts: nextOpts },
      { delay: holdSeconds * 1000, removeOnComplete: true, removeOnFail: true },
    );
  } catch (err) {
    logger.warn({ err: err.message, orderId }, 'queue.dispatch.add retry failed');
  }
  return { offered: [], reason: 'scheduled' };
}

async function acceptOffer(prisma, io, orderId, courierId) {
  // Run in a transaction to keep state consistent.
  return prisma.$transaction(async (tx) => {
    const offer = await tx.dispatchOffer.findUnique({
      where: { orderId_courierId: { orderId, courierId } },
    });
    if (!offer) {
      throw Object.assign(new Error('Offer not found'), { status: 404 });
    }
    if (offer.status !== STATUS_PENDING) {
      throw Object.assign(new Error('Offer is not pending'), { status: 409 });
    }

    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw Object.assign(new Error('Order not found'), { status: 404 });
    if (order.courierId) {
      throw Object.assign(new Error('Order already assigned'), { status: 409 });
    }

    const now = new Date();
    await tx.dispatchOffer.update({
      where: { id: offer.id },
      data: { status: STATUS_ACCEPTED, respondedAt: now },
    });

    await tx.dispatchOffer.updateMany({
      where: {
        orderId,
        status: STATUS_PENDING,
        NOT: { id: offer.id },
      },
      data: { status: STATUS_SUPERSEDED, respondedAt: now },
    });

    // ── Phase 8.1 stacked dispatch ────────────────────────────────────────
    // Resolve the effective batch id from the offer (preferred) or the
    // order. When set, ALL member orders receive the courier assignment
    // and the courier's activeOrderId is pinned to the first sequence.
    const batchId = offer.batchId || order.batchId || null;
    let firstOrderId = orderId;

    if (batchId) {
      await tx.orderBatch.update({
        where: { id: batchId },
        data: { courierId, status: STATUS_ACCEPTED },
      });

      const members = await tx.order.findMany({
        where: { batchId },
        orderBy: { batchSequence: 'asc' },
      });

      for (const m of members) {
        await tx.order.update({
          where: { id: m.id },
          data: {
            courierId,
            status: 'courierAssigned',
            acceptedAt: m.acceptedAt || now,
          },
        });
        // Supersede competing pending offers on sibling orders so other
        // couriers don't double-assign within the batch.
        await tx.dispatchOffer.updateMany({
          where: {
            orderId: m.id,
            status: STATUS_PENDING,
            NOT: { id: offer.id },
          },
          data: { status: STATUS_SUPERSEDED, respondedAt: now },
        });
      }

      firstOrderId = (members[0] && members[0].id) || orderId;
    } else {
      await tx.order.update({
        where: { id: orderId },
        data: {
          courierId,
          status: 'courierAssigned',
          acceptedAt: order.acceptedAt || now,
        },
      });
    }

    const updated = await tx.order.findUnique({
      where: { id: orderId },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });

    await tx.user.update({
      where: { id: courierId },
      data: { activeOrderId: firstOrderId },
    });

    return { order: updated, batchId, firstOrderId };
  }).then(async ({ order }) => {
    // Outside the transaction: gather superseded offers to notify those couriers.
    const others = await prisma.dispatchOffer.findMany({
      where: { orderId, status: STATUS_SUPERSEDED, NOT: { courierId } },
      select: { courierId: true },
    });

    safeEmit(io, `buyer:${order.buyerId}`, 'order:updated', order);
    safeEmit(io, `courier:${courierId}`, 'order:assigned', order);
    for (const o of others) {
      safeEmit(io, `courier:${o.courierId}`, 'dispatch:offer_cancelled', { orderId });
    }

    return order;
  });
}

async function declineOffer(prisma, io, orderId, courierId, reason) {
  const offer = await prisma.dispatchOffer.findUnique({
    where: { orderId_courierId: { orderId, courierId } },
  });
  if (!offer) {
    throw Object.assign(new Error('Offer not found'), { status: 404 });
  }
  if (offer.status !== STATUS_PENDING) {
    throw Object.assign(new Error('Offer is not pending'), { status: 409 });
  }

  await prisma.dispatchOffer.update({
    where: { id: offer.id },
    data: { status: STATUS_DECLINED, respondedAt: new Date() },
  });

  // If no remaining pending offers in this batch, kick off the next batch
  // synchronously (with a wider radius).
  const remaining = await prisma.dispatchOffer.count({
    where: { orderId, status: STATUS_PENDING },
  });
  let followUp = null;
  if (remaining === 0) {
    // Best-effort — failures shouldn't break the decline response.
    followUp = offerNextBatch(prisma, io, orderId, { radiusKm: 20 }).catch((err) => {
      logger.warn({ err: err.message, orderId }, 'follow-up offerNextBatch failed');
    });
    // Track on the module so tests can flush.
    pendingFollowUps.add(followUp);
    followUp.finally(() => pendingFollowUps.delete(followUp));
  }

  return { ok: true, reason: reason || null, followUp };
}

// Tracking set so tests can `await flushPending()` after declines.
const pendingFollowUps = new Set();
async function flushPending() {
  while (pendingFollowUps.size) {
    await Promise.allSettled([...pendingFollowUps]);
  }
}

// Used by the retry job: expire still-pending offers whose expiresAt has passed.
async function expireOverdueOffers(prisma, orderId) {
  const now = new Date();
  await prisma.dispatchOffer.updateMany({
    where: { orderId, status: STATUS_PENDING, expiresAt: { lt: now } },
    data: { status: STATUS_TIMED_OUT, respondedAt: now },
  });
}

module.exports = {
  scoreCourier,
  offerNextBatch,
  acceptOffer,
  declineOffer,
  expireOverdueOffers,
  flushPending,
  buildBatchCandidates,
  commitBatch,
};
