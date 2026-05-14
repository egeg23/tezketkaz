/**
 * End-to-end harness for TezKetKaz.
 *
 * Drives the live backend on localhost:3000 through the same REST contract
 * the Flutter clients use. Three personas + scenarios + edge cases.
 *
 * Usage:  node backend/test_e2e_full.js
 */

const BASE = process.env.API_BASE || 'http://localhost:3000';
const SHOP_ID = '06e42590-e972-4808-ad1a-9ebbef03a9f5'; // Korzinka — Yunusobod

// Unique per-run phone suffixes — avoids OTP-rate-limit collisions between runs.
const RUN_TAG = String(Date.now()).slice(-7);
const PHONES = {
  buyer:   `+99890${RUN_TAG}`,
  shop:    `+99891${RUN_TAG}`,
  courier: `+99893${RUN_TAG}`,
};

// ─── Report aggregator ────────────────────────────────────────────────────────
const report = {
  startedAt: new Date().toISOString(),
  finishedAt: null,
  scenarios: [],
};
let currentScenario = null;
function scenario(name) {
  currentScenario = { name, steps: [], status: 'running', startedAt: new Date().toISOString() };
  report.scenarios.push(currentScenario);
  console.log(`\n━━━ ${name} ━━━`);
}
function step(label, ok, detail) {
  const mark = ok ? '✅' : '❌';
  console.log(`  ${mark} ${label}${detail ? ` — ${detail}` : ''}`);
  currentScenario.steps.push({ label, ok, detail, at: new Date().toISOString() });
  if (!ok) currentScenario.status = 'failed';
}
function endScenario() {
  if (currentScenario.status === 'running') currentScenario.status = 'passed';
  currentScenario.finishedAt = new Date().toISOString();
}

// ─── HTTP helper ──────────────────────────────────────────────────────────────
async function api(method, path, body, token) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const opts = { method, headers };
  if (body !== undefined && body !== null) opts.body = JSON.stringify(body);
  const r = await fetch(`${BASE}${path}`, opts);
  let json = null;
  const text = await r.text();
  try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text }; }
  return { status: r.status, ok: r.ok, body: json };
}

// ─── Auth helper ──────────────────────────────────────────────────────────────
async function authenticate(phone, label) {
  const send = await api('POST', '/api/auth/send-otp', { phone });
  if (!send.ok) throw new Error(`${label} send-otp failed: ${JSON.stringify(send.body)}`);
  const code = send.body.devCode || '123456';
  const verify = await api('POST', '/api/auth/verify-otp', { phone, code });
  if (!verify.ok) throw new Error(`${label} verify-otp failed: ${JSON.stringify(verify.body)}`);
  return { token: verify.body.accessToken, refresh: verify.body.refreshToken, user: verify.body.user };
}

// ─── Utility ──────────────────────────────────────────────────────────────────
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const fmt = (v) => typeof v === 'number' ? v.toLocaleString('ru-RU') : v;

// ─── Shared context ──────────────────────────────────────────────────────────
const ctx = {};

// ════════════════════════════════════════════════════════════════════════════
// SCENARIO A — BUYER HAPPY PATH
// ════════════════════════════════════════════════════════════════════════════
async function scenarioBuyer() {
  scenario('Scenario A — Покупатель: регистрация → заказ → оплата');

  // 1. Sign up
  const auth = await authenticate(PHONES.buyer, 'buyer');
  ctx.buyer = auth;
  step('Регистрация по SMS (OTP 123456)', true, `userId=${auth.user.id.slice(0, 8)}…`);

  // 2. Set name
  let r = await api('PATCH', '/api/users/me', { name: 'Асаль Каримова' }, auth.token);
  step('PATCH /users/me (имя)', r.ok, `name=${r.body?.user?.name}`);

  // 3. Add delivery address — coords ~600m from Korzinka (Yunusobod) so we
  // pass the zone check; the printed label can still say Chilanzar.
  r = await api('POST', '/api/users/addresses', {
    label: 'Дом',
    fullAddress: 'Ташкент, Юнусабад, 13-й кв., дом 28, кв. 42',
    lat: 41.3650,
    lng: 69.2910,
    isDefault: true,
    apartment: '42',
    entrance: '1',
    floor: '3',
    intercom: '142',
  }, auth.token);
  step('POST /users/me/addresses', r.ok, `addressId=${r.body?.address?.id?.slice(0, 8)}…`);
  ctx.address = r.body?.address;

  // 4. Browse shops
  r = await api('GET', '/api/shops', null, auth.token);
  const shopsCount = r.body?.items?.length || 0;
  step('GET /shops (рядом)', r.ok && shopsCount > 0, `${shopsCount} магазинов`);

  // 5. Get products
  r = await api('GET', `/api/products?shopId=${SHOP_ID}&limit=5`, null, auth.token);
  const products = r.body?.items || [];
  step('GET /products?shopId=…', r.ok && products.length >= 2, `${products.length} товаров`);

  // 6. Pick 2 items
  const pick = products.slice(0, 2);
  const items = pick.map((p) => ({ productId: p.id, quantity: 2 }));
  const itemsSubtotal = pick.reduce((s, p) => s + (p.discountPrice ?? p.price) * 2, 0);

  // 7. Estimate with coordinates — exercises the polygon+fee math now that the
  // Korzinka shop has a Tashkent-wide DeliveryZone seeded.
  r = await api('POST', '/api/orders/estimate', {
    shopId: SHOP_ID,
    items,
    address: { lat: ctx.address.lat, lng: ctx.address.lng },
  }, auth.token);
  step('POST /orders/estimate', r.ok,
    `subtotal=${fmt(r.body?.subtotal)} fee=${fmt(r.body?.deliveryFee)} ` +
    `dist=${r.body?.distanceKm} км total=${fmt(r.body?.total)}`);
  ctx.estimate = r.body;

  // 8. Place order with full coords — runs through computeDelivery + the
  // newly-seeded zone to assemble the real fee.
  r = await api('POST', '/api/orders', {
    shopId: SHOP_ID,
    items,
    deliveryAddress: ctx.address.fullAddress,
    deliveryLat: ctx.address.lat,
    deliveryLng: ctx.address.lng,
    paymentMethod: 'cash',
    customerComment: 'Не звонить, оставить у двери',
  }, auth.token);
  step('POST /orders (cash)', r.ok, `orderId=${r.body?.order?.id?.slice(0, 8)}… status=${r.body?.order?.status}`);
  if (!r.ok) throw new Error('Order creation failed: ' + JSON.stringify(r.body));
  ctx.order = r.body.order;

  // 9. Verify in /mine
  r = await api('GET', '/api/orders/mine', null, auth.token);
  const found = (r.body?.orders || []).find(o => o.id === ctx.order.id);
  step('GET /orders/mine видит новый заказ', !!found, `status=${found?.status} fee=${fmt(found?.deliveryFee)}`);

  endScenario();
}

// ════════════════════════════════════════════════════════════════════════════
// SCENARIO B — RESTAURANT OPS
// ════════════════════════════════════════════════════════════════════════════
async function scenarioShop() {
  scenario('Scenario B — Ресторан: подтверждение → сборка → готов');

  // 1. Auth as shop manager
  const auth = await authenticate(PHONES.shop, 'shop');
  ctx.shop = auth;
  step('Регистрация менеджера магазина', true, `userId=${auth.user.id.slice(0, 8)}…`);

  // 2. Connect to shop
  let r = await api('POST', '/api/shops/connect', { shopId: SHOP_ID }, auth.token);
  step('POST /shops/connect (Korzinka)', r.ok, 'shop role granted');

  // 3. Re-fetch profile to confirm role
  r = await api('GET', '/api/auth/me', null, auth.token);
  step('isShop=true в /auth/me', r.body?.user?.isShop === true, `привязок к магазинам=${r.body?.user?.shops?.length}`);

  // 4. See incoming order
  r = await api('GET', `/api/orders/shop/${SHOP_ID}`, null, auth.token);
  const pending = (r.body?.orders || []).filter(o => o.status === 'pending');
  step('GET /orders/shop видит pending', pending.length > 0, `${pending.length} pending заказов`);

  // 5. Accept order
  r = await api('POST', `/api/orders/${ctx.order.id}/shop/accept`, {}, auth.token);
  step('Accept (pending → collecting)', r.ok, `status=${r.body?.order?.status}, № ${r.body?.order?.orderNumber}`);
  ctx.order = r.body.order;

  // 6. Mark ready
  await sleep(150);
  r = await api('POST', `/api/orders/${ctx.order.id}/shop/ready`, {}, auth.token);
  step('Ready (collecting → readyForPickup)', r.ok, `status=${r.body?.order?.status}`);
  ctx.order = r.body.order;

  // 7. Dashboard turnover check
  r = await api('GET', `/api/orders/shop/${SHOP_ID}`, null, auth.token);
  const today = (r.body?.orders || []).filter(o => {
    const d = new Date(o.createdAt);
    return d.toDateString() === new Date().toDateString();
  });
  const turnover = today.reduce((s, o) => s + (o.total || 0), 0);
  step('Сегодняшний оборот растёт', today.length > 0, `${today.length} заказов · ${fmt(turnover)} сум`);

  endScenario();
}

// ════════════════════════════════════════════════════════════════════════════
// SCENARIO C — COURIER FULL LIFECYCLE
// ════════════════════════════════════════════════════════════════════════════
async function scenarioCourier() {
  scenario('Scenario C — Курьер: верификация → доставка → выплата');

  // 1. Sign up
  const auth = await authenticate(PHONES.courier, 'courier');
  ctx.courier = auth;
  step('Регистрация курьера', true, `userId=${auth.user.id.slice(0, 8)}…`);

  // 2. Apply
  let r = await api('POST', '/api/couriers/apply', {
    fullName: 'Бобур Алиев',
    stir: '123456789',
    passportSeries: 'AA1234567',
  }, auth.token);
  step('POST /couriers/apply', r.ok, `status=${r.body?.user?.courierStatus}`);

  // 3. Approve (dev-only shortcut)
  r = await api('POST', '/api/couriers/me/approve', {}, auth.token);
  step('POST /couriers/me/approve (dev)', r.ok, `status=${r.body?.user?.courierStatus}`);

  // 4. Verify courier role active (token re-uses DB-live role check)
  r = await api('GET', '/api/auth/me', null, ctx.courier.token);
  step('isCourier=true в /auth/me', r.body?.user?.isCourier === true, `courierStatus=${r.body?.user?.courierStatus}`);

  // 5. See available orders (must include our shop's readyForPickup)
  r = await api('GET', '/api/orders/courier/available', null, ctx.courier.token);
  const avail = (r.body?.orders || []);
  const ours = avail.find(o => o.id === ctx.order.id);
  step('GET /courier/available содержит наш заказ', !!ours, `всего ${avail.length} офферов`);

  // 6. Accept order
  r = await api('POST', `/api/orders/${ctx.order.id}/courier/accept`, {}, ctx.courier.token);
  step('Accept (→ courierAssigned)', r.ok, `status=${r.body?.order?.status}`);
  ctx.order = r.body.order;

  // 7. Send GPS pings
  for (let i = 0; i < 3; i++) {
    const r2 = await api('POST', '/api/couriers/location', {
      orderId: ctx.order.id,
      lat: 41.3617 + i * 0.001,
      lng: 69.2877 + i * 0.001,
    }, ctx.courier.token);
    if (!r2.ok) step(`GPS ping ${i+1}/3`, false, JSON.stringify(r2.body));
    await sleep(80);
  }
  step('Отправил 3 GPS-точки', true);

  // 8. Pickup (must match orderNumber printed at /shop/accept)
  r = await api('POST', `/api/orders/${ctx.order.id}/courier/pickup`, {
    orderNumber: ctx.order.orderNumber,
  }, ctx.courier.token);
  step('Pickup (→ pickedUp)', r.ok, `status=${r.body?.order?.status}`);

  // 9. Start delivery
  r = await api('POST', `/api/orders/${ctx.order.id}/courier/start`, {}, ctx.courier.token);
  step('Start (→ inDelivery)', r.ok, `status=${r.body?.order?.status}`);

  // 10. Arrived
  r = await api('POST', `/api/orders/${ctx.order.id}/courier/arrived`, {}, ctx.courier.token);
  step('Arrived (→ arrivedAtCustomer)', r.ok, `status=${r.body?.order?.status}`);

  // 11. Complete
  r = await api('POST', `/api/orders/${ctx.order.id}/courier/complete`, {}, ctx.courier.token);
  step('Complete (→ delivered)', r.ok, `status=${r.body?.order?.status}`);
  ctx.order = r.body.order;

  // 12. (Optional) Buyer leaves reviews — must happen while status === 'delivered'
  //     (before they tap "I received the order"). This mirrors the UX in
  //     orders_screen.dart where the "Оценить заказ" CTA only shows for delivered.
  for (const r of [
    { targetType: 'SHOP',    targetId: ctx.order.shopId,    rating: 5, text: 'Очень вкусно' },
    { targetType: 'COURIER', targetId: ctx.order.courierId, rating: 5, text: 'Быстро и вежливо' },
  ]) {
    const resp = await api('POST', `/api/orders/${ctx.order.id}/reviews`, r, ctx.buyer.token);
    step(`Отзыв ${r.targetType}`, resp.ok || resp.body?.error === 'Already reviewed',
      resp.ok ? `rating=${resp.body?.review?.rating}` : resp.body?.error);
  }

  // 13. Buyer confirms receipt
  r = await api('POST', `/api/orders/${ctx.order.id}/buyer/confirm`, {}, ctx.buyer.token);
  step('Buyer confirm (→ confirmedByBuyer)', r.ok, `status=${r.body?.order?.status}`);

  // 14. Check earnings
  r = await api('GET', '/api/couriers/me/earnings', null, ctx.courier.token);
  step('GET /couriers/me/earnings', r.ok, `сегодня ${r.body?.todayOrdersCount} зак., доход ${fmt(r.body?.todayEarnings)}, мес ${fmt(r.body?.monthEarnings)}`);

  // 14. Check available balance (instant payout)
  r = await api('GET', '/api/couriers/me/balance', null, ctx.courier.token);
  step('GET /couriers/me/balance', r.ok, `доступно=${fmt(r.body?.availableBalance)} мин=${fmt(r.body?.minPayout)}`);

  // 15. Request payout if balance >= min
  if (r.body?.availableBalance >= (r.body?.minPayout || 0)) {
    const r2 = await api('POST', '/api/couriers/me/payout/request', {}, ctx.courier.token);
    step('POST /payout/request', r2.ok, r2.ok ? `payoutId=${r2.body?.payout?.id?.slice(0, 8)}… net=${fmt(r2.body?.payout?.netAmount)}` : r2.body?.reason);
  } else {
    step('Payout пропущен (< минимума)', true, 'ожидаемо — 1 заказ обычно ниже минимума');
  }

  endScenario();
}

// ════════════════════════════════════════════════════════════════════════════
// EDGE 1 — LOYALTY ACCRUAL AFTER DELIVERY
// ════════════════════════════════════════════════════════════════════════════
async function edgeLoyalty() {
  scenario('Edge 1 — Начисление лояльности после доставки');

  // Loyalty status (should reflect points credited at delivery)
  let r = await api('GET', '/api/loyalty/me', null, ctx.buyer.token);
  step('GET /loyalty/me', r.ok && (r.body?.points ?? 0) > 0,
    `tier=${r.body?.tier} points=${fmt(r.body?.points)} cashback=${fmt(r.body?.cashback)}`);

  // Public review aggregate for the shop (should now include our 5-star)
  r = await api('GET', `/api/reviews?targetType=SHOP&targetId=${ctx.order.shopId}&limit=5`, null);
  const reviewsCount = r.body?.items?.length ?? r.body?.reviews?.length ?? 0;
  step('GET /reviews?targetType=SHOP — отзывы видны публично', r.ok && reviewsCount > 0,
    `${reviewsCount} отзывов в выдаче`);

  endScenario();
}

// ════════════════════════════════════════════════════════════════════════════
// EDGE 2 — CANCEL FLOW (separate fresh order so we don't taint the main one)
// ════════════════════════════════════════════════════════════════════════════
async function edgeCancelFlow() {
  scenario('Edge 2 — Отмена заказа магазином после подтверждения');

  // Fresh order from existing buyer (qty bumped so we clear zone minOrder=30k)
  let r = await api('GET', `/api/products?shopId=${SHOP_ID}&limit=2`, null, ctx.buyer.token);
  const items = (r.body?.items || []).slice(0, 1).map(p => ({ productId: p.id, quantity: 5 }));

  r = await api('POST', '/api/orders', {
    shopId: SHOP_ID,
    items,
    deliveryAddress: ctx.address.fullAddress,
    deliveryLat: ctx.address.lat,
    deliveryLng: ctx.address.lng,
    paymentMethod: 'cash',
  }, ctx.buyer.token);
  if (!r.ok) { step('Создал заказ для теста отмены', false, JSON.stringify(r.body)); endScenario(); return; }
  const cancelOrderId = r.body.order.id;
  step('Новый заказ для теста отмены', true, `orderId=${cancelOrderId.slice(0, 8)}…`);

  // Accept
  r = await api('POST', `/api/orders/${cancelOrderId}/shop/accept`, {}, ctx.shop.token);
  step('Shop accept', r.ok, `status=${r.body?.order?.status}`);

  // Cancel
  r = await api('POST', `/api/orders/${cancelOrderId}/shop/cancel`, { reason: 'out_of_stock' }, ctx.shop.token);
  step('Shop cancel', r.ok && r.body?.order?.status === 'cancelled', `status=${r.body?.order?.status}, reason=${r.body?.order?.cancelReason}`);

  // Buyer can see it
  r = await api('GET', `/api/orders/${cancelOrderId}`, null, ctx.buyer.token);
  step('Покупатель видит cancelled', r.body?.order?.status === 'cancelled', `${r.body?.order?.cancelReason}`);

  endScenario();
}

// ════════════════════════════════════════════════════════════════════════════
// EDGE 3 — SHOP DASHBOARD: динамика выручки и аналитика
// ════════════════════════════════════════════════════════════════════════════
async function edgeShopDashboard() {
  scenario('Edge 3 — Динамика выручки магазина (dashboard)');

  // Snapshot turnover
  const r = await api('GET', `/api/orders/shop/${SHOP_ID}`, null, ctx.shop.token);
  const orders = r.body?.orders || [];
  const today = orders.filter((o) => new Date(o.createdAt).toDateString() === new Date().toDateString());
  const buckets = {
    pending:           today.filter(o => o.status === 'pending').length,
    collecting:        today.filter(o => o.status === 'collecting').length,
    readyForPickup:    today.filter(o => o.status === 'readyForPickup').length,
    courierAssigned:   today.filter(o => o.status === 'courierAssigned').length,
    inDelivery:        today.filter(o => ['pickedUp','inDelivery','arrivedAtCustomer'].includes(o.status)).length,
    delivered:         today.filter(o => o.status === 'delivered').length,
    confirmedByBuyer:  today.filter(o => o.status === 'confirmedByBuyer').length,
    cancelled:         today.filter(o => o.status === 'cancelled').length,
  };
  const turnoverToday = today
    .filter((o) => !['cancelled'].includes(o.status))
    .reduce((s, o) => s + (o.total || 0), 0);

  step('GET /orders/shop/:id (dashboard feed)', r.ok, `всего сегодня ${today.length}`);
  step('Воронка статусов', true,
    `pending=${buckets.pending} collect=${buckets.collecting} ready=${buckets.readyForPickup} ` +
    `assigned=${buckets.courierAssigned} delivering=${buckets.inDelivery} ` +
    `delivered=${buckets.delivered} confirmed=${buckets.confirmedByBuyer} cancel=${buckets.cancelled}`);
  step('Оборот за сегодня (без отменённых)', turnoverToday > 0, `${fmt(turnoverToday)} сум`);

  endScenario();
}

// ────────────────────────────────────────────────────────────────────────────
async function main() {
  console.log(`▶ Running e2e against ${BASE}, run tag ${RUN_TAG}\n`);
  try {
    await scenarioBuyer();
    await scenarioShop();
    await scenarioCourier();
    await edgeLoyalty();
    await edgeCancelFlow();
    await edgeShopDashboard();
  } catch (err) {
    console.error('FATAL:', err.message);
    if (currentScenario) {
      currentScenario.status = 'failed';
      currentScenario.fatal = err.message;
    }
  }
  report.finishedAt = new Date().toISOString();

  // ─── Final report ───────────────────────────────────────────────────────
  const passed = report.scenarios.filter(s => s.status === 'passed').length;
  const failed = report.scenarios.filter(s => s.status === 'failed').length;
  const okSteps = report.scenarios.reduce((s, sc) => s + sc.steps.filter(x => x.ok).length, 0);
  const failSteps = report.scenarios.reduce((s, sc) => s + sc.steps.filter(x => !x.ok).length, 0);

  console.log('\n══════════════════════════════════════════════════════════════');
  console.log(`  ИТОГО: сценариев ${passed}/${report.scenarios.length} прошли`);
  console.log(`         шагов     ${okSteps}/${okSteps + failSteps} зелёных, ${failSteps} красных`);
  console.log('══════════════════════════════════════════════════════════════');

  const fs = require('fs');
  fs.writeFileSync(
    require('path').join(__dirname, 'test_e2e_report.json'),
    JSON.stringify(report, null, 2),
  );
  console.log('  report → backend/test_e2e_report.json');
  process.exit(failed === 0 ? 0 : 1);
}

main();
