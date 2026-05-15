// Universal "I have a REST API" adapter.
//
// The integrator gives us:
//   • baseUrl       — root of their service (e.g. https://api.kafe.uz)
//   • authHeader    — name of the auth header ("Authorization", "X-API-Key")
//   • authValue     — full value to send ("Bearer xxx" or just the token)
//   • menuPath      — GET endpoint that returns their menu
//   • orderPath     — POST endpoint where we'll deliver new orders
//
// Their menu must return JSON in our shape:
//   {
//     "items": [
//       { "externalId": "sku-1", "name": "...", "price": 60000,
//         "unit": "шт", "category": "pizza", "stock": 50,
//         "imageUrl": "...", "isAvailable": true }
//     ]
//   }
//
// (If their format differs, they write a tiny proxy. That's the trade-off
// of "Custom": we don't write per-shop translation code.)

const prisma = require('../db');

const id = 'custom_rest';
const label = 'Свой REST API';
const summary = 'Подключите любой REST-эндпоинт. Мы шлём заказы → вы шлёте меню. Самый универсальный вариант — подходит для любого самописного backend.';
const docsUrl = '/docs/api/custom-rest';
const tier = 'stable';
const capabilities = ['menu', 'orders'];

const fields = [
  { id: 'baseUrl',    label: 'Базовый URL',    placeholder: 'https://api.example.com', required: true,  secret: false },
  { id: 'authHeader', label: 'Заголовок auth', placeholder: 'Authorization',           required: true,  secret: false },
  { id: 'authValue',  label: 'Значение auth',  placeholder: 'Bearer …',                 required: true,  secret: true  },
  { id: 'menuPath',   label: 'Путь меню (GET)', placeholder: '/api/menu',                required: true,  secret: false },
  { id: 'orderPath',  label: 'Путь заказов (POST)', placeholder: '/api/orders/incoming', required: false, secret: false },
];

function url(creds, path) {
  const base = (creds.baseUrl || '').replace(/\/+$/, '');
  const p = path.startsWith('/') ? path : `/${path}`;
  return `${base}${p}`;
}

function headers(creds) {
  return {
    'content-type': 'application/json',
    [creds.authHeader || 'Authorization']: creds.authValue || '',
  };
}

async function testConnection(creds) {
  try {
    const r = await fetch(url(creds, creds.menuPath || '/'), {
      method: 'GET',
      headers: headers(creds),
      signal: AbortSignal.timeout(8000),
    });
    if (r.ok) {
      return { ok: true, message: `HTTP ${r.status} ${r.statusText}` };
    }
    return { ok: false, message: `HTTP ${r.status} ${r.statusText}` };
  } catch (err) {
    return { ok: false, message: err.message };
  }
}

async function pullMenu(creds, shopId) {
  const r = await fetch(url(creds, creds.menuPath), {
    method: 'GET',
    headers: headers(creds),
    signal: AbortSignal.timeout(30000),
  });
  if (!r.ok) {
    throw new Error(`partner_returned_${r.status}`);
  }
  const body = await r.json().catch(() => ({}));
  const items = Array.isArray(body?.items) ? body.items : [];
  if (items.length === 0) {
    return { fetched: 0, inserted: 0, updated: 0, message: 'empty_menu' };
  }

  let inserted = 0;
  let updated = 0;
  for (const raw of items) {
    const externalId = String(raw.externalId || raw.id || '').trim();
    if (!externalId) continue;
    const data = {
      name: String(raw.name || '').slice(0, 200),
      nameUz: String(raw.nameUz || raw.name || '').slice(0, 200),
      description: raw.description ? String(raw.description).slice(0, 2000) : null,
      price: Math.max(0, Number(raw.price) || 0),
      discountPrice: raw.discountPrice == null ? null : Math.max(0, Number(raw.discountPrice)),
      unit: String(raw.unit || 'шт').slice(0, 16),
      category: String(raw.category || 'grocery').slice(0, 32),
      imageUrl: String(raw.imageUrl || '').slice(0, 500),
      stock: Math.max(0, Math.floor(Number(raw.stock ?? 100))),
      isAvailable: raw.isAvailable !== false,
    };
    if (!data.name || !data.price) continue;

    const existing = await prisma.product.findUnique({
      where: { shopId_externalId: { shopId, externalId } },
    });
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
          externalId,
          ...data,
          searchText: `${data.name} ${data.nameUz}`.toLowerCase(),
        },
      });
      inserted++;
    }
  }
  return { fetched: items.length, inserted, updated, message: `${inserted}+, ${updated}↑` };
}

async function pushOrder(creds, orderPayload) {
  if (!creds.orderPath) {
    return { ok: false, message: 'orderPath_not_configured' };
  }
  try {
    const r = await fetch(url(creds, creds.orderPath), {
      method: 'POST',
      headers: headers(creds),
      body: JSON.stringify(orderPayload),
      signal: AbortSignal.timeout(15000),
    });
    return {
      ok: r.ok,
      message: `HTTP ${r.status}`,
      status: r.status,
    };
  } catch (err) {
    return { ok: false, message: err.message };
  }
}

module.exports = {
  id, label, summary, docsUrl, tier, capabilities, fields,
  testConnection, pullMenu, pushOrder,
};
