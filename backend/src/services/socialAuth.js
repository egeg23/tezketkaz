// Phase 9.3 — Apple + Google id_token verification.
//
// In production we verify the JWT signature against the provider's published
// JWKS using `jose`. `jose` is lazily required so dev/test environments that
// don't install it (and CI without internet) still work. When jose is missing
// or the configured client id is absent, we accept tokens of shape
// `mock_<provider>_<sub>_<email>` — the same pattern click.js uses for mock
// payments. Tests rely exclusively on the mock path.
//
// Public API:
//   verifyAppleIdToken(idToken)  → { sub, email, emailVerified }
//   verifyGoogleIdToken(idToken) → { sub, email, emailVerified }

const env = require('../config/env');
const logger = require('../lib/logger');

const APPLE_ISS = 'https://appleid.apple.com';
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
const GOOGLE_ISS = ['https://accounts.google.com', 'accounts.google.com'];
const GOOGLE_JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';

function tryLoadJose() {
  try {
    // eslint-disable-next-line global-require
    return require('jose');
  } catch {
    return null;
  }
}

// `mock_<provider>_<sub>_<email>` → { sub, email, emailVerified: true }.
// Anything that doesn't match this pattern returns null so callers can
// fall through to a 400.
function parseMockToken(idToken, provider) {
  if (typeof idToken !== 'string') return null;
  const prefix = `mock_${provider}_`;
  if (!idToken.startsWith(prefix)) return null;
  const rest = idToken.slice(prefix.length);
  // Allow either `mock_apple_<sub>` (no email) or `mock_apple_<sub>_<email>`.
  // Email may itself contain underscores after the @, so we split only on
  // the FIRST underscore.
  const idx = rest.indexOf('_');
  if (idx < 0) {
    return { sub: rest, email: null, emailVerified: false };
  }
  const sub = rest.slice(0, idx);
  const email = rest.slice(idx + 1) || null;
  return { sub, email, emailVerified: true };
}

async function verifyWithJose(jose, idToken, { jwksUrl, issuer, audience }) {
  const JWKS = jose.createRemoteJWKSet(new URL(jwksUrl));
  const { payload } = await jose.jwtVerify(idToken, JWKS, {
    issuer,
    audience,
  });
  return {
    sub: payload.sub,
    email: payload.email || null,
    emailVerified: payload.email_verified === true,
  };
}

async function verifyAppleIdToken(idToken) {
  if (!idToken || typeof idToken !== 'string') {
    throw Object.assign(new Error('idToken required'), { status: 400 });
  }

  const audience = process.env.APPLE_BUNDLE_ID;
  const jose = tryLoadJose();

  // Mock-mode triggers when:
  //   • we're in test/dev OR APPLE_BUNDLE_ID is unset, OR
  //   • jose isn't installed.
  if (!audience || !jose) {
    const parsed = parseMockToken(idToken, 'apple');
    if (!parsed) {
      throw Object.assign(new Error('Invalid Apple id_token'), { status: 400 });
    }
    return parsed;
  }

  try {
    return await verifyWithJose(jose, idToken, {
      jwksUrl: APPLE_JWKS_URL,
      issuer: APPLE_ISS,
      audience,
    });
  } catch (err) {
    logger.warn({ err: err.message }, 'apple id_token verification failed');
    throw Object.assign(new Error('Invalid Apple id_token'), { status: 401 });
  }
}

async function verifyGoogleIdToken(idToken) {
  if (!idToken || typeof idToken !== 'string') {
    throw Object.assign(new Error('idToken required'), { status: 400 });
  }

  const audience = process.env.GOOGLE_OAUTH_CLIENT_ID;
  const jose = tryLoadJose();

  if (!audience || !jose) {
    const parsed = parseMockToken(idToken, 'google');
    if (!parsed) {
      throw Object.assign(new Error('Invalid Google id_token'), { status: 400 });
    }
    return parsed;
  }

  try {
    return await verifyWithJose(jose, idToken, {
      jwksUrl: GOOGLE_JWKS_URL,
      issuer: GOOGLE_ISS,
      audience,
    });
  } catch (err) {
    logger.warn({ err: err.message }, 'google id_token verification failed');
    throw Object.assign(new Error('Invalid Google id_token'), { status: 401 });
  }
}

module.exports = {
  verifyAppleIdToken,
  verifyGoogleIdToken,
  // Internal helpers (exported for tests).
  _parseMockToken: parseMockToken,
};

// Silence the unused-env-import lint: env may be used in future for more
// granular mock-mode toggles.
void env;
