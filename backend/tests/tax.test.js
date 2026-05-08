// Phase 7 — services/tax.js unit tests.
//
// VAT applies to subtotal only (delivery fee is the courier reward, not goods).
// Rates: UZ/KZ/KG = 12%, RU = 20%. Output is rounded to whole major units.

const tax = require('../src/services/tax');

describe('tax.vatRateFor', () => {
  test('returns the country VAT rate', () => {
    expect(tax.vatRateFor('UZ')).toBe(0.12);
    expect(tax.vatRateFor('KZ')).toBe(0.12);
    expect(tax.vatRateFor('KG')).toBe(0.12);
    expect(tax.vatRateFor('RU')).toBe(0.20);
  });

  test('falls back to UZ rate on unknown country', () => {
    expect(tax.vatRateFor('ZZ')).toBe(0.12);
    expect(tax.vatRateFor(null)).toBe(0.12);
  });
});

describe('tax.compute', () => {
  test('UZ — 12% on subtotal, delivery fee untaxed', () => {
    const r = tax.compute({ subtotal: 100000, deliveryFee: 12000, country: 'UZ' });
    expect(r.taxRate).toBe(0.12);
    expect(r.taxAmount).toBe(12000);
  });

  test('KZ — 12% on subtotal', () => {
    const r = tax.compute({ subtotal: 5000, deliveryFee: 800, country: 'KZ' });
    expect(r.taxRate).toBe(0.12);
    expect(r.taxAmount).toBe(600);
  });

  test('KG — 12% on subtotal', () => {
    const r = tax.compute({ subtotal: 500, deliveryFee: 100, country: 'KG' });
    expect(r.taxRate).toBe(0.12);
    expect(r.taxAmount).toBe(60);
  });

  test('RU — 20% on subtotal', () => {
    const r = tax.compute({ subtotal: 1000, deliveryFee: 200, country: 'RU' });
    expect(r.taxRate).toBe(0.20);
    expect(r.taxAmount).toBe(200);
  });

  test('rounds to whole major units', () => {
    // 12% of 1234 = 148.08 → 148
    const r = tax.compute({ subtotal: 1234, deliveryFee: 0, country: 'UZ' });
    expect(r.taxAmount).toBe(148);
  });

  test('zero subtotal yields zero tax', () => {
    const r = tax.compute({ subtotal: 0, deliveryFee: 5000, country: 'UZ' });
    expect(r.taxAmount).toBe(0);
  });

  test('non-numeric subtotal coerced to 0', () => {
    const r = tax.compute({ subtotal: undefined, deliveryFee: 0, country: 'UZ' });
    expect(r.taxAmount).toBe(0);
  });
});
