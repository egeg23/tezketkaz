// Unit tests for JWT helpers that don't touch the database.
// Refresh-token flows that require Prisma are exercised in integration tests.

process.env.JWT_SECRET = 'jwt-test-secret-min-8-chars';
process.env.JWT_ACCESS_TTL = '5m';

const jwt = require('jsonwebtoken');

describe('JWT signAccess / verifyAccess', () => {
  let jwtLib;
  beforeAll(() => { jwtLib = require('../src/lib/jwt'); });

  test('signAccess produces a verifiable token with userId + jti', async () => {
    const { token, jti } = jwtLib.signAccess('user-abc');
    expect(token).toBeTruthy();
    expect(jti).toBeTruthy();
    const decoded = await jwtLib.verifyAccess(token);
    expect(decoded.userId).toBe('user-abc');
    expect(decoded.type).toBe('access');
    expect(decoded.jti).toBe(jti);
  });

  test('rejects token signed with wrong secret', async () => {
    const bad = jwt.sign({ userId: 'x', type: 'access' }, 'other-secret', { expiresIn: '5m' });
    await expect(jwtLib.verifyAccess(bad)).rejects.toThrow();
  });

  test('rejects expired access token', async () => {
    const expired = jwt.sign({ userId: 'x', type: 'access' }, process.env.JWT_SECRET, { expiresIn: -1 });
    await expect(jwtLib.verifyAccess(expired)).rejects.toThrow();
  });

  test('rejects refresh-typed token used as access', async () => {
    const wrongType = jwt.sign({ userId: 'x', type: 'refresh' }, process.env.JWT_SECRET, { expiresIn: '5m' });
    await expect(jwtLib.verifyAccess(wrongType)).rejects.toThrow();
  });
});

describe('Redis blacklist (in-memory fallback)', () => {
  let redis;
  beforeAll(() => { redis = require('../src/lib/redis'); });

  test('blacklisted jti reads as blacklisted', async () => {
    await redis.blacklistJti('jti-1', 60);
    expect(await redis.isJtiBlacklisted('jti-1')).toBe(true);
    expect(await redis.isJtiBlacklisted('jti-other')).toBe(false);
  });

  test('blacklist expires after TTL', async () => {
    await redis.blacklistJti('jti-2', 1);
    await new Promise((r) => setTimeout(r, 1100));
    expect(await redis.isJtiBlacklisted('jti-2')).toBe(false);
  });
});

describe('blacklistAccessToken', () => {
  let jwtLib;
  beforeAll(() => { jwtLib = require('../src/lib/jwt'); });

  test('blacklisting a token causes verifyAccess to reject it', async () => {
    const { token } = jwtLib.signAccess('user-blk');
    expect(await jwtLib.verifyAccess(token)).toBeTruthy(); // valid first
    await jwtLib.blacklistAccessToken(token);
    await expect(jwtLib.verifyAccess(token)).rejects.toThrow(/revoked|jti|verify/);
  });
});
