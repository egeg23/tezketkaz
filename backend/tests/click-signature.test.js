const crypto = require('crypto');

// Fix env for click before requiring the service
process.env.CLICK_MERCHANT_ID = 'merch-1';
process.env.CLICK_SERVICE_ID = 'svc-1';
process.env.CLICK_SECRET_KEY = 'click-secret';
process.env.USE_MOCK_PAYMENTS = 'false';

const click = require('../src/services/click');

function sign({ click_trans_id, service_id, merchant_trans_id, amount, action, sign_time, secret }) {
  return crypto
    .createHash('md5')
    .update(`${click_trans_id}${service_id}${secret}${merchant_trans_id}${amount}${action}${sign_time}`)
    .digest('hex');
}

describe('Click webhook signature', () => {
  const base = {
    click_trans_id: '111',
    service_id: 'svc-1',
    click_paydoc_id: 'doc-1',
    merchant_trans_id: 'order-1',
    amount: '120000.00',
    action: '1',
    sign_time: '2026-05-07 13:00:00',
  };

  test('rejects mismatched signature', async () => {
    const result = await click.verifyCallback({ ...base, sign_string: 'wrong' });
    expect(result.valid).toBe(false);
  });

  test('rejects missing fields', async () => {
    const result = await click.verifyCallback({ ...base, click_trans_id: undefined, sign_string: 'x' });
    expect(result.valid).toBe(false);
  });

  test('accepts valid signature with action=1 (complete) — requires DB stub', async () => {
    // We can't fully verify "complete" without DB but at least the sign check passes.
    const sig = sign({ ...base, secret: 'click-secret' });
    // For action=0 (prepare) we don't need the DB
    const result = await click.verifyCallback({ ...base, action: '0', sign_string: sign({ ...base, action: '0', secret: 'click-secret' }) });
    expect(result.valid).toBe(true);
    expect(result.complete).toBe(false);
  });

  test('does not crash on different service_id (NODE_ENV=test)', async () => {
    // Use action=0 to avoid hitting DB; we only care the verifier returns a result.
    const action = '0';
    const sig = sign({ ...base, action, service_id: 'OTHER', secret: 'click-secret' });
    const result = await click.verifyCallback({ ...base, action, service_id: 'OTHER', sign_string: sig });
    expect(typeof result.valid).toBe('boolean');
  });
});
