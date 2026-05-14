// Phase 12 — legal documents (privacy policy + terms of service).
//
// Serves the per-locale Markdown files under backend/legal/<doc>/<locale>.md
// over HTTP so the Flutter app, vendor portal and admin can render them.
// Documents are loaded once at module init into memory — they only change
// when we redeploy the backend.
//
//   GET /api/legal/privacy?locale=ru   →  { content, locale, doc, updatedAt }
//   GET /api/legal/terms?locale=uz     →  same shape
//   GET /api/legal/all?locale=uz       →  { privacy, terms }
//
// Locale fallback: if `<locale>.md` is missing we fall back to `ru.md` (the
// dominant language across UZ + KZ). If both are missing we 404.

const router = require('express').Router();
const fs = require('fs');
const path = require('path');

const DOCS = ['privacy', 'terms'];
const SUPPORTED_LOCALES = ['uz', 'ru', 'en', 'kk'];
const FALLBACK_LOCALE = 'ru';
const LEGAL_ROOT = path.resolve(__dirname, '..', '..', 'legal');

// In-memory cache: { privacy: { uz: {content, updatedAt}, ru: {...}, ... }, terms: {...} }
const cache = { privacy: {}, terms: {} };

function loadAll() {
  for (const doc of DOCS) {
    cache[doc] = {};
    for (const locale of SUPPORTED_LOCALES) {
      const filePath = path.join(LEGAL_ROOT, doc, `${locale}.md`);
      try {
        const content = fs.readFileSync(filePath, 'utf8');
        const stat = fs.statSync(filePath);
        cache[doc][locale] = { content, updatedAt: stat.mtime.toISOString() };
      } catch (err) {
        // Only swallow "file does not exist" — that's an expected missing
        // locale and resolve() will fall back. Permission denied (EACCES),
        // IO error (EIO), too many open files (EMFILE) etc. should surface
        // so an operator notices before the store reviewer hits a 404.
        if (err && err.code === 'ENOENT') {
          continue;
        }
        throw err;
      }
    }
  }
}

loadAll();

function resolve(doc, locale) {
  const bucket = cache[doc];
  if (!bucket) return null;
  if (bucket[locale]) return { ...bucket[locale], locale, doc };
  if (bucket[FALLBACK_LOCALE]) {
    return { ...bucket[FALLBACK_LOCALE], locale: FALLBACK_LOCALE, doc };
  }
  return null;
}

function normaliseLocale(raw) {
  if (!raw || typeof raw !== 'string') return FALLBACK_LOCALE;
  const lower = raw.toLowerCase().slice(0, 2);
  return SUPPORTED_LOCALES.includes(lower) ? lower : FALLBACK_LOCALE;
}

router.get('/privacy', (req, res) => {
  const locale = normaliseLocale(req.query.locale);
  const entry = resolve('privacy', locale);
  if (!entry) return res.status(404).json({ error: 'privacy_not_found' });
  res.set('Cache-Control', 'public, max-age=3600');
  res.json(entry);
});

router.get('/terms', (req, res) => {
  const locale = normaliseLocale(req.query.locale);
  const entry = resolve('terms', locale);
  if (!entry) return res.status(404).json({ error: 'terms_not_found' });
  res.set('Cache-Control', 'public, max-age=3600');
  res.json(entry);
});

router.get('/all', (req, res) => {
  const locale = normaliseLocale(req.query.locale);
  const privacy = resolve('privacy', locale);
  const terms = resolve('terms', locale);
  if (!privacy || !terms) {
    return res.status(404).json({ error: 'legal_documents_missing' });
  }
  res.set('Cache-Control', 'public, max-age=3600');
  res.json({ privacy, terms });
});

// Exported for tests that want to inspect the cache or force a reload.
router.__reload = loadAll;

module.exports = router;
