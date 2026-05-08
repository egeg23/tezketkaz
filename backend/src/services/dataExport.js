// Phase 9.1 — GDPR data export service.
//
// Builds a JSON-shaped export of every record we hold for a user, persists a
// DataExport row tracking status + signed URL, and writes the rendered JSON
// either through Agent B's storage abstraction (lib/storage.js) when present
// or to a local /uploads/exports/ fallback so dev + tests work without S3.
//
// Excludes raw OTP codes and refresh tokens (security-sensitive). FCM tokens
// are reduced to platforms only. Saved payment methods keep brand+last4 only.

const fs = require('fs');
const path = require('path');
const logger = require('../lib/logger');

const EXPORT_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

// Returns a storage driver instance with .put / .list / .del, or null when
// the storage abstraction isn't available (we then fall back to local fs).
// Agent B's lib/storage.js exposes `{ storage, putFromMulterFile }` where
// `storage()` is a factory returning the driver — we accept either shape.
function tryLoadStorage() {
  try {
    // eslint-disable-next-line global-require
    const mod = require('../lib/storage');
    if (mod && typeof mod.storage === 'function') {
      return mod.storage();
    }
    if (mod && typeof mod.put === 'function') {
      return mod;
    }
    return null;
  } catch (err) {
    return null;
  }
}

// Local fallback: writes the export to backend/uploads/exports/<userId>/<id>.json
// and returns a /uploads-relative URL the SPA can hit through express.static.
async function writeLocalFallback(userId, exportId, json) {
  const dir = path.resolve(__dirname, '..', '..', 'uploads', 'exports', userId);
  await fs.promises.mkdir(dir, { recursive: true });
  const file = path.join(dir, `${exportId}.json`);
  await fs.promises.writeFile(file, json, 'utf8');
  return `/uploads/exports/${userId}/${exportId}.json`;
}

/**
 * Build a JSON-shaped export of every record we hold for `userId`.
 * Returns a plain object — caller stringifies + ships.
 */
async function buildExport(prisma, userId) {
  if (!userId) throw new Error('userId required');

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw Object.assign(new Error('User not found'), { status: 404 });

  // Strip secrets / OAuth subjects from the user blob — those are identity
  // links, not data the user "owns" in a portability sense.
  const userExport = {
    id: user.id,
    phone: user.phone,
    email: user.email,
    name: user.name,
    avatarUrl: user.avatarUrl,
    locale: user.locale,
    country: user.country,
    isBuyer: user.isBuyer,
    isCourier: user.isCourier,
    isShop: user.isShop,
    courierStatus: user.courierStatus,
    rating: user.rating,
    ordersCount: user.ordersCount,
    notificationPrefs: user.notificationPrefs,
    referralCode: user.referralCode,
    referredById: user.referredById,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
    deletedAt: user.deletedAt,
  };

  const [
    addresses,
    orders,
    reviewsAuthored,
    chatMessagesSent,
    chatMessagesReceived,
    fcmTokens,
    paymentMethods,
    loyalty,
    loyaltyTransactions,
    membership,
    favorites,
    auditLogs,
  ] = await Promise.all([
    prisma.address.findMany({ where: { userId } }),
    prisma.order.findMany({
      where: { buyerId: userId },
      include: { items: true },
    }),
    prisma.review.findMany({ where: { reviewerId: userId } }),
    prisma.chatMessage.findMany({ where: { senderId: userId } }),
    prisma.chatMessage.findMany({ where: { receiverId: userId } }),
    prisma.fcmToken.findMany({ where: { userId } }),
    prisma.paymentMethod.findMany({ where: { userId } }),
    prisma.loyaltyAccount.findUnique({ where: { userId } }).catch(() => null),
    prisma.loyaltyTransaction.findMany({ where: { userId } }),
    prisma.membership.findUnique({ where: { userId } }).catch(() => null),
    prisma.favorite.findMany({ where: { userId } }),
    prisma.auditLog.findMany({ where: { actorId: userId } }),
  ]);

  // Strip raw FCM tokens — we hand back only platform + lastSeenAt.
  const fcmTokensSanitized = fcmTokens.map((t) => ({
    platform: t.platform,
    lastSeenAt: t.lastSeenAt,
    createdAt: t.createdAt,
  }));

  // Strip provider-side token id from saved payment methods. last4/brand/expiry
  // are display-only and safe to include.
  const paymentMethodsSanitized = paymentMethods.map((pm) => ({
    id: pm.id,
    provider: pm.provider,
    brand: pm.brand,
    last4: pm.last4,
    expiryMonth: pm.expiryMonth,
    expiryYear: pm.expiryYear,
    isDefault: pm.isDefault,
    isActive: pm.isActive,
    createdAt: pm.createdAt,
  }));

  return {
    exportedAt: new Date().toISOString(),
    user: userExport,
    addresses,
    orders,
    reviews: reviewsAuthored,
    chatMessages: {
      sent: chatMessagesSent,
      received: chatMessagesReceived,
    },
    fcmTokens: fcmTokensSanitized,
    paymentMethods: paymentMethodsSanitized,
    loyalty: loyalty || null,
    loyaltyTransactions,
    membership: membership || null,
    favorites,
    auditLog: auditLogs,
  };
}

/**
 * Render an export to storage and persist a DataExport row. Returns the
 * DataExport row (always — failures bubble out so the caller can surface them).
 */
async function renderToFile(prisma, userId) {
  if (!userId) throw new Error('userId required');

  const created = await prisma.dataExport.create({
    data: { userId, status: 'pending' },
  });

  try {
    const data = await buildExport(prisma, userId);
    const json = JSON.stringify(data, null, 2);

    let fileUrl;
    const storage = tryLoadStorage();
    if (storage && typeof storage.put === 'function') {
      const key = `exports/${userId}/${created.id}.json`;
      const result = await storage.put(key, Buffer.from(json, 'utf8'), {
        contentType: 'application/json',
      });
      fileUrl = result?.url || result?.signedUrl || result?.location || null;
      // Fall back to local if storage put returned no usable URL.
      if (!fileUrl) {
        fileUrl = await writeLocalFallback(userId, created.id, json);
      }
    } else {
      fileUrl = await writeLocalFallback(userId, created.id, json);
    }

    const expiresAt = new Date(Date.now() + EXPORT_TTL_MS);
    return prisma.dataExport.update({
      where: { id: created.id },
      data: {
        status: 'ready',
        fileUrl,
        expiresAt,
        completedAt: new Date(),
      },
    });
  } catch (err) {
    logger.warn({ err: err.message, userId, exportId: created.id }, 'data export failed');
    try {
      await prisma.dataExport.update({
        where: { id: created.id },
        data: {
          status: 'failed',
          failedReason: err.message || 'unknown',
        },
      });
    } catch { /* already gone */ }
    throw err;
  }
}

module.exports = {
  buildExport,
  renderToFile,
  EXPORT_TTL_MS,
};
