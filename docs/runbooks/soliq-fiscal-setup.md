# Soliq.uz Fiscal Receipts — Production Activation (Phase 13.3.9)

This runbook walks the operator through enabling automatic fiscal-receipt
issuance via the Uzbek State Tax Committee (Soliq.uz) API. Under the
2024 tax code, cashless transactions over **100,000 UZS** in Uzbekistan
**must** be backed by an issued fiscal receipt. The backend handles this
automatically for every paid order whose shop is wired below.

When the API is mocked (`USE_MOCK_SOLIQ=true`, the default in dev/test),
the backend logs a successful synthetic issue and stores a `mock-…`
receipt id — useful for end-to-end testing without touching production.
In production this must be flipped to `false`.

---

## Prerequisites

- A registered **юр.лицо** (legal entity) profile on https://soliq.uz.
- Access to the Soliq personal cabinet ("Soliq Kabineti") with the
  **TSI** / **ТП** (test-prod) interface unlocked. This requires an EDS
  (electronic digital signature) USB key issued by Uzinfocom.
- For every shop in our platform: their **STIR/INN** (9 or 14 digits).

If the entity is not registered yet, complete the registration first —
Soliq onboarding takes 1-3 business days because the EDS must be issued
physically.

---

## 1. Register your юр.лицо

1. Visit https://soliq.uz → "Кабинет налогоплательщика".
2. Sign in with the EDS USB key.
3. Confirm the legal entity profile: address, contact, VAT/QQS status.
4. Verify that the platform's STIR has the **"Cashless commerce"** flag
   on. If not, file the request via the cabinet — Soliq turns it on
   within 24h.

---

## 2. Get the API key

1. In the cabinet, navigate to **ТП → API → "Создать ключ"** (TSI/TP → API).
2. Generate a new key. Soliq presents it ONCE — copy immediately into a
   password manager (Bitwarden / 1Password).
3. Set the key as both:
   - `SOLIQ_API_KEY` in the backend environment (global fallback).
   - Per-shop `Shop.soliqApiKey` if you want one shop to use a different
     entity (e.g. white-label B2B partner).

If you regenerate the key, the old one is revoked immediately — schedule
the rotation during low-traffic hours.

---

## 3. Collect each shop's STIR / VAT at onboarding

Update the shop-onboarding form (admin-next → Shops → "Create shop") to
require:

- **STIR/INN** (9 or 14 digits) → stored in `Shop.soliqInn`.
- **VAT number** (optional) → stored in `Shop.soliqVatNumber`.

The backend will refuse to issue receipts for any shop missing `soliqInn`
even when the master switch (`Shop.soliqEnabled`) is on. Verify the STIR
in the Soliq cabinet **before** ticking the master switch.

---

## 4. Enable fiscal issuance for a shop

In **admin-next → Shops → [shop] → Edit**:

1. Set `STIR/INN` (required).
2. Set `VAT number` (optional).
3. Set `Soliq API key` (optional; falls back to `SOLIQ_API_KEY` env).
4. Tick **"Soliq fiscal enabled"** → this flips `Shop.soliqEnabled` to
   `true`.
5. Save.

The backend will start issuing fiscal receipts on every paid order from
this shop from this moment on. Existing orders are NOT retroactively
fiscalised — use **§6** below to retry.

---

## 5. Flip the master switch

Once you have at least one shop wired:

```
USE_MOCK_SOLIQ=false
SOLIQ_API_BASE=https://api.soliq.uz/v1
SOLIQ_API_KEY=<your_global_key>   # optional if every shop has a per-shop key
```

Redeploy. The backend now POSTs to the real Soliq endpoint on every
paid order, retrying with exponential backoff (1m, 5m, 30m, 2h, 12h)
on transient failures.

---

## 6. Retrying failed receipts manually

When Soliq is down (or rejects a payload for a fixable reason like wrong
INN), failed orders surface in admin-next → **Fiscal failures**.

To retry from the dashboard:

1. Locate the order in the failures list.
2. Click **"Retry fiscal"**. Behind the scenes this hits
   `POST /api/admin/orders/:id/fiscal-retry`, which re-enqueues the
   `fiscal:issue` BullMQ job AND runs the issue inline once for an
   immediate result.
3. Verify the receipt id + URL populate within ~30 seconds.

You can also bulk-retry via curl:

```bash
for ORDER_ID in $(curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
    https://api.tezketkaz.uz/api/admin/fiscal/failures \
    | jq -r '.orders[].id'); do
  curl -s -X POST \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    https://api.tezketkaz.uz/api/admin/orders/$ORDER_ID/fiscal-retry
done
```

---

## 7. Debugging "fiscal failure" notifications

When the BullMQ job exhausts all 5 retries the backend creates a
`fiscal_failure` Notification for every admin user. The notification's
`data.error` payload contains the last error message from Soliq.

Common errors:

| Error                       | Cause                                | Fix                                      |
| --------------------------- | ------------------------------------ | ---------------------------------------- |
| `soliq_5xx_502`             | Soliq backend transient outage       | Wait for retry; manual retry after outage|
| `shop_not_eligible`         | `soliqEnabled=false` or no INN       | Update shop config in admin-next         |
| `bad_inn`                   | INN doesn't match Soliq registry     | Re-collect STIR from shop                |
| `vat_rate_mismatch`         | Order taxRate doesn't match registry | Verify tax.compute() VAT for that country|
| `auth_failed`               | API key revoked / expired            | Regenerate per §2                        |

---

## Operational notes

- The BullMQ `fiscal` queue runs with concurrency 3 — Soliq's API
  rate-limits at ~5 req/s per partner. Don't bump concurrency above 4
  without prior coordination with Soliq.
- Receipts older than 30 days cannot be modified or refunded via the
  Soliq API — refunds beyond that window require a manual cabinet visit.
- The Soliq.uz endpoint occasionally returns malformed XML on weekends
  during maintenance windows. The job handles this by treating
  unparseable responses as transient and retrying.

---

## Rollback

To temporarily disable fiscal issuance (e.g. during a Soliq outage):

```
USE_MOCK_SOLIQ=true   # synthetic receipts; no real network call
```

…and redeploy. Pending failed jobs will continue to retry against the
mock and silently succeed. Don't leave this on in production for more
than 24h — the tax authority audits every cashless transaction over
100,000 UZS within 7 days.
