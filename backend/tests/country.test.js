// Phase 7 — services/country.js unit tests.
//
// fromPhone() drives auth signup. info() drives currency/VAT/provider mix.
// We assert the prefix priority — most importantly, +77... must classify as
// KZ rather than RU even though both share +7.

const country = require('../src/services/country');

describe('country.fromPhone', () => {
  test('UZ for +998 prefix', () => {
    expect(country.fromPhone('+998901234567')).toBe('UZ');
  });

  test('KG for +996 prefix', () => {
    expect(country.fromPhone('+996700123456')).toBe('KG');
  });

  test('KZ for +77 (mobile) prefix — must beat the bare +7 RU rule', () => {
    expect(country.fromPhone('+77001234567')).toBe('KZ');
    expect(country.fromPhone('+77071234567')).toBe('KZ');
  });

  test('RU for +7 (non-77) prefix', () => {
    expect(country.fromPhone('+79161234567')).toBe('RU');
  });

  test('falls back to UZ on null/empty/unknown', () => {
    expect(country.fromPhone(null)).toBe('UZ');
    expect(country.fromPhone('')).toBe('UZ');
    expect(country.fromPhone('+12025550100')).toBe('UZ'); // US — unsupported, falls back
    expect(country.fromPhone(undefined)).toBe('UZ');
  });
});

describe('country.info', () => {
  test('returns full record for each supported country', () => {
    expect(country.info('UZ').currency).toBe('UZS');
    expect(country.info('UZ').vatRate).toBe(0.12);
    expect(country.info('UZ').locale).toBe('uz');
    expect(country.info('UZ').providers).toContain('click');

    expect(country.info('KZ').currency).toBe('KZT');
    expect(country.info('KZ').locale).toBe('kk');
    expect(country.info('KZ').providers).toContain('kaspi');

    expect(country.info('KG').currency).toBe('KGS');
    expect(country.info('KG').providers).toContain('click_kg');

    expect(country.info('RU').currency).toBe('RUB');
    expect(country.info('RU').vatRate).toBe(0.20);
  });

  test('unknown country falls back to UZ', () => {
    expect(country.info('ZZ').currency).toBe('UZS');
    expect(country.info(null).currency).toBe('UZS');
    expect(country.info(undefined).currency).toBe('UZS');
  });
});

describe('country.isProviderAvailable', () => {
  test('cash always available', () => {
    expect(country.isProviderAvailable('UZ', 'cash')).toBe(true);
    expect(country.isProviderAvailable('KZ', 'cash')).toBe(true);
    expect(country.isProviderAvailable('KG', 'cash')).toBe(true);
    expect(country.isProviderAvailable('RU', 'cash')).toBe(true);
  });

  test('kaspi only in KZ', () => {
    expect(country.isProviderAvailable('KZ', 'kaspi')).toBe(true);
    expect(country.isProviderAvailable('UZ', 'kaspi')).toBe(false);
  });

  test('click only in UZ', () => {
    expect(country.isProviderAvailable('UZ', 'click')).toBe(true);
    expect(country.isProviderAvailable('KG', 'click')).toBe(false);
  });
});
