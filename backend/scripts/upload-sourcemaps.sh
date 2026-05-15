#!/usr/bin/env bash
# Upload Flutter web build sourcemaps to Sentry. Run manually after a release
# build (`flutter build web --source-maps`). Idempotent: re-running with the
# same RELEASE just re-uploads the files.
#
# Required env:
#   SENTRY_AUTH_TOKEN  — user/org auth token with `project:releases` scope
#   SENTRY_ORG         — Sentry org slug
# Optional env:
#   SENTRY_PROJECT     — defaults to tezketkaz-flutter
#   RELEASE            — defaults to the current git HEAD SHA
set -euo pipefail

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN required}"
: "${SENTRY_ORG:?SENTRY_ORG required}"
: "${SENTRY_PROJECT:=tezketkaz-flutter}"
: "${RELEASE:=$(git rev-parse HEAD)}"

export SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT

npx @sentry/cli releases new "$RELEASE"
npx @sentry/cli releases files "$RELEASE" upload-sourcemaps build/web --url-prefix '~/'
npx @sentry/cli releases finalize "$RELEASE"
echo "Sentry release $RELEASE finalized."
