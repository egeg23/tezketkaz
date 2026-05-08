// Global Jest setup — runs once before each test file.
// Provides minimal env so that `src/config/env.js` (zod-validated) doesn't
// abort loading. Tests that need real services should override these.

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DATABASE_URL = process.env.DATABASE_URL || 'file:./test.db';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-min-eight-chars';
process.env.USE_MOCK_PAYMENTS = 'true';
process.env.USE_MOCK_SMS = 'true';
process.env.USE_MOCK_TAX = 'true';
process.env.REDIS_ENABLED = 'false';
process.env.LOG_LEVEL = 'fatal';
