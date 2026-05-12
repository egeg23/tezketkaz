# Money handling

How TezKetKaz represents prices and monetary totals, and why we have not
migrated the schema to `Decimal`.

## Current convention

| Property | Storage | Units |
| --- | --- | --- |
| `Product.price`, `Product.discountPrice` | `Float` (Postgres `DOUBLE PRECISION`) | major units, integer-valued |
| `Order.subtotal`, `Order.total`, `Order.deliveryFee`, `Order.courierReward` | `Float` | major units, integer-valued |
| `Order.discount`, `Order.taxAmount`, `Order.refundedAmount`, `Order.tipAmount` | `Float` | major units, integer-valued |
| `Coupon.value` (when type=`amount`) | `Float` | major units, integer-valued |
| `Payout.grossAmount`, `Payout.netAmount`, `Payout.commission`, `Payout.refundsTotal` | `Float` | major units, integer-valued |
| `Membership.periodAmount` | `Float` | major units, integer-valued |
| `LoyaltyAccount.cashbackBalance`, `LoyaltyTransaction.amount` | `Int` | loyalty points (1 pt ≈ 1 UZS) |

"Major units" = UZS (Узбекский сум), KZT (Казахстанский тенге), RUB (Российский
рубль), KGS (Кыргызский сом). At launch every supported currency is integer-
denominated in practice — sub-unit pricing simply does not happen in retail or
food delivery in Central Asia, so all writes must be whole numbers.

## Why not `Decimal`?

We deliberately keep `Float` instead of switching to Prisma's `Decimal` type
for three reasons:

1. **Integer-only domain.** UZS, KZT, RUB, KGS prices at every payment
   provider and POS we integrate with are integer values. Sub-soum pricing
   would be rejected by every payment gateway and is not used in catalog
   listings either. So the typical motivation for `Decimal` (sub-unit cents)
   does not apply.

2. **Test suite breadth.** The backend test suite (~560 tests at the time of
   this writing) asserts money values with strict `===`/`toBe()` against plain
   JavaScript `Number`s. Switching to `Decimal` would convert every read into
   a `Prisma.Decimal` instance and break essentially every money assertion in
   the codebase. Adopting `Decimal` is therefore a coordinated migration, not
   a schema-only change.

3. **Client serialization.** The Flutter app expects JSON numbers, not
   `{ "value": "12000", "scale": 0 }` shaped objects. The wire format is
   already shaped by `_attachMoneyDecorations` (see `routes/orders.js`) — that
   layer would need to learn `Decimal → Number` coercion at every endpoint.

## Invariant: integer-valued writes

To make the "always integer" assumption explicit and catch bugs early, the
pricing service exposes `assertIntegerMoney(value, label)`. It throws a
400-shaped error when the input is not a finite, integer-valued, non-negative
number. The pricing service uses it before returning the computed
`deliveryFee` and `total` (it already rounded with `Math.round`, so under
normal operation the assertion is a no-op; if a future change introduces a
fractional path, the assertion will surface it instantly).

```js
const { assertIntegerMoney } = require('./services/pricing');

// Anywhere a Float column is written from a freshly computed value:
assertIntegerMoney(deliveryFee, 'Order.deliveryFee');
```

The helper is intentionally cheap (a single typeof + isFinite + integer check)
so adding it at additional write boundaries is safe.

### Where to add the guard

If you introduce a new place that writes a monetary field, add the guard at
the boundary just before the Prisma write. Current call sites:

- `services/pricing.js` — `computeDelivery()` return (`deliveryFee`)
- `routes/orders.js` — `POST /orders` write (when added)
- `services/refunds.js` — `refundOrder()` partial refund branch (when added)

## Test pattern for money assertions

Prefer `toBe(integer)` over `toEqual` or `toBeCloseTo`:

```js
expect(order.total).toBe(57000);             // exact integer compare
expect(order.deliveryFee).toBe(0);
expect(Number.isInteger(order.subtotal)).toBe(true);  // shape check
```

Avoid `toBeCloseTo` — it accepts fractional drift, which is exactly what we
want to catch.

## When to migrate to `Decimal`

Migrate the schema when one of these is true:

- A supported country introduces sub-currency pricing (e.g. KZT tiyin pricing
  for groceries, RUB kopeck pricing). Today none of them do.
- A precision bug surfaces in production. Float arithmetic accumulates error
  in `Order.subtotal = sum(item.total)` once item counts exceed ~2^53 in
  pathological cases; we will hit that long after a Decimal migration.
- A Prisma client upgrade makes the JSON serialization friction go away.

Until then, the integer-Float convention plus `assertIntegerMoney` is the
documented contract.
