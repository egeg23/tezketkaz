// Unit tests for scheduling service.

const { setupTestDb, teardownTestDb, createUser, createShopWithOwner } = require('./helpers/db');
const scheduling = require('../src/services/scheduling');

let ctx;
let prisma;
let buyer;
let shop;

beforeAll(async () => {
  ctx = await setupTestDb('scheduled');
  prisma = ctx.prisma;
  const owner = await createUser(prisma, { isShop: true });
  buyer = await createUser(prisma);
  shop = await createShopWithOwner(prisma, owner.user);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function makePendingOrder() {
  return prisma.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'X', customerPhone: '+99800',
      shopId: shop.id,
      deliveryAddress: 'addr', paymentMethod: 'cash',
      subtotal: 50000, total: 50000, status: 'pending',
    },
  });
}

// queues stub: returns a no-op shim that records adds.
function makeQueues() {
  const adds = [];
  const fn = () => ({
    scheduled: {
      async add(name, data, opts) { adds.push({ queue: 'scheduled', name, data, opts }); return { id: 'noop' }; },
    },
    dispatch: {
      async add(name, data, opts) { adds.push({ queue: 'dispatch', name, data, opts }); return { id: 'noop' }; },
    },
    autoCancel: {
      async add(name, data, opts) { adds.push({ queue: 'autoCancel', name, data, opts }); return { id: 'noop' }; },
    },
  });
  fn.adds = adds;
  return fn;
}

describe('scheduling.scheduleOrder', () => {
  test('past schedule throws 400', async () => {
    const order = await makePendingOrder();
    const past = new Date(Date.now() - 60 * 1000);
    await expect(
      scheduling.scheduleOrder(prisma, makeQueues(), { orderId: order.id, scheduledFor: past }),
    ).rejects.toMatchObject({ status: 400 });
  });

  test('schedule >7 days throws 400', async () => {
    const order = await makePendingOrder();
    const farFuture = new Date(Date.now() + 8 * 24 * 60 * 60 * 1000);
    await expect(
      scheduling.scheduleOrder(prisma, makeQueues(), { orderId: order.id, scheduledFor: farFuture }),
    ).rejects.toMatchObject({ status: 400 });
  });

  test('valid schedule creates ScheduledOrder + enqueues', async () => {
    const order = await makePendingOrder();
    const when = new Date(Date.now() + 2 * 60 * 60 * 1000); // 2h ahead
    const queues = makeQueues();
    const row = await scheduling.scheduleOrder(prisma, queues, {
      orderId: order.id, scheduledFor: when,
    });
    expect(row.status).toBe('pending');
    expect(row.orderId).toBe(order.id);
    const adds = queues.adds.filter((a) => a.queue === 'scheduled');
    expect(adds.length).toBe(1);
    expect(adds[0].name).toBe('activate');
  });
});

describe('scheduling.cancelScheduledOrder', () => {
  test('cancels pending row', async () => {
    const order = await makePendingOrder();
    const when = new Date(Date.now() + 2 * 60 * 60 * 1000);
    await scheduling.scheduleOrder(prisma, makeQueues(), { orderId: order.id, scheduledFor: when });

    const result = await scheduling.cancelScheduledOrder(prisma, makeQueues(), order.id);
    expect(result.ok).toBe(true);
    const row = await prisma.scheduledOrder.findUnique({ where: { orderId: order.id } });
    expect(row.status).toBe('cancelled');
  });

  test('refuses to cancel an activated row', async () => {
    const order = await makePendingOrder();
    const when = new Date(Date.now() + 2 * 60 * 60 * 1000);
    await scheduling.scheduleOrder(prisma, makeQueues(), { orderId: order.id, scheduledFor: when });
    await prisma.scheduledOrder.update({
      where: { orderId: order.id },
      data: { status: 'activated', activatedAt: new Date() },
    });
    const result = await scheduling.cancelScheduledOrder(prisma, makeQueues(), order.id);
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('already_activated');
  });
});

describe('scheduling.activateScheduledOrder', () => {
  test('marks scheduled row activated and enqueues dispatch', async () => {
    const order = await makePendingOrder();
    const when = new Date(Date.now() + 2 * 60 * 60 * 1000);
    await scheduling.scheduleOrder(prisma, makeQueues(), { orderId: order.id, scheduledFor: when });

    const queues = makeQueues();
    const result = await scheduling.activateScheduledOrder(prisma, null, queues, order.id);
    expect(result.ok).toBe(true);
    const row = await prisma.scheduledOrder.findUnique({ where: { orderId: order.id } });
    expect(row.status).toBe('activated');
    const dispatchAdds = queues.adds.filter((a) => a.queue === 'dispatch');
    expect(dispatchAdds.length).toBe(1);
  });
});
