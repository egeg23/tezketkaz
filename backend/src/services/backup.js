// Phase 9.4 — daily backup automation.
//
// SQLite path: copy the .sqlite file, gzip it, write through the storage
// abstraction to /backups/<YYYY-MM-DD>.sqlite.gz.
//
// Postgres path (Phase 13.1.1+): shell out to `pg_dump`, gzip the SQL stream,
// store as /backups/<YYYY-MM-DD>.pg.gz. We pick the path based on the
// DATABASE_URL scheme.
//
// 30-day retention: any backup older than 30 days is pruned from storage on
// every run.

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { spawn } = require('child_process');
const { promisify } = require('util');
const { audit } = require('../lib/audit');
const logger = require('../lib/logger');

const gzip = promisify(zlib.gzip);
const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

// Same shape-accommodating loader as services/dataExport.js. Agent B's
// lib/storage.js exposes `{ storage, ... }` with `storage()` as a factory.
function tryLoadStorage() {
  try {
    // eslint-disable-next-line global-require
    const mod = require('../lib/storage');
    if (mod && typeof mod.storage === 'function') {
      return mod.storage();
    }
    if (mod && typeof mod.put === 'function') {
      return mod;
    }
    return null;
  } catch {
    return null;
  }
}

function isoDay(d = new Date()) {
  return d.toISOString().slice(0, 10);
}

// Resolve the SQLite file path from DATABASE_URL. We support `file:./x.db`,
// `file:/abs/x.db`, and bare paths. Returns absolute path or null when the
// URL points to a non-file provider (Postgres).
//
// IMPORTANT: Prisma resolves relative URLs *from the schema file's directory*
// (backend/prisma/), not from the project root. We mirror that behavior so
// the snapshot path matches what the running PrismaClient is reading from.
function resolveSqliteFile() {
  const url = process.env.DATABASE_URL || '';
  if (!url.startsWith('file:')) return null;
  const raw = url.slice('file:'.length);
  if (path.isAbsolute(raw)) return raw;
  return path.resolve(__dirname, '..', '..', 'prisma', raw);
}

// Snapshot a Postgres database via `pg_dump` and gzip the SQL stream in-memory.
// Resolves to a Buffer of the gzipped dump, or rejects on non-zero exit.
//
// We strip the Prisma-specific `schema=` query parameter (pg_dump rejects it)
// and forward it via `-n <schema>` so per-schema test DBs still dump cleanly.
function dumpPostgres(databaseUrl) {
  let cleanUrl = databaseUrl;
  let schemaName = null;
  try {
    const u = new URL(databaseUrl);
    if (u.searchParams.has('schema')) {
      schemaName = u.searchParams.get('schema');
      u.searchParams.delete('schema');
      cleanUrl = u.toString();
    }
  } catch {
    // Non-URL inputs fall through to raw use.
  }

  return new Promise((resolve, reject) => {
    const args = ['--no-owner', '--no-privileges', '--format=plain'];
    if (schemaName) args.push('-n', schemaName);
    args.push(cleanUrl);
    const proc = spawn('pg_dump', args, { stdio: ['ignore', 'pipe', 'pipe'] });
    const chunks = [];
    const errChunks = [];
    proc.stdout.on('data', (d) => chunks.push(d));
    proc.stderr.on('data', (d) => errChunks.push(d));
    proc.on('error', reject);
    proc.on('close', async (code) => {
      if (code !== 0) {
        const stderr = Buffer.concat(errChunks).toString('utf8').trim();
        return reject(new Error(`pg_dump exited ${code}: ${stderr || 'unknown error'}`));
      }
      try {
        const raw = Buffer.concat(chunks);
        const gz = await gzip(raw);
        resolve(gz);
      } catch (err) {
        reject(err);
      }
    });
  });
}

async function writeLocalBackup(key, bytes) {
  const dir = path.resolve(__dirname, '..', '..', 'uploads', 'backups');
  await fs.promises.mkdir(dir, { recursive: true });
  const file = path.join(dir, path.basename(key));
  await fs.promises.writeFile(file, bytes);
  return `/uploads/backups/${path.basename(file)}`;
}

async function listLocalBackups() {
  const dir = path.resolve(__dirname, '..', '..', 'uploads', 'backups');
  try {
    const files = await fs.promises.readdir(dir);
    const out = [];
    for (const f of files) {
      try {
        const stat = await fs.promises.stat(path.join(dir, f));
        out.push({ key: `/backups/${f}`, modifiedAt: stat.mtime, _localPath: path.join(dir, f) });
      } catch { /* race */ }
    }
    return out;
  } catch {
    return [];
  }
}

async function pruneLocalBackups(now = new Date()) {
  const cutoff = now.getTime() - RETENTION_MS;
  const files = await listLocalBackups();
  let deleted = 0;
  for (const f of files) {
    if (f.modifiedAt && f.modifiedAt.getTime() < cutoff) {
      try {
        await fs.promises.unlink(f._localPath);
        deleted += 1;
      } catch { /* ignore */ }
    }
  }
  return deleted;
}

/**
 * Run the daily backup. Returns { ok, key, sizeBytes, prunedCount } on
 * success, or { ok: false, error } when the snapshot itself failed (we
 * audit the failure but never throw — the caller is a cron job).
 */
async function runDailyBackup({ now = new Date() } = {}) {
  const storage = tryLoadStorage();
  const url = process.env.DATABASE_URL || '';
  const dbFile = resolveSqliteFile();
  const isPostgres = /^postgres(ql)?:\/\//.test(url);

  let bytes;
  let ext;
  if (dbFile) {
    try {
      const raw = await fs.promises.readFile(dbFile);
      bytes = await gzip(raw);
      ext = 'sqlite.gz';
    } catch (err) {
      logger.error({ err: err.message, dbFile }, 'backup snapshot failed');
      await audit({
        action: 'system.backup',
        metadata: { ok: false, error: err.message },
      });
      return { ok: false, error: err.message };
    }
  } else if (isPostgres) {
    try {
      bytes = await dumpPostgres(url);
      ext = 'pg.gz';
    } catch (err) {
      logger.error({ err: err.message }, 'pg_dump backup snapshot failed');
      await audit({
        action: 'system.backup',
        metadata: { ok: false, error: err.message },
      });
      return { ok: false, error: err.message };
    }
  } else {
    logger.warn('runDailyBackup: unsupported DATABASE_URL scheme');
    return { ok: false, error: 'unsupported_provider' };
  }

  const key = `backups/${isoDay(now)}.${ext}`;
  let backupUrl;
  try {
    if (storage && typeof storage.put === 'function') {
      const result = await storage.put(key, bytes, { contentType: 'application/gzip' });
      backupUrl = result?.url || result?.location || key;
    } else {
      backupUrl = await writeLocalBackup(key, bytes);
    }
  } catch (err) {
    logger.error({ err: err.message, key }, 'backup upload failed');
    await audit({
      action: 'system.backup',
      metadata: { ok: false, error: err.message },
    });
    return { ok: false, error: err.message };
  }

  // Prune old backups. Storage drivers expose either `del` (current) or
  // `delete` (in case of future API change); accept both.
  let prunedCount = 0;
  try {
    const deleteFn = storage?.del || storage?.delete;
    if (storage && typeof storage.list === 'function' && typeof deleteFn === 'function') {
      const cutoff = now.getTime() - RETENTION_MS;
      const items = await storage.list('backups/');
      for (const it of items || []) {
        const t = it?.modifiedAt instanceof Date ? it.modifiedAt.getTime() : Date.parse(it?.modifiedAt || '');
        if (Number.isFinite(t) && t < cutoff) {
          try { await deleteFn.call(storage, it.key); prunedCount += 1; } catch { /* skip */ }
        }
      }
    } else {
      prunedCount = await pruneLocalBackups(now);
    }
  } catch (err) {
    logger.warn({ err: err.message }, 'backup prune failed');
  }

  await audit({
    action: 'system.backup',
    metadata: { ok: true, key, url: backupUrl, sizeBytes: bytes.length, prunedCount },
  });

  return { ok: true, key, url: backupUrl, sizeBytes: bytes.length, prunedCount };
}

module.exports = {
  runDailyBackup,
  pruneLocalBackups,
  RETENTION_MS,
  // Internal helpers (exported for tests).
  _resolveSqliteFile: resolveSqliteFile,
  _isoDay: isoDay,
};
