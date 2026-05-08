// Phase 9.4 — daily backup automation tests.

const fs = require('fs');
const path = require('path');
const { setupTestDb, teardownTestDb } = require('./helpers/db');
const backup = require('../src/services/backup');

let ctx;

beforeAll(async () => {
  ctx = await setupTestDb('backup');
}, 30000);

afterAll(async () => { await teardownTestDb(ctx); });

describe('backup.runDailyBackup', () => {
  test('writes a gzipped sqlite snapshot under /uploads/backups/', async () => {
    const result = await backup.runDailyBackup();
    expect(result.ok).toBe(true);
    expect(result.key).toMatch(/backups\/\d{4}-\d{2}-\d{2}\.sqlite\.gz/);
    expect(result.sizeBytes).toBeGreaterThan(0);

    // The local-fallback URL is /uploads/backups/<date>.sqlite.gz.
    if (result.url && result.url.startsWith('/uploads/')) {
      const localPath = path.resolve(__dirname, '..', result.url.replace(/^\//, ''));
      expect(fs.existsSync(localPath)).toBe(true);
    }
  });

  test('prune logic removes files older than 30 days', async () => {
    const dir = path.resolve(__dirname, '..', 'uploads', 'backups');
    await fs.promises.mkdir(dir, { recursive: true });
    const stale = path.join(dir, '2020-01-01.sqlite.gz');
    await fs.promises.writeFile(stale, 'stale');
    // Backdate the stale file.
    const old = new Date(Date.now() - 60 * 24 * 60 * 60 * 1000);
    await fs.promises.utimes(stale, old, old);
    expect(fs.existsSync(stale)).toBe(true);

    const deleted = await backup.pruneLocalBackups();
    expect(deleted).toBeGreaterThanOrEqual(1);
    expect(fs.existsSync(stale)).toBe(false);
  });

  test('failure path returns ok=false but does not crash', async () => {
    // Point DATABASE_URL at a non-existent file so readFile fails.
    const prev = process.env.DATABASE_URL;
    process.env.DATABASE_URL = 'file:./prisma/does-not-exist-' + Date.now() + '.db';
    try {
      const result = await backup.runDailyBackup();
      expect(result.ok).toBe(false);
      expect(result.error).toBeTruthy();
    } finally {
      process.env.DATABASE_URL = prev;
    }
  });
});
