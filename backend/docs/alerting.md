# Sentry Alerting Rules (Production)

This document describes the alerting rules we recommend configuring against
the `tezketkaz-backend` Sentry project once Phase 12 reaches production.
Nothing here is enforced in code; rules are configured manually in the
Sentry UI under **Alerts → Create Alert**.

## On-call paging rules

| # | Condition | Window | Action |
|---|-----------|--------|--------|
| 1 | Error rate > 5% of all events | 1 min | Page on-call (PagerDuty / phone) |
| 2 | HTTP 5xx count > 10 events | 1 min | Page on-call |
| 3 | `/api/orders/*` p95 latency > 1 s | 5 min | Notify #ops Slack |
| 4 | New issue fingerprint (first seen) | 30 min | Notify #engineering Slack |

### 1. Error rate > 5%/min

Use a *Metric Alert* on `event.type:error` with a threshold of
`count() / count_unique(transaction) > 0.05` over a 1-minute window.
This catches deploys that suddenly start failing en masse.

### 2. 5xx > 10/min

Issue alert filtered on `http.status_code:5xx` with the count threshold at
10 in 1 minute. The 5xx rate is more actionable than raw error count because
4xx noise (auth failures, validation) doesn't pollute it.

### 3. Latency p95 on `/api/orders`

Metric alert on `transaction.duration` for `transaction:/api/orders/*`
with p95 > 1000 ms over a 5-minute window. Notifies #ops without paging;
investigators should look at Yandex Routing API latency, DB lock contention,
and Redis health first.

### 4. New error fingerprint

Issue alert on `event.type:error` with the *"A new issue is created"* trigger.
Routed to #engineering with a 30-minute cool-down so we don't get flooded
when a release introduces a flood of related issues. Use this to catch
regressions early without paging.

## Release tagging

CI tags each commit's Sentry release in `.github/workflows/test.yml`. This
ties Sentry issues to the deploy that introduced them. Without release
tagging the alerts above are still useful but root-cause analysis is harder.

Flutter web sourcemaps can be uploaded with
`backend/scripts/upload-sourcemaps.sh` after a release build.

## Recommended escalation policy

1. **Page on-call** for rules 1 & 2 (production impact).
2. **Slack notify** for rules 3 & 4 (investigate same-day).
3. Auto-resolve after 30 minutes of no recurrence.
