// Firebase Cloud Messaging service.
//
// Phase 13.1.6 — credential resolution order (first hit wins):
//   1. FIREBASE_SERVICE_ACCOUNT_JSON env var  (inline JSON; preferred for
//      managed platforms like Render / Railway)
//   2. FIREBASE_SERVICE_ACCOUNT_PATH env var  (filesystem path; preferred
//      for self-hosted deploys)
//   3. Legacy backend/firebase-admin.json     (kept for backward compat)
//
// Setup (one-time, in production):
//   1. Create Firebase project at https://console.firebase.google.com
//   2. Project Settings → Service Accounts → Generate new private key
//   3. Provide it via FIREBASE_SERVICE_ACCOUNT_JSON (inline) OR
//      FIREBASE_SERVICE_ACCOUNT_PATH (file)
//   4. Set FCM_ENABLED=true
// See docs/runbooks/firebase-prod-setup.md for the full checklist.

const fs = require('fs');
const path = require('path');
const env = require('../config/env');
const logger = require('../lib/logger');
const prisma = require('../db');

let admin = null;

/** Resolve a parsed service-account credential object, or return null. */
function loadServiceAccount() {
  // 1. Inline JSON (managed platforms).
  if (env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    try {
      return JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON);
    } catch (err) {
      logger.warn({ err: err.message },
        'FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON; ignoring');
    }
  }
  // 2. Explicit path.
  if (env.FIREBASE_SERVICE_ACCOUNT_PATH) {
    const resolved = path.isAbsolute(env.FIREBASE_SERVICE_ACCOUNT_PATH)
      ? env.FIREBASE_SERVICE_ACCOUNT_PATH
      : path.resolve(process.cwd(), env.FIREBASE_SERVICE_ACCOUNT_PATH);
    try {
      const raw = fs.readFileSync(resolved, 'utf8');
      return JSON.parse(raw);
    } catch (err) {
      logger.warn({ err: err.message, path: resolved },
        'FIREBASE_SERVICE_ACCOUNT_PATH unreadable; ignoring');
    }
  }
  // 3. Legacy default location.
  const legacy = path.resolve(__dirname, '../../firebase-admin.json');
  if (fs.existsSync(legacy)) {
    try {
      // eslint-disable-next-line global-require, import/no-dynamic-require
      return require(legacy);
    } catch (err) {
      logger.warn({ err: err.message }, 'legacy firebase-admin.json unreadable');
    }
  }
  return null;
}

if (env.fcmEnabled) {
  const serviceAccount = loadServiceAccount();
  if (!serviceAccount) {
    logger.warn(
      'FCM_ENABLED=true but no service account found. Set '
      + 'FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_SERVICE_ACCOUNT_PATH. '
      + 'Push notifications will be mocked.',
    );
  } else {
    try {
      // eslint-disable-next-line global-require
      admin = require('firebase-admin');
      if (!admin.apps.length) {
        admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
      }
      logger.info({ projectId: serviceAccount.project_id }, 'FCM initialized');
    } catch (err) {
      logger.warn({ err: err.message }, 'FCM init failed, falling back to mock');
      admin = null;
    }
  }
} else {
  logger.info('FCM_ENABLED=false — push notifications run in mock mode');
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
