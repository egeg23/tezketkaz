// Phase 10.2 — customer support inbox tests.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb, createUser,
} = require('./helpers/db');

// Mock push so support reply notifications don't blow up.
jest.mock('../src/services/push', () => ({
  sendToUser: jest.fn(async () => ({ sent: 0 })),
  sendToToken: jest.fn(async () => ({ success: true })),
  notifyShopNewOrder: jest.fn(async () => {}),
  notifyBuyerStatusUpdate: jest.fn(async () => {}),
  notifyCouriersNewOrder: jest.fn(async () => {}),
}));

let ctx;
let buyer, otherBuyer, admin;

beforeAll(async () => {
  ctx = await setupTestDb('support');
  buyer = await createUser(ctx.prisma, { name: 'Buyer A' });
  otherBuyer = await createUser(ctx.prisma, { name: 'Buyer B' });
  admin = await createUser(ctx.prisma, { isAdmin: true, name: 'Admin' });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('support inbox', () => {
  test('user creates ticket → row inserted with status=open and first message added', async () => {
    const res = await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: 'Order missing item', body: "I didn't get my soup." });
    expect(res.status).toBe(201);
    expect(res.body.ticket.status).toBe('open');
    expect(res.body.ticket.authorId).toBe(buyer.user.id);
    expect(res.body.ticket.lastReplyBy).toBe('user');
    expect(res.body.ticket.messages.length).toBe(1);
    expect(res.body.ticket.messages[0].body).toBe("I didn't get my soup.");
    expect(res.body.ticket.messages[0].senderRole).toBe('user');
  });

  test('user can list and read own ticket; cross-user gets 403', async () => {
    const create = await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: 'Coupon broken', body: 'Wont apply.' });
    const ticketId = create.body.ticket.id;

    const list = await request(ctx.app)
      .get('/api/support/tickets/me')
      .set('Authorization', buyer.auth);
    expect(list.status).toBe(200);
    expect(list.body.tickets.find((t) => t.id === ticketId)).toBeTruthy();

    const detail = await request(ctx.app)
      .get(`/api/support/tickets/me/${ticketId}`)
      .set('Authorization', buyer.auth);
    expect(detail.status).toBe(200);
    expect(detail.body.ticket.id).toBe(ticketId);

    const cross = await request(ctx.app)
      .get(`/api/support/tickets/me/${ticketId}`)
      .set('Authorization', otherBuyer.auth);
    expect(cross.status).toBe(403);
  });

  test('user reply transitions awaiting_user → open with lastReplyBy=user', async () => {
    const create = await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: 'Help me', body: 'Hello' });
    const ticketId = create.body.ticket.id;

    // Force into awaiting_user.
    await ctx.prisma.supportTicket.update({
      where: { id: ticketId },
      data: { status: 'awaiting_user', lastReplyBy: 'admin' },
    });

    const reply = await request(ctx.app)
      .post(`/api/support/tickets/${ticketId}/messages`)
      .set('Authorization', buyer.auth)
      .send({ body: 'Still broken' });
    expect(reply.status).toBe(201);

    const updated = await ctx.prisma.supportTicket.findUnique({ where: { id: ticketId } });
    expect(updated.status).toBe('open');
    expect(updated.lastReplyBy).toBe('user');
  });

  test('admin reply transitions open → awaiting_user with lastReplyBy=admin', async () => {
    const create = await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: 'Admin reply test', body: 'plz help' });
    const ticketId = create.body.ticket.id;

    const reply = await request(ctx.app)
      .post(`/api/admin/support/tickets/${ticketId}/messages`)
      .set('Authorization', admin.auth)
      .send({ body: 'Looking into it' });
    expect(reply.status).toBe(201);
    expect(reply.body.message.senderRole).toBe('admin');

    const updated = await ctx.prisma.supportTicket.findUnique({ where: { id: ticketId } });
    expect(updated.status).toBe('awaiting_user');
    expect(updated.lastReplyBy).toBe('admin');
    expect(updated.assigneeId).toBe(admin.user.id); // claim on first reply
  });

  test('admin can assign, change priority, and close a ticket', async () => {
    const create = await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: 'Mgmt test', body: 'mgmt' });
    const ticketId = create.body.ticket.id;

    const assign = await request(ctx.app)
      .post(`/api/admin/support/tickets/${ticketId}/assign`)
      .set('Authorization', admin.auth)
      .send({ assigneeId: admin.user.id });
    expect(assign.status).toBe(200);
    expect(assign.body.ticket.assigneeId).toBe(admin.user.id);
    expect(assign.body.ticket.status).toBe('in_progress');

    const patch = await request(ctx.app)
      .patch(`/api/admin/support/tickets/${ticketId}`)
      .set('Authorization', admin.auth)
      .send({ priority: 'urgent', category: 'order' });
    expect(patch.status).toBe(200);
    expect(patch.body.ticket.priority).toBe('urgent');
    expect(patch.body.ticket.category).toBe('order');

    const close = await request(ctx.app)
      .post(`/api/admin/support/tickets/${ticketId}/close`)
      .set('Authorization', admin.auth)
      .send({ reason: 'duplicate' });
    expect(close.status).toBe(200);
    expect(close.body.ticket.status).toBe('closed');
    expect(close.body.ticket.closedAt).toBeTruthy();
  });

  test('user can close own ticket', async () => {
    const create = await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: 'Self close', body: 'Solved myself' });
    const ticketId = create.body.ticket.id;

    const close = await request(ctx.app)
      .post(`/api/support/tickets/${ticketId}/close`)
      .set('Authorization', buyer.auth);
    expect(close.status).toBe(200);
    expect(close.body.ticket.status).toBe('closed');
  });

  test('admin stats counts correctly', async () => {
    // Snapshot existing counts and create one of each variety.
    const before = await request(ctx.app)
      .get('/api/admin/support/stats')
      .set('Authorization', admin.auth);
    expect(before.status).toBe(200);

    // Create open ticket.
    await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: 'Open one', body: 'x' });
    // Create another and force it to in_progress.
    const t2 = await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: 'IP one', body: 'y' });
    await ctx.prisma.supportTicket.update({
      where: { id: t2.body.ticket.id },
      data: { status: 'in_progress' },
    });

    const after = await request(ctx.app)
      .get('/api/admin/support/stats')
      .set('Authorization', admin.auth);
    expect(after.status).toBe(200);
    expect(after.body.open).toBeGreaterThanOrEqual(before.body.open + 1);
    expect(after.body.in_progress).toBeGreaterThanOrEqual(before.body.in_progress + 1);
    expect(after.body).toHaveProperty('awaiting_user');
    expect(after.body).toHaveProperty('closed_today');
    expect(after.body).toHaveProperty('resolved_today');
  });

  test('non-admin gets 403 on admin endpoints', async () => {
    const list = await request(ctx.app)
      .get('/api/admin/support/tickets')
      .set('Authorization', buyer.auth);
    expect(list.status).toBe(403);

    const stats = await request(ctx.app)
      .get('/api/admin/support/stats')
      .set('Authorization', buyer.auth);
    expect(stats.status).toBe(403);
  });

  test('subject and body required on create', async () => {
    const res1 = await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: '', body: 'x' });
    expect(res1.status).toBe(400);

    const res2 = await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: 'hi' });
    expect(res2.status).toBe(400);
  });

  test('admin can resolve ticket via PATCH and resolvedAt is set', async () => {
    const create = await request(ctx.app)
      .post('/api/support/tickets')
      .set('Authorization', buyer.auth)
      .send({ subject: 'Resolve test', body: 'k' });
    const ticketId = create.body.ticket.id;

    const patch = await request(ctx.app)
      .patch(`/api/admin/support/tickets/${ticketId}`)
      .set('Authorization', admin.auth)
      .send({ status: 'resolved' });
    expect(patch.status).toBe(200);
    expect(patch.body.ticket.status).toBe('resolved');
    expect(patch.body.ticket.resolvedAt).toBeTruthy();
  });
});
