// Phase 2 dispatcher — picks N candidate couriers per offer batch, records
// DispatchOffer rows, schedules a BullMQ retry, and processes courier
// accept/decline transitions.

const presence = require('./redis-state');
const logger = require('../lib/logger');

const STATUS_PENDING = 'pending';
const STATUS_ACCEPTED = 'accepted';
const STATUS_DECLINED = 'declined';
const STATUS_TIMED_OUT = 'timed_out';
const STATUS_SUPERSEDED = 'superseded';

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

async function offerNextBatch(prisma, io, orderId, opts = {}) {
  const {
    batchSize = 3,
    holdSeconds = 60,
    radiusKm = 15,
    maxBatches = 5,
    maxRadiusKm = 30,
    batchIndex = 0,
  } = opts;

  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: { shop: true },
  });
  if (!order) return { offered: [], reason: 'not-found' };
  if (order.courierId) return { offered: [], reason: 'already-assigned' };

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
        },
      });
      created.push(offer);
      safeEmit(io, `courier:${p.courier.id}`, 'dispatch:offer', {
        orderId,
        offerId: offer.id,
        expiresAt: expiresAt.toISOString(),
        distanceKm: p.distanceKm,
      });
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

    const updated = await tx.order.update({
      where: { id: orderId },
      data: {
        courierId,
        status: 'courierAssigned',
        acceptedAt: order.acceptedAt || now,
      },
      include: { items: true, shop: true, courier: { select: { id: true, name: true, phone: true } } },
    });

    await tx.user.update({
      where: { id: courierId },
      data: { activeOrderId: orderId },
    });

    return { order: updated, supersededCourierIds: [] };
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
};
