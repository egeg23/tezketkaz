// Phase 9.3 — social login (Apple + Google) tests.

const request = require('supertest');
const { setupTestDb, teardownTestDb } = require('./helpers/db');

let ctx;
let prisma;

beforeAll(async () => {
  ctx = await setupTestDb('social-auth');
  prisma = ctx.prisma;
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('POST /api/auth/oauth/apple', () => {
  test('mock token issues JWT pair; new user created with appleSubject set', async () => {
    const sub = 'apple-sub-' + Date.now();
    const res = await request(ctx.app)
      .post('/api/auth/oauth/apple')
      .send({ idToken: `mock_apple_${sub}_alice@example.com` });
    expect(res.status).toBe(200);
    expect(res.body.accessToken).toBeTruthy();
    expect(res.body.refreshToken).toBeTruthy();
    expect(res.body.user.pendingPhone).toBe(true);

    const u = await prisma.user.findFirst({ where: { appleSubject: sub } });
    expect(u).not.toBeNull();
    expect(u.email).toBe('alice@example.com');
  });

  test('same Apple sub on second login → same user', async () => {
    const sub = 'apple-sub-recur-' + Date.now();
    const r1 = await request(ctx.app)
      .post('/api/auth/oauth/apple')
      .send({ idToken: `mock_apple_${sub}_bob@example.com` });
    const r2 = await request(ctx.app)
      .post('/api/auth/oauth/apple')
      .send({ idToken: `mock_apple_${sub}_bob@example.com` });
    expect(r1.body.user.id).toBe(r2.body.user.id);
  });

  test('invalid token format returns 400', async () => {
    const res = await request(ctx.app)
      .post('/api/auth/oauth/apple')
      .send({ idToken: 'not-a-valid-token' });
    expect(res.status).toBe(400);
  });

  test('missing idToken returns 400', async () => {
    const res = await request(ctx.app)
      .post('/api/auth/oauth/apple')
      .send({});
    expect(res.status).toBe(400);
  });
});

describe('POST /api/auth/oauth/google — email-match linking', () => {
  test('user signed up via OTP with email; Google login with same email → google sub linked', async () => {
    // Create a user via direct DB write to simulate prior OTP signup.
    const phone = '+998' + String(Math.floor(Math.random() * 1e9)).padStart(9, '0').slice(0, 9);
    const existing = await prisma.user.create({
      data: {
        phone,
        email: 'shared@example.com',
        name: 'Shared',
      },
    });

    const sub = 'google-sub-' + Date.now();
    const res = await request(ctx.app)
      .post('/api/auth/oauth/google')
      .send({ idToken: `mock_google_${sub}_shared@example.com` });
    expect(res.status).toBe(200);
    expect(res.body.user.id).toBe(existing.id);
    // pendingPhone should be false because they have a real phone.
    expect(res.body.user.pendingPhone).toBe(false);

    const after = await prisma.user.findUnique({ where: { id: existing.id } });
    expect(after.googleSubject).toBe(sub);
  });
});
