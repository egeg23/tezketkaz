// Phase 3 notifications service tests.

const {
  setupTestDb, teardownTestDb, createUser,
} = require('./helpers/db');

// Mock the FCM client BEFORE notifications.js is loaded.
jest.mock('../src/services/push', () => ({
  sendToUser: jest.fn(async () => ({ sent: 1 })),
  sendToToken: jest.fn(async () => ({ success: true, mock: false })),
  notifyShopNewOrder: jest.fn(async () => {}),
  notifyBuyerStatusUpdate: jest.fn(async () => {}),
  notifyCouriersNewOrder: jest.fn(async () => {}),
}));

let ctx;
let push;
let notifications;

beforeAll(async () => {
  ctx = await setupTestDb('notifications');
  // After setupTestDb wipes module cache, re-resolve.
  push = require('../src/services/push');
  notifications = require('../src/services/notifications');
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

beforeEach(() => {
  push.sendToUser.mockClear();
});

describe('notifications.sendOrderEvent', () => {
  test('writes Notification row + calls FCM', async () => {
    const u = await createUser(ctx.prisma);
    const ioMock = { to: jest.fn(() => ({ emit: jest.fn() })) };

    const result = await notifications.sendOrderEvent(ctx.prisma, ioMock, {
      userId: u.user.id,
      type: 'order_delivered',
      orderId: 'o1',
      data: { foo: 'bar' },
    });

    expect(result.notification).toBeTruthy();
    expect(result.notification.type).toBe('order_update');
    expect(push.sendToUser).toHaveBeenCalledTimes(1);
    const [uid, payload] = push.sendToUser.mock.calls[0];
    expect(uid).toBe(u.user.id);
    expect(payload.title).toBeDefined();

    // Socket emit fired on personal rooms.
    expect(ioMock.to).toHaveBeenCalled();

    // Persisted in DB.
    const stored = await ctx.prisma.notification.findMany({ where: { userId: u.user.id } });
    expect(stored.length).toBe(1);
  });

  test('locale routing: ru user gets Russian title', async () => {
    const u = await createUser(ctx.prisma);
    await ctx.prisma.user.update({ where: { id: u.user.id }, data: { locale: 'ru' } });

    await notifications.sendOrderEvent(ctx.prisma, null, {
      userId: u.user.id,
      type: 'order_delivered',
    });

    const [, payload] = push.sendToUser.mock.calls[0];
    expect(payload.title).toBe('Доставлено');
  });

  test('locale uz default', async () => {
    const u = await createUser(ctx.prisma);
    await notifications.sendOrderEvent(ctx.prisma, null, {
      userId: u.user.id,
      type: 'order_dispatched',
    });
    const [, payload] = push.sendToUser.mock.calls[0];
    expect(payload.title).toBe('Kuryer topildi');
  });

  test('chat_message bucket maps to type=chat', async () => {
    const u = await createUser(ctx.prisma);
    await notifications.sendChat(ctx.prisma, null, {
      senderName: 'Ali', receiverId: u.user.id, orderId: 'o1', text: 'Hi',
    });
    const stored = await ctx.prisma.notification.findFirst({
      where: { userId: u.user.id }, orderBy: { createdAt: 'desc' },
    });
    expect(stored.type).toBe('chat');
  });
});
