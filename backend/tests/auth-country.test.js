// Phase 7 — auth signup auto-sets User.country from phone prefix.
//
// We exercise the live POST /api/auth/verify-otp path via supertest. The
// helper boots a per-file SQLite DB, runs migrations, and we mount /api/auth
// onto a fresh Express app so we don't depend on the full server stack.

const request = require('supertest');
const express = require('express');
const { setupTestDb, teardownTestDb } = require('./helpers/db');

let ctx;
let app;

beforeAll(async () => {
  ctx = await setupTestDb('auth-country');
  app = express();
  app.use(express.json());
  // Stub `req.id` so pino-http downstream doesn't choke if it fires.
  app.use((req, res, next) => { req.id = 'test'; next(); });
  app.use('/api/auth', require('../src/routes/auth'));
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, _next) => {
    res.status(err.status || 500).json({ error: err.message });
  });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function sendAndGetCode(phone) {
  // /send-otp seeds an OtpCode row; in test env useMockSms=true so the code
  // is the deterministic '123456' but we read it from the DB to be safe.
  const r = await request(app).post('/api/auth/send-otp').send({ phone });
  expect(r.status).toBe(200);
  const otp = await ctx.prisma.otpCode.findFirst({
    where: { phone },
    orderBy: { createdAt: 'desc' },
  });
  return otp.code;
}

describe('auth signup country auto-detection', () => {
  test('+77 phone signup → User.country = KZ + locale = kk', async () => {
    const phone = '+77011234567';
    const code = await sendAndGetCode(phone);
    const r = await request(app).post('/api/auth/verify-otp').send({ phone, code });
    expect(r.status).toBe(200);
    expect(r.body.user.country).toBe('KZ');
    // Default locale for KZ is Kazakh.
    expect(r.body.user.locale).toBe('kk');

    const dbUser = await ctx.prisma.user.findUnique({ where: { phone } });
    expect(dbUser.country).toBe('KZ');
    expect(dbUser.locale).toBe('kk');
  });

  test('+998 phone signup → User.country = UZ + locale = uz', async () => {
    const phone = '+998901234567';
    const code = await sendAndGetCode(phone);
    const r = await request(app).post('/api/auth/verify-otp').send({ phone, code });
    expect(r.status).toBe(200);
    expect(r.body.user.country).toBe('UZ');
    expect(r.body.user.locale).toBe('uz');
  });

  test('+996 phone signup → User.country = KG + locale = ru', async () => {
    const phone = '+996700123456';
    const code = await sendAndGetCode(phone);
    const r = await request(app).post('/api/auth/verify-otp').send({ phone, code });
    expect(r.status).toBe(200);
    expect(r.body.user.country).toBe('KG');
    expect(r.body.user.locale).toBe('ru');
  });

  test('+79 (RU) phone signup → User.country = RU', async () => {
    const phone = '+79161234567';
    const code = await sendAndGetCode(phone);
    const r = await request(app).post('/api/auth/verify-otp').send({ phone, code });
    expect(r.status).toBe(200);
    expect(r.body.user.country).toBe('RU');
    expect(r.body.user.locale).toBe('ru');
  });

  test('repeat verify on existing user keeps country (no overwrite)', async () => {
    const phone = '+77051234567';
    const code = await sendAndGetCode(phone);
    const r = await request(app).post('/api/auth/verify-otp').send({ phone, code });
    expect(r.status).toBe(200);
    expect(r.body.user.country).toBe('KZ');

    // Manually flip country to RU. Re-verifying should NOT clobber it because
    // the auto-detect path only runs on creation OR when country is null
    // (backfill). We assert by direct DB read — the OTP debounce makes a full
    // round-trip flaky in unit tests.
    await ctx.prisma.user.update({
      where: { phone },
      data: { country: 'RU' },
    });

    // Backdate the recent OtpCode + clear redis-style fail counters so
    // verify can run immediately. Then issue a fresh OTP via direct DB insert
    // (bypassing the 60s debounce on send-otp).
    await ctx.prisma.otpCode.create({
      data: {
        phone,
        code: '654321',
        expiresAt: new Date(Date.now() + 5 * 60_000),
      },
    });
    const r2 = await request(app)
      .post('/api/auth/verify-otp')
      .send({ phone, code: '654321' });
    expect(r2.status).toBe(200);
    expect(r2.body.user.country).toBe('RU');
  });
});
