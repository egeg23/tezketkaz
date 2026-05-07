// Firebase Cloud Messaging service.
// Once you create Firebase project at https://console.firebase.google.com:
// 1. Download serviceAccountKey.json
// 2. Place it in backend/firebase-admin.json (gitignored)
// 3. Set FCM_ENABLED=true in .env

const FCM_ENABLED = process.env.FCM_ENABLED === 'true';
let admin = null;

if (FCM_ENABLED) {
  try {
    admin = require('firebase-admin');
    const serviceAccount = require('../../firebase-admin.json');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  } catch (err) {
    console.warn('⚠️  FCM not initialized:', err.message);
  }
}

/**
 * Отправить push на одно устройство.
 */
async function sendToToken(fcmToken, { title, body, data = {} }) {
  if (!admin) {
    console.log(`📲 [MOCK PUSH] → ${fcmToken?.substring(0, 8)}... ${title}: ${body}`);
    return { mock: true };
  }

  try {
    const res = await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: {
        priority: 'high',
        notification: {
          channelId: 'orders',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: { sound: 'default', badge: 1 },
        },
      },
    });
    return { success: true, messageId: res };
  } catch (err) {
    console.error('FCM error:', err.message);
    return { success: false, error: err.message };
  }
}

/**
 * Отправить всем пользователям магазина при новом заказе.
 */
async function notifyShopNewOrder(order, shopMembers) {
  const tokens = shopMembers
    .filter(m => m.user?.fcmToken)
    .map(m => m.user.fcmToken);

  for (const token of tokens) {
    await sendToToken(token, {
      title: '🔔 Yangi buyurtma!',
      body: `${order.customerName} — ${order.total.toLocaleString('uz-UZ')} so'm`,
      data: { type: 'order_new', orderId: order.id },
    });
  }
}

/**
 * Уведомить покупателя об изменении статуса заказа.
 */
async function notifyBuyerStatusUpdate(order, buyer) {
  if (!buyer?.fcmToken) return;

  const messages = {
    confirmed: { title: '✅ Buyurtma tasdiqlandi', body: `${order.shop?.name || 'Do\'kon'} tayyorlamoqda` },
    collecting: { title: '📦 Yig\'ilmoqda', body: 'Buyurtmangiz tayyorlanmoqda' },
    readyForPickup: { title: '🏪 Tayyor', body: 'Kuryer tez orada keladi' },
    courierAssigned: { title: '🛵 Kuryer yo\'lda', body: 'Buyurtmangiz tayyorlanyapti' },
    pickedUp: { title: '🚀 Yo\'lda', body: 'Kuryer sizga yo\'lda' },
    delivered: { title: '🎉 Yetkazildi', body: 'Bahuzur foydalaning!' },
    cancelled: { title: '❌ Bekor qilindi', body: 'Pul qaytariladi' },
  };

  const msg = messages[order.status];
  if (!msg) return;

  await sendToToken(buyer.fcmToken, {
    ...msg,
    data: { type: 'order_update', orderId: order.id, status: order.status },
  });
}

/**
 * Уведомить курьеров о новом доступном заказе.
 */
async function notifyCouriersNewOrder(order, couriers) {
  const tokens = couriers.filter(c => c.fcmToken).map(c => c.fcmToken);
  for (const token of tokens) {
    await sendToToken(token, {
      title: '🛵 Yangi buyurtma',
      body: `${order.shop?.name || ''} — ${order.courierReward.toLocaleString('uz-UZ')} so'm`,
      data: { type: 'order_available', orderId: order.id },
    });
  }
}

module.exports = { sendToToken, notifyShopNewOrder, notifyBuyerStatusUpdate, notifyCouriersNewOrder };
