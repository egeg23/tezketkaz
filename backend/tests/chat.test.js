// Phase 3 chat API integration tests.

const request = require('supertest');
const {
  setupTestDb, teardownTestDb,
  createUser, createShopWithOwner, createProduct,
} = require('./helpers/db');

let ctx;
let buyer, courier, outsider, owner;
let shop, product;

async function makeOrder(prismaClient, status = 'inDelivery') {
  return prismaClient.order.create({
    data: {
      buyerId: buyer.user.id,
      customerName: 'Test',
      customerPhone: '+998900000000',
      shopId: shop.id,
      courierId: courier.user.id,
      deliveryAddress: '1 Test',
      paymentMethod: 'cash',
      isPaid: false,
      subtotal: 30000, total: 30000, deliveryFee: 0,
      status,
      items: {
        create: [{
          productId: product.id,
          productName: product.name,
          quantity: 1,
          price: 30000, basePrice: 30000, total: 30000,
        }],
      },
    },
  });
}

beforeAll(async () => {
  ctx = await setupTestDb('chat');
  owner = await createUser(ctx.prisma, { isShop: true });
  buyer = await createUser(ctx.prisma);
  outsider = await createUser(ctx.prisma);
  courier = await createUser(ctx.prisma, { isCourier: true });
  await ctx.prisma.user.update({
    where: { id: courier.user.id },
    data: { isCourier: true, courierStatus: 'approved' },
  });
  shop = await createShopWithOwner(ctx.prisma, owner.user);
  product = await createProduct(ctx.prisma, shop.id, { name: 'Pizza', price: 30000 });
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('chat', () => {
  test('participant (buyer) can post and read messages', async () => {
    const order = await makeOrder(ctx.prisma);

    const post = await request(ctx.app)
      .post(`/api/orders/${order.id}/chat`)
      .set('Authorization', buyer.auth)
      .send({ text: 'Hello' });
    expect(post.status).toBe(201);
    expect(post.body.message.text).toBe('Hello');
    expect(post.body.message.senderId).toBe(buyer.user.id);
    expect(post.body.message.receiverId).toBe(courier.user.id);

    const get = await request(ctx.app)
      .get(`/api/orders/${order.id}/chat`)
      .set('Authorization', courier.auth);
    expect(get.status).toBe(200);
    expect(get.body.messages.length).toBe(1);
  });

  test('outsider gets 403', async () => {
    const order = await makeOrder(ctx.prisma);
    const get = await request(ctx.app)
      .get(`/api/orders/${order.id}/chat`)
      .set('Authorization', outsider.auth);
    expect(get.status).toBe(403);

    const post = await request(ctx.app)
      .post(`/api/orders/${order.id}/chat`)
      .set('Authorization', outsider.auth)
      .send({ text: 'Hi' });
    expect(post.status).toBe(403);
  });

  test('text or imageUrl required', async () => {
    const order = await makeOrder(ctx.prisma);
    const res = await request(ctx.app)
      .post(`/api/orders/${order.id}/chat`)
      .set('Authorization', buyer.auth)
      .send({});
    expect(res.status).toBe(400);
  });

  test('read-receipt flips isRead only for current user\'s incoming msgs', async () => {
    const order = await makeOrder(ctx.prisma);

    // Buyer sends → receiver=courier
    await request(ctx.app)
      .post(`/api/orders/${order.id}/chat`)
      .set('Authorization', buyer.auth)
      .send({ text: 'A' });
    // Courier sends → receiver=buyer
    await request(ctx.app)
      .post(`/api/orders/${order.id}/chat`)
      .set('Authorization', courier.auth)
      .send({ text: 'B' });

    // Courier marks read — only the message with receiverId=courier flips.
    const r = await request(ctx.app)
      .post(`/api/orders/${order.id}/chat/read`)
      .set('Authorization', courier.auth)
      .send({});
    expect(r.status).toBe(200);
    expect(r.body.updated).toBe(1);

    const all = await ctx.prisma.chatMessage.findMany({
      where: { orderId: order.id },
      orderBy: { createdAt: 'asc' },
    });
    // First message: buyer→courier, courier just marked read
    expect(all[0].receiverId).toBe(courier.user.id);
    expect(all[0].isRead).toBe(true);
    // Second message: courier→buyer, still unread
    expect(all[1].receiverId).toBe(buyer.user.id);
    expect(all[1].isRead).toBe(false);
  });
});
