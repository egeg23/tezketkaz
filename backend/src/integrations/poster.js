// Poster POS adapter.
//
// API docs:    https://dev.joinposter.com/docs/v3/start
// Sandbox:     a developer account gives you a working API token immediately
//
// Wire-up status: SCAFFOLD. As with iiko, the endpoints + payload shapes are
// per Poster's public docs, but real calls are gated by `MOCK_POSTER=1`. To
// activate against a real account:
//
//   1. User generates a token in their Poster admin → API → Personal token
//   2. GET  https://joinposter.com/api/menu.getProducts?token=…
//   3. POST https://joinposter.com/api/incomingOrders.createIncomingOrder
//
// Poster's auth model is even simpler than iiko — just a query-string token.

const prisma = require('../db');

const id = 'poster';
const label = 'Poster POS';
const summary = 'Подключение через personal API token. Тащим menu.getProducts, шлём incomingOrders. Подходит для кафе и средних ресторанов.';
const docsUrl = 'https://dev.joinposter.com';
const tier = 'beta';
const capabilities = ['menu', 'orders'];

const fields = [
  { id: 'token',     label: 'API token',     placeholder: 'из Poster → Настройки → API', required: true, secret: true },
  { id: 'accountId', label: 'Account name',  placeholder: 'mycafe',                       required: true, secret: false },
];

const MOCK = process.env.MOCK_POSTER !== '0';
const BASE = 'https://joinposter.com/api';

async function testConnection(creds) {
  if (MOCK) {
    return { ok: true, message: `Poster mock — account=${creds.accountId} ✓` };
  }
  try {
    const r = await fetch(`${BASE}/access.getAccountInfo?token=${creds.token}`, {
      signal: AbortSignal.timeout(8000),
    });
    const j = await r.json().catch(() => ({}));
    const ok = r.ok && j?.response?.account_name === creds.accountId;
    return {
      ok,
      message: ok ? 'account_matched' : (j?.error?.message || `HTTP ${r.status}`),
    };
  } catch (err) {
    return { ok: false, message: err.message };
  }
}

async function pullMenu(creds, shopId) {
  if (MOCK) {
    const items = [
      {
        externalId: `poster-mock-001-${shopId.slice(0, 4)}`,
        name: 'Капучино (Poster mock)',
        nameUz: 'Cappuccino',
        price: 22000,
        unit: 'шт',
        category: 'drinks',
        stock: 100,
        isAvailable: true,
        imageUrl: 'https://images.unsplash.com/photo-1572442388796-11668a67e53d?w=400',
      },
      {
        externalId: `poster-mock-002-${shopId.slice(0, 4)}`,
        name: 'Чизкейк Нью-Йорк (Poster mock)',
        nameUz: 'Cheesecake',
        price: 35000,
        unit: 'шт',
        category: 'bakery',
        stock: 18,
        isAvailable: true,
      },
    ];
    return _upsertAll(shopId, items);
  }

  // TODO live:
  // const r = await fetch(`${BASE}/menu.getProducts?token=${creds.token}`);
  // const j = await r.json();
  // const items = (j.response || []).map(p => mapPoster(p));
  // return _upsertAll(shopId, items);
  void creds;
  throw new Error('poster_live_mode_not_implemented_yet');
}

async function pushOrder(creds, orderPayload) {
  if (MOCK) {
    return { ok: true, message: 'Poster mock accepted order' };
  }
  // TODO live: POST incomingOrders.createIncomingOrder
  void creds; void orderPayload;
  return { ok: false, message: 'poster_live_mode_not_implemented_yet' };
}

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
  return { fetched: items.length, inserted, updated, message: `${inserted}+, ${updated}↑ (Poster)` };
}

module.exports = {
  id, label, summary, docsUrl, tier, capabilities, fields,
  testConnection, pullMenu, pushOrder,
};
