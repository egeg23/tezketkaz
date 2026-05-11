// Phase 13.1.5 — Legal acceptance versioning.
//
// `CURRENT_LEGAL_VERSION` is the version users will be asked to accept on
// new sign-ups and after material updates to the T&C / Privacy Policy.
// Bump this string whenever the legal documents in `backend/legal/` change
// in a way that requires re-acceptance.
//
// `SUPPORTED_LEGAL_VERSIONS` is the set of versions still considered valid.
// Versions newer than the user's last acceptance but still in this list do
// not force a re-acceptance. Drop a version when it's no longer acceptable
// (e.g. a major privacy-policy revision); the user will be prompted to
// re-accept on next login via the `legalUpdateRequired` flag.

const CURRENT_LEGAL_VERSION = 'v1.0.0';
const SUPPORTED_LEGAL_VERSIONS = ['v1.0.0'];

module.exports = { CURRENT_LEGAL_VERSION, SUPPORTED_LEGAL_VERSIONS };
