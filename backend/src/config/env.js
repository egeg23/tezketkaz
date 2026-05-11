// Centralized env validation. Fails fast on startup if required vars are missing.
require('dotenv').config();
const { z } = require('zod');

const isProd = process.env.NODE_ENV === 'production';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().min(1, 'DATABASE_URL is required'),

  FRONTEND_URL: z.string().optional(),

  JWT_SECRET: z.string().min(isProd ? 32 : 8, 'JWT_SECRET too short'),
  JWT_ACCESS_TTL: z.string().default('1h'),
  JWT_REFRESH_TTL: z.string().default('30d'),

  REDIS_URL: z.string().optional(),
  REDIS_ENABLED: z.enum(['true', 'false']).default('false'),

  USE_MOCK_SMS: z.enum(['true', 'false']).default('true'),
  ESKIZ_EMAIL: z.string().optional(),
  ESKIZ_PASSWORD: z.string().optional(),
  ESKIZ_FROM: z.string().default('4546'),

  USE_MOCK_PAYMENTS: z.enum(['true', 'false']).default('true'),
  // Phase 13.1.7 — per-provider mock override. When `USE_MOCK_PAYMENTS=false`
  // (production mode) you can still force-mock a single provider that
  // misbehaves at runtime, without flipping everything back to mock. Used for
  // surgical rollback per the payments-go-live runbook. Empty / 'false' ⇒
  // honour the global flag.
  USE_MOCK_CLICK: z.enum(['true', 'false']).optional(),
  USE_MOCK_PAYME: z.enum(['true', 'false']).optional(),
  USE_MOCK_UZUM: z.enum(['true', 'false']).optional(),
  USE_MOCK_KASPI: z.enum(['true', 'false']).optional(),
  USE_MOCK_CLICK_KG: z.enum(['true', 'false']).optional(),
  CLICK_MERCHANT_ID: z.string().optional(),
  CLICK_SERVICE_ID: z.string().optional(),
  CLICK_SECRET_KEY: z.string().optional(),
  PAYME_MERCHANT_ID: z.string().optional(),
  PAYME_KEY: z.string().optional(),
  UZUM_MERCHANT_ID: z.string().optional(),
  UZUM_SECRET_KEY: z.string().optional(),

  // Phase 7 — Kazakhstan (Kaspi) and Kyrgyzstan (Click KG) launch.
  KASPI_MERCHANT_ID: z.string().optional(),
  KASPI_SECRET: z.string().optional(),
  CLICK_KG_MERCHANT_ID: z.string().optional(),
  CLICK_KG_SERVICE_ID: z.string().optional(),
  CLICK_KG_SECRET_KEY: z.string().optional(),

  // Phase 7 — transactional email (Resend). Optional in dev/test; absent ⇒ noop.
  RESEND_API_KEY: z.string().optional(),

  // ─── Phase 13.1.6 — Firebase Admin (push notifications) ─────────────────
  // FCM_ENABLED is the master switch. When 'true', services/push.js will
  // initialise firebase-admin using one of:
  //   • FIREBASE_SERVICE_ACCOUNT_JSON — full service-account JSON inline.
  //     Recommended for managed platforms (Render / Railway / Fly) that
  //     can't host secret files. Single-line, escaped quotes.
  //   • FIREBASE_SERVICE_ACCOUNT_PATH — absolute or repo-relative path to a
  //     service-account JSON file. Used in self-hosted deploys.
  // Falling back to the legacy `backend/firebase-admin.json` lookup remains
  // supported for backward compat with pre-13.1.6 setups.
  FCM_ENABLED: z.enum(['true', 'false']).default('false'),
  FIREBASE_SERVICE_ACCOUNT_JSON: z.string().optional(),
  FIREBASE_SERVICE_ACCOUNT_PATH: z.string().optional(),

  USE_MOCK_TAX: z.enum(['true', 'false']).default('true'),
  ADMIN_PHONES: z.string().optional(),

  COURIER_RADIUS_KM: z.coerce.number().positive().default(5),

  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  SENTRY_DSN: z.string().optional(),

  // ─── Storage (Phase 9 + Phase 13.1.2) ─────────────────────────────────────
  // Where uploaded files live. Defaults to local /uploads/* serving.
  STORAGE_PROVIDER: z.enum(['local', 'r2', 's3']).default('local'),
  // Used to build absolute URLs for files served by /uploads/* (local).
  PUBLIC_URL: z.string().optional(),
  // Required when STORAGE_PROVIDER=r2 or s3 (Phase 9 names).
  S3_BUCKET: z.string().optional(),
  S3_ENDPOINT: z.string().optional(),
  S3_REGION: z.string().default('auto'),
  S3_ACCESS_KEY: z.string().optional(),
  S3_SECRET_KEY: z.string().optional(),
  S3_PUBLIC_BASE: z.string().optional(),

  // Phase 12 — Yandex Routing API for road-aware ETAs. Optional; when absent
  // services/routing.js falls back to haversine + 25 km/h heuristic.
  YANDEX_ROUTING_KEY: z.string().optional(),

  // ─── Phase 13.3.9 — Soliq.uz fiscal API ─────────────────────────────────
  // Uzbek State Tax Committee fiscalisation. Cashless transactions over
  // 100,000 UZS legally require an issued fiscal receipt. When mocked
  // (default in dev/test) the backend logs and returns synthetic receipts;
  // production deploys must set USE_MOCK_SOLIQ=false and provide SOLIQ_API_KEY
  // (or per-shop Shop.soliqApiKey).
  USE_MOCK_SOLIQ: z.enum(['true', 'false']).default('true'),
  SOLIQ_API_BASE: z.string().default('https://api.soliq.uz/v1'),
  SOLIQ_API_KEY: z.string().optional(),
});

let parsed;
try {
  parsed = schema.parse(process.env);
} catch (err) {
  // eslint-disable-next-line no-console
  console.error('❌ Invalid environment configuration:');
  if (err.issues) {
    for (const issue of err.issues) {
      // eslint-disable-next-line no-console
      console.error(`   • ${issue.path.join('.')}: ${issue.message}`);
    }
  } else {
    // eslint-disable-next-line no-console
    console.error(err);
  }
  process.exit(1);
}

// Production hard requirements
if (parsed.NODE_ENV === 'production') {
  const missing = [];
  if (parsed.USE_MOCK_PAYMENTS === 'false') {
    if (!parsed.CLICK_SECRET_KEY) missing.push('CLICK_SECRET_KEY');
    if (!parsed.PAYME_KEY) missing.push('PAYME_KEY');
    if (!parsed.UZUM_SECRET_KEY) missing.push('UZUM_SECRET_KEY');
  }
  if (parsed.USE_MOCK_SMS === 'false') {
    if (!parsed.ESKIZ_EMAIL || !parsed.ESKIZ_PASSWORD) {
      missing.push('ESKIZ_EMAIL / ESKIZ_PASSWORD');
    }
  }
  if (parsed.USE_MOCK_SOLIQ === 'false') {
    // Per-shop key (Shop.soliqApiKey) can still cover individual shops; the
    // global key is a fallback but is strongly recommended in production so
    // the worker never has to skip un-keyed shops.
    if (!parsed.SOLIQ_API_KEY) missing.push('SOLIQ_API_KEY');
  }
  if (parsed.REDIS_ENABLED === 'true' && !parsed.REDIS_URL) {
    missing.push('REDIS_URL');
  }
  if (parsed.STORAGE_PROVIDER === 'r2' || parsed.STORAGE_PROVIDER === 's3') {
    if (!parsed.R2_ACCESS_KEY_ID) missing.push('R2_ACCESS_KEY_ID');
    if (!parsed.R2_SECRET_ACCESS_KEY) missing.push('R2_SECRET_ACCESS_KEY');
    if (!parsed.R2_BUCKET) missing.push('R2_BUCKET');
    if (!parsed.R2_ENDPOINT && parsed.STORAGE_PROVIDER === 'r2') missing.push('R2_ENDPOINT');
    if (!parsed.R2_PUBLIC_URL) missing.push('R2_PUBLIC_URL');
  }
  if (missing.length) {
    // eslint-disable-next-line no-console
    console.error('❌ Production env missing:', missing.join(', '));
    process.exit(1);
  }
}

const env = {
  ...parsed,
  isProd: parsed.NODE_ENV === 'production',
  isDev: parsed.NODE_ENV === 'development',
  isTest: parsed.NODE_ENV === 'test',
  useMockSms: parsed.USE_MOCK_SMS === 'true',
  useMockPayments: parsed.USE_MOCK_PAYMENTS === 'true',
  // Per-provider mock toggles: provider-level flag wins when set, otherwise
  // honour the global USE_MOCK_PAYMENTS. Used by services/click.js et al via
  // env.useMockProvider(name) below.
  useMockClick: parsed.USE_MOCK_CLICK === 'true'
    || (parsed.USE_MOCK_CLICK !== 'false' && parsed.USE_MOCK_PAYMENTS === 'true'),
  useMockPayme: parsed.USE_MOCK_PAYME === 'true'
    || (parsed.USE_MOCK_PAYME !== 'false' && parsed.USE_MOCK_PAYMENTS === 'true'),
  useMockUzum: parsed.USE_MOCK_UZUM === 'true'
    || (parsed.USE_MOCK_UZUM !== 'false' && parsed.USE_MOCK_PAYMENTS === 'true'),
  useMockKaspi: parsed.USE_MOCK_KASPI === 'true'
    || (parsed.USE_MOCK_KASPI !== 'false' && parsed.USE_MOCK_PAYMENTS === 'true'),
  useMockClickKg: parsed.USE_MOCK_CLICK_KG === 'true'
    || (parsed.USE_MOCK_CLICK_KG !== 'false' && parsed.USE_MOCK_PAYMENTS === 'true'),
  useMockTax: parsed.USE_MOCK_TAX === 'true',
  useMockSoliq: parsed.USE_MOCK_SOLIQ === 'true',
  redisEnabled: parsed.REDIS_ENABLED === 'true' && Boolean(parsed.REDIS_URL),
  fcmEnabled: parsed.FCM_ENABLED === 'true',
};

module.exports = env;
