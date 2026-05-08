const crypto = require('crypto');

process.env.UZUM_SECRET_KEY = 'uzum-secret';
process.env.USE_MOCK_PAYMENTS = 'false';

const uzum = require('../src/services/uzum');

function hmac(body, secret) {
  return crypto.createHmac('sha256', secret).update(body).digest('hex');
}

describe('Uzum HMAC verification', () => {
  test('valid signature accepted', () => {
    const body = JSON.stringify({ orderId: 'o1', amount: 100, status: 'paid' });
    const sig = hmac(body, 'uzum-secret');
    expect(uzum.verifySignature(Buffer.from(body), sig)).toBe(true);
  });

  test('mismatched signature rejected', () => {
    const body = '{"a":1}';
    expect(uzum.verifySignature(Buffer.from(body), 'deadbeef'.repeat(8))).toBe(false);
  });

  test('missing signature rejected', () => {
    expect(uzum.verifySignature(Buffer.from('{}'), undefined)).toBe(false);
    expect(uzum.verifySignature(Buffer.from('{}'), '')).toBe(false);
  });

  test('different-length signature rejected without throwing', () => {
    expect(uzum.verifySignature(Buffer.from('{}'), 'abc')).toBe(false);
  });

  test('handleCallback ignores body when signatureValid=false', async () => {
    const result = await uzum.handleCallback({ orderId: 'o-fake', status: 'paid' }, { signatureValid: false });
    expect(result.ok).toBe(false);
  });
});
