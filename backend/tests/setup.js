// Global Jest setup — runs once before each test file.
// Provides minimal env so that `src/config/env.js` (zod-validated) doesn't
// abort loading. Tests that need real services should override these.
//
// As of Phase 13.1.1 the backend is Postgres-only. Tests require a reachable
// Postgres instance via DATABASE_URL (or TEST_DATABASE_URL). The per-file
// helper in tests/helpers/db.js carves out a unique schema and applies the
// baseline migration, so the only requirement here is that the URL points
// at a server we can reach.

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DATABASE_URL =
  process.env.DATABASE_URL ||
  process.env.TEST_DATABASE_URL ||
  'postgresql://postgres:postgres@localhost:5432/tezketkaz_test';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-min-eight-chars';
process.env.USE_MOCK_PAYMENTS = 'true';
process.env.USE_MOCK_SMS = 'true';
process.env.USE_MOCK_TAX = 'true';
process.env.REDIS_ENABLED = 'false';
process.env.LOG_LEVEL = 'fatal';
