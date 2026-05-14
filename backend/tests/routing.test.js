// Unit tests for backend/src/services/routing.js. The service must:
//   1. Fall back to haversine when YANDEX_ROUTING_KEY is unset.
//   2. Use Yandex Routing when the key is set and the API succeeds.
//   3. Fall back gracefully when the API returns 5xx.
//   4. Cache successful results within the 60 s TTL.

// Force-clear NODE_ENV to 'test' before requiring env so we don't bail out.
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-min-eight-chars';
process.env.DATABASE_URL = process.env.DATABASE_URL || 'file:./test-routing.db';

// We re-require the routing module per-test so env mutations take effect.
// env.js is cached after first parse, so we use jest.resetModules() to wipe
// Jest's module registry and pick up the new YANDEX_ROUTING_KEY value.
function freshRouting() {
  jest.resetModules();
  return require('../src/services/routing');
}

const ORIGIN = { lat: 41.30, lng: 69.20 };
const DEST = { lat: 41.32, lng: 69.24 };

describe('services/routing', () => {
  const originalFetch = global.fetch;

  beforeEach(() => {
    global.fetch = jest.fn();
  });

  afterEach(() => {
    global.fetch = originalFetch;
    delete process.env.YANDEX_ROUTING_KEY;
  });

  test('falls back to haversine when YANDEX_ROUTING_KEY is unset', async () => {
    delete process.env.YANDEX_ROUTING_KEY;
    const routing = freshRouting();
    routing._clearCache();

    const r = await routing.route(ORIGIN, DEST);
    expect(r.source).toBe('fallback');
    expect(r.distanceKm).toBeGreaterThan(0);
    expect(r.etaMinutes).toBeGreaterThanOrEqual(1);
    // fetch must NOT have been called when no key is configured.
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test('returns yandex source on successful API response', async () => {
    process.env.YANDEX_ROUTING_KEY = 'test-key';
    const routing = freshRouting();
    routing._clearCache();

    global.fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        route: {
          // Yandex /v2/route shape: per-step length/duration inside legs.
          // Sum across steps = 4.5 km / 12 min.
          legs: [{
            steps: [
              { length: 2500, duration: 400 },
              { length: 2000, duration: 320 },
            ],
          }],
        },
      }),
    });

    const r = await routing.route(ORIGIN, DEST);
    expect(r.source).toBe('yandex');
    expect(r.distanceKm).toBeCloseTo(4.5, 3);
    expect(r.etaMinutes).toBe(12);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  test('falls back gracefully when Yandex returns 5xx', async () => {
    process.env.YANDEX_ROUTING_KEY = 'test-key';
    const routing = freshRouting();
    routing._clearCache();

    global.fetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: async () => ({}),
    });

    const r = await routing.route(ORIGIN, DEST);
    expect(r.source).toBe('fallback');
    // haversine still returns a sane positive distance for these points.
    expect(r.distanceKm).toBeGreaterThan(0);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  test('falls back when response body is missing distance/duration', async () => {
    process.env.YANDEX_ROUTING_KEY = 'test-key';
    const routing = freshRouting();
    routing._clearCache();

    global.fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ route: {} }),
    });

    const r = await routing.route(ORIGIN, DEST);
    expect(r.source).toBe('fallback');
  });

  test('cache hit within TTL skips fetch', async () => {
    process.env.YANDEX_ROUTING_KEY = 'test-key';
    const routing = freshRouting();
    routing._clearCache();

    global.fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        route: {
          legs: [{ steps: [{ length: 4500, duration: 720 }] }],
        },
      }),
    });

    const first = await routing.route(ORIGIN, DEST);
    expect(first.source).toBe('yandex');
    expect(global.fetch).toHaveBeenCalledTimes(1);

    // Second call with identical coords should reuse the cached value.
    const second = await routing.route(ORIGIN, DEST);
    expect(second.source).toBe('yandex');
    expect(second.distanceKm).toBeCloseTo(4.5, 3);
    expect(second.etaMinutes).toBe(12);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });
});
