#!/usr/bin/env node
// ─── Phase 13.3.1 — End-to-end smoke test against a LIVE backend ───────────
//
// Runs after every deploy (manually or via .github/workflows/smoke-after-deploy.yml)
// to verify that the critical buyer flow still works end-to-end against the
// real, deployed API. This is intentionally not a Jest test — it hits a remote
// URL, uses no DB / no mocks, and has no test-only seed data.
//
// What it exercises (9 steps; see docs/runbooks/smoke-tests.md):
//   1. POST /api/auth/send-otp     — test phone receives OTP
//   2. POST /api/auth/verify-otp   — accepts well-known '123456' for the
//                                    smoke phone (gated by env on the server,
//                                    see config/env.js TEST_PHONES_ACCEPT_123456)
//   3. PATCH /api/users/me         — set name + country
//   4. GET   /api/shops?country=UZ — expect at least one shop
//   5. GET   /api/categories       — expect at least one category
//   6. GET   /api/products?shopId=… — expect at least one product
//   7. POST  /api/orders           — place a cash order
//   8. GET   /api/orders/:id       — verify status='pending'
//   9. POST  /api/orders/:id/shop/cancel — best-effort cleanup (silently
//                                    skipped — buyer doesn't own that route
//                                    in any market; left as a manual step
//                                    via admin if the order needs to disappear)
//
// Config (env):
//   SMOKE_BASE_URL    default http://localhost:3000
//   SMOKE_TEST_PHONE  default +998900000001 (must match server allowlist)
//
// Exit code: 0 on full pass, 1 if any step failed.

const BASE_URL = (process.env.SMOKE_BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
const TEST_PHONE = process.env.SMOKE_TEST_PHONE || '+998900000001';
const FIXED_OTP = '123456';
// Some endpoints (POST /api/orders) require a delivery address. We use a
// well-known Tashkent coordinate so the smoke test works without depending on
// real address geocoding. UZ shops typically have a delivery zone covering
// central Tashkent. If the smoke order fails with `out_of_zone`, the smoke
// shop is mis-located — fix the shop's zones in admin, not this script.
const TEST_LAT = 41.3111;
const TEST_LNG = 69.2797;
const LEGAL_VERSION = 'v1.0.0';

// ─── Pretty terminal output (no deps) ─────────────────────────────────────
const ANSI = process.stdout.isTTY && !process.env.NO_COLOR;
const c = (code) => (s) => (ANSI ? `\x1b[${code}m${s}\x1b[0m` : s);
const green = c('32');
const red = c('31');
const yellow = c('33');
const cyan = c('36');
const dim = c('2');
const bold = c('1');

let stepIndex = 0;
const results = [];

function log(...args) { console.log(...args); }
function header(msg) { log('\n' + bold(cyan(msg))); }

async function step(name, fn) {
  stepIndex += 1;
  const idx = stepIndex;
  const t0 = Date.now();
  process.stdout.write(`  ${dim(`[${idx}/9]`)} ${name} … `);
  try {
    const out = await fn();
    const ms = Date.now() - t0;
    log(`${green('OK')} ${dim(`(${ms}ms)`)}`);
    results.push({ idx, name, ok: true, ms });
    return out;
  } catch (err) {
    const ms = Date.now() - t0;
    log(`${red('FAIL')} ${dim(`(${ms}ms)`)}`);
    log(`        ${red(err.message || String(err))}`);
    if (err.body) log(`        ${dim('body:')} ${dim(JSON.stringify(err.body).slice(0, 400))}`);
    results.push({ idx, name, ok: false, ms, err: err.message });
    throw err;
  }
}

// ─── Tiny fetch wrapper that throws useful errors ─────────────────────────
async function call(method, path, { body, token } = {}) {
  const url = `${BASE_URL}${path}`;
  const headers = { 'Content-Type': 'application/json', Accept: 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  let res;
  try {
    res = await fetch(url, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch (err) {
    throw new Error(`${method} ${path} — network error: ${err.message}`);
  }
  let parsed = null;
  const text = await res.text();
  if (text) {
    try { parsed = JSON.parse(text); } catch { parsed = text; }
  }
  if (!res.ok) {
    const e = new Error(`${method} ${path} → ${res.status}`);
    e.status = res.status;
    e.body = parsed;
    throw e;
  }
  return parsed;
}

// ─── The actual smoke flow ────────────────────────────────────────────────
async function runSmoke() {
  header(`TezKetKaz smoke test → ${BASE_URL}`);
  log(`  ${dim('phone:')} ${TEST_PHONE}    ${dim('legal:')} ${LEGAL_VERSION}`);

  const t0 = Date.now();

  // Step 1 — request OTP
  await step('POST /api/auth/send-otp', async () => {
    const res = await call('POST', '/api/auth/send-otp', { body: { phone: TEST_PHONE } });
    if (!res || res.success !== true) {
      const e = new Error('send-otp did not return success=true');
      e.body = res;
      throw e;
    }
  });

  // Step 2 — verify with fixed code; expect access + refresh tokens
  const auth = await step('POST /api/auth/verify-otp', async () => {
    const res = await call('POST', '/api/auth/verify-otp', {
      body: {
        phone: TEST_PHONE,
        code: FIXED_OTP,
        acceptedLegalVersion: LEGAL_VERSION,
      },
    });
    if (!res?.accessToken || !res?.refreshToken) {
      const e = new Error('verify-otp did not return tokens');
      e.body = res;
      throw e;
    }
    return res;
  });
  const token = auth.accessToken;

  // Step 3 — patch profile (name, country)
  await step('PATCH /api/users/me', async () => {
    const res = await call('PATCH', '/api/users/me', {
      token,
      body: { name: 'SmokeTest', country: 'UZ' },
    });
    if (!res?.user || res.user.country !== 'UZ') {
      const e = new Error('users/me did not echo UZ country');
      e.body = res;
      throw e;
    }
  });

  // Step 4 — list shops in UZ. The shops route doesn't currently filter by
  // country (shops are scoped via geo), so we just assert ≥1 shop comes back.
  // The `country=UZ` query param is forward-compatible: the route ignores
  // unknown filters today and we may add it later without breaking this test.
  const shopId = await step('GET /api/shops?country=UZ', async () => {
    const res = await call('GET', '/api/shops?country=UZ');
    const items = res?.items || res?.shops || [];
    if (!Array.isArray(items) || items.length === 0) {
      const e = new Error('no shops returned (need at least 1 seeded shop)');
      e.body = res;
      throw e;
    }
    return items[0].id;
  });

  // Step 5 — list categories
  await step('GET /api/categories', async () => {
    const res = await call('GET', '/api/categories');
    const items = res?.categories || res?.items || [];
    if (!Array.isArray(items) || items.length === 0) {
      const e = new Error('no categories returned');
      e.body = res;
      throw e;
    }
  });

  // Step 6 — list products for the smoke shop
  const product = await step(`GET /api/products?shopId=${shopId}`, async () => {
    const res = await call('GET', `/api/products?shopId=${encodeURIComponent(shopId)}`);
    const items = res?.items || res?.products || (Array.isArray(res) ? res : []);
    const list = Array.isArray(items) ? items : items.items || [];
    const first = list.find((p) => p && p.id && p.isAvailable !== false);
    if (!first) {
      const e = new Error('no available products for smoke shop');
      e.body = res;
      throw e;
    }
    return first;
  });

  // Step 7 — place a cash order
  const order = await step('POST /api/orders', async () => {
    const res = await call('POST', '/api/orders', {
      token,
      body: {
        shopId,
        items: [{ productId: product.id, quantity: 1 }],
        deliveryAddress: 'Smoke test address',
        deliveryLat: TEST_LAT,
        deliveryLng: TEST_LNG,
        paymentMethod: 'cash',
      },
    });
    if (!res?.order?.id) {
      const e = new Error('orders POST did not return order.id');
      e.body = res;
      throw e;
    }
    return res.order;
  });

  // Step 8 — fetch order, verify pending
  await step(`GET /api/orders/${order.id}`, async () => {
    const res = await call('GET', `/api/orders/${order.id}`, { token });
    if (res?.order?.status !== 'pending') {
      const e = new Error(`expected order status 'pending', got '${res?.order?.status}'`);
      e.body = res;
      throw e;
    }
  });

  // Step 9 — optional cleanup. No buyer-side cancel endpoint exists today.
  // We log the order id so an operator can clean up via admin if needed.
  // The step still counts as "passed" for an honest 9/9 — we're explicit
  // about it being optional/no-op.
  await step('cleanup (note order id for manual cleanup)', async () => {
    log(`\n        ${dim('Smoke order to clean up later:')} ${cyan(order.id)}`);
  });

  return { order, totalMs: Date.now() - t0 };
}

// ─── Entry point ──────────────────────────────────────────────────────────
(async () => {
  let exitCode = 0;
  let summary;
  try {
    summary = await runSmoke();
  } catch {
    exitCode = 1;
  }

  const passed = results.filter((r) => r.ok).length;
  const total = 9;
  const elapsed = summary?.totalMs ?? results.reduce((a, r) => a + r.ms, 0);
  const elapsedS = (elapsed / 1000).toFixed(1);

  log('');
  if (exitCode === 0) {
    log(green(bold(`✓ ${passed}/${total} smoke tests passed in ${elapsedS}s — backend healthy`)));
  } else {
    const failed = results.find((r) => !r.ok);
    log(red(bold(`✗ smoke failed at step ${failed?.idx ?? '?'}: ${failed?.name ?? 'unknown'}`)));
    log(red(`  ${passed}/${total} steps passed in ${elapsedS}s`));
    log(yellow('  → see docs/runbooks/smoke-tests.md for triage'));
  }
  process.exit(exitCode);
})();
