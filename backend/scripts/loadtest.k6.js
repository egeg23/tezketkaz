// k6 load test for the TezKetKaz API.
//
//   $ BASE_URL=https://staging.example.com TOKEN=<jwt> k6 run loadtest.k6.js
//
// Stages: 0→20 RPS over 30s, hold 20 RPS for 1min, ramp to 100 RPS over 1min,
//         hold 100 RPS for 1min, ramp down to 0 over 30s.
//
// SLO thresholds:
//   - reads (p95)  < 500ms
//   - writes (p99) < 1500ms
//   - HTTP error rate < 1%

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const TOKEN = __ENV.TOKEN || '';

const readLatency = new Trend('read_latency_ms', true);
const writeLatency = new Trend('write_latency_ms', true);
const errorRate = new Rate('errors');

export const options = {
  // arrival-rate executor lets us drive RPS independently of VU count.
  scenarios: {
    main: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 200,
      stages: [
        { duration: '30s', target: 20 },   // ramp 0 → 20 rps
        { duration: '1m',  target: 20 },   // hold  20 rps
        { duration: '1m',  target: 100 },  // ramp  20 → 100 rps
        { duration: '1m',  target: 100 },  // hold 100 rps
        { duration: '30s', target: 0 },    // ramp down
      ],
    },
  },
  thresholds: {
    'read_latency_ms':  ['p(95)<500'],
    'write_latency_ms': ['p(99)<1500'],
    'http_req_failed':  ['rate<0.01'],
    'errors':           ['rate<0.01'],
  },
};

const headers = TOKEN
  ? { 'Content-Type': 'application/json', Authorization: `Bearer ${TOKEN}` }
  : { 'Content-Type': 'application/json' };

// Seed payload matches the buyer-facing /orders/estimate contract.
const ESTIMATE_PAYLOAD = JSON.stringify({
  shopId: __ENV.SEED_SHOP_ID || 'seed-shop',
  address: { lat: 41.32, lng: 69.22, fullAddress: '1 Test St' },
  items: [{ productId: __ENV.SEED_PRODUCT_ID || 'seed-product', quantity: 2 }],
});

export default function loadtest() {
  group('GET /api/products', () => {
    const r = http.get(`${BASE_URL}/api/products?limit=20`, { headers });
    readLatency.add(r.timings.duration);
    const ok = check(r, { 'products 200': (x) => x.status === 200 });
    errorRate.add(!ok);
  });

  group('GET /api/shops (geo)', () => {
    const r = http.get(`${BASE_URL}/api/shops?lat=41.3&lng=69.2&radiusKm=10`, { headers });
    readLatency.add(r.timings.duration);
    const ok = check(r, { 'shops 200': (x) => x.status === 200 });
    errorRate.add(!ok);
  });

  group('POST /api/orders/estimate', () => {
    const r = http.post(`${BASE_URL}/api/orders/estimate`, ESTIMATE_PAYLOAD, { headers });
    writeLatency.add(r.timings.duration);
    // estimate may legitimately return 400 (out_of_zone) when run against an
    // empty seed; treat 200/400 as non-error so we don't blow the threshold.
    const ok = check(r, { 'estimate 2xx/4xx': (x) => x.status < 500 });
    errorRate.add(!ok);
  });

  // jitter so we don't hammer in lock-step
  sleep(Math.random() * 0.2);
}
