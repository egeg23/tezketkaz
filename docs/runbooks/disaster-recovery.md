# Disaster Recovery Runbook

Operator handbook for when TezKetKaz is on fire. Each scenario lists severity
(P1/P2/P3), recovery time objective (RTO), step-by-step actions, who to
escalate to, and how to communicate with users.

**Severity levels**
- **P1** — full outage or data loss; user-facing impact within minutes.
- **P2** — degraded service; partial features broken.
- **P3** — silent / observability problem; no user impact.

**Conventions**
- Commands assume the operator is on a Mac/Linux box with `psql`, `gh`,
  and the deployed host's CLI (Render `render`, Railway `railway`, Fly
  `flyctl`) installed and authenticated.
- Placeholders: `<ESCALATION>` is the engineering on-call (set in PagerDuty
  / SaveMyTime / etc.; replace before publishing). `<STATUS_URL>` is the
  public statuspage. `<SUPPORT_PHONE>` is the customer-support hotline.

> **TODO before pilot launch:** these three placeholders MUST be replaced
> with real values throughout this document. Grep for `<ESCALATION>`,
> `<STATUS_URL>`, `<SUPPORT_PHONE>` to find every reference. Suggested:
> - `<ESCALATION>` → `@cto` (Telegram) + `+998 XX XXX-XX-XX` (Бахром / CTO mobile)
> - `<STATUS_URL>` → `https://status.tezketkaz.uz` (Statuspage / Atlassian or
>   self-hosted via `cstate`); register the subdomain in Cloudflare first.
> - `<SUPPORT_PHONE>` → `+998 71 200-XX-XX` (24/7 dispatcher line — see
>   `courier-onboarding.md` §10).

---

## 1. Database corrupt or lost

**Severity** P1 · **RTO** 30 min (Neon PITR) to 2 h (rebuild from scratch)

The Postgres database is the source of truth for every order, user, payment,
and shop. If it's gone, the app is gone. Neon's point-in-time recovery (PITR)
covers the last 7 days on the free tier, 30 days on the paid tier — pick the
**latest** good restore point that is **before** the corruption was committed.

### Steps

1. **Stop writes.** Flip the backend into read-only mode immediately to avoid
   compounding the corruption.
   ```
   # On the host (Render dashboard → Env, or `flyctl secrets set`):
   READ_ONLY=true
   ```
   (If `READ_ONLY` isn't wired yet, just scale the backend to 0 instances —
   the apps will show an "in maintenance" screen via the FE's 503 handler.)
2. **Identify the corruption window.** Look at Sentry for the first error
   referencing the bad data. Check the recent migration history in
   `backend/prisma/migrations/`. Pin a target timestamp `T0` 5 minutes
   *before* the first bad write.
3. **Restore via Neon UI.** Neon Console → Project → Branches → "Create branch
   from point in time" → pick `T0` → name it `restore-YYYY-MM-DD`.
   This creates a fresh writable branch with a new `DATABASE_URL`.
4. **Swap the connection string.** On the host, update `DATABASE_URL` to the
   restored branch's URL. Redeploy.
5. **Sanity check.**
   ```bash
   psql $NEW_DATABASE_URL -c "SELECT COUNT(*) FROM \"User\";"
   psql $NEW_DATABASE_URL -c "SELECT MAX(\"createdAt\") FROM \"Order\";"
   ```
   The latest order should be at or before `T0`. Newer orders are gone —
   that's expected and irrecoverable from a PITR perspective.
6. **Run smoke.**
   ```
   SMOKE_BASE_URL=https://api.tezketkaz.uz \
   SMOKE_TEST_PHONE=+998900000001 \
     node backend/scripts/smoke-test.js
   ```
   9/9 green = restored. Otherwise see `smoke-tests.md` for triage.
7. **Lift read-only.** Remove `READ_ONLY=true` and let writes resume.
8. **Promote the branch.** In Neon, promote `restore-YYYY-MM-DD` to be the
   primary branch (deletes the corrupt one). Update `DATABASE_URL` on the
   host once more if Neon issued a new URL.

### What CANNOT be restored

- **Redis cache** — rate limits, OTP fail-counters, cart drafts, dispatcher
  offer state. All re-populate within minutes of resumed traffic. Cart
  drafts may be lost for users whose drafts hadn't yet been promoted to a
  `pending` order.
- **Local uploads** — if `STORAGE_PROVIDER=local`, the `/uploads/*` directory
  on the host's ephemeral disk. **Always** be on `r2` or `s3` in production
  for this reason.
- **In-flight orders between `T0` and now** — gone. See "Communicate" below;
  most need manual reconciliation with the payment provider.

### Communicate

- Statuspage incident: "Database outage — orders placed between HH:MM and
  HH:MM may be lost." Pin to top.
- Push notification to all users (via `/api/admin/push-campaigns`):
  "We had a brief outage. If your order between HH:MM and HH:MM is missing,
  please contact support."
- Escalate to `<ESCALATION>` immediately on declaring P1.

---

## 2. Backend completely down

**Severity** P1 · **RTO** 10 min

### Steps

1. **Check host dashboard.** Render: status, deployment log, memory/CPU
   graphs. Railway: same. Fly: `flyctl status -a tezketkaz-api`. Look for:
   - Recent deploy that's still rolling out / failed health checks
   - Memory at 100% (likely an N+1 query or runaway job)
   - "App suspended for free tier" (free hosts auto-sleep)
2. **Check Sentry.** Filter by environment=production, last 15 min, level≥error.
   A crash loop usually shows the same stack trace repeating ~once per second.
3. **Check Postgres.** Sometimes the backend is "up" but every request hangs
   waiting for a DB connection.
   ```bash
   psql $DATABASE_URL -c "SELECT NOW();"
   psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity WHERE state='active';"
   ```
   If the second number is > ~20, the connection pool is saturated. Bounce
   the backend to drop stale connections.
4. **Tail logs.** Render: dashboard → Logs → live. `flyctl logs -a …`. Look
   for "uncaught exception", "EADDRINUSE", "ETIMEDOUT" (DB), Prisma errors.
5. **Manual rollback.** If the cause is a bad deploy:
   - Render: Deployments tab → previous green build → "Rollback".
   - Railway: Deployments tab → previous → "Redeploy this".
   - Fly: `flyctl releases list -a tezketkaz-api` then `flyctl releases rollback <n>`.
6. **Run smoke.** `SMOKE_BASE_URL=https://api.tezketkaz.uz node backend/scripts/smoke-test.js`.
7. **Post-mortem.** Open a GitHub issue. Add the failing commit SHA, the
   Sentry issue ID, and the resolution.

### Communicate

- Statuspage: "Investigating elevated errors" → "Identified" → "Resolved".
- Skip push notifications unless the outage lasts > 30 min — most users
  will just retry.
- Escalate to `<ESCALATION>` after 5 min if root cause isn't obvious.

---

## 3. Payment provider outage

**Severity** P2 · **RTO** 5 min (flip mock) + manual reconciliation

Click, Payme, Uzum, Kaspi, and Click KG each have an independent `USE_MOCK_*`
toggle (Wave 3c). Flip the affected provider to mock so orders keep flowing
— affected payments get logged for later reconciliation.

### Steps

1. **Identify the affected provider.** Sentry will show 5xx from the provider
   plus our 402 responses. Provider statuspages: click.uz, payme.uz, etc.
2. **Flip the per-provider switch.** On the host:
   ```
   USE_MOCK_CLICK=true    # or USE_MOCK_PAYME / _UZUM / _KASPI / _CLICK_KG
   ```
   Restart. From now on, calls to that provider return a synthetic
   "success" — money is **not** actually charged.
3. **Notify users.** Push campaign (`/api/admin/push-campaigns`):
   "Click payments are temporarily delayed. Your order will go through;
   we'll bill you once Click is back."
4. **Track affected orders.** Query for the time window:
   ```sql
   SELECT id, total, "paymentMethod", "createdAt"
   FROM "Order"
   WHERE "paymentMethod" = 'click'
     AND "createdAt" > '<T0>'
     AND "paymentStatus" = 'paid';
   ```
   Export to CSV (admin → orders → export). Hand to finance for manual
   reconciliation against Click's reports.
5. **Restore.** Once the provider is healthy, remove the env override. The
   `useMock*` derivation in `config/env.js` falls back to the global
   `USE_MOCK_PAYMENTS` automatically.

### Communicate

- In-app banner via admin → push campaigns: "Click is briefly degraded."
- Don't statuspage unless multiple providers are down — most users use only
  one. Escalate to `<ESCALATION>` only if no provider works.

---

## 4. R2 / S3 storage outage

**Severity** P2 · **RTO** 10 min (degraded uploads) to 30 min (clean restore)

Storage is used for product images, delivery photos, support attachments,
shop avatars. R2/S3 outages typically affect *uploads* (writes); reads via
the public CDN URL usually keep working.

### Steps

1. **Confirm scope.** Test a curl to the public URL: a known image should
   load. If yes, only writes are affected; if no, it's a global Cloudflare
   incident — check status.cloudflare.com.
2. **Degraded mode (allow uploads).** On the host:
   ```
   STORAGE_PROVIDER=local
   ```
   New uploads land on the host's ephemeral disk and serve via `/uploads/*`.
   Restart the backend.
3. **Or — block new uploads.** If host disk is small or you can't risk
   losing local files in a restart, set `UPLOADS_DISABLED=true` instead
   and surface a 503 to clients trying to upload. (Add this flag if it
   doesn't exist yet — out of scope for this initial DR pass.)
4. **Watch the local disk.** `df -h` on the host. Bounce if disk fills up.
5. **Sync back to R2 when restored.**
   ```bash
   # Once R2 is back and STORAGE_PROVIDER is flipped back to 'r2':
   aws s3 sync ./uploads s3://tezketkaz-prod/ \
     --endpoint-url=https://<accountid>.r2.cloudflarestorage.com \
     --acl public-read
   ```
   Files uploaded during the outage are NOT auto-migrated by the code —
   their DB rows reference the relative local URL and will keep working
   while `STORAGE_PROVIDER=local`. After the sync, run a DB rewrite to
   point them at the new R2 URLs (admin task; see `prisma/scripts/`).
6. **Flip back.** `STORAGE_PROVIDER=r2`. Redeploy. Smoke.

### Communicate

- No public messaging unless reads are also down.
- Notify shops via admin chat that they may see "upload failed" briefly.

---

## 5. FCM (push) outage

**Severity** P3 · **RTO** 2 min

Push is best-effort. Users still get in-app notifications via sockets and
in-app notification feed. The risk during a FCM outage is *retry storms* —
queued retries piling up in BullMQ and eating CPU.

### Steps

1. **Confirm.** Sentry: 5xx from `firebase-admin`. Status: status.firebase.google.com.
2. **Silence retries.** On the host:
   ```
   FCM_ENABLED=false
   ```
   Restart. `services/push.js` becomes a no-op; the BullMQ retry queue
   drains naturally.
3. **Drop the queue if needed.** If thousands of retries are pending:
   ```bash
   redis-cli -u $REDIS_URL FLUSHDB --bull push
   ```
   (Be careful — this also drops other Bull queues if they share the DB.
   Prefer per-queue clear via `bullmq` CLI.)
4. **Restore.** Once FCM is healthy, `FCM_ENABLED=true` and redeploy.

### Communicate

- None. Users will see in-app notifications; missing pushes are silent.

---

## 6. Redis outage

**Severity** P2 · **RTO** 2 min (degraded mode)

Redis backs rate limits, OTP fail-counters, JWT blacklist, cart drafts, and
the Socket.IO multi-instance adapter. Without Redis the backend can still
serve traffic, but:
- Rate limits become per-instance (multi-instance setups lose global limits).
- Cart drafts fall back to DB writes (slower; ~100ms vs ~5ms).
- Sockets fall back to polling (no multi-instance fan-out).
- JWT blacklist resets — logout-all loses the in-flight access-token revoke.

### Steps

1. **Confirm.** Backend logs: "redis connection refused", "ECONNRESET".
   Check provider status (Upstash, Render Redis, Railway).
2. **Disable Redis.** On the host:
   ```
   REDIS_ENABLED=false
   ```
   Restart. `lib/redis.js` switches to its in-memory shim transparently.
3. **Verify smoke still passes.** `node backend/scripts/smoke-test.js`.
4. **Monitor DB load.** Cart drafts and OTP rate-limits move to DB —
   if order rate is high, watch for `pg_stat_activity` spikes.
5. **Restore.** Provision a new Redis (or wait for the existing one),
   set `REDIS_URL` + `REDIS_ENABLED=true`, redeploy. State (rate limits etc.)
   starts fresh — that's fine.

### Communicate

- None unless cart-draft loss is widespread.

---

## 7. Lost Android signing keystore

**Severity** P2 (no user-facing outage, but **cannot ship updates**) · **RTO** 1 week+

The Google Play upload key is irrecoverable. If it's lost, the **only**
options Google offers are:

1. **Upload key reset.** If you enrolled in Play App Signing (Google holds
   the actual signing key), you can request a new upload key via Play
   Console → Setup → App Integrity → "Request upload key reset". Google
   needs 1–2 business days. Once approved, generate a new key and update
   `android/fastlane/Pluginfile` / CI secrets.

2. **No Play App Signing → republish as a new package.** Brutal. Existing
   users cannot update. Procedure:
   - Decide on a new package name, e.g. `uz.tezketkaz.app2`.
   - Search-and-replace `uz.tezketkaz` → `uz.tezketkaz.app2` in `android/`,
     `ios/`, marketing site, deep-link configs.
   - Generate a fresh keystore. Store it in **two** redundant secret stores
     (1Password + Bitwarden, or 1Password + a sealed envelope in a safe).
   - Submit `app2` to Play. Wait for review (1–7 days).
   - In the **old** app's next (final) update, add a forced migration prompt:
     "TezKetKaz has moved — install the new app to keep using it." Deep-link
     to the new Play Store entry.
   - Encourage migration via push + in-app banner + SMS for 60 days. After
     90 days, unpublish the old app from Play.

### Communicate

- All Android users via push + in-app banner.
- Statuspage incident describing the rollover.
- Brace for a ~20% churn — non-trivial fraction of users won't migrate.

---

## 8. Lost iOS signing

**Severity** P2 · **RTO** 4 hours

Easier than Android. Apple holds the signing certificate; the **private key**
can be regenerated if lost.

### Steps

1. **Recover from password manager.** The keystore + provisioning profiles
   should be in 1Password under "TezKetKaz / iOS Signing". This is the
   primary store.
2. **Regenerate via App Store Connect.** If the password manager is also lost:
   - Sign in to developer.apple.com.
   - Certificates → revoke the old Distribution cert.
   - Generate a new one (download to a Mac with the corresponding CSR).
   - Provisioning Profiles → regenerate the App Store profile.
   - Update `ios/fastlane/Appfile` and `ios/fastlane/Matchfile`.
   - Re-run `fastlane match appstore` (this is documented in
     `fastlane/README.md`).
   - Submit a new build with the regenerated profile.
3. **Store rollover.** Apple may ask for re-verification of the apple-app-site
   association if the app's entitlements changed. Update
   `web/public/.well-known/apple-app-site-association` if needed.

### Communicate

- No user-facing message needed; existing builds keep working.
- Internal: notify the iOS dev so they don't waste an hour on a "signing
  failure" of unknown origin.

---

## 9. Sentry quota exceeded

**Severity** P3 · **RTO** 5 min (suppress) — quota resets monthly

Sentry's free tier is 5k events/month; paid is whatever you bought. When
exhausted, Sentry drops events silently and you lose observability.

### Two paths

#### Path A — increase plan

Sentry → Settings → Billing → upgrade. Takes effect immediately. Pick a
plan that gives 2–3× current peak monthly volume. This is the right answer
if your error rate is reasonable and you genuinely need the headroom.

#### Path B — suppress noise

If a single bug is generating 90% of events:

1. **Identify the offender.** Sentry → Issues → sort by event count. The top
   issue typically dominates.
2. **Fix the bug.** Always preferred. The smoke test gives you a baseline
   to verify the fix.
3. **If you can't fix today, suppress.** Two options:
   - Sentry-side: Issue → "Ignore" or "Resolve in next release" or
     "Delete & discard" (drops future occurrences).
   - Code-side: In `backend/src/index.js` Sentry init, add a
     `beforeSend` filter:
     ```js
     Sentry.init({
       beforeSend(event, hint) {
         const msg = hint?.originalException?.message || event.message || '';
         if (msg.includes('the-noisy-pattern')) return null;
         return event;
       },
     });
     ```
     Redeploy.
4. **Common quick-win drops:**
   - `EPIPE` / `ECONNRESET` from clients dropping mid-request.
   - `JsonWebTokenError: jwt malformed` from broken clients.
   - 4xx ValidationError thrown from input validation — these belong in
     `logger.info`, not Sentry.

### Communicate

- None externally. Internally, flag in the eng channel that observability
  is degraded so people know "no errors in Sentry" doesn't mean "no errors".

---

## Escalation matrix

| Severity | First responder | Escalate after | Who |
|---|---|---|---|
| P1 | On-call eng | 5 min | `<ESCALATION>` |
| P2 | On-call eng | 30 min | `<ESCALATION>` |
| P3 | Next-business-day | n/a | File GitHub issue |

Customer comms run through the support channel (`<SUPPORT_PHONE>` for
voice, statuspage `<STATUS_URL>` for written). Operators must **never**
post incident details on public social media without sign-off from
`<ESCALATION>`.

---

## Quarterly DR drill

Once per quarter, the on-call engineer:

1. Creates a staging Neon branch named `dr-drill-<date>`.
2. Pretends it's prod. Walks through scenarios 1, 2, 6 above using staging.
3. Times each. Updates this runbook if RTO estimates are wrong.
4. Files a GitHub issue with the timings.

Skipped drills are a leading indicator of unrecoverable outages. Don't skip.
