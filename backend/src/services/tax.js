// Phase 7 — VAT/НДС calculation per country.
//
// Rates come from services/country.js. VAT applies to goods (subtotal) only —
// the delivery fee is the courier reward and is not taxed in our model. If
// that policy ever changes, update compute() here.
//
// Output uses major currency units (UZS / KZT / KGS have 0 decimals; RUB has 2)
// rounded to whole units, matching the rest of the order math (Order.subtotal
// etc are stored as Float in major units).

const country = require('./country');

function vatRateFor(c) {
  return country.info(c).vatRate;
}

/**
 * Compute VAT for an order.
 *
 * @param {{ subtotal: number, deliveryFee?: number, country: string }} args
 * @returns {{ taxRate: number, taxAmount: number }}
 *   taxRate    fractional rate that was applied (e.g. 0.12)
 *   taxAmount  amount added on top of subtotal (rounded to whole major units)
 */
function compute({ subtotal, deliveryFee, country: c } = {}) {
  const taxRate = vatRateFor(c);
  const sub = Number(subtotal) || 0;
  // Delivery fee is intentionally not taxed — the courier reward is not "goods".
  // We accept it as an arg so callers can pass the full breakdown without
  // having to remember to omit it.
  void deliveryFee;
  const taxAmount = Math.round(sub * taxRate);
  return { taxRate, taxAmount };
}

module.exports = { vatRateFor, compute };
