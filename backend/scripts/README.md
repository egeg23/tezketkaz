# Load testing — k6

`loadtest.k6.js` exercises the buyer-facing read paths plus the order
estimate write path. It is meant to be run from a CI box or a developer
laptop against a staging environment — **never** point it at production.

## Install k6

```bash
brew install k6                       # macOS
sudo apt install k6                   # Debian/Ubuntu (with InfluxData repo)
docker pull grafana/k6                # any platform
```

## Required env

| var               | example                           | notes                         |
| ----------------- | --------------------------------- | ----------------------------- |
| `BASE_URL`        | `https://staging.tezketkaz.uz`    | defaults to `http://localhost:3000` |
| `TOKEN`           | `eyJhbGc…`                        | Buyer JWT — needed for `/estimate` |
| `SEED_SHOP_ID`    | `…`                               | from a freshly seeded DB      |
| `SEED_PRODUCT_ID` | `…`                               | from a freshly seeded DB      |

## Run

```bash
BASE_URL=https://staging.tezketkaz.uz \
TOKEN=$(curl -s -X POST .../api/auth/verify-otp -d '{...}' | jq -r .accessToken) \
SEED_SHOP_ID=... SEED_PRODUCT_ID=... \
k6 run loadtest.k6.js
```

## Stages

```
0 → 20 RPS   (30s)   ramp
20 RPS       (60s)   hold
20 → 100 RPS (60s)   ramp
100 RPS      (60s)   hold
100 → 0 RPS  (30s)   ramp down
```

## SLO thresholds

| metric                           | budget         |
| -------------------------------- | -------------- |
| read latency (p95)               | < 500 ms       |
| write latency (p99) — `estimate` | < 1500 ms      |
| HTTP failure rate                | < 1 %          |

If thresholds fail, k6 exits non-zero — wire that into CI as a perf gate.
