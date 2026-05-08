// Phase 10.1 — group orders / split-bill backend tests.
//
// Covers the host-create → friend-join → set-cart → lock → split-pay flow,
// the host-pay variant, cancellation by the host, expiry sweep, and the
// validation paths (expired groups, member-cap, cross-shop products).

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let host;
let friend;
let stranger;
let shopOwner;
let shop;
let otherShop;
let burger;
let pizza;
let cookie; // belongs to otherShop — used to test cross-shop validation

beforeAll(async () => {
  ctx = await setupTestDb('order-groups');
  host = await createUser(ctx.prisma, { name: 'Host' });
  friend = await createUser(ctx.prisma, { name: 'Friend' });
  stranger = await createUser(ctx.prisma, { name: 'Stranger' });
  shopOwner = await createUser(ctx.prisma, { isShop: true });
  shop = await createShopWithOwner(ctx.prisma, shopOwner.user);
  otherShop = await ctx.prisma.shop.create({
    data: { name: 'Other', address: '2 Other St', lat: 41.1, lng: 69.1, isActive: true },
  });
  burger = await createProduct(ctx.prisma, shop.id, { price: 30000, name: 'Burger' });
  pizza = await createProduct(ctx.prisma, shop.id, { price: 50000, name: 'Pizza' });
  cookie = await createProduct(ctx.prisma, otherShop.id, { price: 5000, name: 'Cookie' });

  // Mount the order-groups router into the test app.
  ctx.app.use('/api/order-groups', require('../src/routes/order-groups'));
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

// Helper: save a click payment method for a user.
async function saveMethod(prisma, userId) {
  return prisma.paymentMethod.create({
    data: {
      userId,
      provider: 'click',
      providerId: `mock_token_${userId}_${Date.now()}`,
      last4: '1111',
      brand: 'visa',
      isActive: true,
    },
  });
}

describe('OrderGroup creation + join', () => {
  test('host creates group → joinCode unique, host membership row inserted', async () => {
    const res = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id, paymentMode: 'split', expiresInMin: 60 });
    expect(res.status).toBe(201);
    expect(res.body.group.joinCode).toMatch(/^[A-Z2-9]{4}-[A-Z]{2}$/);
    expect(res.body.group.shopId).toBe(shop.id);
    expect(res.body.group.status).toBe('open');
    expect(res.body.hostMembership.userId).toBe(host.user.id);

    // Second create yields a *different* joinCode.
    const res2 = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id });
    expect(res2.status).toBe(201);
    expect(res2.body.group.joinCode).not.toBe(res.body.group.joinCode);
  });

  test('friend joins via valid code → membership row, can read group', async () => {
    const create = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id });
    const joinCode = create.body.group.joinCode;

    const join = await request(ctx.app)
      .post('/api/order-groups/join')
      .set('Authorization', friend.auth)
      .send({ joinCode });
    expect(join.status).toBe(201);
    expect(join.body.member.userId).toBe(friend.user.id);

    // Friend can read detail.
    const detail = await request(ctx.app)
      .get(`/api/order-groups/${create.body.group.id}`)
      .set('Authorization', friend.auth);
    expect(detail.status).toBe(200);
    expect(detail.body.group.members.length).toBe(2);

    // Stranger (not a member) is forbidden.
    const denied = await request(ctx.app)
      .get(`/api/order-groups/${create.body.group.id}`)
      .set('Authorization', stranger.auth);
    expect(denied.status).toBe(403);
  });

  test('friend joins expired group → 410', async () => {
    const create = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id });
    // Backdate expiresAt directly.
    await ctx.prisma.orderGroup.update({
      where: { id: create.body.group.id },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });
    const join = await request(ctx.app)
      .post('/api/order-groups/join')
      .set('Authorization', friend.auth)
      .send({ joinCode: create.body.group.joinCode });
    expect(join.status).toBe(410);
  });

  test('friend joins at maxMembers cap → 409', async () => {
    const create = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id, maxMembers: 2 });
    // Friend joins → 2 active.
    const r1 = await request(ctx.app)
      .post('/api/order-groups/join')
      .set('Authorization', friend.auth)
      .send({ joinCode: create.body.group.joinCode });
    expect(r1.status).toBe(201);
    // Stranger joins → cap exceeded.
    const r2 = await request(ctx.app)
      .post('/api/order-groups/join')
      .set('Authorization', stranger.auth)
      .send({ joinCode: create.body.group.joinCode });
    expect(r2.status).toBe(409);
  });
});

describe('OrderGroup setMemberCart validation', () => {
  test('rejects products that belong to a different shop', async () => {
    const create = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id });
    const groupId = create.body.group.id;

    const r = await request(ctx.app)
      .patch(`/api/order-groups/${groupId}/me/cart`)
      .set('Authorization', host.auth)
      .send({ cartJson: [{ productId: cookie.id, quantity: 1 }] });
    expect(r.status).toBe(400);
    expect(r.body.error).toBe('product_not_in_group_shop');
  });

  test('accepts items from the same shop', async () => {
    const create = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id });
    const r = await request(ctx.app)
      .patch(`/api/order-groups/${create.body.group.id}/me/cart`)
      .set('Authorization', host.auth)
      .send({ cartJson: [{ productId: burger.id, quantity: 2 }] });
    expect(r.status).toBe(200);
    expect(r.body.subtotal).toBe(60000);
  });
});

describe('OrderGroup lock + split pay', () => {
  test('lock computes amountOwed for each member', async () => {
    const create = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id, paymentMode: 'split' });
    const groupId = create.body.group.id;
    await request(ctx.app)
      .post('/api/order-groups/join')
      .set('Authorization', friend.auth)
      .send({ joinCode: create.body.group.joinCode });

    await request(ctx.app)
      .patch(`/api/order-groups/${groupId}/me/cart`)
      .set('Authorization', host.auth)
      .send({ cartJson: [{ productId: burger.id, quantity: 1 }] });
    await request(ctx.app)
      .patch(`/api/order-groups/${groupId}/me/cart`)
      .set('Authorization', friend.auth)
      .send({ cartJson: [{ productId: pizza.id, quantity: 2 }] });

    // Non-host can't lock.
    const denied = await request(ctx.app)
      .post(`/api/order-groups/${groupId}/lock`)
      .set('Authorization', friend.auth);
    expect(denied.status).toBe(403);

    const lock = await request(ctx.app)
      .post(`/api/order-groups/${groupId}/lock`)
      .set('Authorization', host.auth);
    expect(lock.status).toBe(200);
    expect(lock.body.group.status).toBe('locked');
    expect(lock.body.groupSubtotal).toBe(30000 + 100000);

    const hostMember = lock.body.members.find((m) => m.userId === host.user.id);
    const friendMember = lock.body.members.find((m) => m.userId === friend.user.id);
    expect(hostMember.amountOwed).toBe(30000);
    expect(friendMember.amountOwed).toBe(100000);
  });

  test('all members pay → Order created with merged items', async () => {
    const hostMethod = await saveMethod(ctx.prisma, host.user.id);
    const friendMethod = await saveMethod(ctx.prisma, friend.user.id);

    const create = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id, paymentMode: 'split' });
    const groupId = create.body.group.id;
    await request(ctx.app)
      .post('/api/order-groups/join')
      .set('Authorization', friend.auth)
      .send({ joinCode: create.body.group.joinCode });

    await request(ctx.app)
      .patch(`/api/order-groups/${groupId}/me/cart`)
      .set('Authorization', host.auth)
      .send({ cartJson: [{ productId: burger.id, quantity: 1 }] });
    await request(ctx.app)
      .patch(`/api/order-groups/${groupId}/me/cart`)
      .set('Authorization', friend.auth)
      .send({ cartJson: [{ productId: pizza.id, quantity: 1 }] });

    await request(ctx.app)
      .post(`/api/order-groups/${groupId}/lock`)
      .set('Authorization', host.auth);

    const r1 = await request(ctx.app)
      .post(`/api/order-groups/${groupId}/me/pay`)
      .set('Authorization', host.auth)
      .send({ paymentMethodId: hostMethod.id });
    expect(r1.status).toBe(200);
    expect(r1.body.member.status).toBe('paid');
    // Group not finalised until everyone pays.
    expect(r1.body.order).toBeNull();
    expect(r1.body.group.status).toBe('locked');

    const r2 = await request(ctx.app)
      .post(`/api/order-groups/${groupId}/me/pay`)
      .set('Authorization', friend.auth)
      .send({ paymentMethodId: friendMethod.id });
    expect(r2.status).toBe(200);
    expect(r2.body.order).toBeTruthy();
    expect(r2.body.group.status).toBe('paid');

    // Single Order has both members' items merged.
    const order = await ctx.prisma.order.findUnique({
      where: { id: r2.body.order.id },
      include: { items: true },
    });
    expect(order).toBeTruthy();
    expect(order.shopId).toBe(shop.id);
    expect(order.buyerId).toBe(host.user.id);
    expect(order.subtotal).toBe(30000 + 50000);
    expect(order.isPaid).toBe(true);
    const productIds = order.items.map((i) => i.productId).sort();
    expect(productIds).toEqual([burger.id, pizza.id].sort());
  });
});

describe('OrderGroup host-pay mode', () => {
  test('host single charge for total, Order created', async () => {
    const hostMethod = await saveMethod(ctx.prisma, host.user.id);

    const create = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id, paymentMode: 'host' });
    const groupId = create.body.group.id;
    await request(ctx.app)
      .post('/api/order-groups/join')
      .set('Authorization', friend.auth)
      .send({ joinCode: create.body.group.joinCode });

    await request(ctx.app)
      .patch(`/api/order-groups/${groupId}/me/cart`)
      .set('Authorization', host.auth)
      .send({ cartJson: [{ productId: burger.id, quantity: 1 }] });
    await request(ctx.app)
      .patch(`/api/order-groups/${groupId}/me/cart`)
      .set('Authorization', friend.auth)
      .send({ cartJson: [{ productId: pizza.id, quantity: 1 }] });

    await request(ctx.app)
      .post(`/api/order-groups/${groupId}/lock`)
      .set('Authorization', host.auth);

    // /me/pay rejects in host mode.
    const wrong = await request(ctx.app)
      .post(`/api/order-groups/${groupId}/me/pay`)
      .set('Authorization', friend.auth)
      .send({ paymentMethodId: hostMethod.id });
    expect(wrong.status).toBe(400);

    const pay = await request(ctx.app)
      .post(`/api/order-groups/${groupId}/host-pay`)
      .set('Authorization', host.auth)
      .send({ paymentMethodId: hostMethod.id });
    expect(pay.status).toBe(200);
    expect(pay.body.order).toBeTruthy();
    expect(pay.body.group.status).toBe('paid');

    // Verify all members are 'paid' on the host's single charge.
    const members = await ctx.prisma.orderGroupMember.findMany({
      where: { groupId },
    });
    expect(members.every((m) => m.status === 'paid')).toBe(true);

    const order = await ctx.prisma.order.findUnique({
      where: { id: pay.body.order.id },
      include: { items: true },
    });
    expect(order.subtotal).toBe(30000 + 50000);
    expect(order.items.length).toBe(2);
  });
});

describe('OrderGroup cancel + expire', () => {
  test('host cancels → status="cancelled"', async () => {
    const create = await request(ctx.app)
      .post('/api/order-groups')
      .set('Authorization', host.auth)
      .send({ shopId: shop.id });
    const groupId = create.body.group.id;
    await request(ctx.app)
      .post('/api/order-groups/join')
      .set('Authorization', friend.auth)
      .send({ joinCode: create.body.group.joinCode });

    // Friend can't cancel — only host or sole-remaining member.
    const denied = await request(ctx.app)
      .post(`/api/order-groups/${groupId}/cancel`)
      .set('Authorization', friend.auth)
      .send({ reason: 'change of plans' });
    expect(denied.status).toBe(403);

    const r = await request(ctx.app)
      .post(`/api/order-groups/${groupId}/cancel`)
      .set('Authorization', host.auth)
      .send({ reason: 'change of plans' });
    expect(r.status).toBe(200);
    expect(r.body.group.status).toBe('cancelled');
    expect(r.body.group.cancelledAt).toBeTruthy();
  });

  test('expireDue marks open groups past expiresAt as "expired"', async () => {
    const orderGroup = require('../src/services/orderGroup');
    // Seed: one group already past expiresAt, one still in-window.
    const stale = await ctx.prisma.orderGroup.create({
      data: {
        hostUserId: host.user.id,
        shopId: shop.id,
        joinCode: orderGroup.generateJoinCode(),
        status: 'open',
        expiresAt: new Date(Date.now() - 60 * 1000),
      },
    });
    const fresh = await ctx.prisma.orderGroup.create({
      data: {
        hostUserId: host.user.id,
        shopId: shop.id,
        joinCode: orderGroup.generateJoinCode(),
        status: 'open',
        expiresAt: new Date(Date.now() + 30 * 60 * 1000),
      },
    });

    const summary = await orderGroup.expireDue(ctx.prisma);
    expect(summary.expired).toBeGreaterThanOrEqual(1);

    const reloadStale = await ctx.prisma.orderGroup.findUnique({ where: { id: stale.id } });
    const reloadFresh = await ctx.prisma.orderGroup.findUnique({ where: { id: fresh.id } });
    expect(reloadStale.status).toBe('expired');
    expect(reloadFresh.status).toBe('open');
  });
});
