# Payment Providers — Production Activation (Phase 13.1.7)

This runbook walks the operator through the steps required to switch each
payment provider from mock mode to real production traffic after merchant
credentials have been received.

## Prerequisites

You have received merchant credentials from one or more of:

- Click (UZ): https://click.uz/business
- Payme (UZ): https://merchant.payme.uz
- Uzum (UZ): https://uzum.uz/merchant
- Kaspi (KZ): https://kaspi.kz/merchant
- Click KG: https://my.click.kg/business

You have **deployed** the backend at least once to your prod hosting (Render,
Railway, Fly, self-hosted, etc.) and you know how to set environment variables
on that platform without redeploying secrets to git.

## Activation order

Activate **one provider at a time** in this order — UZ first because that is
where the pilot launches. Wait until each provider has processed at least one
real (1000 UZS / 100 KZT) live transaction before moving to the next.

---

## Click (Uzbekistan)

1. Receive from Click: `merchant_id`, `service_id`, `secret_key`.
2. Set env vars in production:
   ```
   USE_MOCK_PAYMENTS=false
   CLICK_MERCHANT_ID=<your_merchant_id>
   CLICK_SERVICE_ID=<your_service_id>
   CLICK_SECRET_KEY=<your_secret_key>
   ```
3. Configure Click callback URL in their merchant dashboard:
   ```
   https://api.tezketkaz.uz/api/payments/click/callback
   ```
4. Local diagnostic:
   ```bash
   CLICK_MERCHANT_ID=... CLICK_SERVICE_ID=... CLICK_SECRET_KEY=... \
     node backend/scripts/payment-diagnose.js click
   ```
   Expected: all four checks pass. Copy the printed `sign_string` and verify
   it against Click's "Test signature" tool in their merchant cabinet.
5. Production smoke test:
   - Create a real order in the app for 1000 UZS.
   - Pay with a real Click card.
   - Verify the order is marked `isPaid=true` within 30 s.
   - Verify the transaction appears in your Click merchant dashboard.
   - Issue a 1000 UZS refund from the admin panel; verify in Click dashboard.

---

## Payme (Uzbekistan)

1. Receive from Payme: `merchant_id` (24-char hex), `key` (the test endpoint
   password). The `key` is shown ONCE in the Payme cabinet — copy carefully.
2. Set env vars:
   ```
   USE_MOCK_PAYMENTS=false
   PAYME_MERCHANT_ID=<your_merchant_id>
   PAYME_KEY=<your_key>
   ```
3. In Payme merchant cabinet → Settings → Endpoints:
   ```
   https://api.tezketkaz.uz/api/payments/payme/callback
   ```
4. In the same cabinet, configure "Параметры счёта" (Account parameters):
   - Field name: `order_id` (matches `ac.order_id` we emit in createInvoice).
   - Field type: String. Required: yes.
5. Diagnostic:
   ```bash
   PAYME_MERCHANT_ID=... PAYME_KEY=... \
     node backend/scripts/payment-diagnose.js payme
   ```
6. Payme will run their automated test endpoint suite against your URL
   immediately after activation. Watch backend logs for `payme/callback`
   requests; all six methods (CheckPerformTransaction, CreateTransaction,
   PerformTransaction, CancelTransaction, CheckTransaction, GetStatement)
   must respond with `result` (not `error`) on the happy path.
7. Production smoke test: 1000 UZS via real Payme card, verify, refund.

---

## Uzum Pay (Uzbekistan)

1. Receive from Uzum: `merchant_id`, `secret_key` (HMAC signing secret).
2. Set env vars:
   ```
   USE_MOCK_PAYMENTS=false
   UZUM_MERCHANT_ID=<your_merchant_id>
   UZUM_SECRET_KEY=<your_secret_key>
   ```
3. In Uzum merchant cabinet → Webhook settings:
   ```
   https://api.tezketkaz.uz/api/payments/uzum/callback
   ```
4. Diagnostic:
   ```bash
   UZUM_MERCHANT_ID=... UZUM_SECRET_KEY=... \
     node backend/scripts/payment-diagnose.js uzum
   ```
5. **Note**: `services/uzum.js createInvoice` currently builds a hosted GET
   URL. After receiving prod creds, verify with Uzum support whether their
   production flow needs the POST `/v1/payment/create` API call instead.
   If yes — fix the createInvoice body BEFORE running smoke tests.
6. Smoke test: 1000 UZS via real Uzum card, verify, refund.

---

## Kaspi (Kazakhstan)

1. Receive from Kaspi: `merchant_id`, `secret` (HMAC signing secret).
2. Set env vars:
   ```
   USE_MOCK_PAYMENTS=false
   KASPI_MERCHANT_ID=<your_merchant_id>
   KASPI_SECRET=<your_secret>
   ```
3. In Kaspi merchant cabinet → Webhooks:
   ```
   https://api.tezketkaz.uz/api/payments/kaspi/callback
   ```
4. Diagnostic:
   ```bash
   KASPI_MERCHANT_ID=... KASPI_SECRET=... \
     node backend/scripts/payment-diagnose.js kaspi
   ```
5. **Note**: `services/kaspi.js pay()` currently returns
   `kaspi_not_configured` — the createInvoice POST body needs to be wired up
   against Kaspi's prod docs. Do this before smoke testing.
6. Smoke test: 100 KZT via Kaspi QR pay, verify, refund.

---

## Click KG (Kyrgyzstan)

Same flow as Click UZ but with `CLICK_KG_*` env vars and callback URL
`/api/payments/click-kg/callback`. Only enable when launching in KG.

---

## Troubleshooting

- **"Signature mismatch"** → check secret key has no leading/trailing
  whitespace (the diagnose script catches this). Also verify Click did not
  rotate the key — the cabinet sometimes silently regenerates it after a
  password reset.
- **"Merchant not found"** → wait 1–2 hours after merchant approval; Click
  and Payme cache merchant lookups for ~30 min on their side.
- **"401 Unauthorized" on Payme webhook** → the `Authorization` header must
  be exactly `Basic <base64(Paycom:<PAYME_KEY>)>`. The user portion is the
  literal string `Paycom`, NOT your merchant id.
- **Refund stuck in 'pending'** → Click and Payme process refunds in 1–3
  business days (not instant). Uzum is usually same-day. Kaspi is instant.
- **HMAC verification failing on Uzum/Kaspi** → the webhook handler computes
  HMAC over the **raw bytes** of the request body. If you put a JSON-parsing
  proxy in front of the backend it may re-serialize and break the HMAC. The
  raw-body parser is mounted in `src/routes/payments.js` — verify your
  Render / Railway config does not strip it.
- **Double-charge fear** → every webhook is idempotent on
  `(provider, externalId)` via the `ProcessedWebhook` table; retries replay
  the cached response. Safe to enable provider's retry feature.

---

## Per-provider rollback

If a single provider breaks in production (e.g. Click signature suddenly
mismatches after their key rotation), you can mock-out only that provider
without disabling the others. Set in prod env:

```
USE_MOCK_CLICK=true        # only this provider goes back to mock
# (leave USE_MOCK_PAYMENTS=false and other providers untouched)
```

Available per-provider flags:

- `USE_MOCK_CLICK`
- `USE_MOCK_PAYME`
- `USE_MOCK_UZUM`
- `USE_MOCK_KASPI`
- `USE_MOCK_CLICK_KG`

Redeploy backend (≤ 2 min). New payments via the affected provider get
auto-confirmed in mock mode so users aren't blocked.

## Full rollback procedure

If multiple providers break or you need to take payments offline:

1. Set `USE_MOCK_PAYMENTS=true` in env.
2. Redeploy backend (≤ 2 min).
3. Existing orders that were initiated in real mode and never reached the
   webhook will be stuck in `payment_pending` state. Two options:
   - Admin marks them paid manually in the admin panel (Orders → Edit →
     toggle isPaid). The `POST /admin/orders/:id/force-paid` endpoint is
     **not yet implemented** — use the admin UI's order edit form or a
     direct SQL update (`UPDATE "Order" SET "isPaid"=true WHERE id=...`).
   - Refund them off-band via the provider's merchant cabinet and notify
     the buyer via push.
4. Notify affected users via push: "Платежи временно недоступны, оплата
   при доставке."

---

## Post-activation checklist

After each provider goes live, verify these continue to pass:

```bash
cd backend && DATABASE_URL=postgresql://postgres:postgres@localhost:5432/tezketkaz_test \
  npx jest --runInBand --testPathPattern="signature|payment|webhook"
```

If any signature test fails, the provider's response shape has likely changed
and the verification code in `src/services/<provider>.js` needs review.

Also: monitor Sentry for `payment.received` audit events in the first 24 h.
Absence of these for a provider that should be live ⇒ webhook not reaching
the backend (firewall? wrong URL? https cert?).
