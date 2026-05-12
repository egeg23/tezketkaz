# Smoke Tests — Post-Deploy Checks

Operator runbook for `backend/scripts/smoke-test.js`. Read this before your
first deploy and again whenever the script fails.

## TL;DR

```bash
# Local backend
SMOKE_BASE_URL=http://localhost:3000 \
SMOKE_TEST_PHONE=+998900000001 \
  node backend/scripts/smoke-test.js

# Staging
SMOKE_BASE_URL=https://staging.api.tezketkaz.uz \
SMOKE_TEST_PHONE=+998900000001 \
  node backend/scripts/smoke-test.js

# Production
SMOKE_BASE_URL=https://api.tezketkaz.uz \
SMOKE_TEST_PHONE=+998900000001 \
  node backend/scripts/smoke-test.js
```

Exit code `0` means everything works. Exit code `1` means something is broken
— see "Interpreting failures" below.

## What this is (and isn't)

This is a **post-deploy live-API check**. It exercises the same paths a real
buyer would in the critical bootstrap flow:

1. `POST /api/auth/send-otp` — the OTP plumbing is wired up
2. `POST /api/auth/verify-otp` — JWT tokens are issued, the legal-acceptance
   gate works, refresh rotation works
3. `PATCH /api/users/me` — authenticated writes hit the DB
4. `GET /api/shops` — public reads, geo indexing
5. `GET /api/categories` — category tree is populated
6. `GET /api/products?shopId=…` — product listing per shop
7. `POST /api/orders` — order creation incl. pricing, delivery fee, coupons
8. `GET /api/orders/:id` — order is queryable and in `pending`
9. Manual cleanup note (no buyer-cancel endpoint; admin cleans up if needed)

It is **not** a replacement for the Jest test suite. Jest covers branches,
errors, edge cases. The smoke test only proves the happy path is alive in
production. Run both — Jest in CI, smoke after every deploy.

What it does **not** cover:

- Push notifications (FCM)
- Payment provider webhooks (Click, Payme, Uzum, Kaspi, Click KG)
- Real-time sockets / dispatch
- Courier or shop-owner flows
- Admin endpoints

To exercise those, add steps (see "Adding new steps" below) or rely on Jest +
manual QA.

## When to run

- **After every backend deploy** — the GitHub workflow at
  `.github/workflows/smoke-after-deploy.yml` wires this up automatically once
  you pick a host with `deployment_status` events.
- **After every database migration** — schema changes can break order creation
  silently if a required column is missing.
- **After rotating any third-party credentials** — Eskiz, Click, Payme, Soliq,
  Resend, FCM. The smoke flow uses none of them directly but a broken Eskiz
  token can crash `send-otp` even for the test phone (because `services/sms.js`
  refreshes the token on every call).
- **Before announcing a new market launch** — run with a phone for that
  market (e.g. `+77000000001` for KZ) once you have a regional test number
  on the allowlist.

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `SMOKE_BASE_URL` | `http://localhost:3000` | Backend root URL. No trailing slash. |
| `SMOKE_TEST_PHONE` | `+998900000001` | Phone the script logs in as. Must be in the server's allowlist (see below). |
| `NO_COLOR` | unset | Set to disable ANSI colour for log piping. |

The script has no other configuration — it uses only Node 20+ built-ins
(`fetch`, no third-party deps).

## Server-side allowlist

In production, real SMS goes through Eskiz and the OTP is random. The smoke
script needs a phone for which the server always issues code `123456`. That
allowlist lives in env on the backend:

```
TEST_PHONES_ACCEPT_123456=+998900000001,+998900000002
```

Rules:

- Set on the server (Render/Railway/Fly env), **not** in the smoke runner.
- Limit to numbers under operator control. Anyone who knows a number on this
  list can log in with `123456`.
- The numbers don't need to be real SIMs — the server skips SMS dispatch for
  them entirely. Pick reserved E.164 prefixes that don't collide with real
  ranges (e.g. UZ `+99890000xxxx`).
- Adding a number does **not** retroactively allow `123456` for prior OTPs
  — the next `send-otp` call seeds a new row.

In dev / staging (`NODE_ENV !== 'production'`) or when `USE_MOCK_SMS=true`,
all phones already accept `123456`. The allowlist is a production-only
escape hatch.

## Required state in the live DB

Smoke needs the following seeded *somewhere* the smoke phone can see:

- At least 1 active shop with delivery zone covering `(41.3111, 69.2797)`
  (central Tashkent). The default `backend/prisma/seed.js` does this.
- At least 1 category.
- At least 1 available product on the seeded shop.

If you wipe prod and start cold, run `npm run db:seed` from the backend
container, then re-run smoke.

## Adding new steps

Each step is a `step('name', async () => {...})` call. The closure can throw
and the runner will record a failure, attach `err.body` for context, and
exit non-zero.

```js
const newOrder = await step('POST /api/orders/from-cart', async () => {
  const res = await call('POST', '/api/orders/from-cart', { token, body: {…} });
  if (!res?.order?.id) throw Object.assign(new Error('no order'), { body: res });
  return res.order;
});
```

When you add steps, also bump the `total = 9` in the summary line and the
`[idx/9]` slot in `step()` (both at the top of `smoke-test.js`).

Keep steps idempotent or self-cleaning. The smoke phone re-runs hundreds of
times — accumulating data is fine as long as nothing fails.

## Interpreting failures

The script prints which step failed plus the response body (truncated to
400 chars). Common failure modes:

| Symptom | Cause | Fix |
|---|---|---|
| Step 1 `network error` | Backend is down or BASE_URL wrong | Check Render/Railway dashboard. See `disaster-recovery.md` §2. |
| Step 1 `400 Invalid phone number` | `SMOKE_TEST_PHONE` doesn't match the E.164 patterns in `auth.js#isAllowedPhone` | Use a valid country prefix. |
| Step 1 `429 Too many OTP requests` | Smoke phone hit the per-hour limit (5/hr) | Wait an hour or rotate `SMOKE_TEST_PHONE` to a second allowlisted number. |
| Step 2 `400 Invalid or expired code` | Phone isn't in `TEST_PHONES_ACCEPT_123456` on the server | Add it on the backend env and redeploy. |
| Step 2 `400 legal_acceptance_required` | `CURRENT_LEGAL_VERSION` in `constants/legal.js` is no longer `v1.0.0` | Update `LEGAL_VERSION` constant at the top of `smoke-test.js`. |
| Step 4 `no shops returned` | Empty DB or all shops `isActive=false` | Re-run `prisma seed` or check `Shop` rows. |
| Step 5 `no categories returned` | Same — empty category table | Re-seed. |
| Step 6 `no available products` | Smoke shop has no products with `isAvailable=true` | Re-seed or add a product. |
| Step 7 `400 out_of_zone` | Smoke shop's delivery zone polygon doesn't cover `(41.31, 69.28)` | Either (a) move the test coordinate, (b) widen the zone, or (c) point at a different shop. |
| Step 7 `400 min_order_not_met` | Cheapest product < zone's `minOrder` | Increase product quantity in step 7, or lower zone minOrder. |
| Step 7 `400 shop_closed` | Shop's working hours don't include "now" | Either add 24/7 hours to the smoke shop, or pass `scheduledFor: <iso>` in step 7. |
| Step 8 `expected status 'pending', got 'collecting'` | Auto-accept rule fired (rare in prod) | Check shop's auto-accept config; usually harmless — adjust assertion. |

## Cleanup of smoke-generated data

Each run leaves behind:

- One row in `User` (or reuses the existing smoke user).
- One row in `OtpCode` (expired after 5 min, GC'd by the cleanup job).
- One `Order` in `pending` state per run.

The smoke order ID is printed at the end of every successful run. To clean
up, log into the admin app, search the smoke user, and bulk-cancel pending
orders. Or hit `POST /api/orders/:id/shop/cancel` as a shop-owner of the
smoke shop.

Long-term, consider a nightly cron that deletes orders older than 24h
belonging to the smoke phone — out of scope for Phase 13.3.1.

## Wiring into CI

`.github/workflows/smoke-after-deploy.yml` triggers on `deployment_status`.
That fires when whichever host you pick (Render / Railway / Vercel / Fly)
reports a successful deploy back to GitHub.

The workflow is intentionally checked in but commented as **optional** — it
won't trigger until you (a) connect the host to GitHub Deployments and (b)
set the required secrets in repo settings:

- `SMOKE_BASE_URL` — production API URL (repository secret)
- `SMOKE_TEST_PHONE` — E.164 phone from the server's allowlist

Once set, every successful deploy triggers the smoke; a smoke failure fails
the workflow and (depending on your branch protection) blocks rollouts. See
`disaster-recovery.md` §2 for what to do when it fails.
