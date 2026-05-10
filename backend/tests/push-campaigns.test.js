// Phase 10.3 — push notification campaign tests.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb, createUser,
} = require('./helpers/db');

// Mock push.sendToUser so we can control success/failure deterministically.
jest.mock('../src/services/push', () => ({
  sendToUser: jest.fn(async () => ({ sent: 1, total: 1 })),
  sendToToken: jest.fn(async () => ({ success: true })),
  notifyShopNewOrder: jest.fn(async () => {}),
  notifyBuyerStatusUpdate: jest.fn(async () => {}),
  notifyCouriersNewOrder: jest.fn(async () => {}),
}));

let ctx;
let push;
let admin, buyerRu, buyerUz, buyerKz;

beforeAll(async () => {
  ctx = await setupTestDb('push-campaigns');
  push = require('../src/services/push');

  admin = await createUser(ctx.prisma, { isAdmin: true });

  buyerRu = await createUser(ctx.prisma);
  await ctx.prisma.user.update({
    where: { id: buyerRu.user.id },
    data: { country: 'UZ', locale: 'ru' },
  });

  buyerUz = await createUser(ctx.prisma);
  await ctx.prisma.user.update({
    where: { id: buyerUz.user.id },
    data: { country: 'UZ', locale: 'uz' },
  });

  buyerKz = await createUser(ctx.prisma);
  await ctx.prisma.user.update({
    where: { id: buyerKz.user.id },
    data: { country: 'KZ', locale: 'ru' },
  });
}, 30000);

beforeEach(() => {
  push.sendToUser.mockClear();
  push.sendToUser.mockImplementation(async () => ({ sent: 1, total: 1 }));
});

afterAll(async () => { await teardownTestDb(ctx); });

async function createDraft(extra = {}) {
  const res = await request(ctx.app)
    .post('/api/admin/push-campaigns')
    .set('Authorization', admin.auth)
    .send({
      titleUz: 'UZ Title',
      titleRu: 'RU Title',
      bodyUz: 'UZ Body',
      bodyRu: 'RU Body',
      audienceQuery: { country: 'UZ' },
      ...extra,
    });
  expect(res.status).toBe(201);
  return res.body.campaign;
}

describe('push campaigns', () => {
  test('preview returns count without sending', async () => {
    const res = await request(ctx.app)
      .post('/api/admin/push-campaigns/preview')
      .set('Authorization', admin.auth)
      .send({ audienceQuery: { country: 'UZ' } });
    expect(res.status).toBe(200);
    expect(res.body.recipientCount).toBeGreaterThanOrEqual(2);
    expect(push.sendToUser).not.toHaveBeenCalled();
  });

  test('send marks status=sent and tallies counts; sendToUser called per user with locale-specific body', async () => {
    // First call succeeds, second fails. Track payloads for locale check.
    let i = 0;
    push.sendToUser.mockImplementation(async () => {
      i += 1;
      return i === 1 ? { sent: 1 } : { sent: 0 };
    });

    const campaign = await createDraft();
    const res = await request(ctx.app)
      .post(`/api/admin/push-campaigns/${campaign.id}/send`)
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(res.body.campaign.status).toBe('sent');
    expect(res.body.campaign.recipientCount).toBeGreaterThanOrEqual(2);
    expect(res.body.campaign.successCount + res.body.campaign.failureCount)
      .toBe(res.body.campaign.recipientCount);
    expect(res.body.campaign.sentAt).toBeTruthy();

    // Each call's payload had a title from one of the supported locales.
    const titles = push.sendToUser.mock.calls.map((c) => c[1].title);
    expect(titles.every((t) => ['UZ Title', 'RU Title'].includes(t))).toBe(true);

    // The buyer with locale=ru should have gotten the RU title.
    const ruCall = push.sendToUser.mock.calls.find((c) => c[0] === buyerRu.user.id);
    expect(ruCall).toBeTruthy();
    expect(ruCall[1].title).toBe('RU Title');
    expect(ruCall[1].body).toBe('RU Body');

    // The uz-locale buyer should have gotten the UZ title.
    const uzCall = push.sendToUser.mock.calls.find((c) => c[0] === buyerUz.user.id);
    expect(uzCall).toBeTruthy();
    expect(uzCall[1].title).toBe('UZ Title');
  });

  test('cancel a draft', async () => {
    const campaign = await createDraft();
    const res = await request(ctx.app)
      .post(`/api/admin/push-campaigns/${campaign.id}/cancel`)
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(res.body.campaign.status).toBe('cancelled');
  });

  test('non-admin gets 403', async () => {
    const non = await createUser(ctx.prisma);
    const res = await request(ctx.app)
      .post('/api/admin/push-campaigns/preview')
      .set('Authorization', non.auth)
      .send({ audienceQuery: {} });
    expect(res.status).toBe(403);

    const list = await request(ctx.app)
      .get('/api/admin/push-campaigns')
      .set('Authorization', non.auth);
    expect(list.status).toBe(403);
  });

  test('track-open increments openCount', async () => {
    const campaign = await createDraft();
    const before = await request(ctx.app)
      .get(`/api/admin/push-campaigns/${campaign.id}/stats`)
      .set('Authorization', admin.auth);
    expect(before.body.openCount).toBe(0);

    const tap = await request(ctx.app)
      .post(`/api/push-campaigns/${campaign.id}/track-open`)
      .send();
    expect(tap.status).toBe(200);
    expect(tap.body.openCount).toBe(1);

    const after = await request(ctx.app)
      .get(`/api/admin/push-campaigns/${campaign.id}/stats`)
      .set('Authorization', admin.auth);
    expect(after.body.openCount).toBe(1);
  });

  test('delete draft works; cannot delete sent', async () => {
    const draft = await createDraft();
    const del = await request(ctx.app)
      .delete(`/api/admin/push-campaigns/${draft.id}`)
      .set('Authorization', admin.auth);
    expect(del.status).toBe(200);

    const sent = await createDraft();
    await request(ctx.app)
      .post(`/api/admin/push-campaigns/${sent.id}/send`)
      .set('Authorization', admin.auth);
    const delSent = await request(ctx.app)
      .delete(`/api/admin/push-campaigns/${sent.id}`)
      .set('Authorization', admin.auth);
    expect(delSent.status).toBe(400);
  });

  test('list filters by status', async () => {
    const draft = await createDraft();
    const res = await request(ctx.app)
      .get('/api/admin/push-campaigns?status=draft')
      .set('Authorization', admin.auth);
    expect(res.status).toBe(200);
    expect(res.body.campaigns.find((c) => c.id === draft.id)).toBeTruthy();
    expect(res.body.campaigns.every((c) => c.status === 'draft')).toBe(true);
  });

  test('PATCH updates draft fields', async () => {
    const draft = await createDraft();
    const res = await request(ctx.app)
      .patch(`/api/admin/push-campaigns/${draft.id}`)
      .set('Authorization', admin.auth)
      .send({ titleRu: 'New RU Title', deepLink: '/promos/x' });
    expect(res.status).toBe(200);
    expect(res.body.campaign.titleRu).toBe('New RU Title');
    expect(res.body.campaign.deepLink).toBe('/promos/x');
  });
});
