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
  CLICK_MERCHANT_ID: z.string().optional(),
  CLICK_SERVICE_ID: z.string().optional(),
  CLICK_SECRET_KEY: z.string().optional(),
  PAYME_MERCHANT_ID: z.string().optional(),
  PAYME_KEY: z.string().optional(),
  UZUM_MERCHANT_ID: z.string().optional(),
  UZUM_SECRET_KEY: z.string().optional(),

  FCM_ENABLED: z.enum(['true', 'false']).default('false'),

  USE_MOCK_TAX: z.enum(['true', 'false']).default('true'),
  ADMIN_PHONES: z.string().optional(),

  COURIER_RADIUS_KM: z.coerce.number().positive().default(5),

  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  SENTRY_DSN: z.string().optional(),
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
  if (parsed.REDIS_ENABLED === 'true' && !parsed.REDIS_URL) {
    missing.push('REDIS_URL');
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
  useMockTax: parsed.USE_MOCK_TAX === 'true',
  redisEnabled: parsed.REDIS_ENABLED === 'true' && Boolean(parsed.REDIS_URL),
  fcmEnabled: parsed.FCM_ENABLED === 'true',
};

module.exports = env;
