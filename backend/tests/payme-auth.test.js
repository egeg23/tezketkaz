process.env.PAYME_KEY = 'payme-test-key';
process.env.USE_MOCK_PAYMENTS = 'false';

const payme = require('../src/services/payme');

describe('Payme Basic Auth verification', () => {
  test('accepts correct Paycom:KEY base64', () => {
    const header = 'Basic ' + Buffer.from('Paycom:payme-test-key').toString('base64');
    expect(payme.verifyAuthHeader(header)).toBe(true);
  });

  test('rejects wrong key', () => {
    const header = 'Basic ' + Buffer.from('Paycom:wrong').toString('base64');
    expect(payme.verifyAuthHeader(header)).toBe(false);
  });

  test('rejects wrong username', () => {
    const header = 'Basic ' + Buffer.from('attacker:payme-test-key').toString('base64');
    expect(payme.verifyAuthHeader(header)).toBe(false);
  });

  test('rejects missing header', () => {
    expect(payme.verifyAuthHeader(undefined)).toBe(false);
    expect(payme.verifyAuthHeader('')).toBe(false);
    expect(payme.verifyAuthHeader('Bearer xyz')).toBe(false);
  });

  test('rejects malformed base64', () => {
    expect(payme.verifyAuthHeader('Basic not_base64!!!!')).toBe(false);
  });
});
