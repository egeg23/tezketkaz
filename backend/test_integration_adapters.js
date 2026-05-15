/**
 * Phase 14 wave 2 — smoke test for provider connectors.
 *
 * Three providers, three scenarios:
 *   • custom_rest — uses a tiny local echo server so the test is hermetic
 *   • iiko        — mock mode (MOCK_IIKO defaults to on)
 *   • poster      — mock mode (MOCK_POSTER defaults to on)
 */

const http = require('http');

const BASE = 'http://localhost:3000';
const SHOP_ID = '06e42590-e972-4808-ad1a-9ebbef03a9f5';
const PHONE = `+99896${String(Date.now()).slice(-7)}`;

async function api(method, path, body, token) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const opts = { method, headers };
  if (body !== undefined && body !== null) opts.body = JSON.stringify(body);
  const r = await fetch(`${BASE}${path}`, opts);
  const txt = await r.text();
  let json = null;
  try { json = txt ? JSON.parse(txt) : null; } catch { json = { raw: txt }; }
  return { status: r.status, ok: r.ok, body: json };
}

function step(label, ok, detail) {
  console.log(`  ${ok ? '✅' : '❌'} ${label}${detail ? ' — ' + detail : ''}`);
}

// Local fake POS — exposes a `/menu` GET returning two products + a noop
// `/orders` POST. Runs on a random free port and is torn down at exit.
function startFakePos() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      // Auth header check — basic sanity that our adapter sends what we configured.
      const auth = req.headers.authorization || '';
      if (!auth.startsWith('Bearer test-token-123')) {
        res.writeHead(401, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ error: 'unauthorized', got: auth.slice(0, 30) }));
        return;
      }
      if (req.method === 'GET' && req.url.startsWith('/menu')) {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({
          items: [
            {
              externalId: 'fake-001',
              name: 'Тестовая пицца',
              nameUz: 'Test pitsa',
              price: 50000,
              unit: 'шт',
              category: 'pizza',
              stock: 10,
              isAvailable: true,
            },
            {
              externalId: 'fake-002',
              name: 'Тестовый бургер',
              nameUz: 'Test burger',
              price: 35000,
              unit: 'шт',
              category: 'burger',
              stock: 25,
              isAvailable: true,
            },
          ],
        }));
        return;
      }
      if (req.method === 'POST' && req.url === '/orders') {
        let chunks = '';
        req.on('data', (c) => (chunks += c));
        req.on('end', () => {
          res.writeHead(201, { 'content-type': 'application/json' });
          res.end(JSON.stringify({ accepted: true, len: chunks.length }));
        });
        return;
      }
      res.writeHead(404);
      res.end();
    });
    server.listen(0, '127.0.0.1', () => {
      resolve({ port: server.address().port, close: () => server.close() });
    });
  });
}

(async () => {
  console.log('\n━━━ Phase 14 wave 2 — Adapter smoke ━━━\n');

  const fake = await startFakePos();
  console.log(`  (fake POS listening on http://127.0.0.1:${fake.port})\n`);

  // ─── auth ──────────────────────────────────────────────────────────────
  await api('POST', '/api/auth/send-otp', { phone: PHONE });
  const v = await api('POST', '/api/auth/verify-otp', { phone: PHONE, code: '123456' });
  if (!v.ok) { step('auth', false, JSON.stringify(v.body)); process.exit(1); }
  const tok = v.body.accessToken;
  step('auth', true);

  const c = await api('POST', '/api/shops/connect', { shopId: SHOP_ID }, tok);
  step('connect shop', c.ok);

  // ─── registry ──────────────────────────────────────────────────────────
  const reg = await api('GET', '/api/shops/me/integrations/providers', null, tok);
  const providerIds = (reg.body?.providers || []).map(p => p.id);
  step('GET providers', reg.ok && providerIds.length === 3,
    `providers=${providerIds.join(',')}`);

  // ─── 1. Custom REST ────────────────────────────────────────────────────
  const cust = await api('POST', '/api/shops/me/integrations', {
    provider: 'custom_rest',
    creds: {
      baseUrl: `http://127.0.0.1:${fake.port}`,
      authHeader: 'Authorization',
      authValue: 'Bearer test-token-123',
      menuPath: '/menu',
      orderPath: '/orders',
    },
  }, tok);
  step('install custom_rest', cust.ok && cust.body?.test?.ok,
    `test=${cust.body?.test?.message}`);

  const custId = cust.body?.integration?.id;
  const syncCust = await api('POST', `/api/shops/me/integrations/${custId}/sync-now`, null, tok);
  step('custom_rest sync-now',
    syncCust.ok && syncCust.body?.result?.fetched === 2,
    `${syncCust.body?.result?.message || syncCust.body?.error}`);

  // ─── 2. iiko (mock) ────────────────────────────────────────────────────
  const iko = await api('POST', '/api/shops/me/integrations', {
    provider: 'iiko',
    creds: {
      apiLogin: 'mock-iiko-login-abc-def',
      organizationId: '7c2b1e5a-aaaa-bbbb-cccc-1234567890ab',
      terminalGroup: 'main-terminal',
    },
  }, tok);
  step('install iiko (mock)', iko.ok && iko.body?.test?.ok, iko.body?.test?.message);

  const ikoId = iko.body?.integration?.id;
  const syncIko = await api('POST', `/api/shops/me/integrations/${ikoId}/sync-now`, null, tok);
  step('iiko sync-now (mock)',
    syncIko.ok && syncIko.body?.result?.fetched === 3,
    syncIko.body?.result?.message);

  // ─── 3. Poster (mock) ──────────────────────────────────────────────────
  const pst = await api('POST', '/api/shops/me/integrations', {
    provider: 'poster',
    creds: { token: 'mock-poster-token-xyz', accountId: 'demo-cafe' },
  }, tok);
  step('install poster (mock)', pst.ok && pst.body?.test?.ok, pst.body?.test?.message);

  const pstId = pst.body?.integration?.id;
  const syncPst = await api('POST', `/api/shops/me/integrations/${pstId}/sync-now`, null, tok);
  step('poster sync-now (mock)',
    syncPst.ok && syncPst.body?.result?.fetched === 2,
    syncPst.body?.result?.message);

  // ─── list, test, patch toggles, delete ─────────────────────────────────
  const list = await api('GET', '/api/shops/me/integrations', null, tok);
  step('list installed', list.ok && list.body?.integrations?.length === 3,
    `count=${list.body?.integrations?.length}`);

  const reTest = await api('POST', `/api/shops/me/integrations/${custId}/test`, null, tok);
  step('re-test custom_rest', reTest.ok && reTest.body?.test?.ok);

  const patch = await api('PATCH', `/api/shops/me/integrations/${custId}`,
    { syncMenu: false, syncOrders: true }, tok);
  step('PATCH toggles',
    patch.ok && patch.body?.integration?.syncMenu === false,
    `syncMenu=${patch.body?.integration?.syncMenu}, syncOrders=${patch.body?.integration?.syncOrders}`);

  // syncMenu=false should now block sync-now with 400
  const blocked = await api('POST', `/api/shops/me/integrations/${custId}/sync-now`, null, tok);
  step('sync-now blocked when toggle off',
    blocked.status === 400 && blocked.body?.error === 'menu_sync_disabled',
    `status=${blocked.status} err=${blocked.body?.error}`);

  const del = await api('DELETE', `/api/shops/me/integrations/${pstId}`, null, tok);
  step('disconnect poster', del.ok);

  // ─── invalid creds ─────────────────────────────────────────────────────
  const bad = await api('POST', '/api/shops/me/integrations', {
    provider: 'custom_rest',
    creds: { baseUrl: '', authHeader: 'X', authValue: 'X' }, // baseUrl missing
  }, tok);
  step('invalid creds rejected',
    bad.status === 400 && bad.body?.error === 'field_required',
    `field=${bad.body?.field}`);

  // ─── log ───────────────────────────────────────────────────────────────
  const log = await api('GET', '/api/shops/me/integration/log?limit=20', null, tok);
  const kinds = [...new Set((log.body?.events || []).map((e) => e.kind))];
  step('sync log captured everything',
    kinds.some(k => k.includes('menu.synced')) && kinds.includes('integration.connected'),
    `kinds=${kinds.join(',')}`);

  console.log('\n  Done.\n');
  fake.close();
  process.exit(0);
})();
