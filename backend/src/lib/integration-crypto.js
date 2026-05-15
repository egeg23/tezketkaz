// AES-256-GCM helper for storing partner credentials (iiko/Poster/REST keys).
//
// Key is read from INTEGRATION_ENC_KEY (32 random bytes, base64). For dev we
// fall back to a deterministic hash of JWT_SECRET so a `git clone && npm
// start` works without operator setup. For prod, generate with:
//
//   node -e 'console.log(require("crypto").randomBytes(32).toString("base64"))'
//
// Cipher format: `<ivB64>:<tagB64>:<dataB64>`. IV is 12 bytes per spec.
// We never log raw plaintext or ciphertext — the only thing that ever leaves
// this module is the opaque envelope.

const crypto = require('crypto');

const ALG = 'aes-256-gcm';
const IV_LEN = 12;

function key() {
  const envKey = process.env.INTEGRATION_ENC_KEY;
  if (envKey) {
    const buf = Buffer.from(envKey, 'base64');
    if (buf.length === 32) return buf;
    // Fall through to derived key on bad envKey, with a warning.
    // eslint-disable-next-line no-console
    console.warn('[integration-crypto] INTEGRATION_ENC_KEY is not 32 bytes; falling back to derived key');
  }
  // Dev fallback: derive from JWT_SECRET. NOT for production.
  const secret = process.env.JWT_SECRET || 'tezketkaz-dev-secret';
  return crypto.createHash('sha256').update(`integration:${secret}`).digest();
}

function encrypt(plain) {
  const json = JSON.stringify(plain ?? {});
  const iv = crypto.randomBytes(IV_LEN);
  const c = crypto.createCipheriv(ALG, key(), iv);
  const enc = Buffer.concat([c.update(json, 'utf8'), c.final()]);
  const tag = c.getAuthTag();
  return `${iv.toString('base64')}:${tag.toString('base64')}:${enc.toString('base64')}`;
}

function decrypt(envelope) {
  if (!envelope || typeof envelope !== 'string') {
    throw new Error('integration-crypto: empty envelope');
  }
  const [ivB64, tagB64, dataB64] = envelope.split(':');
  if (!ivB64 || !tagB64 || !dataB64) {
    throw new Error('integration-crypto: malformed envelope');
  }
  const iv = Buffer.from(ivB64, 'base64');
  const tag = Buffer.from(tagB64, 'base64');
  const data = Buffer.from(dataB64, 'base64');
  const d = crypto.createDecipheriv(ALG, key(), iv);
  d.setAuthTag(tag);
  const dec = Buffer.concat([d.update(data), d.final()]).toString('utf8');
  return JSON.parse(dec);
}

module.exports = { encrypt, decrypt };
