const state = require('../src/services/redis-state');

describe('redis-state (in-memory fallback)', () => {
  beforeEach(async () => {
    // Wipe known couriers from previous tests
    for (const id of await state.listOnlineCouriers()) {
      await state.setCourierOffline(id);
    }
  });

  test('online → location → query', async () => {
    await state.setCourierOnline('c1', 'sock-1');
    await state.setCourierLocation('c1', 41.31, 69.24);
    const loc = await state.getCourierLocation('c1');
    expect(loc).toEqual(expect.objectContaining({ lat: 41.31, lng: 69.24 }));
    const online = await state.listOnlineCouriers();
    expect(online).toContain('c1');
  });

  test('offline removes presence and location', async () => {
    await state.setCourierOnline('c2', 'sock-2');
    await state.setCourierLocation('c2', 1, 2);
    await state.setCourierOffline('c2');
    expect(await state.getCourierLocation('c2')).toBeNull();
    expect(await state.listOnlineCouriers()).not.toContain('c2');
  });

  test('nearby filters by radius', async () => {
    await state.setCourierOnline('a', 's-a');
    await state.setCourierOnline('b', 's-b');
    await state.setCourierLocation('a', 41.31, 69.24);   // Tashkent center
    await state.setCourierLocation('b', 51.50, -0.12);   // London
    const near = await state.nearbyCourierIds({ lat: 41.30, lng: 69.25 }, 5);
    expect(near).toContain('a');
    expect(near).not.toContain('b');
  });

  test('distanceKm sanity', () => {
    const d = state.distanceKm({ lat: 41.31, lng: 69.24 }, { lat: 41.31, lng: 69.24 });
    expect(d).toBeLessThan(0.001);
  });
});
