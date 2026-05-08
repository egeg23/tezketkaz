// Integration tests for /api/users/addresses (incl. detailed delivery fields
// and POST /default).

const request = require('supertest');
const { setupTestDb, teardownTestDb, createUser } = require('./helpers/db');

let ctx;
let userA, userB;

beforeAll(async () => {
  ctx = await setupTestDb('addresses');
  userA = await createUser(ctx.prisma);
  userB = await createUser(ctx.prisma);
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

async function postAddress(auth, body) {
  return request(ctx.app)
    .post('/api/users/addresses')
    .set('Authorization', auth)
    .send(body);
}

describe('Addresses with delivery details', () => {
  test('POST stores entrance/floor/apartment/intercom/instructions', async () => {
    const res = await postAddress(userA.auth, {
      label: 'Уй',
      fullAddress: 'Ул. Ширин 12',
      lat: 41.31, lng: 69.27,
      entrance: '2',
      floor: '5',
      apartment: '47',
      intercom: '47B',
      instructions: 'Лестница справа',
    });
    expect(res.status).toBe(201);
    expect(res.body.address.entrance).toBe('2');
    expect(res.body.address.floor).toBe('5');
    expect(res.body.address.apartment).toBe('47');
    expect(res.body.address.intercom).toBe('47B');
    expect(res.body.address.instructions).toBe('Лестница справа');
  });

  test('PATCH updates delivery details', async () => {
    const created = await postAddress(userA.auth, {
      label: 'Иш', fullAddress: 'Mirobod 3',
    });
    const id = created.body.address.id;
    const res = await request(ctx.app)
      .patch(`/api/users/addresses/${id}`)
      .set('Authorization', userA.auth)
      .send({ floor: '12', apartment: '7' });
    expect(res.status).toBe(200);
    expect(res.body.address.floor).toBe('12');
    expect(res.body.address.apartment).toBe('7');
  });
});

describe('POST /api/users/addresses/:id/default', () => {
  test('marks chosen address default and unsets others', async () => {
    const a1 = await postAddress(userB.auth, { label: 'A', fullAddress: 'Addr A', isDefault: true });
    const a2 = await postAddress(userB.auth, { label: 'B', fullAddress: 'Addr B' });
    const a3 = await postAddress(userB.auth, { label: 'C', fullAddress: 'Addr C' });

    const before = await ctx.prisma.address.findMany({ where: { userId: userB.user.id } });
    expect(before.find((a) => a.id === a1.body.address.id).isDefault).toBe(true);

    const res = await request(ctx.app)
      .post(`/api/users/addresses/${a3.body.address.id}/default`)
      .set('Authorization', userB.auth)
      .send({});
    expect(res.status).toBe(200);
    expect(res.body.address.id).toBe(a3.body.address.id);
    expect(res.body.address.isDefault).toBe(true);

    const after = await ctx.prisma.address.findMany({ where: { userId: userB.user.id } });
    const defaults = after.filter((a) => a.isDefault);
    expect(defaults).toHaveLength(1);
    expect(defaults[0].id).toBe(a3.body.address.id);
    // a1 and a2 are now not-default.
    expect(after.find((a) => a.id === a1.body.address.id).isDefault).toBe(false);
    expect(after.find((a) => a.id === a2.body.address.id).isDefault).toBe(false);
  });

  test('cannot default another user\'s address — 404', async () => {
    const others = await postAddress(userA.auth, { label: 'mine', fullAddress: 'Addr X' });
    const res = await request(ctx.app)
      .post(`/api/users/addresses/${others.body.address.id}/default`)
      .set('Authorization', userB.auth)
      .send({});
    expect(res.status).toBe(404);
  });

  test('non-existent id returns 404', async () => {
    const res = await request(ctx.app)
      .post('/api/users/addresses/no-such-id/default')
      .set('Authorization', userA.auth)
      .send({});
    expect(res.status).toBe(404);
  });
});
