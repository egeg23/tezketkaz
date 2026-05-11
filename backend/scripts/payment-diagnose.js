#!/usr/bin/env node
//
// Phase 13.1.7 — payment provider production-readiness diagnostic.
//
// Usage:
//   node backend/scripts/payment-diagnose.js [click|payme|uzum|kaspi|click_kg|all]
//
// For each requested provider, runs four checks:
//   1. Env vars are set (CLICK_MERCHANT_ID, etc.).
//   2. Env values pass a format sanity check (length, charset).
//   3. Reachability — HTTPS GET to the provider's API endpoint with a 5s
//      timeout. We only care that DNS + TCP + TLS succeed; the body / status
//      code is irrelevant (providers commonly return 404 / 405 to a bare GET).
//   4. Signature generation — synthesize a fake payload + signature with the
//      configured secret and print both. You then paste the payload into the
//      provider's test tool to verify the signature matches.
//
// Exit codes:
//   0 — all configured providers passed every check.
//   1 — at least one provider failed at least one check.
//
// Safety: this script NEVER posts data to a real provider. It performs only
// outbound HTTPS GET requests (no payload, no auth headers) plus local
// crypto math. Run it freely against production env files.

'use strict';

const crypto = require('crypto');
const https = require('https');
const path = require('path');

// Load .env from backend/.env so the script can be run from the repo root.
try {
  require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });
} catch (_) {
  // dotenv is a backend dep so it always resolves, but be defensive.
}

// ─── Tiny ANSI color helpers (no chalk dep) ──────────────────────────────────
const COLORS = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  gray: '\x1b[90m',
};

const useColor = process.stdout.isTTY && !process.env.NO_COLOR;
function color(c, s) {
  if (!useColor) return s;
  return `${COLORS[c] || ''}${s}${COLORS.reset}`;
}
const ok = (s) => color('green', `  OK  ${s}`);
const fail = (s) => color('red', `  FAIL ${s}`);
const warn = (s) => color('yellow', `  WARN ${s}`);
const info = (s) => color('cyan', `  --  ${s}`);

// ─── Provider definitions ────────────────────────────────────────────────────
//
// Each entry declares:
//   • requiredVars  — env vars that must be set & non-empty for production.
//   • optionalVars  — env vars that are nice-to-have but not blocking.
//   • formatChecks  — map of envVar → predicate(value) → null|string.
//                     null means OK; string is the failure reason.
//   • pingUrl       — HTTPS URL we hit to verify network reachability.
//   • sign          — function(envSnapshot) → { name, value, payload, scheme }
//                     producing a sample signature the user can verify.
const PROVIDERS = {
  click: {
    label: 'Click.uz (Uzbekistan)',
    requiredVars: ['CLICK_MERCHANT_ID', 'CLICK_SERVICE_ID', 'CLICK_SECRET_KEY'],
    optionalVars: [],
    formatChecks: {
      CLICK_MERCHANT_ID: (v) => (/^\d{3,10}$/.test(v) ? null : 'should be a 3-10 digit numeric merchant id'),
      CLICK_SERVICE_ID: (v) => (/^\d{3,10}$/.test(v) ? null : 'should be a 3-10 digit numeric service id'),
      CLICK_SECRET_KEY: (v) => (v.length >= 8 ? null : 'looks too short (<8 chars) — verify with Click'),
    },
    pingUrl: 'https://my.click.uz/services/pay',
    sign(envSnap) {
      const click_trans_id = '999999';
      const service_id = envSnap.CLICK_SERVICE_ID || 'SERVICE';
      const merchant_trans_id = 'diag-order-1';
      const amount = '120000.00';
      const action = '1';
      const sign_time = '2026-01-01 12:00:00';
      const secret = envSnap.CLICK_SECRET_KEY || 'SECRET';
      const payloadStr = `${click_trans_id}|${service_id}|<SECRET>|${merchant_trans_id}|${amount}|${action}|${sign_time}`;
      const value = crypto
        .createHash('md5')
        .update(`${click_trans_id}${service_id}${secret}${merchant_trans_id}${amount}${action}${sign_time}`)
        .digest('hex');
      return { name: 'sign_string', value, payload: payloadStr, scheme: 'md5' };
    },
  },
  payme: {
    label: 'Payme (Uzbekistan)',
    requiredVars: ['PAYME_MERCHANT_ID', 'PAYME_KEY'],
    optionalVars: [],
    formatChecks: {
      PAYME_MERCHANT_ID: (v) => (/^[0-9a-f]{24}$/i.test(v) ? null : 'expected 24-char hex string (Payme merchant id format)'),
      PAYME_KEY: (v) => (v.length >= 16 ? null : 'looks too short — Payme keys are typically 32+ chars'),
    },
    pingUrl: 'https://checkout.paycom.uz/',
    sign(envSnap) {
      // Payme doesn't sign request bodies; auth is HTTP Basic. We synthesize
      // the exact header the merchant endpoint should expect so the user
      // can confirm their env matches Payme's "Test endpoint" tool.
      const key = envSnap.PAYME_KEY || 'KEY';
      const value = Buffer.from(`Paycom:${key}`).toString('base64');
      return {
        name: 'Authorization',
        value: `Basic ${value}`,
        payload: 'Paycom:<PAYME_KEY>',
        scheme: 'http-basic',
      };
    },
  },
  uzum: {
    label: 'Uzum Pay (Uzbekistan)',
    requiredVars: ['UZUM_MERCHANT_ID', 'UZUM_SECRET_KEY'],
    optionalVars: [],
    formatChecks: {
      UZUM_MERCHANT_ID: (v) => (v.length >= 4 ? null : 'looks too short'),
      UZUM_SECRET_KEY: (v) => (v.length >= 16 ? null : 'looks too short — HMAC secrets are typically 32+ chars'),
    },
    pingUrl: 'https://api.business.uzum.uz/',
    sign(envSnap) {
      const body = JSON.stringify({
        orderId: 'diag-order-1',
        amount: 100000,
        status: 'paid',
        transactionId: 'diag-tx-1',
      });
      const secret = envSnap.UZUM_SECRET_KEY || 'SECRET';
      const value = crypto.createHmac('sha256', secret).update(body).digest('hex');
      return { name: 'X-Uzum-Signature', value, payload: body, scheme: 'hmac-sha256' };
    },
  },
  kaspi: {
    label: 'Kaspi (Kazakhstan)',
    requiredVars: ['KASPI_MERCHANT_ID', 'KASPI_SECRET'],
    optionalVars: [],
    formatChecks: {
      KASPI_MERCHANT_ID: (v) => (v.length >= 4 ? null : 'looks too short'),
      KASPI_SECRET: (v) => (v.length >= 16 ? null : 'looks too short — HMAC secrets are typically 32+ chars'),
    },
    pingUrl: 'https://kaspi.kz/',
    sign(envSnap) {
      const body = JSON.stringify({
        orderId: 'diag-order-1',
        amount: 5000,
        status: 'paid',
        transactionId: 'diag-tx-1',
      });
      const secret = envSnap.KASPI_SECRET || 'SECRET';
      const value = crypto.createHmac('sha256', secret).update(body).digest('hex');
      return { name: 'X-Kaspi-Signature', value, payload: body, scheme: 'hmac-sha256' };
    },
  },
  click_kg: {
    label: 'Click KG (Kyrgyzstan)',
    requiredVars: ['CLICK_KG_MERCHANT_ID', 'CLICK_KG_SERVICE_ID', 'CLICK_KG_SECRET_KEY'],
    optionalVars: [],
    formatChecks: {
      CLICK_KG_MERCHANT_ID: (v) => (/^\d{3,10}$/.test(v) ? null : 'should be a 3-10 digit numeric merchant id'),
      CLICK_KG_SERVICE_ID: (v) => (/^\d{3,10}$/.test(v) ? null : 'should be a 3-10 digit numeric service id'),
      CLICK_KG_SECRET_KEY: (v) => (v.length >= 8 ? null : 'looks too short'),
    },
    pingUrl: 'https://my.click.kg/services/pay',
    sign(envSnap) {
      const click_trans_id = '999999';
      const service_id = envSnap.CLICK_KG_SERVICE_ID || 'SERVICE';
      const merchant_trans_id = 'diag-order-1';
      const amount = '5000.00';
      const action = '1';
      const sign_time = '2026-01-01 12:00:00';
      const secret = envSnap.CLICK_KG_SECRET_KEY || 'SECRET';
      const payloadStr = `${click_trans_id}|${service_id}|<SECRET>|${merchant_trans_id}|${amount}|${action}|${sign_time}`;
      const value = crypto
        .createHash('md5')
        .update(`${click_trans_id}${service_id}${secret}${merchant_trans_id}${amount}${action}${sign_time}`)
        .digest('hex');
      return { name: 'sign_string', value, payload: payloadStr, scheme: 'md5' };
    },
  },
};

// ─── Check primitives ────────────────────────────────────────────────────────

function checkEnvVars(spec) {
  const results = [];
  for (const v of spec.requiredVars) {
    const val = process.env[v];
    if (!val || !String(val).trim()) {
      results.push({ ok: false, message: `${v} is not set` });
    } else {
      results.push({ ok: true, message: `${v} is set (${val.length} chars)` });
    }
  }
  return results;
}

function checkFormats(spec) {
  const results = [];
  for (const [name, predicate] of Object.entries(spec.formatChecks || {})) {
    const val = process.env[name];
    if (!val) continue; // Already caught by checkEnvVars.
    const trimmed = String(val);
    if (trimmed !== val) {
      results.push({ ok: false, message: `${name} has surrounding whitespace — strip it` });
    }
    const reason = predicate(trimmed);
    if (reason) {
      results.push({ ok: false, message: `${name}: ${reason}` });
    } else {
      results.push({ ok: true, message: `${name} format OK` });
    }
  }
  return results;
}

/**
 * Ping a URL with a 5 s timeout. We treat any HTTP response (including 4xx/5xx)
 * as success — the only failure modes that matter are DNS, TCP-refused, and
 * TLS errors. Returns Promise<{ok, message}>.
 */
function pingUrl(url) {
  return new Promise((resolve) => {
    const TIMEOUT_MS = 5000;
    let settled = false;
    const settle = (r) => {
      if (!settled) {
        settled = true;
        resolve(r);
      }
    };
    let req;
    try {
      req = https.request(
        url,
        { method: 'GET', timeout: TIMEOUT_MS, headers: { 'User-Agent': 'tezketkaz-diagnose/1.0' } },
        (res) => {
          // Drain the socket so the connection can close cleanly.
          res.resume();
          settle({ ok: true, message: `${url} → HTTP ${res.statusCode}` });
        },
      );
    } catch (err) {
      settle({ ok: false, message: `${url} → ${err.message}` });
      return;
    }
    req.on('timeout', () => {
      req.destroy(new Error('timeout'));
    });
    req.on('error', (err) => {
      settle({ ok: false, message: `${url} → ${err.code || err.message}` });
    });
    req.end();
  });
}

function describeSignature(sig) {
  return [
    info(`scheme: ${sig.scheme}`),
    info(`payload: ${sig.payload}`),
    info(`${sig.name}: ${sig.value}`),
  ].join('\n');
}

// ─── Main per-provider runner ────────────────────────────────────────────────

async function diagnoseProvider(name) {
  const spec = PROVIDERS[name];
  if (!spec) {
    console.log(color('red', `Unknown provider: ${name}`));
    return false;
  }

  console.log(color('bold', `\n[${name}] ${spec.label}`));
  console.log(color('gray', '────────────────────────────────────────'));

  let allOk = true;

  // 1. Env vars set
  const envResults = checkEnvVars(spec);
  for (const r of envResults) {
    console.log(r.ok ? ok(r.message) : fail(r.message));
    if (!r.ok) allOk = false;
  }

  // If no envs at all are set, skip the rest — provider obviously not configured.
  const anyVarSet = spec.requiredVars.some((v) => process.env[v] && String(process.env[v]).trim());
  if (!anyVarSet) {
    console.log(warn('skipping format / reachability / signature — no env vars configured'));
    return allOk;
  }

  // 2. Format sanity
  const fmtResults = checkFormats(spec);
  for (const r of fmtResults) {
    console.log(r.ok ? ok(r.message) : fail(r.message));
    if (!r.ok) allOk = false;
  }

  // 3. Reachability
  const ping = await pingUrl(spec.pingUrl);
  console.log(ping.ok ? ok(`reachability: ${ping.message}`) : fail(`reachability: ${ping.message}`));
  if (!ping.ok) allOk = false;

  // 4. Sample signature
  try {
    const sig = spec.sign(process.env);
    console.log(info('sample signature (paste into provider test tool):'));
    console.log(describeSignature(sig));
  } catch (err) {
    console.log(fail(`signature generation failed: ${err.message}`));
    allOk = false;
  }

  return allOk;
}

async function main() {
  const target = (process.argv[2] || 'all').toLowerCase();
  const providers = target === 'all' ? Object.keys(PROVIDERS) : [target];

  console.log(color('bold', 'TezKetKaz — payment provider diagnostic'));
  console.log(color('gray', `target: ${providers.join(', ')}`));
  console.log(color('gray', `USE_MOCK_PAYMENTS=${process.env.USE_MOCK_PAYMENTS || '(unset, defaults to true)'}`));
  if (process.env.USE_MOCK_PAYMENTS === 'true') {
    console.log(warn('USE_MOCK_PAYMENTS=true — production env vars optional. Set to false for full check.'));
  }

  let allOk = true;
  for (const p of providers) {
    const ok2 = await diagnoseProvider(p);
    if (!ok2) allOk = false;
  }

  console.log('');
  if (allOk) {
    console.log(color('green', color('bold', 'All configured providers passed.')));
    process.exit(0);
  } else {
    console.log(color('red', color('bold', 'One or more providers failed — fix and re-run.')));
    process.exit(1);
  }
}

// Allow `require()` from tests without auto-running main.
if (require.main === module) {
  main().catch((err) => {
    console.error(color('red', `fatal: ${err.stack || err.message}`));
    process.exit(2);
  });
}

module.exports = { PROVIDERS, diagnoseProvider, pingUrl };
