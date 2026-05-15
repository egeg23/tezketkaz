# Android Data Safety — TezKetKaz

> Mapping of data categories TezKetKaz collects to Google Play's Data Safety
> form. Update this file whenever the data collected by the app changes;
> the store-listing build pipeline reads from here.

Last updated: 2026-05-12 (Phase 13.2.9).

## Top-level declarations

- **Data is encrypted in transit** — yes (TLS 1.2+ for every backend call;
  HSTS enforced on api.tezketkaz.uz).
- **User can request data deletion** — yes (in-app
  `Settings → Privacy → Delete account` and email channel; see retention
  section below).
- **Independent security review** — internal review only at this time.
- **Adheres to Play Families policy** — not applicable (the app is 16+; we
  do not knowingly collect data from children).

## Data types collected

| Category | Type | Collected? | Shared? | Required / Optional | Purposes |
|---|---|---|---|---|---|
| **Personal info** | Name | Yes | With shop owners & couriers (for delivery) | Required | App functionality |
| Personal info | Phone number | Yes | With shop owners & couriers | Required | Account management, App functionality |
| Personal info | User IDs | Yes | No | Required | App functionality |
| **Financial info** | Payment card | Tokenised by Click / Payme; we store only the masked reference | With Click / Payme processors | Required (for paid orders) | App functionality (checkout) |
| Financial info | Purchase history | Yes | No | Required | App functionality |
| **Location** | Precise location | Yes — only while a buyer places an order or a courier is on shift | With assigned courier (delivery pin) | Required during order placement / shift | App functionality (delivery routing) |
| Location | Approximate location | Yes | No | Optional | App functionality (nearby shops feed) |
| **Photos & videos** | Photos | Yes — delivery proof, KYC documents, shop product photos | Delivery-proof images sent to the buyer; KYC photos to internal review only | Required for couriers (KYC + proof); optional for buyers | App functionality, Fraud prevention |
| **App activity** | App interactions | Yes | No | Required | Analytics (own), App functionality |
| App activity | In-app search history | Yes | No | Optional | App functionality, Product personalisation |
| **App info & performance** | Crash logs | Yes | No | Required | Analytics, App functionality |
| App info & performance | Diagnostics | Yes | No | Required | Analytics, App functionality |
| **Device or other IDs** | Device or other IDs | Yes — only a TezKetKaz-issued user ID; no Advertising ID is read | No | Required | Account management, App functionality |

## What we explicitly do NOT collect

- Email address (we authenticate by phone only; email is optional and used
  solely for receipt delivery when the user opts in).
- Contacts list, calendar, microphone, SMS, call logs.
- Health, fitness, biometric data.
- Web browsing history.
- Sexual orientation, race, ethnicity, political views, religious beliefs.
- Advertising IDs / GAID.
- Files outside the photos a user explicitly attaches.

## Data sharing — third parties

We share data with third parties only to deliver the service. The
recipients and the data they receive:

- **Click and Payme** (Uzbek payment providers): card tokenisation requests
  during checkout. They never receive line items or addresses.
- **Shop owners** (when an order is placed at their shop): buyer first
  name, phone number, delivery address, order line items.
- **Couriers** (when an order is dispatched to them): pickup address,
  delivery address, buyer phone number for their currently assigned order
  only.

We do **not** sell or rent data to data brokers, and do not share with
advertising networks.

## Data retention

- Active accounts: retained for the lifetime of the account.
- Account deletion: per Phase 12's deletion flow, all personal data is
  fully purged from production databases **90 days after the deletion
  request**. KYC photos are purged on the same schedule.
- Audit logs: retained 12 months for fraud-prevention purposes.

## Contacts

- Privacy: privacy@tezketkaz.uz
- Data deletion: in-app `Settings → Privacy → Delete account`, or email
  privacy@tezketkaz.uz.
