// Phase 6 — multi-currency framework. UZS is the only active currency at
// launch; KZT/KGS activate in Phase 7. Wraps numeric amounts with their
// currency so serialization carries both fields uniformly.

// Currencies we care about across CIS launch markets.
const CURRENCIES = {
  UZS: { code: 'UZS', symbol: "so'm", decimals: 0 },
  KZT: { code: 'KZT', symbol: '₸', decimals: 0 },
  KGS: { code: 'KGS', symbol: 'сом', decimals: 0 },
  RUB: { code: 'RUB', symbol: '₽', decimals: 2 },
  USD: { code: 'USD', symbol: '$', decimals: 2 },
};

function isSupported(code) {
  return Object.prototype.hasOwnProperty.call(CURRENCIES, code);
}

// Build a Money value object. Negative amounts are allowed (refunds, deltas).
function money(amount, currency = 'UZS') {
  const code = String(currency || 'UZS').toUpperCase();
  if (!isSupported(code)) {
    throw new Error(`Unsupported currency: ${currency}`);
  }
  const n = Number(amount);
  if (!Number.isFinite(n)) {
    throw new Error(`Invalid money amount: ${amount}`);
  }
  return { amount: n, currency: code };
}

// Serialize for API responses. Returns `{ amount, currency, formatted }`
// so clients can either render `formatted` directly or apply their own
// locale-aware formatting.
function toJson(m, locale = 'ru') {
  if (m == null) return null;
  return {
    amount: m.amount,
    currency: m.currency,
    formatted: format(m, locale),
  };
}

// Locale-aware string. Currency symbols come from CURRENCIES; thousand
// separators follow the locale convention.
function format(m, locale = 'ru') {
  if (m == null) return '';
  const meta = CURRENCIES[m.currency] || CURRENCIES.UZS;
  const fixed = m.amount.toFixed(meta.decimals);
  const [intPart, fracPart] = fixed.split('.');
  const sep = (locale || 'ru').startsWith('en') ? ',' : ' ';
  const grouped = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, sep);
  const numStr = fracPart != null ? `${grouped}.${fracPart}` : grouped;
  return `${numStr} ${meta.symbol}`;
}

// Convert between currencies using an explicit rates table.
// rates: { from: { to: rate } }, e.g. { UZS: { KZT: 0.038 } }.
function convert(m, toCurrency, rates) {
  if (m == null) return null;
  const target = String(toCurrency).toUpperCase();
  if (m.currency === target) return m;
  const rate = rates && rates[m.currency] && rates[m.currency][target];
  if (!Number.isFinite(rate)) {
    throw new Error(`No conversion rate for ${m.currency}→${target}`);
  }
  return money(m.amount * rate, target);
}

module.exports = {
  money,
  toJson,
  format,
  convert,
  isSupported,
  CURRENCIES,
};
