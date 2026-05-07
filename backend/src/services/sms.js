// Eskiz.uz SMS gateway
// Docs: https://documenter.getpostman.com/view/663428/RzfmES4z

const env = require('../config/env');
const logger = require('../lib/logger');

let eskizToken = null;
let eskizTokenExpiresAt = 0;

async function getEskizToken() {
  if (env.useMockSms) return null;
  if (eskizToken && Date.now() < eskizTokenExpiresAt) return eskizToken;

  const res = await fetch('https://notify.eskiz.uz/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: env.ESKIZ_EMAIL,
      password: env.ESKIZ_PASSWORD,
    }),
  });
  if (!res.ok) throw new Error(`Eskiz auth failed: ${res.status}`);
  const data = await res.json();
  eskizToken = data?.data?.token;
  // Eskiz tokens last 30 days; cache for 25 days to be safe.
  eskizTokenExpiresAt = Date.now() + 25 * 24 * 60 * 60 * 1000;
  return eskizToken;
}

async function sendSms(phone, text) {
  if (env.useMockSms) {
    logger.info({ phone, text }, 'mock sms');
    return { success: true, mock: true };
  }
  try {
    const token = await getEskizToken();
    const res = await fetch('https://notify.eskiz.uz/api/message/sms/send', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        mobile_phone: phone.replace(/\D/g, ''),
        message: text,
        from: env.ESKIZ_FROM,
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) logger.warn({ status: res.status, data }, 'eskiz send failed');
    return { success: res.ok, data };
  } catch (err) {
    logger.error({ err: err.message }, 'sms send error');
    return { success: false, error: err.message };
  }
}

async function sendOtp(phone, code) {
  // Eskiz template — must be pre-approved by Eskiz before production.
  const text = `TezKetKaz: kodingiz ${code}. Hech kimga aytmang.`;
  return sendSms(phone, text);
}

module.exports = { sendSms, sendOtp };
