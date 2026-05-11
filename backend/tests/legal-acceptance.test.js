// Phase 13.1.5 — legal acceptance enforcement.
//
// Covers POST /api/auth/verify-otp acceptance gating for new users, the
// `legalUpdateRequired` signal for existing users on outdated versions, and
// the POST /api/auth/accept-legal endpoint used to refresh acceptance after
// a legal-version bump.

const request = require('supertest');

const { setupTestDb, teardownTestDb, createUser } = require('./helpers/db');
const {
  CURRENT_LEGAL_VERSION,
} = require('../src/constants/legal');

let ctx;
let prisma;
let app;

beforeAll(async () => {
  ctx = await setupTestDb('legal-acceptance');
  prisma = ctx.prisma;
  app = ctx.app;
  // helpers/db.js doesn't mount /api/auth by default — add it for this suite.
  app.use('/api/auth', require('../src/routes/auth'));
}, 60000);

afterAll(async () => {
  await teardownTestDb(ctx);
});

// Helper — runs the OTP send+verify pair for a fresh phone.
async function sendOtp(phone) {
  const res = await request(app).post('/api/auth/send-otp').send({ phone });
  expect(res.status).toBe(200);
  expect(res.body.devCode).toBe('123456');
  return res.body.devCode;
}

describe('verify-otp legal acceptance — new user', () => {
  test('rejects when acceptedLegalVersion is missing', async () => {
    const phone = '+998900000001';
    await sendOtp(phone);

    const res = await request(app)
      .post('/api/auth/verify-otp')
      .send({ phone, code: '123456' });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('legal_acceptance_required');
    expect(res.body.currentVersion).toBe(CURRENT_LEGAL_VERSION);

    // No user should have been created.
    const user = await prisma.user.findUnique({ where: { phone } });
    expect(user).toBeNull();
  });

  test('rejects when acceptedLegalVersion is unknown', async () => {
    const phone = '+998900000002';
    await sendOtp(phone);

    const res = await request(app)
      .post('/api/auth/verify-otp')
      .send({ phone, code: '123456', acceptedLegalVersion: 'v999.999' });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('legal_acceptance_required');
    expect(res.body.currentVersion).toBe(CURRENT_LEGAL_VERSION);

    const user = await prisma.user.findUnique({ where: { phone } });
    expect(user).toBeNull();
  });

  test('accepts and persists acceptedLegalAt + version on valid version', async () => {
    const phone = '+998900000003';
    await sendOtp(phone);

    const res = await request(app)
      .post('/api/auth/verify-otp')
      .send({ phone, code: '123456', acceptedLegalVersion: CURRENT_LEGAL_VERSION });

    expect(res.status).toBe(200);
    expect(res.body.accessToken).toBeTruthy();
    expect(res.body.legalUpdateRequired).toBe(false);
    expect(res.body.currentLegalVersion).toBe(CURRENT_LEGAL_VERSION);

    const user = await prisma.user.findUnique({ where: { phone } });
    expect(user).not.toBeNull();
    expect(user.acceptedLegalVersion).toBe(CURRENT_LEGAL_VERSION);
    expect(user.acceptedLegalAt).toBeInstanceOf(Date);
  });
});

describe('verify-otp legal acceptance — existing user', () => {
  test('current-version user logs in without legalUpdateRequired flag', async () => {
    const phone = '+998900000010';
    // Pre-create the user as if they accepted on signup.
    await prisma.user.create({
      data: {
        phone,
        acceptedLegalAt: new Date(),
        acceptedLegalVersion: CURRENT_LEGAL_VERSION,
      },
    });
    await sendOtp(phone);

    const res = await request(app)
      .post('/api/auth/verify-otp')
      .send({ phone, code: '123456' });

    expect(res.status).toBe(200);
    expect(res.body.legalUpdateRequired).toBe(false);
    expect(res.body.currentLegalVersion).toBe(CURRENT_LEGAL_VERSION);
  });

  test('outdated-version user logs in with legalUpdateRequired=true', async () => {
    const phone = '+998900000011';
    await prisma.user.create({
      data: {
        phone,
        acceptedLegalAt: new Date('2024-01-01'),
        acceptedLegalVersion: 'v0.9',
      },
    });
    await sendOtp(phone);

    const res = await request(app)
      .post('/api/auth/verify-otp')
      .send({ phone, code: '123456' });

    expect(res.status).toBe(200);
    expect(res.body.accessToken).toBeTruthy();
    expect(res.body.legalUpdateRequired).toBe(true);
    expect(res.body.currentLegalVersion).toBe(CURRENT_LEGAL_VERSION);
  });
});

describe('POST /api/auth/accept-legal', () => {
  test('rejects unauthenticated requests with 401', async () => {
    const res = await request(app)
      .post('/api/auth/accept-legal')
      .send({ version: CURRENT_LEGAL_VERSION });
    expect(res.status).toBe(401);
  });

  test('updates acceptedLegalAt + version on current version', async () => {
    // Seed an authenticated user that was on an older legal version.
    const { user, auth } = await createUser(prisma, { phone: '+998900000020' });
    await prisma.user.update({
      where: { id: user.id },
      data: {
        acceptedLegalAt: new Date('2024-01-01'),
        acceptedLegalVersion: 'v0.9',
      },
    });

    const res = await request(app)
      .post('/api/auth/accept-legal')
      .set('Authorization', auth)
      .send({ version: CURRENT_LEGAL_VERSION });

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    const updated = await prisma.user.findUnique({ where: { id: user.id } });
    expect(updated.acceptedLegalVersion).toBe(CURRENT_LEGAL_VERSION);
    expect(updated.acceptedLegalAt).toBeInstanceOf(Date);
    expect(updated.acceptedLegalAt.getTime()).toBeGreaterThan(
      new Date('2024-01-02').getTime(),
    );
  });

  test('rejects an unknown version with 400', async () => {
    const { auth } = await createUser(prisma, { phone: '+998900000021' });
    const res = await request(app)
      .post('/api/auth/accept-legal')
      .set('Authorization', auth)
      .send({ version: 'v999.999' });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('invalid_legal_version');
    expect(res.body.currentVersion).toBe(CURRENT_LEGAL_VERSION);
  });
});
