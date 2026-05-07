// Integration tests for /api/couriers/me/shifts and online toggle.

const request = require('supertest');
const express = require('express');
const { setupTestDb, teardownTestDb, createUser } = require('./helpers/db');

let ctx;
let app;
let courier;
let buyer;

beforeAll(async () => {
  ctx = await setupTestDb('courier-shifts');
  // Build a fresh app with courier-shifts router mounted.
  app = express();
  app.use(express.json());
  app.use((req, res, next) => { req.id = 'test'; next(); });
  app.set('io', { to: () => ({ emit: () => {} }), emit: () => {} });
  app.use('/api', require('../src/routes/courier-shifts'));
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, _next) => {
    res.status(err.status || 500).json({ error: err.message });
  });

  courier = await createUser(ctx.prisma, { isBuyer: false });
  // Promote to approved courier.
  await ctx.prisma.user.update({
    where: { id: courier.user.id },
    data: { isCourier: true, courierStatus: 'approved' },
  });
  // Re-issue token+user — middleware loads fresh user from DB anyway.
  courier.user = await ctx.prisma.user.findUnique({ where: { id: courier.user.id } });

  buyer = await createUser(ctx.prisma);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('POST /api/couriers/me/shifts/start', () => {
  test('starts a shift and flips isOnline=true', async () => {
    const res = await request(app)
      .post('/api/couriers/me/shifts/start')
      .set('Authorization', courier.auth)
      .send({ zoneIds: ['zone-1'] });
    expect(res.status).toBe(201);
    expect(res.body.shift.id).toBeDefined();
    expect(res.body.shift.endedAt).toBeNull();

    const fresh = await ctx.prisma.user.findUnique({ where: { id: courier.user.id } });
    expect(fresh.isOnline).toBe(true);
  });

  test('starting a second shift closes the prior open one', async () => {
    // Ensure there is already an open shift after the first test.
    const before = await ctx.prisma.courierShift.findMany({
      where: { courierId: courier.user.id, endedAt: null },
    });
    expect(before.length).toBeGreaterThanOrEqual(1);

    const res = await request(app)
      .post('/api/couriers/me/shifts/start')
      .set('Authorization', courier.auth)
      .send({});
    expect(res.status).toBe(201);

    const open = await ctx.prisma.courierShift.findMany({
      where: { courierId: courier.user.id, endedAt: null },
    });
    expect(open).toHaveLength(1);
    expect(open[0].id).toBe(res.body.shift.id);
  });

  test('non-courier blocked', async () => {
    const res = await request(app)
      .post('/api/couriers/me/shifts/start')
      .set('Authorization', buyer.auth)
      .send({});
    expect(res.status).toBe(403);
  });
});

describe('POST /api/couriers/me/shifts/end', () => {
  test('ends current shift and flips isOnline=false', async () => {
    const res = await request(app)
      .post('/api/couriers/me/shifts/end')
      .set('Authorization', courier.auth)
      .send({});
    expect(res.status).toBe(200);
    expect(res.body.shift).not.toBeNull();
    expect(res.body.shift.endedAt).not.toBeNull();

    const fresh = await ctx.prisma.user.findUnique({ where: { id: courier.user.id } });
    expect(fresh.isOnline).toBe(false);
  });

  test('end with no open shift is idempotent (returns null)', async () => {
    const res = await request(app)
      .post('/api/couriers/me/shifts/end')
      .set('Authorization', courier.auth)
      .send({});
    expect(res.status).toBe(200);
    expect(res.body.shift).toBeNull();
  });
});

describe('POST /api/couriers/me/online', () => {
  test('toggle online without shift bookkeeping works', async () => {
    const res = await request(app)
      .post('/api/couriers/me/online')
      .set('Authorization', courier.auth)
      .send({ isOnline: true });
    expect(res.status).toBe(200);
    expect(res.body.user.isOnline).toBe(true);

    const off = await request(app)
      .post('/api/couriers/me/online')
      .set('Authorization', courier.auth)
      .send({ isOnline: false });
    expect(off.status).toBe(200);
    expect(off.body.user.isOnline).toBe(false);
  });

  test('rejects non-boolean payload', async () => {
    const res = await request(app)
      .post('/api/couriers/me/online')
      .set('Authorization', courier.auth)
      .send({ isOnline: 'yes' });
    expect(res.status).toBe(400);
  });
});

describe('GET /api/couriers/me/shifts(/current)', () => {
  test('lists shifts with cursor pagination', async () => {
    // Make a couple of completed shifts.
    await request(app).post('/api/couriers/me/shifts/start').set('Authorization', courier.auth).send({});
    await request(app).post('/api/couriers/me/shifts/end').set('Authorization', courier.auth).send({});
    await request(app).post('/api/couriers/me/shifts/start').set('Authorization', courier.auth).send({});
    await request(app).post('/api/couriers/me/shifts/end').set('Authorization', courier.auth).send({});

    const res = await request(app)
      .get('/api/couriers/me/shifts?limit=2')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.shifts)).toBe(true);
    expect(res.body.shifts.length).toBeLessThanOrEqual(2);
  });

  test('current returns null when ended', async () => {
    const res = await request(app)
      .get('/api/couriers/me/shifts/current')
      .set('Authorization', courier.auth);
    expect(res.status).toBe(200);
    expect(res.body.shift).toBeNull();
  });
});
