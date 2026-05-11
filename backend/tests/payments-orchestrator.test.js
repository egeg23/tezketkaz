// Phase 13.1.7 — payments orchestrator + diagnose script unit tests.
//
// These tests don't touch the network — pingUrl is mocked or tested with a
// known-unreachable host. We only assert the pure-logic surface.

process.env.USE_MOCK_PAYMENTS = 'true';

const payments = require('../src/services/payments');
const diagnose = require('../scripts/payment-diagnose');

describe('payments orchestrator', () => {
  test('preferredProviderFor(UZ) → click (first in providers list)', () => {
    expect(payments.preferredProviderFor('UZ')).toBe('click');
  });

  test('preferredProviderFor(KZ) → kaspi', () => {
    expect(payments.preferredProviderFor('KZ')).toBe('kaspi');
  });

  test('preferredProviderFor(KG) → click_kg', () => {
    expect(payments.preferredProviderFor('KG')).toBe('click_kg');
  });

  test('preferredProviderFor(unknown) falls back to UZ default', () => {
    expect(payments.preferredProviderFor('ZZ')).toBe('click');
  });

  test('preferredProviderFor(RU) → null (cash-only)', () => {
    expect(payments.preferredProviderFor('RU')).toBe(null);
  });

  test('availableProvidersFor(UZ) lists click, payme, uzum', () => {
    const list = payments.availableProvidersFor('UZ');
    expect(list).toEqual(expect.arrayContaining(['click', 'payme', 'uzum']));
    expect(list).not.toContain('cash');
  });

  test('isProviderAllowed gating', () => {
    expect(payments.isProviderAllowed('UZ', 'click')).toBe(true);
    expect(payments.isProviderAllowed('UZ', 'kaspi')).toBe(false);
    expect(payments.isProviderAllowed('KZ', 'kaspi')).toBe(true);
    expect(payments.isProviderAllowed('KZ', 'click')).toBe(false);
  });

  test('getProvider returns the actual module', () => {
    const click = payments.getProvider('click');
    expect(click).toBeTruthy();
    expect(typeof click.createInvoice).toBe('function');
    expect(typeof click.verifyCallback).toBe('function');
  });

  test('getProvider returns null for unknown', () => {
    expect(payments.getProvider('stripe')).toBe(null);
    expect(payments.getProvider('')).toBe(null);
    expect(payments.getProvider(null)).toBe(null);
  });
});

describe('payment-diagnose script', () => {
  test('PROVIDERS map exposes all 5 providers', () => {
    expect(Object.keys(diagnose.PROVIDERS).sort()).toEqual(
      ['click', 'click_kg', 'kaspi', 'payme', 'uzum'].sort(),
    );
  });

  test('click signature generator produces 32-char md5 hex', () => {
    const sig = diagnose.PROVIDERS.click.sign({ CLICK_SERVICE_ID: '1', CLICK_SECRET_KEY: 's' });
    expect(sig.name).toBe('sign_string');
    expect(sig.scheme).toBe('md5');
    expect(sig.value).toMatch(/^[a-f0-9]{32}$/);
  });

  test('payme signature generator produces a Basic auth header', () => {
    const sig = diagnose.PROVIDERS.payme.sign({ PAYME_KEY: 'secret' });
    expect(sig.name).toBe('Authorization');
    expect(sig.value).toMatch(/^Basic /);
    expect(Buffer.from(sig.value.slice(6), 'base64').toString('utf8')).toBe('Paycom:secret');
  });

  test('uzum signature generator produces 64-char hmac hex', () => {
    const sig = diagnose.PROVIDERS.uzum.sign({ UZUM_SECRET_KEY: 'secret' });
    expect(sig.name).toBe('X-Uzum-Signature');
    expect(sig.value).toMatch(/^[a-f0-9]{64}$/);
  });

  test('kaspi signature generator produces 64-char hmac hex', () => {
    const sig = diagnose.PROVIDERS.kaspi.sign({ KASPI_SECRET: 'secret' });
    expect(sig.name).toBe('X-Kaspi-Signature');
    expect(sig.value).toMatch(/^[a-f0-9]{64}$/);
  });

  test('pingUrl resolves to ok=false on unreachable host without throwing', async () => {
    // 198.51.100.0/24 is TEST-NET-2 (RFC 5737) — guaranteed unroutable, so
    // we get a fast connection failure rather than a hang.
    const r = await diagnose.pingUrl('https://198.51.100.1:1/');
    expect(r).toHaveProperty('ok');
    expect(typeof r.message).toBe('string');
  }, 10000);
});
