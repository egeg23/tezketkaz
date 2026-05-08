// Phase 7 — multi-country dispatch table.
//
// Drives currency, VAT rate, payment provider mix, and default locale per ISO
// country code. Phone-prefix detection on signup wires User.country
// automatically; users can override via PATCH /api/users/me.
//
// Single source of truth — services/tax.js and the auth/order pipelines call
// info() rather than duplicating the table.

const COUNTRIES = {
  UZ: {
    currency: 'UZS',
    vatRate: 0.12,
    locale: 'uz',
    providers: ['click', 'payme', 'uzum', 'cash'],
    phonePrefix: '+998',
  },
  KZ: {
    currency: 'KZT',
    vatRate: 0.12,
    locale: 'kk',
    providers: ['kaspi', 'cash'],
    phonePrefix: '+7',
  },
  KG: {
    currency: 'KGS',
    vatRate: 0.12,
    locale: 'ru',
    providers: ['click_kg', 'cash'],
    phonePrefix: '+996',
  },
  RU: {
    currency: 'RUB',
    vatRate: 0.20,
    locale: 'ru',
    providers: ['cash'],
    phonePrefix: '+7',
  },
};

/**
 * Best-effort country detection from E.164 phone.
 * Order matters: +77 must come before +7 because KZ mobile numbers start
 * with +77 and we must not classify them as RU.
 */
function fromPhone(phone) {
  if (!phone || typeof phone !== 'string') return 'UZ';
  if (phone.startsWith('+998')) return 'UZ';
  if (phone.startsWith('+996')) return 'KG';
  if (phone.startsWith('+77')) return 'KZ';   // KZ mobile (also covers +7700, +7707, etc.)
  if (phone.startsWith('+7')) return 'RU';    // RU mobile (+79xx)
  return 'UZ';
}

function info(country) {
  if (!country) return COUNTRIES.UZ;
  return COUNTRIES[country] || COUNTRIES.UZ;
}

function isProviderAvailable(country, provider) {
  const c = info(country);
  return Array.isArray(c.providers) && c.providers.includes(provider);
}

module.exports = { COUNTRIES, fromPhone, info, isProviderAvailable };
