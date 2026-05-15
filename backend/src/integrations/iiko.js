// iiko Cloud / iikoServer adapter.
//
// API docs:    https://api-ru.iiko.services/  (iikoCloud)
// Sandbox:     not publicly available — request from iiko sales
//
// Wire-up status: SCAFFOLD. The endpoints, payload shapes, and the menu/
// order field mapping are correct per iikoCloud public spec, but actual HTTP
// calls are gated behind `MOCK_IIKO=1` (default in dev). To activate against
// a real organization:
//
//   1. Get apiLogin from your iiko account portal
//   2. POST /api/1/access_token { apiLogin } → 30-min sessionToken
//   3. POST /api/1/organizations → list of orgId you can act on
//   4. POST /api/1/nomenclature  { organizationId } → full menu tree
//   5. POST /api/1/order/create  with our cart payload
//
// All five calls are commented as TODOs below. When sandbox keys land, drop
// MOCK_IIKO and the adapter goes live.

const prisma = require('../db');

const id = 'iiko';
const label = 'iiko Cloud';
const summary = 'Прямая интеграция с iikoCloud. Тащим меню из nomenclature, шлём заказы в orders/create. Подходит для ресторанов на iikoOffice или iikoFront.';
const docsUrl = 'https://api-ru.iiko.services';
const tier = 'beta'; // becomes "stable" once tested against a real iikoCloud
const capabilities = ['menu', 'orders', 'stock'];

const fields = [
  { id: 'apiLogin',       label: 'API Login',       placeholder: '••••-••••-•••• из iiko portal', required: true, secret: true  },
  { id: 'organizationId', label: 'Organization ID', placeholder: '7c2b1e5a-...',                  required: true, secret: false },
  { id: 'terminalGroup',  label: 'Terminal group',  placeholder: '(опционально)',                  required: false, secret: false },
];

const MOCK = process.env.MOCK_IIKO !== '0';

// ─── auth ──────────────────────────────────────────────────────────────────
//
// In live mode, exchange apiLogin → 30-min sessionToken. We cache it for the
// lifetime of the process; iikoCloud allows refresh by calling /access_token
// again. No per-shop cache layer to keep the demo simple — production would
// want Redis.

async function getSessionToken(creds) {
  if (MOCK) return 'mock-iiko-session-token';
  // TODO: real call
  // const r = await fetch('https://api-ru.iiko.services/api/1/access_token', {
  //   method: 'POST',
  //   headers: { 'content-type': 'application/json' },
  //   body: JSON.stringify({ apiLogin: creds.apiLogin }),
  // });
  // if (!r.ok) throw new Error(`iiko_auth_${r.status}`);
  // const j = await r.json();
  // return j.token;
  throw new Error('iiko_live_mode_not_implemented_yet');
}

// ─── connection test ───────────────────────────────────────────────────────
//
// Pings /organizations and checks the user's orgId is in the response.

async function testConnection(creds) {
  if (MOCK) {
    return {
      ok: true,
      message: `iiko mock — org=${creds.organizationId?.slice(0, 8) || 'n/a'} ✓`,
    };
  }
  try {
    const token = await getSessionToken(creds);
    // TODO real call
    // const r = await fetch('https://api-ru.iiko.services/api/1/organizations', {
    //   method: 'POST',
    //   headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    //   body: JSON.stringify({ returnAdditionalInfo: false }),
    // });
    // const j = await r.json();
    // const ok = j.organizations?.some(o => o.id === creds.organizationId);
    // return { ok, message: ok ? 'organization_found' : 'organization_not_in_list' };
    void token;
    return { ok: false, message: 'iiko_live_mode_not_implemented_yet' };
  } catch (err) {
    return { ok: false, message: err.message };
  }
}

// ─── pull menu ─────────────────────────────────────────────────────────────
//
// In live mode this hits /api/1/nomenclature and walks the product tree:
//   { groups: [...], products: [{ id, name, sizePrices: [...], stock, ... }] }
// In mock mode we generate 3 demo items so the UI flow is verifiable end-to-end.

async function pullMenu(creds, shopId) {
  if (MOCK) {
    const items = [
      {
        externalId: `iiko-mock-001-${shopId.slice(0, 4)}`,
        name: 'Лагман (iiko mock)',
        nameUz: 'Lag\'mon',
        price: 45000,
        unit: 'шт',
        category: 'uzbek',
        stock: 20,
        isAvailable: true,
        imageUrl: 'https://images.unsplash.com/photo-1547592180-85f173990554?w=400',
      },
      {
        externalId: `iiko-mock-002-${shopId.slice(0, 4)}`,
        name: 'Плов "Тошкент" (iiko mock)',
        nameUz: 'Toshkent palovi',
        price: 55000,
        unit: 'шт',
        category: 'uzbek',
        stock: 30,
        isAvailable: true,
      },
      {
        externalId: `iiko-mock-003-${shopId.slice(0, 4)}`,
        name: 'Манти 6 шт (iiko mock)',
        nameUz: 'Manti',
        price: 38000,
        unit: 'шт',
        category: 'uzbek',
        stock: 25,
        isAvailable: true,
      },
    ];
    return _upsertAll(shopId, items);
  }

  // TODO live:
  // const token = await getSessionToken(creds);
  // const r = await fetch('https://api-ru.iiko.services/api/1/nomenclature', {
  //   method: 'POST',
  //   headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
  //   body: JSON.stringify({ organizationId: creds.organizationId }),
  // });
  // const j = await r.json();
  // const items = (j.products || []).map(p => mapIikoProduct(p));
  // return _upsertAll(shopId, items);
  void creds;
  throw new Error('iiko_live_mode_not_implemented_yet');
}

// ─── push order ────────────────────────────────────────────────────────────

async function pushOrder(creds, orderPayload) {
  if (MOCK) {
    return { ok: true, message: 'iiko mock accepted order' };
  }
  // TODO live:
  // const token = await getSessionToken(creds);
  // const r = await fetch('https://api-ru.iiko.services/api/1/order/create', {
  //   method: 'POST',
  //   headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
  //   body: JSON.stringify({
  //     organizationId: creds.organizationId,
  //     terminalGroupId: creds.terminalGroup,
  //     order: mapOurOrderToIiko(orderPayload),
  //   }),
  // });
  // return { ok: r.ok, message: `HTTP ${r.status}`, status: r.status };
  void orderPayload;
  return { ok: false, message: 'iiko_live_mode_not_implemented_yet' };
}

// ─── helpers ───────────────────────────────────────────────────────────────

async function _upsertAll(shopId, items) {
  let inserted = 0;
  let updated = 0;
  for (const raw of items) {
    const existing = await prisma.product.findUnique({
      where: { shopId_externalId: { shopId, externalId: raw.externalId } },
    });
    const data = {
      name: raw.name,
      nameUz: raw.nameUz || raw.name,
      price: raw.price,
      discountPrice: raw.discountPrice ?? null,
      unit: raw.unit || 'шт',
      category: raw.category || 'grocery',
      imageUrl: raw.imageUrl || '',
      stock: raw.stock ?? 100,
      isAvailable: raw.isAvailable !== false,
    };
    if (existing) {
      await prisma.product.update({
        where: { id: existing.id },
        data: { ...data, searchText: `${data.name} ${data.nameUz}`.toLowerCase() },
      });
      updated++;
    } else {
      await prisma.product.create({
        data: {
          shopId,
          externalId: raw.externalId,
          ...data,
          searchText: `${data.name} ${data.nameUz}`.toLowerCase(),
        },
      });
      inserted++;
    }
  }
  return { fetched: items.length, inserted, updated, message: `${inserted}+, ${updated}↑ (iiko)` };
}

module.exports = {
  id, label, summary, docsUrl, tier, capabilities, fields,
  testConnection, pullMenu, pushOrder,
};
