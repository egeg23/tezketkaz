# iOS Privacy Nutrition Labels — TezKetKaz

> Mapping of data categories TezKetKaz collects to Apple's App Privacy form
> in App Store Connect. Update this file whenever the data collected by the
> app changes; the store-listing build pipeline reads from here.

Last updated: 2026-05-12 (Phase 13.2.9).

## 1. Data Used to Track You

TezKetKaz **does not track users** in the App Tracking Transparency sense:
we never link first-party data to third-party data for advertising, do not
share data with data brokers, and do not use SDKs that perform cross-app
tracking (no Meta SDK, no AppsFlyer, no Branch, no Adjust). The app does
not display the ATT prompt because no tracking is performed.

## 2. Data Linked to You

These categories are collected and linked to the user's account identifier.

### Contact Info
- **Phone Number** — required for SMS-based authentication and for the
  shop / courier to contact the buyer on delivery.
- **Name** — first + last name supplied during onboarding, shown to shops
  and couriers on order receipts.

### Location
- **Precise Location** — captured only while:
  - a buyer is placing an order (delivery address pin),
  - a courier is on shift (live location stream for dispatcher routing).
- **Coarse Location** — used to populate the buyer "shops near me" feed.

### Identifiers
- **User ID** — internal account identifier issued by our backend, persisted
  in the JWT and used for every authenticated API call.

### Financial Info
- **Payment Info** — card tokens are processed and stored by Click and
  Payme (PCI-compliant Uzbekistan payment providers). TezKetKaz **never
  stores raw PAN, CVV, or full card numbers**; we store only a masked
  reference (last 4 digits, brand) so the user can identify their card
  inside the app.

### User Content
- **Photos** captured for:
  - delivery proof (courier uploads on hand-off),
  - KYC documents (couriers and shop owners during verification),
  - product images (shop owners only).

### Purchases
- **Purchase History** — order lines, totals, delivery fees, and applied
  coupons.

### Diagnostics
- **Crash Data** and **Performance Data** — captured to triage app stability,
  attached to the user ID so support can trace user-reported issues.

### Usage Data
- **Product Interaction** — order placement, cart events, navigation
  actions inside the app.

## 3. Data Not Linked to You

None at this time. Every datum currently collected is linked to the account.

## 4. Purposes (per Apple's required mapping)

| Category | Purposes |
|---|---|
| Contact Info | App Functionality, Customer Support |
| Location | App Functionality (delivery routing) |
| Identifiers | App Functionality |
| Financial Info | App Functionality (order checkout) |
| User Content | App Functionality (delivery proof / KYC) |
| Purchases | App Functionality |
| Diagnostics | App Functionality, Analytics (own analytics only — no third-party) |
| Usage Data | Analytics (own only), Product Personalisation |

## 5. Data Sharing

We share data with third parties **only** to deliver the service:

- **Shop owners** — see the order details, buyer first name, phone, and
  delivery address for orders they receive.
- **Couriers** — see pickup address, delivery address, and the buyer's
  phone for their currently assigned order.
- **Click / Payme** — receive card tokenisation requests; never receive
  delivery addresses or order line items.

We do **not** sell or rent data, and do not share with advertising networks.

## 6. Retention

- Account data is retained while the account is active.
- Per Phase 12's GDPR-style account-deletion flow, soft-deleted accounts
  are fully purged from production databases **90 days after the delete
  request**. KYC photos are purged at the same cadence.
- Audit logs are kept 12 months for fraud-prevention purposes.

## 7. Contacts

- Privacy: privacy@tezketkaz.uz
- Data deletion request: in-app `Settings → Privacy → Delete account` or
  email the above address.
