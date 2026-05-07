// Firebase Cloud Messaging service.
// Setup:
// 1. Create Firebase project at https://console.firebase.google.com
// 2. Download serviceAccountKey.json
// 3. Place it in backend/firebase-admin.json (gitignored)
// 4. Set FCM_ENABLED=true in .env

const path = require('path');
const env = require('../config/env');
const logger = require('../lib/logger');
const prisma = require('../db');

let admin = null;

if (env.fcmEnabled) {
  try {
    // eslint-disable-next-line global-require
    admin = require('firebase-admin');
    // eslint-disable-next-line global-require, import/no-dynamic-require
    const serviceAccount = require(path.resolve(__dirname, '../../firebase-admin.json'));
    if (!admin.apps.length) {
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    }
    logger.info('FCM initialized');
  } catch (err) {
    logger.warn({ err: err.message }, 'FCM init failed, falling back to mock');
    admin = null;
  }
}

const isReal = () => Boolean(admin);

async function sendToToken(fcmToken, { title, body, data = {} }) {
  if (!isReal()) {
    logger.debug({ token: fcmToken?.substring(0, 8), title }, 'mock push');
    return { mock: true };
  }
  try {
    const messageId = await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: {
        priority: 'high',
        notification: { channelId: 'orders', sound: 'default' },
      },
      apns: {
        payload: { aps: { sound: 'default', badge: 1 } },
      },
    });
    return { success: true, messageId };
  } catch (err) {
    // Token can be stale (registration-token-not-registered). Drop it from DB.
    const code = err.code || err.errorInfo?.code;
    if (code === 'messaging/registration-token-not-registered'
      || code === 'messaging/invalid-registration-token') {
      try {
        await prisma.fcmToken.deleteMany({ where: { token: fcmToken } });
        logger.info({ token: fcmToken.substring(0, 8) }, 'pruned stale fcm token');
      } catch (_) { /* ignore */ }
    } else {
      logger.warn({ err: err.message }, 'fcm send error');
    }
    return { success: false, error: err.message };
  }
}

async function sendToUser(userId, payload) {
  const tokens = await prisma.fcmToken.findMany({ where: { userId } });
  if (!tokens.length) return { sent: 0 };
  const results = await Promise.all(tokens.map((t) => sendToToken(t.token, payload)));
  const sent = results.filter((r) => r.success || r.mock).length;
  return { sent, total: tokens.length };
}

async function notifyShopNewOrder(order, shopMembers) {
  const userIds = shopMembers.map((m) => m.userId);
  if (!userIds.length) return;
  const tokens = await prisma.fcmToken.findMany({ where: { userId: { in: userIds } } });
  for (const t of tokens) {
    await sendToToken(t.token, {
      title: '🔔 Yangi buyurtma!',
      body: `${order.customerName} — ${(order.total ?? 0).toLocaleString('uz-UZ')} so'm`,
      data: { type: 'order_new', orderId: order.id },
    });
  }
}

const STATUS_MESSAGES = {
  confirmed:        { title: '✅ Buyurtma tasdiqlandi',   body: 'Tayyorlanyapti' },
  collecting:       { title: '📦 Yig\'ilmoqda',           body: 'Buyurtmangiz tayyorlanmoqda' },
  readyForPickup:   { title: '🏪 Tayyor',                  body: 'Kuryer tez orada keladi' },
  courierAssigned:  { title: '🛵 Kuryer topildi',          body: 'Kuryer yo\'lda' },
  pickedUp:         { title: '🚀 Yo\'lda',                 body: 'Kuryer sizga yo\'lda' },
  inDelivery:       { title: '🚀 Yetkazilmoqda',           body: 'Kuryer yo\'lda' },
  arrivedAtCustomer:{ title: '📍 Kuryer keldi',            body: 'Kuryer manzilingizda' },
  delivered:        { title: '🎉 Yetkazildi',              body: 'Bahuzur foydalaning!' },
  cancelled:        { title: '❌ Bekor qilindi',           body: 'Pul qaytariladi' },
};

async function notifyBuyerStatusUpdate(order) {
  const msg = STATUS_MESSAGES[order.status];
  if (!msg) return;
  await sendToUser(order.buyerId, {
    ...msg,
    data: { type: 'order_update', orderId: order.id, status: order.status },
  });
}

async function notifyCouriersNewOrder(order, courierIds) {
  if (!courierIds?.length) return;
  const tokens = await prisma.fcmToken.findMany({ where: { userId: { in: courierIds } } });
  for (const t of tokens) {
    await sendToToken(t.token, {
      title: '🛵 Yangi buyurtma',
      body: `${order.shop?.name || ''} — ${(order.courierReward ?? 0).toLocaleString('uz-UZ')} so'm`,
      data: { type: 'order_available', orderId: order.id },
    });
  }
}

module.exports = {
  sendToToken,
  sendToUser,
  notifyShopNewOrder,
  notifyBuyerStatusUpdate,
  notifyCouriersNewOrder,
};
