// Phase 7 — services/kaspi.js mock-mode tests.
//
// Real Kaspi credentials aren't provisioned at launch; mock mode is the only
// path we can exercise without touching the network. We assert the public
// surface: pay returns a redirect URL, tokenizeCard returns a mockToken,
// chargeWithToken succeeds with a deterministic externalId.

// Force mock mode BEFORE requiring the module so env.useMockPayments is true.
process.env.USE_MOCK_PAYMENTS = 'true';
delete process.env.KASPI_MERCHANT_ID;
delete process.env.KASPI_SECRET;

const kaspi = require('../src/services/kaspi');

describe('kaspi.pay (mock mode)', () => {
  test('returns mock redirect URL + externalId when no merchant id', async () => {
    const r = await kaspi.pay({ orderId: 'ord-1', amount: 5000, currency: 'KZT' });
    expect(r.ok).toBe(true);
    expect(r.redirectUrl).toBe('mock://kaspi/ord-1');
    expect(r.externalId).toBe('mock_kaspi_ord-1');
  });

  test('throws on missing orderId', async () => {
    await expect(kaspi.pay({})).rejects.toThrow(/orderId required/);
  });
});

describe('kaspi.tokenizeCard (mock mode)', () => {
  test('returns deterministic mock token for tests', async () => {
    const r = await kaspi.tokenizeCard('user-1');
    expect(r.provider).toBe('kaspi');
    expect(r.mockToken).toMatch(/^mock_kaspi_token_user-1_/);
    expect(r.state).toMatch(/^kaspi_state_user-1_/);
    expect(r.redirectUrl).toContain('payment-method-result');
  });

  test('throws on missing userId', async () => {
    await expect(kaspi.tokenizeCard()).rejects.toThrow(/userId required/);
  });
});

describe('kaspi.chargeWithToken (mock mode)', () => {
  test('succeeds with mock externalId', async () => {
    const r = await kaspi.chargeWithToken('mock_token', 1000, 'ord-2', 'KZT');
    expect(r.ok).toBe(true);
    expect(r.externalId).toMatch(/^mock_kaspi_charge_ord-2_/);
    expect(r.message).toBe('ok');
  });

  test('rejects missing token', async () => {
    const r = await kaspi.chargeWithToken(null, 1000);
    expect(r.ok).toBe(false);
    expect(r.message).toBe('token_required');
  });

  test('rejects invalid amount', async () => {
    const r = await kaspi.chargeWithToken('tok', 0);
    expect(r.ok).toBe(false);
    expect(r.message).toBe('invalid_amount');
  });

  test('rejects negative amount', async () => {
    const r = await kaspi.chargeWithToken('tok', -100);
    expect(r.ok).toBe(false);
    expect(r.message).toBe('invalid_amount');
  });
});

describe('kaspi.verifySignature', () => {
  test('returns false without KASPI_SECRET configured', () => {
    expect(kaspi.verifySignature(Buffer.from('{}'), 'abc')).toBe(false);
  });
});

describe('kaspi.callback (mock mode)', () => {
  test('returns invalid_signature without secret/header', async () => {
    const fakeReq = {
      body: { transactionId: 't1', orderId: 'o1', status: 'paid' },
      headers: {},
      get: () => null,
    };
    const r = await kaspi.callback(fakeReq);
    expect(r.ok).toBe(false);
    expect(r.error).toBe('invalid_signature');
  });

  test('rejects null req', async () => {
    const r = await kaspi.callback(null);
    expect(r.ok).toBe(false);
  });
});
