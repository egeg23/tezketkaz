// Phase 13.1.7 — payments orchestrator.
//
// Single entry point that maps a buyer's `country` (User.country) to the
// preferred payment provider service module. Country → providers table lives
// in services/country.js; this file just wires the resolved provider name
// to the actual module (click.js / payme.js / uzum.js / kaspi.js / click-kg.js).
//
// Why an orchestrator: routes/orders.js and routes/subscription.js previously
// hard-coded `services/click.js` in places. As we expand to KZ + KG those
// hard-codes silently route Kaspi/Click-KG users to Click UZ. This module
// centralizes the dispatch so adding a new country is one line in
// services/country.js + the module map below.
//
// Mock-mode rules:
//   • `USE_MOCK_PAYMENTS=true` (default) ⇒ all providers serve mock responses.
//   • `USE_MOCK_PAYMENTS=false` + `USE_MOCK_CLICK=true` ⇒ only Click is mocked
//     (surgical rollback). Per-provider flags live in services themselves.
//   • `USE_MOCK_PAYMENTS=false` AND no per-provider override AND the provider's
//     MERCHANT_ID is missing ⇒ providers fall back to mock (defensive).

const click = require('./click');
const payme = require('./payme');
const uzum = require('./uzum');
const kaspi = require('./kaspi');
const clickKg = require('./click-kg');
const country = require('./country');

// Static module map. Keys must match the strings used in
// services/country.js's `providers` arrays.
const PROVIDER_MODULES = {
  click,
  payme,
  uzum,
  kaspi,
  click_kg: clickKg,
};

/**
 * Resolve the preferred provider for a country.
 *
 * Returns the first provider in the country's preference list that has a
 * module entry here. 'cash' is filtered out because it has no online flow.
 *
 * @param {string} countryCode  ISO2, e.g. 'UZ' / 'KZ' / 'KG'
 * @returns {string|null} provider name (e.g. 'click') or null if none.
 */
function preferredProviderFor(countryCode) {
  const info = country.info(countryCode);
  if (!info || !Array.isArray(info.providers)) return null;
  for (const p of info.providers) {
    if (p === 'cash') continue;
    if (PROVIDER_MODULES[p]) return p;
  }
  return null;
}

/**
 * Get the provider service module by name.
 *
 * @param {string} name  'click' | 'payme' | 'uzum' | 'kaspi' | 'click_kg'
 * @returns {object|null} module or null.
 */
function getProvider(name) {
  if (!name) return null;
  return PROVIDER_MODULES[name] || null;
}

/**
 * List provider names available in a country (excluding 'cash').
 */
function availableProvidersFor(countryCode) {
  const info = country.info(countryCode);
  if (!info || !Array.isArray(info.providers)) return [];
  return info.providers.filter((p) => p !== 'cash' && PROVIDER_MODULES[p]);
}

/**
 * Is `provider` valid for `countryCode`? Used by routes to reject mismatched
 * (provider, country) tuples — e.g. a KZ user picking `click` would be wrong.
 */
function isProviderAllowed(countryCode, provider) {
  return availableProvidersFor(countryCode).includes(provider);
}

module.exports = {
  preferredProviderFor,
  getProvider,
  availableProvidersFor,
  isProviderAllowed,
  PROVIDER_MODULES,
};
