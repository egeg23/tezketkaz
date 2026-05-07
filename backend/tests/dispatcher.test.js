// Pure unit tests for dispatcher.scoreCourier — no DB / no IO.

const { scoreCourier } = require('../src/services/dispatcher');

describe('dispatcher.scoreCourier', () => {
  const order = { id: 'ord-1' };

  test('closer courier outranks farther one with equal stats', () => {
    const a = { id: 'a', rating: 5, ordersCount: 10 };
    const b = { id: 'b', rating: 5, ordersCount: 10 };
    expect(scoreCourier(a, order, 1.0)).toBeGreaterThan(scoreCourier(b, order, 5.0));
  });

  test('higher rating outranks lower rating at equal distance', () => {
    const a = { id: 'a', rating: 5, ordersCount: 10 };
    const b = { id: 'b', rating: 4, ordersCount: 10 };
    expect(scoreCourier(a, order, 2.0)).toBeGreaterThan(scoreCourier(b, order, 2.0));
  });

  test('busy (active) courier is penalised', () => {
    const free = { id: 'a', rating: 5, ordersCount: 10, activeOrderId: null };
    const busy = { id: 'b', rating: 5, ordersCount: 10, activeOrderId: 'someOrder' };
    expect(scoreCourier(free, order, 2.0)).toBeGreaterThan(scoreCourier(busy, order, 2.0));
  });

  test('null/undefined rating treated safely', () => {
    const c = { id: 'a' };
    const score = scoreCourier(c, order, 2.0);
    expect(Number.isFinite(score)).toBe(true);
  });

  test('zero/negative distance does not produce Infinity', () => {
    const c = { id: 'a', rating: 5, ordersCount: 10 };
    const s1 = scoreCourier(c, order, 0);
    const s2 = scoreCourier(c, order, -1);
    expect(Number.isFinite(s1)).toBe(true);
    expect(Number.isFinite(s2)).toBe(true);
  });
});
