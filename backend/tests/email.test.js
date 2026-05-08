// Phase 7 — services/email.js unit tests.
//
// Resend SDK is lazy-required; we never install it for tests, and the absent
// RESEND_API_KEY path returns { skipped:true, reason:'no_api_key' } without
// touching the network. We assert: interpolation, locale fallback to uz,
// missing-template handling, and noop without API key.

// Make sure env doesn't leak a key from the host shell.
delete process.env.RESEND_API_KEY;

const email = require('../src/services/email');

describe('email.interpolate', () => {
  test('replaces {placeholder} tokens', () => {
    const out = email.interpolate('Hello {name}, order #{orderNumber}', {
      name: 'Ali', orderNumber: 'K-101',
    });
    expect(out).toBe('Hello Ali, order #K-101');
  });

  test('leaves unknown placeholders untouched', () => {
    const out = email.interpolate('Hello {who}', {});
    expect(out).toBe('Hello {who}');
  });

  test('handles null/undefined data safely', () => {
    expect(email.interpolate('hi', null)).toBe('hi');
    expect(email.interpolate(null, {})).toBe('');
  });

  test('does not crash on multi-token templates', () => {
    const out = email.interpolate('{a}-{b}-{a}', { a: 'X', b: 'Y' });
    expect(out).toBe('X-Y-X');
  });
});

describe('email.send (no API key) → noop', () => {
  test('returns skipped when RESEND_API_KEY is unset', async () => {
    const r = await email.send({
      to: 'user@example.com',
      locale: 'ru',
      template: 'order_confirmation',
      data: { name: 'A', orderNumber: '1', total: '10', currency: 'UZS' },
    });
    expect(r.skipped).toBe(true);
    expect(r.reason).toBe('no_api_key');
  });

  test('returns skipped when no recipient', async () => {
    const r = await email.send({ template: 'order_confirmation' });
    expect(r.skipped).toBe(true);
    expect(r.reason).toBe('no_recipient');
  });

  test('returns skipped on unknown template', async () => {
    const r = await email.send({ to: 'a@b.com', template: 'nonsense' });
    expect(r.skipped).toBe(true);
    expect(r.reason).toBe('unknown_template');
  });
});

describe('email locale fallback', () => {
  test('unknown locale falls back to uz', () => {
    expect(email._pickLocale('zz')).toBe('uz');
    expect(email._pickLocale(undefined)).toBe('uz');
    expect(email._pickLocale('')).toBe('uz');
  });

  test('all four locales are recognized', () => {
    expect(email._pickLocale('uz')).toBe('uz');
    expect(email._pickLocale('ru')).toBe('ru');
    expect(email._pickLocale('en')).toBe('en');
    expect(email._pickLocale('kk')).toBe('kk');
  });
});

describe('email TEMPLATES coverage', () => {
  test('every template has uz / ru / en / kk variants', () => {
    for (const [name, bundle] of Object.entries(email.TEMPLATES)) {
      for (const loc of ['uz', 'ru', 'en', 'kk']) {
        expect(bundle[loc]).toBeDefined();
        expect(typeof bundle[loc].subject).toBe('string');
        expect(typeof bundle[loc].body).toBe('string');
        expect(bundle[loc].subject.length).toBeGreaterThan(0);
        // Sanity — name resolution pulls a real bundle, not an alias.
        expect(name).toBeTruthy();
      }
    }
  });
});
