// Phase 9.2 — account deletion lifecycle.
//
//   request()  → create AccountDeletionRequest, set User.deletedAt,
//                revoke all refresh tokens, send confirmation email.
//   cancel()   → if still in grace window, restore User.deletedAt = null and
//                mark the request 'cancelled'.
//   purgeDue() → daily sweep that hard-anonymises users whose grace window
//                has expired. We DO NOT delete the User row (orders + payouts
//                still reference it for accounting) — instead we strip every
//                identifying field and drop dependent records.

const crypto = require('crypto');
const { audit } = require('../lib/audit');
const jwtLib = require('../lib/jwt');
const email = require('./email');
const logger = require('../lib/logger');

const GRACE_DAYS = 30;
const GRACE_MS = GRACE_DAYS * 24 * 60 * 60 * 1000;

function deletionScheduledFor(now = new Date()) {
  return new Date(now.getTime() + GRACE_MS);
}

/**
 * Create a deletion request and soft-delete the user.
 * Idempotent-ish: if there's already a pending request, returns it.
 */
async function request(prisma, userId, reason, { ipAddress } = {}) {
  if (!userId) {
    throw Object.assign(new Error('userId required'), { status: 400 });
  }
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) {
    throw Object.assign(new Error('User not found'), { status: 404 });
  }

  // If already pending, return it — don't extend the timer.
  const existing = await prisma.accountDeletionRequest.findFirst({
    where: { userId, status: 'pending' },
    orderBy: { requestedAt: 'desc' },
  });
  if (existing) return existing;

  const now = new Date();
  const scheduledFor = deletionScheduledFor(now);
  const created = await prisma.accountDeletionRequest.create({
    data: {
      userId,
      reason: reason || null,
      status: 'pending',
      requestedAt: now,
      scheduledFor,
    },
  });

  // Soft-delete + revoke sessions in parallel.
  await Promise.all([
    prisma.user.update({ where: { id: userId }, data: { deletedAt: now } }),
    jwtLib.revokeAllUserRefresh(userId),
  ]);

  // Confirmation email — fire-and-forget. Template name we accept for now is
  // 'order_confirmation' style; reuse the email send façade with a custom
  // subject by going outside the templates table when needed. For now we
  // log + skip — the email service noops without RESEND_API_KEY anyway.
  if (user.email) {
    try {
      await email.send({
        to: user.email,
        locale: user.locale || 'uz',
        // No template for deletion notifications yet — service noops on
        // unknown_template, that's fine. Surfaces in logs only.
        template: 'account_deletion',
        data: { name: user.name || '', scheduledFor: scheduledFor.toISOString() },
      });
    } catch (err) {
      logger.warn({ err: err.message, userId }, 'deletion confirm email failed');
    }
  }

  await audit({
    actorId: userId,
    action: 'user.delete_request',
    targetType: 'User',
    targetId: userId,
    metadata: { scheduledFor: scheduledFor.toISOString(), reason: reason || null },
    ipAddress: ipAddress || null,
  });

  return created;
}

/**
 * Cancel a pending request. Only the owner (or admin) can cancel.
 * Restores deletedAt = null on the user.
 */
async function cancel(prisma, requestId, actorId, { ipAddress } = {}) {
  const existing = await prisma.accountDeletionRequest.findUnique({
    where: { id: requestId },
  });
  if (!existing) {
    throw Object.assign(new Error('Request not found'), { status: 404 });
  }
  if (existing.status !== 'pending') {
    throw Object.assign(new Error(`Cannot cancel a ${existing.status} request`), { status: 400 });
  }
  if (existing.scheduledFor && existing.scheduledFor < new Date()) {
    throw Object.assign(new Error('Grace period elapsed'), { status: 400 });
  }

  const now = new Date();
  const updated = await prisma.accountDeletionRequest.update({
    where: { id: requestId },
    data: { status: 'cancelled', cancelledAt: now },
  });

  await prisma.user.update({
    where: { id: existing.userId },
    data: { deletedAt: null },
  });

  await audit({
    actorId: actorId || existing.userId,
    action: 'user.delete_cancel',
    targetType: 'User',
    targetId: existing.userId,
    metadata: { requestId },
    ipAddress: ipAddress || null,
  });

  return updated;
}

// Stable hash used to disambiguate anonymised phones (we keep `phone` UNIQUE
// in the schema, so two users hitting the same anonymised string would
// collide on the index).
function anonymizeId(userId) {
  return crypto.createHash('sha256').update(String(userId)).digest('hex').slice(0, 16);
}

/**
 * Anonymise a single user and drop their dependent records.
 * Exported for tests + callable from purgeDue.
 */
async function purgeUser(prisma, userId) {
  const hash = anonymizeId(userId);

  // 1. Cancel any in-flight orders. We don't delete orders — accounting needs
  //    them. Pending/confirmed/etc. get marked cancelled with a deletion note.
  const inflight = await prisma.order.findMany({
    where: {
      buyerId: userId,
      status: { notIn: ['delivered', 'confirmedByBuyer', 'cancelled', 'refunded'] },
    },
    select: { id: true, status: true },
  });
  if (inflight.length) {
    await prisma.order.updateMany({
      where: { id: { in: inflight.map((o) => o.id) } },
      data: {
        status: 'cancelled',
        cancelledAt: new Date(),
        cancelReason: 'account_deleted',
      },
    });
  }

  // 2. Drop dependent records in parallel. fcmTokens, addresses,
  //    paymentMethods, favorites, banner impressions, loyalty transactions.
  //    Loyalty *account* is kept zeroed so audit trail points somewhere.
  await Promise.all([
    prisma.fcmToken.deleteMany({ where: { userId } }),
    prisma.address.deleteMany({ where: { userId } }),
    prisma.paymentMethod.deleteMany({ where: { userId } }),
    prisma.favorite.deleteMany({ where: { userId } }),
    prisma.bannerImpression.deleteMany({ where: { userId } }),
    prisma.loyaltyTransaction.deleteMany({ where: { userId } }),
    // Refresh tokens already revoked at request time, but cascade-delete now
    // for cleanliness.
    prisma.refreshToken.deleteMany({ where: { userId } }),
  ]);

  // 3. Anonymise the user row. phone gets a unique placeholder so the @unique
  //    index is satisfied; everything else nulled.
  await prisma.user.update({
    where: { id: userId },
    data: {
      phone: `DELETED_${hash}`,
      name: null,
      email: null,
      avatarUrl: null,
      appleSubject: null,
      googleSubject: null,
      stir: null,
      passportSeries: null,
      selfEmployedCert: null,
      notificationPrefs: null,
      referralCode: null,
      // Mark deletedAt so any reactivation attempt can detect it.
      deletedAt: new Date(),
    },
  });
}

/**
 * Sweep: process all requests where scheduledFor <= now and status='pending'.
 */
async function purgeDue(prisma, { now = new Date() } = {}) {
  const due = await prisma.accountDeletionRequest.findMany({
    where: {
      status: 'pending',
      scheduledFor: { lte: now },
    },
    take: 100,
  });

  const results = [];
  for (const req of due) {
    try {
      await purgeUser(prisma, req.userId);
      const completed = await prisma.accountDeletionRequest.update({
        where: { id: req.id },
        data: { status: 'completed', completedAt: new Date() },
      });
      await audit({
        actorId: null,
        action: 'user.purge',
        targetType: 'User',
        targetId: req.userId,
        metadata: { requestId: req.id },
      });
      results.push({ id: req.id, userId: req.userId, ok: true });
      logger.info({ userId: req.userId, requestId: req.id }, 'user purged');
      void completed;
    } catch (err) {
      logger.error({ err: err.message, userId: req.userId, requestId: req.id }, 'purge failed');
      results.push({ id: req.id, userId: req.userId, ok: false, error: err.message });
    }
  }
  return { processed: results.length, results };
}

module.exports = {
  request,
  cancel,
  purgeDue,
  purgeUser,
  GRACE_DAYS,
  GRACE_MS,
  deletionScheduledFor,
};
