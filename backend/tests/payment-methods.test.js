// Phase 6.1 — saved payment methods CRUD + ownership checks.

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser } = require('./helpers/db');

let ctx;
let userA;
let userB;

beforeAll(async () => {
  ctx = await setupTestDb('payment-methods');
  userA = await createUser(ctx.prisma, { name: 'A' });
  userB = await createUser(ctx.prisma, { name: 'B' });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function confirmMethod(auth, body) {
  return request(ctx.app)
    .post('/api/payment-methods/me/confirm')
    .set('Authorization', auth)
    .send(body);
}

describe('POST /api/payment-methods/me/tokenize', () => {
  test('mock mode returns deterministic mock token', async () => {
    const res = await request(ctx.app)
      .post('/api/payment-methods/me/tokenize')
      .set('Authorization', userA.auth)
      .send({ provider: 'click' });
    expect(res.status).toBe(200);
    expect(res.body.provider).toBe('click');
    expect(res.body.state).toBeTruthy();
    expect(res.body.mockToken).toMatch(/^mock_click_/);
  });

  test('rejects invalid provider', async () => {
    const res = await request(ctx.app)
      .post('/api/payment-methods/me/tokenize')
      .set('Authorization', userA.auth)
      .send({ provider: 'kaspi' });
    expect(res.status).toBe(400);
  });
});

describe('payment method CRUD lifecycle', () => {
  test('create + list returns the saved method as default', async () => {
    const before = await request(ctx.app)
      .get('/api/payment-methods/me')
      .set('Authorization', userA.auth);
    expect(before.status).toBe(200);
    expect(before.body.items.length).toBe(0);

    const create = await confirmMethod(userA.auth, {
      provider: 'click',
      mockToken: 'mock_click_abc',
      last4: '4242',
      brand: 'visa',
      expiryMonth: 12,
      expiryYear: 2030,
    });
    expect(create.status).toBe(201);
    expect(create.body.method.isDefault).toBe(true);
    expect(create.body.method.last4).toBe('4242');
    // Crucially: never echoes back providerId / token.
    expect(create.body.method.providerId).toBeUndefined();

    const list = await request(ctx.app)
      .get('/api/payment-methods/me')
      .set('Authorization', userA.auth);
    expect(list.status).toBe(200);
    expect(list.body.items.length).toBe(1);
  });

  test('second method created defaults to non-default', async () => {
    const r = await confirmMethod(userA.auth, {
      provider: 'payme',
      mockToken: 'mock_payme_xyz',
      last4: '1234',
    });
    expect(r.status).toBe(201);
    expect(r.body.method.isDefault).toBe(false);
  });

  test('set-default flips others off atomically', async () => {
    const list = await request(ctx.app)
      .get('/api/payment-methods/me')
      .set('Authorization', userA.auth);
    const second = list.body.items.find((m) => !m.isDefault);
    expect(second).toBeTruthy();

    const setDef = await request(ctx.app)
      .post(`/api/payment-methods/${second.id}/default`)
      .set('Authorization', userA.auth)
      .send({});
    expect(setDef.status).toBe(200);
    expect(setDef.body.method.isDefault).toBe(true);

    const after = await request(ctx.app)
      .get('/api/payment-methods/me')
      .set('Authorization', userA.auth);
    const defaults = after.body.items.filter((m) => m.isDefault);
    expect(defaults.length).toBe(1);
    expect(defaults[0].id).toBe(second.id);
  });

  test('cannot set-default on another user\'s method', async () => {
    const list = await request(ctx.app)
      .get('/api/payment-methods/me')
      .set('Authorization', userA.auth);
    const target = list.body.items[0];
    const res = await request(ctx.app)
      .post(`/api/payment-methods/${target.id}/default`)
      .set('Authorization', userB.auth)
      .send({});
    expect(res.status).toBe(404);
  });

  test('soft-delete sets isActive=false, hides from list', async () => {
    const list = await request(ctx.app)
      .get('/api/payment-methods/me')
      .set('Authorization', userA.auth);
    const toDelete = list.body.items.find((m) => !m.isDefault);
    expect(toDelete).toBeTruthy();

    const del = await request(ctx.app)
      .delete(`/api/payment-methods/${toDelete.id}`)
      .set('Authorization', userA.auth);
    expect(del.status).toBe(200);

    const after = await request(ctx.app)
      .get('/api/payment-methods/me')
      .set('Authorization', userA.auth);
    expect(after.body.items.find((m) => m.id === toDelete.id)).toBeUndefined();
  });

  test('cannot delete another user\'s method', async () => {
    const aList = await request(ctx.app)
      .get('/api/payment-methods/me')
      .set('Authorization', userA.auth);
    const target = aList.body.items[0];
    const res = await request(ctx.app)
      .delete(`/api/payment-methods/${target.id}`)
      .set('Authorization', userB.auth);
    expect(res.status).toBe(404);
  });
});
