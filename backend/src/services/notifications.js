// Phase 3 notifications façade.
//
// Combines: (a) DB Notification row, (b) FCM push via existing services/push.js,
// and (c) realtime socket emit on the user's personal `buyer:` room. Localises
// title/body via User.locale (uz | ru | en).

const push = require('./push');
const logger = require('../lib/logger');

const T = {
  order_paid: {
    uz: { title: "To'lov muvaffaqiyatli", body: "Buyurtmangiz uchun to'lov qabul qilindi" },
    ru: { title: 'Оплата прошла', body: 'Платёж за заказ принят' },
    en: { title: 'Payment succeeded', body: 'Your order payment has been received' },
    kk: { title: 'Төлем сәтті өтті', body: 'Тапсырыс үшін төлем қабылданды' },
  },
  order_confirmed: {
    uz: { title: 'Buyurtma tasdiqlandi', body: 'Buyurtmangiz tayyorlanmoqda' },
    ru: { title: 'Заказ подтверждён', body: 'Магазин начал готовить' },
    en: { title: 'Order confirmed', body: 'The shop is preparing your order' },
    kk: { title: 'Тапсырыс расталды', body: 'Дүкен тапсырысыңызды дайындап жатыр' },
  },
  order_dispatched: {
    uz: { title: 'Kuryer topildi', body: "Kuryer yo'lda" },
    ru: { title: 'Курьер найден', body: 'Курьер уже едет' },
    en: { title: 'Courier assigned', body: 'A courier is on the way' },
    kk: { title: 'Курьер тағайындалды', body: 'Курьер жолда' },
  },
  order_picked_up: {
    uz: { title: "Yo'lda", body: "Kuryer buyurtmangizni olib yo'lga chiqdi" },
    ru: { title: 'В пути', body: 'Курьер забрал заказ' },
    en: { title: 'On the way', body: 'Courier picked up your order' },
    kk: { title: 'Курьер тапсырысыңды алды', body: 'Курьер тапсырысты алып, жолға шықты' },
  },
  order_in_delivery: {
    uz: { title: 'Yetkazilmoqda', body: "Kuryer yo'lda" },
    ru: { title: 'Доставляется', body: 'Курьер уже едет' },
    en: { title: 'Out for delivery', body: 'Courier is on the way' },
    kk: { title: 'Жеткізілуде', body: 'Курьер жолда' },
  },
  order_delivered: {
    uz: { title: 'Yetkazildi', body: 'Bahuzur foydalaning!' },
    ru: { title: 'Доставлено', body: 'Приятного использования!' },
    en: { title: 'Delivered', body: 'Enjoy your order!' },
    kk: { title: 'Жеткізілді', body: 'Пайдаланғанда көңіл көтерсін!' },
  },
  order_cancelled: {
    uz: { title: 'Bekor qilindi', body: 'Buyurtmangiz bekor qilindi' },
    ru: { title: 'Заказ отменён', body: 'Ваш заказ был отменён' },
    en: { title: 'Order cancelled', body: 'Your order was cancelled' },
    kk: { title: 'Тапсырыс жойылды', body: 'Тапсырысыңыз жойылды' },
  },
  chat_message: {
    uz: { title: 'Yangi xabar', body: 'Buyurtma chatida yangi xabar' },
    ru: { title: 'Новое сообщение', body: 'Сообщение в чате заказа' },
    en: { title: 'New message', body: 'New message in order chat' },
    kk: { title: 'Курьерден хабарлама', body: 'Тапсырыс чатында жаңа хабарлама' },
  },
  promo: {
    uz: { title: 'Aksiya', body: 'Yangi aksiya siz uchun!' },
    ru: { title: 'Акция', body: 'Для вас новая акция!' },
    en: { title: 'Promo', body: 'A new offer for you!' },
    kk: { title: 'Жаңа акция', body: 'Сізге арналған жаңа акция!' },
  },
};

function pickLocale(locale) {
  if (locale === 'ru' || locale === 'en' || locale === 'uz' || locale === 'kk') return locale;
  return 'uz';
}

function templateFor(type, locale) {
  const bundle = T[type];
  if (!bundle) return { title: 'TezKetKaz', body: '' };
  return bundle[pickLocale(locale)] || bundle.uz;
}

// Map our Notification.type set into the canonical DB type bucket.
function dbTypeBucket(type) {
  if (type === 'chat_message') return 'chat';
  if (type === 'promo') return 'promo';
  if (type && type.startsWith('order_')) return 'order_update';
  return 'system';
}

/**
 * Send a transactional/event notification to a user.
 *
 * @param {object} prisma  Prisma client.
 * @param {object} io      socket.io server (or null in tests).
 * @param {object} args    { userId, type, orderId?, data? }
 *
 * Side effects:
 *   1. Insert Notification row (DB).
 *   2. Look up FcmToken for user, send via push.sendToUser().
 *   3. Emit `notification` to room `buyer:${userId}` (also `courier:${userId}`).
 */
async function sendOrderEvent(prisma, io, args) {
  const { userId, type, orderId = null, data = {} } = args || {};
  if (!userId || !type) throw new Error('userId and type required');

  // Resolve user locale & FCM tokens.
  let user = null;
  try {
    user = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, locale: true, notificationPrefs: true },
    });
  } catch (err) {
    logger.warn({ err: err.message, userId }, 'notif user lookup failed');
  }

  const tmpl = templateFor(type, user?.locale);
  const title = data.title || tmpl.title;
  const body = data.body || tmpl.body;

  // Respect notificationPrefs (best-effort; opt-out only for promo).
  let allowFcm = true;
  if (user?.notificationPrefs) {
    try {
      const prefs = JSON.parse(user.notificationPrefs);
      if (type === 'promo' && prefs.promo === false) allowFcm = false;
      if (type.startsWith('order_') && prefs.orderUpdates === false) allowFcm = false;
    } catch { /* ignore parse errors */ }
  }

  // 1. DB row.
  let notif = null;
  try {
    notif = await prisma.notification.create({
      data: {
        userId,
        title,
        body,
        type: dbTypeBucket(type),
        data: JSON.stringify({ ...data, orderId, kind: type }),
      },
    });
  } catch (err) {
    logger.warn({ err: err.message, userId, type }, 'notification row create failed');
  }

  // 2. FCM push.
  let fcmResult = { sent: 0 };
  if (allowFcm) {
    try {
      fcmResult = await push.sendToUser(userId, {
        title,
        body,
        data: { type, orderId: orderId || '', ...stringify(data) },
      });
    } catch (err) {
      logger.warn({ err: err.message, userId, type }, 'fcm sendToUser failed');
    }
  }

  // 3. Realtime socket emit (user's personal rooms).
  if (io && typeof io.to === 'function') {
    try {
      const payload = {
        id: notif?.id,
        type, orderId, title, body, data, createdAt: notif?.createdAt || new Date(),
      };
      io.to(`buyer:${userId}`).emit('notification', payload);
      io.to(`courier:${userId}`).emit('notification', payload);
    } catch (err) {
      logger.warn({ err: err.message }, 'notification socket emit failed');
    }
  }

  return { notification: notif, fcm: fcmResult };
}

function stringify(obj) {
  const out = {};
  if (!obj) return out;
  for (const [k, v] of Object.entries(obj)) {
    if (v == null) continue;
    out[k] = typeof v === 'string' ? v : JSON.stringify(v);
  }
  return out;
}

async function sendChat(prisma, io, args) {
  const { senderName, receiverId, orderId, text } = args || {};
  return sendOrderEvent(prisma, io, {
    userId: receiverId,
    type: 'chat_message',
    orderId,
    data: { senderName: senderName || '', preview: (text || '').slice(0, 80) },
  });
}

// Map order status → notification type. Returns null for transitions we don't notify on.
function statusToType(status) {
  switch (status) {
    case 'confirmed':         return 'order_confirmed';
    case 'collecting':        return 'order_confirmed';
    case 'courierAssigned':   return 'order_dispatched';
    case 'pickedUp':          return 'order_picked_up';
    case 'inDelivery':        return 'order_in_delivery';
    case 'delivered':         return 'order_delivered';
    case 'cancelled':         return 'order_cancelled';
    default:                  return null;
  }
}

module.exports = {
  sendOrderEvent,
  sendChat,
  statusToType,
  // exposed for tests / debugging
  _T: T,
  _templateFor: templateFor,
  _dbTypeBucket: dbTypeBucket,
};
