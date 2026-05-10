// Phase 11 — onboarding completion stamp.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser } = require('./helpers/db');

let ctx;
let prisma;
let buyer;

beforeAll(async () => {
  ctx = await setupTestDb('users-onboarding');
  prisma = ctx.prisma;
  buyer = await createUser(prisma);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('GET /api/users/me/onboarding-status', () => {
  test('returns onboarded=false for a brand-new user', async () => {
    const res = await request(ctx.app)
      .get('/api/users/me/onboarding-status')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.onboarded).toBe(false);
    expect(res.body.completedAt).toBeUndefined();
  });

  test('requires auth', async () => {
    const res = await request(ctx.app).get('/api/users/me/onboarding-status');
    expect(res.status).toBe(401);
  });
});

describe('PATCH /api/users/me with onboardedAt', () => {
  test('setting onboardedAt: "now" stamps the column server-side', async () => {
    const before = Date.now();
    const res = await request(ctx.app)
      .patch('/api/users/me')
      .set('Authorization', buyer.auth)
      .send({ onboardedAt: 'now' });
    expect(res.status).toBe(200);
    expect(res.body.user.onboardedAt).toBeTruthy();
    const stampedAt = new Date(res.body.user.onboardedAt).getTime();
    expect(stampedAt).toBeGreaterThanOrEqual(before - 1000);
    expect(stampedAt).toBeLessThanOrEqual(Date.now() + 1000);
  });

  test('value sent by client is ignored — server always uses now()', async () => {
    // Send an absurd ISO date to verify the server overrides it.
    const fakePast = '2001-01-01T00:00:00.000Z';
    const res = await request(ctx.app)
      .patch('/api/users/me')
      .set('Authorization', buyer.auth)
      .send({ onboardedAt: fakePast });
    expect(res.status).toBe(200);
    expect(new Date(res.body.user.onboardedAt).getFullYear())
      .toBeGreaterThan(2020);
  });

  test('subsequent GET reflects onboarded=true with completedAt', async () => {
    const res = await request(ctx.app)
      .get('/api/users/me/onboarding-status')
      .set('Authorization', buyer.auth);
    expect(res.status).toBe(200);
    expect(res.body.onboarded).toBe(true);
    expect(res.body.completedAt).toBeTruthy();
    expect(Number.isNaN(new Date(res.body.completedAt).getTime())).toBe(false);
  });
});
