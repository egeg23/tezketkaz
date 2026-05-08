// Phase 9 — storage abstraction.
//
// Routes shouldn't know whether bytes land on the local disk under
// `backend/uploads/` or in a Cloudflare R2 / S3 bucket. They call
// `storage().putFromMulterFile(req.file, key)` and get back a `{ url, key }`
// pair to persist on the model.
//
// Driver selection is implicit:
//   • S3 vars present (S3_BUCKET + S3_ACCESS_KEY) ⇒ s3Driver
//   • otherwise ⇒ localDriver (writes under backend/uploads/<key>)
//
// The S3 driver lazy-requires `@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner`
// so dev environments that don't install them still boot.

const fs = require('fs');
const path = require('path');
const env = require('../config/env');
const logger = require('./logger');

// ─── Local-fs driver ────────────────────────────────────────────────────────
function localDriver() {
  const root = path.resolve(__dirname, '..', '..', 'uploads');
  fs.mkdirSync(root, { recursive: true });

  return {
    name: 'local',
    async put(key, body /* Buffer */, _opts = {}) {
      const fullPath = path.join(root, key);
      fs.mkdirSync(path.dirname(fullPath), { recursive: true });
      fs.writeFileSync(fullPath, body);
      // Public URL the express static handler serves.
      return { url: `/uploads/${key}`, key };
    },
    async get(key) {
      const fullPath = path.join(root, key);
      if (!fs.existsSync(fullPath)) return null;
      return fs.readFileSync(fullPath);
    },
    async del(key) {
      const fullPath = path.join(root, key);
      try { fs.unlinkSync(fullPath); } catch { /* noop */ }
    },
    async list(prefix, { olderThan } = {}) {
      const dir = path.join(root, prefix);
      if (!fs.existsSync(dir)) return [];
      const entries = [];
      function walk(d, rel) {
        for (const name of fs.readdirSync(d)) {
          const full = path.join(d, name);
          const stat = fs.statSync(full);
          if (stat.isDirectory()) {
            walk(full, path.join(rel, name));
          } else {
            if (olderThan && stat.mtime > olderThan) continue;
            entries.push({
              key: path.posix.join(prefix, rel.split(path.sep).join('/'), name),
              size: stat.size,
              modifiedAt: stat.mtime,
            });
          }
        }
      }
      walk(dir, '');
      return entries;
    },
    // Local "signed URLs" are just the public path; expiresIn is ignored.
    signedUrl(key /* , { expiresIn = 7 * 24 * 3600 } = {} */) {
      return `/uploads/${key}`;
    },
  };
}

// ─── S3-compatible driver (Cloudflare R2 / AWS S3) ──────────────────────────
function s3Driver() {
  let _client = null;
  const bucket = env.S3_BUCKET;
  const endpoint = env.S3_ENDPOINT;       // e.g. https://<acct>.r2.cloudflarestorage.com
  const region = env.S3_REGION || 'auto';

  function client() {
    if (_client) return _client;
    // eslint-disable-next-line global-require
    const { S3Client } = require('@aws-sdk/client-s3');
    _client = new S3Client({
      region,
      endpoint,
      forcePathStyle: true,
      credentials: {
        accessKeyId: env.S3_ACCESS_KEY,
        secretAccessKey: env.S3_SECRET_KEY,
      },
    });
    return _client;
  }

  return {
    name: 's3',
    async put(key, body, { contentType } = {}) {
      // eslint-disable-next-line global-require
      const { PutObjectCommand } = require('@aws-sdk/client-s3');
      await client().send(new PutObjectCommand({
        Bucket: bucket, Key: key, Body: body, ContentType: contentType,
      }));
      const url = env.S3_PUBLIC_BASE
        ? `${String(env.S3_PUBLIC_BASE).replace(/\/+$/, '')}/${key}`
        : key;
      return { url, key };
    },
    async get(key) {
      // eslint-disable-next-line global-require
      const { GetObjectCommand } = require('@aws-sdk/client-s3');
      const res = await client().send(new GetObjectCommand({ Bucket: bucket, Key: key }));
      return Buffer.from(await res.Body.transformToByteArray());
    },
    async del(key) {
      // eslint-disable-next-line global-require
      const { DeleteObjectCommand } = require('@aws-sdk/client-s3');
      await client().send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
    },
    async list(prefix, opts = {}) {
      // eslint-disable-next-line global-require
      const { ListObjectsV2Command } = require('@aws-sdk/client-s3');
      const out = [];
      let token;
      do {
        // eslint-disable-next-line no-await-in-loop
        const res = await client().send(new ListObjectsV2Command({
          Bucket: bucket, Prefix: prefix, ContinuationToken: token,
        }));
        for (const obj of res.Contents || []) {
          if (opts.olderThan && obj.LastModified > opts.olderThan) continue;
          out.push({ key: obj.Key, size: obj.Size, modifiedAt: obj.LastModified });
        }
        token = res.NextContinuationToken;
      } while (token);
      return out;
    },
    async signedUrl(key, { expiresIn = 7 * 24 * 3600 } = {}) {
      // eslint-disable-next-line global-require
      const { GetObjectCommand } = require('@aws-sdk/client-s3');
      // eslint-disable-next-line global-require
      const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
      const cmd = new GetObjectCommand({ Bucket: bucket, Key: key });
      return getSignedUrl(client(), cmd, { expiresIn });
    },
  };
}

let _instance = null;

function storage() {
  if (_instance) return _instance;
  if (env.S3_BUCKET && env.S3_ACCESS_KEY) {
    try {
      _instance = s3Driver();
      logger.info({ driver: 's3', bucket: env.S3_BUCKET }, 'storage initialized');
    } catch (err) {
      logger.warn({ err: err.message }, 'S3 driver init failed, falling back to local');
      _instance = localDriver();
    }
  } else {
    _instance = localDriver();
  }
  return _instance;
}

// Helper: route handlers store uploads via multer to disk first; this wraps
// "read from req.file.path → put under <key> → drop the local copy if S3 took
// the bytes". When the local driver is active we leave the file in place — it's
// the source of truth and is served via express.static('/uploads').
async function putFromMulterFile(file, key) {
  const drv = storage();
  const body = fs.readFileSync(file.path);
  const result = await drv.put(key, body, { contentType: file.mimetype });
  if (drv.name === 's3') {
    // Bytes are in S3 — local copy is no longer needed.
    try { fs.unlinkSync(file.path); } catch { /* noop */ }
  }
  return result;
}

// Test-only: clear the cached instance so a new driver picks up changed env.
function _resetForTests() {
  _instance = null;
}

module.exports = {
  storage,
  putFromMulterFile,
  _resetForTests,
};
