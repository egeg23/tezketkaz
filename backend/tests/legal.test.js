// Phase 12 — legal document HTTP endpoint tests.
//
// The router loads the Markdown files under backend/legal at module init and
// serves them as JSON. We exercise the locale-resolution rules and the /all
// combo endpoint.

const request = require('supertest');
const { setupTestDb, teardownTestDb } = require('./helpers/db');

let ctx;

beforeAll(async () => { ctx = await setupTestDb('legal'); }, 30000);
afterAll(async () => { await teardownTestDb(ctx); });

describe('GET /api/legal/privacy', () => {
  test('returns ru content for locale=ru', async () => {
    const res = await request(ctx.app).get('/api/legal/privacy?locale=ru');
    expect(res.status).toBe(200);
    expect(res.body.doc).toBe('privacy');
    expect(res.body.locale).toBe('ru');
    expect(typeof res.body.content).toBe('string');
    // The ru policy contains "Политика конфиденциальности" in its title.
    expect(res.body.content).toMatch(/Политика конфиденциальности/);
    // Cache header is set so app/CDN can re-use the body for an hour.
    expect(res.headers['cache-control']).toMatch(/max-age=3600/);
    expect(res.body.updatedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  test('returns uz content for locale=uz', async () => {
    const res = await request(ctx.app).get('/api/legal/privacy?locale=uz');
    expect(res.status).toBe(200);
    expect(res.body.locale).toBe('uz');
    expect(res.body.content).toMatch(/Maxfiylik siyosati/);
  });

  test('returns en content for locale=en', async () => {
    const res = await request(ctx.app).get('/api/legal/privacy?locale=en');
    expect(res.status).toBe(200);
    expect(res.body.locale).toBe('en');
    expect(res.body.content).toMatch(/Privacy Policy/);
  });

  test('falls back to ru when locale unsupported', async () => {
    const res = await request(ctx.app).get('/api/legal/privacy?locale=zz');
    expect(res.status).toBe(200);
    // Unsupported locales normalise to the fallback (ru) before lookup.
    expect(res.body.locale).toBe('ru');
    expect(res.body.content).toMatch(/Политика конфиденциальности/);
  });

  test('falls back when locale is missing entirely', async () => {
    const res = await request(ctx.app).get('/api/legal/privacy');
    expect(res.status).toBe(200);
    expect(res.body.locale).toBe('ru');
  });
});

describe('GET /api/legal/terms', () => {
  test('returns terms in ru', async () => {
    const res = await request(ctx.app).get('/api/legal/terms?locale=ru');
    expect(res.status).toBe(200);
    expect(res.body.doc).toBe('terms');
    expect(res.body.locale).toBe('ru');
    expect(res.body.content).toMatch(/Условия использования/);
  });

  test('returns terms in kk', async () => {
    const res = await request(ctx.app).get('/api/legal/terms?locale=kk');
    expect(res.status).toBe(200);
    expect(res.body.locale).toBe('kk');
    // The Kazakh file should mention "Қызмет көрсету шарттары".
    expect(res.body.content).toMatch(/Қызмет/);
  });
});

describe('GET /api/legal/all', () => {
  test('returns both docs for the requested locale', async () => {
    const res = await request(ctx.app).get('/api/legal/all?locale=uz');
    expect(res.status).toBe(200);
    expect(res.body.privacy).toBeDefined();
    expect(res.body.terms).toBeDefined();
    expect(res.body.privacy.doc).toBe('privacy');
    expect(res.body.privacy.locale).toBe('uz');
    expect(res.body.terms.doc).toBe('terms');
    expect(res.body.terms.locale).toBe('uz');
    expect(res.body.privacy.content).toMatch(/Maxfiylik siyosati/);
    expect(res.body.terms.content).toMatch(/Foydalanish shartlari/);
  });

  test('all endpoint also falls back when locale is bogus', async () => {
    const res = await request(ctx.app).get('/api/legal/all?locale=xx');
    expect(res.status).toBe(200);
    expect(res.body.privacy.locale).toBe('ru');
    expect(res.body.terms.locale).toBe('ru');
  });
});
