/**
 * Phase 14 — smoke test for the new B2B integration endpoints.
 *
 * 1. Sign up a shop manager
 * 2. Connect their account to the seeded shop
 * 3. Mint an API key
 * 4. Hit /api/v1/me with that key (proves auth works)
 * 5. POST /api/v1/products/upsert with two SKUs (proves catalog ingest)
 * 6. Repeat the upsert with one of those SKUs at a new price (proves
 *    idempotency — should be "updated" not "inserted")
 * 7. POST /api/v1/products/delete (proves soft-delete)
 * 8. GET the sync log (proves auditing wrote rows)
 */

const BASE = 'http://localhost:3000';
const SHOP_ID = '06e42590-e972-4808-ad1a-9ebbef03a9f5'; // Korzinka — Yunusobod
const PHONE = `+99895${String(Date.now()).slice(-7)}`;

async function api(method, path, body, token, contentTypeJson = true) {
  const headers = {};
  if (contentTypeJson) headers['content-type'] = 'application/json';
  if (token) headers.authorization = `Bearer ${token}`;
  const opts = { method, headers };
  if (body !== undefined && body !== null) opts.body = JSON.stringify(body);
  const r = await fetch(`${BASE}${path}`, opts);
  let json = null;
  const txt = await r.text();
  try { json = txt ? JSON.parse(txt) : null; } catch { json = { raw: txt }; }
  return { status: r.status, ok: r.ok, body: json };
}

function step(label, ok, detail) {
  console.log(`  ${ok ? '✅' : '❌'} ${label}${detail ? ' — ' + detail : ''}`);
}

(async () => {
  console.log('\n━━━ Phase 14 Integration API smoke ━━━\n');

  // 1. Sign up
  await api('POST', '/api/auth/send-otp', { phone: PHONE });
  const v = await api('POST', '/api/auth/verify-otp', { phone: PHONE, code: '123456' });
  if (!v.ok) { step('OTP auth', false, JSON.stringify(v.body)); process.exit(1); }
  const ownerToken = v.body.accessToken;
  step('OTP auth', true, `userId=${v.body.user.id.slice(0,8)}…`);

  // 2. Connect to shop
  const c = await api('POST', '/api/shops/connect', { shopId: SHOP_ID }, ownerToken);
  step('Connect to Korzinka', c.ok);

  // 3. Mint API key
  const k = await api('POST', '/api/shops/me/integration/api-key/rotate', null, ownerToken);
  if (!k.ok) { step('Rotate key', false, JSON.stringify(k.body)); process.exit(1); }
  const apiKey = k.body.apiKey;
  step('Rotate key', true, `apiKey=${apiKey.slice(0, 14)}… (len=${apiKey.length})`);

  // 4. /v1/me
  const me = await api('GET', '/api/v1/me', null, apiKey);
  step('GET /api/v1/me with API key', me.ok, `shop=${me.body?.shop?.name}`);

  // 5. Upsert two products
  const u1 = await api('POST', '/api/v1/products/upsert', {
    items: [
      {
        externalId: 'pos-001',
        name: 'Маргарита 30 см',
        nameUz: 'Margherita 30 sm',
        price: 60000,
        discountPrice: 48000,
        unit: 'шт',
        category: 'pizza',
        stock: 50,
        imageUrl: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400',
      },
      {
        externalId: 'pos-002',
        name: 'Пепперони 30 см',
        nameUz: 'Pepperoni 30 sm',
        price: 85000,
        unit: 'шт',
        category: 'pizza',
        stock: 40,
      },
    ],
  }, apiKey);
  step('Upsert 2 SKUs', u1.ok,
    `inserted=${u1.body?.inserted} updated=${u1.body?.updated} failed=${u1.body?.failed}`);

  // 6. Idempotent upsert (one same externalId, new price)
  const u2 = await api('POST', '/api/v1/products/upsert', {
    items: [
      {
        externalId: 'pos-001',
        name: 'Маргарита 30 см (-30%)',
        nameUz: 'Margherita 30 sm',
        price: 60000,
        discountPrice: 42000,
        unit: 'шт',
        category: 'pizza',
        stock: 45,
        imageUrl: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400',
      },
    ],
  }, apiKey);
  const wasUpdate = u2.body?.results?.[0]?.action === 'updated';
  step('Idempotent re-upsert hits update path', wasUpdate,
    `action=${u2.body?.results?.[0]?.action} (must be "updated")`);

  // 7. Soft delete
  const d = await api('POST', '/api/v1/products/delete',
    { externalIds: ['pos-002'] }, apiKey);
  step('Soft-delete (mark unavailable)', d.ok,
    `disabled=${d.body?.disabled}/${d.body?.requested}`);

  // 8. Sync log
  const log = await api('GET', '/api/shops/me/integration/log?limit=10', null, ownerToken);
  const kinds = (log.body?.events ?? []).map(e => e.kind).join(', ');
  step('Sync log has events', (log.body?.events ?? []).length >= 4, kinds);

  // 9. Invalid key
  const bad = await api('GET', '/api/v1/me', null, 'tz_live_DEFINITELY_WRONG');
  step('Invalid API key → 401', bad.status === 401, `status=${bad.status}`);

  // 10. Webhook register
  const wh = await api('POST', '/api/shops/me/integration/webhook',
    { url: 'https://example.com/hooks/tz', events: 'order.created,order.delivered' },
    ownerToken);
  step('Register webhook', wh.ok, `secret=${wh.body?.webhookSecret?.slice(0,12)}…`);

  console.log('\n  Done.\n');
  process.exit(0);
})();
