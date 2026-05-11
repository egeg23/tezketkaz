// Soliq.uz fiscal API client (Phase 13.3.9).
//
// Soliq is Uzbekistan's State Tax Committee fiscalisation endpoint. Cashless
// transactions above 100,000 UZS legally require an issued fiscal receipt.
// This module provides a clean client interface with two modes:
//
//   • Mock mode (USE_MOCK_SOLIQ=true, default in dev/test) — returns a
//     deterministic synthetic receiptId/receiptUrl without touching the
//     network. Used by tests and by dev environments without Soliq creds.
//
//   • Production mode — performs a real HTTPS request to SOLIQ_API_BASE with
//     a Bearer-token Authorization header. The real Soliq backend exposes a
//     SOAP/XML protocol, but most operators today proxy it through a small
//     JSON wrapper service (provided by the cashier-software vendor); the
//     contract here matches that wrapper. When the user wires the actual
//     SOAP endpoint they only need to replace the body builder.
//
// Errors:
//   • Network / 5xx / parse failures THROW (so BullMQ retries them).
//   • Business-logic failures (4xx, validation errors from Soliq) return
//     { ok: false, error } so the worker records the failure and stops
//     retrying — re-trying a bad-INN response is pointless.
//
// Eligibility:
//   • Shop must have soliqEnabled=true AND soliqInn set.
//   • Per-shop soliqApiKey takes precedence over global SOLIQ_API_KEY env.

const env = require('../config/env');
const logger = require('../lib/logger');

// VAT rate fallback: order.taxRate is decimal (0.12), Soliq wants percent (12).
function taxRatePercent(order) {
  const rate = Number(order && order.taxRate) || 0;
  if (rate <= 0) return 0;
  return Math.round(rate * 100);
}

// Build the payload Soliq expects. Mirrors the JSON-wrapper contract; for
// the raw SOAP endpoint the user re-shapes this in the production code path.
function buildPayload(order, shop) {
  const items = Array.isArray(order.items) ? order.items : [];
  const vatRate = taxRatePercent(order);
  return {
    shopInn: shop.soliqInn,
    shopVatNumber: shop.soliqVatNumber || null,
    orderId: order.id,
    orderNumber: order.orderNumber || order.id,
    paymentMethod: order.paymentMethod, // click | payme | uzumpay | cash
    currency: order.currency || 'UZS',
    subtotal: order.subtotal,
    total: order.total,
    vatRate,
    vatAmount: order.taxAmount,
    items: items.map((it) => ({
      name: it.productName,
      quantity: it.quantity,
      price: it.price,
      total: it.total,
      vatRate,
    })),
  };
}

function resolveApiKey(shop) {
  return (shop && shop.soliqApiKey) || env.SOLIQ_API_KEY || '';
}

function useMock() {
  // Always mock in test, regardless of explicit env, so accidental misconfig
  // can't produce a real network call in CI.
  if (env.isTest) return true;
  return env.useMockSoliq;
}

function isShopEligible(shop) {
  if (!shop) return false;
  if (!shop.soliqEnabled) return false;
  if (!shop.soliqInn) return false;
  // In mock mode we don't need an API key — the goal is to exercise the
  // flow end-to-end. In production we require either per-shop or env key.
  if (!useMock() && !resolveApiKey(shop)) return false;
  return true;
}

// Surface for tests to swap fetch impl + clear any cached state.
let _fetchImpl = null;
function _resetForTests() {
  _fetchImpl = null;
}
function _setFetchForTests(fn) {
  _fetchImpl = fn;
}

function getFetch() {
  if (_fetchImpl) return _fetchImpl;
  if (typeof fetch === 'function') return fetch;
  // Node 20+ guarantees global fetch; fall back to undici for paranoia.
  // eslint-disable-next-line global-require
  return require('undici').fetch;
}

// POST a fiscal receipt for an order. Returns:
//   { ok: true, receiptId, receiptUrl, fiscalCode?, qrCode? }
//   { ok: false, error }   — business-logic rejection (no retry)
// Throws on network/5xx (BullMQ retries with backoff).
async function issueReceipt(order, shop) {
  if (!isShopEligible(shop)) {
    return { ok: false, error: 'shop_not_eligible' };
  }
  if (order && order.fiscalReceiptId) {
    // Idempotent guard at the service level — caller should also check.
    return {
      ok: true,
      receiptId: order.fiscalReceiptId,
      receiptUrl: order.fiscalReceiptUrl,
    };
  }

  if (useMock()) {
    const receiptId = `mock-${order.id}`;
    return {
      ok: true,
      receiptId,
      receiptUrl: `https://soliq.uz/mock-receipt/${order.id}`,
      fiscalCode: `MOCKFISC-${order.id.slice(0, 8)}`,
      qrCode: `https://soliq.uz/qr/${receiptId}`,
    };
  }

  const apiBase = env.SOLIQ_API_BASE || 'https://api.soliq.uz/v1';
  const url = `${apiBase.replace(/\/$/, '')}/fiscal/receipts`;
  const apiKey = resolveApiKey(shop);
  const body = buildPayload(order, shop);

  let resp;
  try {
    const f = getFetch();
    resp = await f(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
    });
  } catch (err) {
    // Network/DNS/TLS failures — retryable. Re-throw so BullMQ records the
    // attempt count and waits for the next backoff slot.
    logger.warn({ err: err.message, orderId: order.id }, 'soliq network error');
    throw err;
  }

  if (resp.status >= 500) {
    // 5xx is transient on Soliq's side — retry.
    const text = await safeReadText(resp);
    const err = new Error(`soliq_5xx_${resp.status}: ${text.slice(0, 200)}`);
    err.status = resp.status;
    throw err;
  }

  let parsed;
  try {
    parsed = await resp.json();
  } catch (err) {
    // Couldn't parse JSON — treat as transient/parse error so BullMQ retries.
    throw new Error('soliq_invalid_json');
  }

  if (resp.status >= 400) {
    // Business-logic rejection (bad INN, malformed payload). Don't retry.
    return {
      ok: false,
      error: (parsed && (parsed.error || parsed.message)) || `soliq_http_${resp.status}`,
    };
  }

  if (!parsed || !parsed.receiptId) {
    return { ok: false, error: 'soliq_missing_receipt_id' };
  }

  return {
    ok: true,
    receiptId: parsed.receiptId,
    receiptUrl: parsed.receiptUrl,
    fiscalCode: parsed.fiscalCode,
    qrCode: parsed.qrCode,
  };
}

// Fetch the status of a previously issued receipt. Used by support tooling
// when a buyer reports a broken receipt link.
async function getReceipt(receiptId) {
  if (!receiptId) return { ok: false, status: null, error: 'missing_receipt_id' };

  if (useMock()) {
    if (receiptId.startsWith('mock-')) {
      const orderId = receiptId.slice(5);
      return {
        ok: true,
        status: 'issued',
        receiptUrl: `https://soliq.uz/mock-receipt/${orderId}`,
      };
    }
    return { ok: false, status: 'unknown', error: 'mock_receipt_unknown' };
  }

  const apiBase = env.SOLIQ_API_BASE || 'https://api.soliq.uz/v1';
  const apiKey = env.SOLIQ_API_KEY || '';
  const url = `${apiBase.replace(/\/$/, '')}/fiscal/receipts/${encodeURIComponent(receiptId)}`;

  let resp;
  try {
    const f = getFetch();
    resp = await f(url, {
      method: 'GET',
      headers: { Authorization: `Bearer ${apiKey}` },
    });
  } catch (err) {
    throw err;
  }
  if (resp.status >= 500) {
    const text = await safeReadText(resp);
    const err = new Error(`soliq_5xx_${resp.status}: ${text.slice(0, 200)}`);
    err.status = resp.status;
    throw err;
  }
  if (resp.status === 404) {
    return { ok: false, status: 'not_found', error: 'not_found' };
  }
  let parsed;
  try { parsed = await resp.json(); } catch { return { ok: false, status: null, error: 'invalid_json' }; }
  if (resp.status >= 400) {
    return { ok: false, status: parsed.status || null, error: parsed.error || `http_${resp.status}` };
  }
  return {
    ok: true,
    status: parsed.status || 'issued',
    receiptUrl: parsed.receiptUrl,
  };
}

async function safeReadText(resp) {
  try { return await resp.text(); } catch { return ''; }
}

module.exports = {
  issueReceipt,
  getReceipt,
  isShopEligible,
  _resetForTests,
  _setFetchForTests,
  // Exported for tests
  _buildPayload: buildPayload,
};
