// Tests requireRole behavior without spinning up Prisma.

const { requireRole } = require('../src/middleware/auth');

function mkRes() {
  return {
    statusCode: null, body: null,
    status(c) { this.statusCode = c; return this; },
    json(b) { this.body = b; return this; },
  };
}

describe('requireRole(courier)', () => {
  const fn = requireRole('courier');

  test('blocks anonymous', () => {
    const res = mkRes();
    let nextCalled = false;
    fn({}, res, () => { nextCalled = true; });
    expect(res.statusCode).toBe(401);
    expect(nextCalled).toBe(false);
  });

  test('blocks user with isCourier=false', () => {
    const res = mkRes();
    fn({ user: { isCourier: false, courierStatus: 'approved' } }, res, () => {});
    expect(res.statusCode).toBe(403);
  });

  test('blocks pending courier', () => {
    const res = mkRes();
    fn({ user: { isCourier: true, courierStatus: 'pending' } }, res, () => {});
    expect(res.statusCode).toBe(403);
  });

  test('blocks rejected courier', () => {
    const res = mkRes();
    fn({ user: { isCourier: true, courierStatus: 'rejected' } }, res, () => {});
    expect(res.statusCode).toBe(403);
  });

  test('allows approved courier', () => {
    const res = mkRes();
    let nextCalled = false;
    fn({ user: { isCourier: true, courierStatus: 'approved' } }, res, () => { nextCalled = true; });
    expect(nextCalled).toBe(true);
    expect(res.statusCode).toBeNull();
  });
});

describe('requireRole(admin)', () => {
  const fn = requireRole('admin');

  test('blocks non-admin', () => {
    const res = mkRes();
    fn({ user: { isAdmin: false } }, res, () => {});
    expect(res.statusCode).toBe(403);
  });

  test('allows admin', () => {
    const res = mkRes();
    let nextCalled = false;
    fn({ user: { isAdmin: true } }, res, () => { nextCalled = true; });
    expect(nextCalled).toBe(true);
  });
});

describe('requireRole(shop)', () => {
  const fn = requireRole('shop');

  test('blocks user with isShop=false', () => {
    const res = mkRes();
    fn({ user: { isShop: false, shopMemberships: [{ shopId: 'a' }] } }, res, () => {});
    expect(res.statusCode).toBe(403);
  });

  test('blocks user without memberships', () => {
    const res = mkRes();
    fn({ user: { isShop: true, shopMemberships: [] } }, res, () => {});
    expect(res.statusCode).toBe(403);
  });

  test('allows shop user with membership', () => {
    const res = mkRes();
    let nextCalled = false;
    fn({ user: { isShop: true, shopMemberships: [{ shopId: 'a' }] } }, res, () => { nextCalled = true; });
    expect(nextCalled).toBe(true);
  });
});
