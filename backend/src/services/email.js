// Phase 7 — transactional email façade.
//
// Backed by Resend (https://resend.com). The SDK is *lazy-required* so tests
// run without it installed; missing API key or missing module both noop with
// a structured log line. Templates mirror the localised pattern in
// notifications.js (uz / ru / en / kk).
//
// Public API: send({ to, locale, template, data }) — fire and forget; never
// throws so callers can inline-await without a try/catch.

const env = require('../config/env');
const logger = require('../lib/logger');

// Simple {placeholder} interpolation — no escaping. Templates here are server
// owned; we don't accept user-controlled template strings.
function interpolate(str, data) {
  if (!str) return '';
  if (!data) return String(str);
  return String(str).replace(/\{(\w+)\}/g, (m, key) => {
    if (Object.prototype.hasOwnProperty.call(data, key) && data[key] != null) {
      return String(data[key]);
    }
    return m;
  });
}

const TEMPLATES = {
  order_confirmation: {
    uz: {
      subject: 'Buyurtmangiz qabul qilindi #{orderNumber}',
      body: '<p>Salom {name},</p><p>Buyurtmangiz #{orderNumber} qabul qilindi. Jami: {total} {currency}.</p><p>Rahmat!</p>',
    },
    ru: {
      subject: 'Заказ #{orderNumber} принят',
      body: '<p>Здравствуйте, {name}!</p><p>Ваш заказ #{orderNumber} принят. Сумма: {total} {currency}.</p><p>Спасибо!</p>',
    },
    en: {
      subject: 'Order #{orderNumber} confirmed',
      body: '<p>Hi {name},</p><p>Your order #{orderNumber} is confirmed. Total: {total} {currency}.</p><p>Thanks!</p>',
    },
    kk: {
      subject: 'Тапсырыс #{orderNumber} қабылданды',
      body: '<p>Сәлем, {name}!</p><p>Тапсырысыңыз #{orderNumber} қабылданды. Сома: {total} {currency}.</p><p>Рахмет!</p>',
    },
  },
  refund_processed: {
    uz: {
      subject: "Qaytarish bajarildi #{orderNumber}",
      body: '<p>Salom {name},</p><p>#{orderNumber} buyurtmangiz uchun {amount} {currency} qaytarildi.</p>',
    },
    ru: {
      subject: 'Возврат произведён #{orderNumber}',
      body: '<p>Здравствуйте, {name}!</p><p>Возврат {amount} {currency} по заказу #{orderNumber} выполнен.</p>',
    },
    en: {
      subject: 'Refund processed #{orderNumber}',
      body: '<p>Hi {name},</p><p>We refunded {amount} {currency} for order #{orderNumber}.</p>',
    },
    kk: {
      subject: 'Қайтару орындалды #{orderNumber}',
      body: '<p>Сәлем, {name}!</p><p>#{orderNumber} тапсырысы бойынша {amount} {currency} қайтарылды.</p>',
    },
  },
  membership_renewed: {
    uz: {
      subject: 'Obunangiz yangilandi',
      body: '<p>Salom {name},</p><p>Premium obunangiz muvaffaqiyatli yangilandi. Keyingi to‘lov: {nextBillingAt}.</p>',
    },
    ru: {
      subject: 'Подписка продлена',
      body: '<p>Здравствуйте, {name}!</p><p>Подписка Premium успешно продлена. Следующий платёж: {nextBillingAt}.</p>',
    },
    en: {
      subject: 'Membership renewed',
      body: '<p>Hi {name},</p><p>Your Premium membership renewed. Next charge: {nextBillingAt}.</p>',
    },
    kk: {
      subject: 'Жазылым жаңартылды',
      body: '<p>Сәлем, {name}!</p><p>Premium жазылымыңыз жаңартылды. Келесі төлем: {nextBillingAt}.</p>',
    },
  },
  membership_failed: {
    uz: {
      subject: 'Obuna to‘lovi muvaffaqiyatsiz',
      body: '<p>Salom {name},</p><p>Premium obunangiz uchun to‘lovni amalga oshira olmadik. Iltimos, kartani tekshiring.</p>',
    },
    ru: {
      subject: 'Не удалось списать оплату подписки',
      body: '<p>Здравствуйте, {name}!</p><p>Не удалось списать оплату Premium. Пожалуйста, проверьте карту.</p>',
    },
    en: {
      subject: 'Membership renewal failed',
      body: '<p>Hi {name},</p><p>We couldn’t charge your Premium membership. Please check your card.</p>',
    },
    kk: {
      subject: 'Жазылым төлемі сәтсіз',
      body: '<p>Сәлем, {name}!</p><p>Premium жазылым үшін төлемді ала алмадық. Картаны тексеріңіз.</p>',
    },
  },
};

const SUPPORTED_LOCALES = new Set(['uz', 'ru', 'en', 'kk']);

function pickLocale(locale) {
  if (locale && SUPPORTED_LOCALES.has(locale)) return locale;
  return 'uz';
}

/**
 * Send a transactional email.
 *
 * @param {object}   args
 * @param {string}   args.to          recipient email; if falsy → noop
 * @param {string}   [args.locale]    one of uz | ru | en | kk; falls back to uz
 * @param {string}   args.template    one of TEMPLATES keys
 * @param {object}   [args.data]      values interpolated into subject + body
 * @returns {Promise<{ skipped?: boolean, ok?: boolean, error?: string }>}
 */
async function send({ to, locale = 'uz', template, data = {} } = {}) {
  if (!to) return { skipped: true, reason: 'no_recipient' };
  const bundle = TEMPLATES[template];
  if (!bundle) return { skipped: true, reason: 'unknown_template' };
  const tpl = bundle[pickLocale(locale)] || bundle.uz;
  if (!tpl) return { skipped: true, reason: 'no_template_for_locale' };

  const subject = interpolate(tpl.subject, data);
  const body = interpolate(tpl.body, data);

  if (!env.RESEND_API_KEY) {
    logger.info({ to, subject, template, locale }, 'email noop (no RESEND_API_KEY)');
    return { skipped: true, reason: 'no_api_key' };
  }

  // Lazy-require — runs without `resend` installed (tests don't pull it in).
  let Resend;
  try {
    // eslint-disable-next-line global-require
    ({ Resend } = require('resend'));
  } catch (err) {
    logger.warn({ err: err.message }, 'email send failed: resend SDK not installed');
    return { skipped: true, reason: 'sdk_missing' };
  }

  try {
    const resend = new Resend(env.RESEND_API_KEY);
    await resend.emails.send({
      from: 'TezKetKaz <noreply@tezketkaz.uz>',
      to,
      subject,
      html: body,
    });
    return { ok: true };
  } catch (err) {
    logger.warn({ err: err.message, to, template }, 'email send failed');
    return { ok: false, error: err.message };
  }
}

module.exports = { send, TEMPLATES, interpolate, _pickLocale: pickLocale };
