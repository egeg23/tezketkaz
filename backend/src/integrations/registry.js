// Adapter registry. Each provider exports the same shape:
//
//   { id, label, fields, testConnection(creds), pullMenu(creds, shopId),
//     pushOrder(creds, order) }
//
// `fields` describes what the UI should ask the user (label + secret flag).
// `testConnection` returns { ok, message }. It MUST NOT throw uncaught.
// `pullMenu` is invoked by the scheduled syncer and the manual "Sync now"
// button. `pushOrder` fires when our marketplace creates a new order.
//
// Stages:
//   • custom_rest — fully wired, talks to a generic REST endpoint
//   • iiko        — scaffold + happy-path mock until we have sandbox creds
//   • poster      — scaffold + happy-path mock

const custom = require('./custom-rest');
const iiko = require('./iiko');
const poster = require('./poster');

const REGISTRY = {
  [custom.id]: custom,
  [iiko.id]: iiko,
  [poster.id]: poster,
};

/** Strip secret fields before exposing the field schema to clients. */
function fieldsFor(providerId) {
  const p = REGISTRY[providerId];
  if (!p) return null;
  return p.fields;
}

/** Public catalogue of supported providers. Used by the picker UI. */
function listProviders() {
  return Object.values(REGISTRY).map((p) => ({
    id: p.id,
    label: p.label,
    summary: p.summary,
    docsUrl: p.docsUrl,
    capabilities: p.capabilities, // ["menu", "orders", "stock"]
    fields: p.fields,
    tier: p.tier, // "stable" | "beta" | "scaffold"
  }));
}

/** Validate that the user-submitted `creds` object has every required field
 * and nothing extra. Returns sanitized creds OR throws. */
function validateCreds(providerId, raw) {
  const p = REGISTRY[providerId];
  if (!p) throw new Error('unknown_provider');
  const out = {};
  for (const f of p.fields) {
    const v = raw?.[f.id];
    if (f.required && (v == null || String(v).trim() === '')) {
      const err = new Error(`field_required:${f.id}`);
      err.code = 'field_required';
      err.field = f.id;
      throw err;
    }
    if (v != null) out[f.id] = String(v).trim();
  }
  return out;
}

/** Extract only non-secret fields for storage in `publicMeta`. The UI uses
 * this to show e.g. "iiko · org=AB12" without ever decrypting. */
function publicMetaFrom(providerId, creds) {
  const p = REGISTRY[providerId];
  if (!p) return {};
  const out = {};
  for (const f of p.fields) {
    if (!f.secret && creds[f.id] != null) out[f.id] = creds[f.id];
  }
  return out;
}

function getAdapter(providerId) {
  return REGISTRY[providerId] || null;
}

module.exports = {
  listProviders,
  fieldsFor,
  validateCreds,
  publicMetaFrom,
  getAdapter,
};
