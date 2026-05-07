// Eskiz.uz SMS gateway
// In production: replace with real Eskiz API. https://documenter.getpostman.com/view/663428/RzfmES4z

let eskizToken = null;

async function getEskizToken() {
  if (process.env.USE_MOCK_SMS === 'true') return null;
  if (eskizToken) return eskizToken;

  const res = await fetch('https://notify.eskiz.uz/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: process.env.ESKIZ_EMAIL,
      password: process.env.ESKIZ_PASSWORD,
    }),
  });
  const data = await res.json();
  eskizToken = data.data.token;
  return eskizToken;
}

async function sendSms(phone, text) {
  // Mock mode for development — log to console
  if (process.env.USE_MOCK_SMS === 'true') {
    console.log(`📱 [MOCK SMS] → ${phone}: ${text}`);
    return { success: true, mock: true };
  }

  try {
    const token = await getEskizToken();
    const res = await fetch('https://notify.eskiz.uz/api/message/sms/send', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        mobile_phone: phone.replace(/\D/g, ''),
        message: text,
        from: process.env.ESKIZ_FROM || '4546',
      }),
    });
    const data = await res.json();
    return { success: res.ok, data };
  } catch (err) {
    console.error('SMS error:', err);
    return { success: false, error: err.message };
  }
}

async function sendOtp(phone, code) {
  const text = `TezKetKaz: kodingiz ${code}. Hech kimga aytmang.`;
  return sendSms(phone, text);
}

module.exports = { sendSms, sendOtp };
