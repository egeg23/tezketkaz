// Phase 7.3 — promotional banners.
//
// Public buyers see active banners filtered by vertical/country, ordered by
// priority. Admins manage the banner library + upload images. Impressions
// (`view` and `click`) are recorded for the admin dashboard's stats endpoint.

const router = require('express').Router();
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const prisma = require('../db');
const { authMiddleware, optionalAuth, requireAdmin } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const logger = require('../lib/logger');

// ─── Upload setup (mirrors products) ────────────────────────────────────────
const UPLOAD_ROOT = path.resolve(__dirname, '../../uploads');
fs.mkdirSync(path.join(UPLOAD_ROOT, 'banners'), { recursive: true });

const imageStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, path.join(UPLOAD_ROOT, 'banners')),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase().replace(/[^a-z0-9.]/g, '') || '.jpg';
    cb(null, `${Date.now()}-${Math.random().toString(36).slice(2, 8)}${ext}`);
  },
});
const uploadImage = multer({
  storage: imageStorage,
  limits: { fileSize: 8 * 1024 * 1024 }, // 8 MB
  fileFilter: (req, file, cb) => {
    if (!/^image\/(jpeg|png|webp)$/.test(file.mimetype)) {
      return cb(new Error('Only JPEG/PNG/WebP allowed'));
    }
    cb(null, true);
  },
});

// ─── Helpers ────────────────────────────────────────────────────────────────
const ALLOWED_FIELDS = [
  'titleUz', 'titleRu', 'titleEn',
  'subtitleUz', 'subtitleRu', 'subtitleEn',
  'imageUrl', 'deepLink', 'vertical', 'country',
  'priority', 'isActive', 'validFrom', 'validUntil',
];

function pickBannerFields(input) {
  const out = {};
  for (const k of ALLOWED_FIELDS) {
    if (input[k] !== undefined) out[k] = input[k];
  }
  if (out.priority !== undefined) out.priority = parseInt(out.priority, 10) || 0;
  if (out.isActive !== undefined) out.isActive = Boolean(out.isActive);
  if (out.country === '' ) out.country = null;
  if (out.deepLink === '') out.deepLink = null;
  if (out.validFrom === '' || out.validFrom === null) out.validFrom = null;
  else if (out.validFrom !== undefined) out.validFrom = new Date(out.validFrom);
  if (out.validUntil === '' || out.validUntil === null) out.validUntil = null;
  else if (out.validUntil !== undefined) out.validUntil = new Date(out.validUntil);
  return out;
}

function validateBanner(b) {
  const errors = [];
  if (!b.titleUz || !String(b.titleUz).trim()) errors.push('titleUz required');
  if (!b.titleRu || !String(b.titleRu).trim()) errors.push('titleRu required');
  if (!b.imageUrl || !String(b.imageUrl).trim()) errors.push('imageUrl required');
  if (b.vertical && !['all', 'grocery', 'restaurant', 'pharmacy', 'electronics'].includes(b.vertical)) {
    errors.push('invalid vertical');
  }
  if (b.country && !['UZ', 'KZ', 'KG'].includes(String(b.country).toUpperCase())) {
    errors.push('invalid country');
  }
  return errors;
}

// Best-effort impression recording. Never throws out of the request handler.
function recordImpressions(bannerIds, userId, kind) {
  if (!Array.isArray(bannerIds) || bannerIds.length === 0) return;
  const data = bannerIds.map((bannerId) => ({ bannerId, userId: userId || null, kind }));
  prisma.bannerImpression
    .createMany({ data })
    .catch((err) => logger.warn({ err: err.message, kind }, 'banner impression failed'));
}

// ─── GET /api/banners — public list, filtered by vertical + country ─────────
router.get('/banners', optionalAuth, async (req, res, next) => {
  try {
    const { vertical, country } = req.query;
    const userCountry = (req.user?.country || country || '').toUpperCase() || null;

    const now = new Date();
    const where = {
      isActive: true,
      AND: [
        { OR: [{ validFrom: null }, { validFrom: { lte: now } }] },
        { OR: [{ validUntil: null }, { validUntil: { gte: now } }] },
      ],
    };
    if (vertical) {
      where.OR = [{ vertical: String(vertical) }, { vertical: 'all' }];
    }
    if (userCountry) {
      where.AND.push({ OR: [{ country: userCountry }, { country: null }] });
    }

    const banners = await prisma.banner.findMany({
      where,
      orderBy: [{ priority: 'desc' }, { createdAt: 'desc' }],
      take: 10,
    });

    // Fire-and-forget impression record.
    recordImpressions(banners.map((b) => b.id), req.user?.id, 'view');

    res.json({ banners });
  } catch (err) { next(err); }
});

// ─── POST /api/banners/:id/click — record click ─────────────────────────────
router.post('/banners/:id/click', optionalAuth, async (req, res, next) => {
  try {
    // We don't strictly require the banner to exist — but verify so we don't
    // pollute the table with garbage IDs.
    const banner = await prisma.banner.findUnique({ where: { id: req.params.id } });
    if (!banner) return res.status(404).json({ error: 'Not found' });
    recordImpressions([banner.id], req.user?.id, 'click');
    res.status(204).end();
  } catch (err) { next(err); }
});

// ─── Admin endpoints ────────────────────────────────────────────────────────

// GET /api/admin/banners — paginated list (all, including inactive)
router.get('/admin/banners', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const cursor = req.query.cursor || null;
    const findArgs = {
      orderBy: [{ priority: 'desc' }, { createdAt: 'desc' }, { id: 'asc' }],
      take: limit + 1,
    };
    if (cursor) {
      findArgs.cursor = { id: String(cursor) };
      findArgs.skip = 1;
    }
    const rows = await prisma.banner.findMany(findArgs);
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;

    // Cheap impression counts per banner — group by ids.
    const ids = page.map((b) => b.id);
    let viewMap = new Map();
    let clickMap = new Map();
    if (ids.length) {
      const grouped = await prisma.bannerImpression.groupBy({
        by: ['bannerId', 'kind'],
        where: { bannerId: { in: ids } },
        _count: { _all: true },
      });
      for (const g of grouped) {
        if (g.kind === 'view') viewMap.set(g.bannerId, g._count._all);
        else if (g.kind === 'click') clickMap.set(g.bannerId, g._count._all);
      }
    }
    const banners = page.map((b) => ({
      ...b,
      viewsCount: viewMap.get(b.id) || 0,
      clicksCount: clickMap.get(b.id) || 0,
    }));
    res.json({
      banners,
      nextCursor: hasMore ? page[page.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// POST /api/admin/banners/upload-image — multipart upload
router.post(
  '/admin/banners/upload-image',
  authMiddleware,
  requireAdmin,
  uploadImage.single('image'),
  async (req, res, next) => {
    try {
      if (!req.file) return res.status(400).json({ error: 'No file' });
      const url = `/uploads/banners/${req.file.filename}`;
      res.json({ url, filename: req.file.filename, size: req.file.size });
    } catch (err) { next(err); }
  },
);

// POST /api/admin/banners — create
router.post('/admin/banners', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const data = pickBannerFields(req.body || {});
    const errors = validateBanner(data);
    if (errors.length) return res.status(400).json({ error: errors.join('; ') });
    if (data.country) data.country = String(data.country).toUpperCase();
    const banner = await prisma.banner.create({ data });
    await audit({
      actorId: req.user.id, action: 'banner.create',
      targetType: 'Banner', targetId: banner.id,
      metadata: { vertical: banner.vertical, country: banner.country },
      ipAddress: req.ip,
    });
    res.status(201).json({ banner });
  } catch (err) { next(err); }
});

// PATCH /api/admin/banners/:id — update
router.patch('/admin/banners/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const data = pickBannerFields(req.body || {});
    if (data.country) data.country = String(data.country).toUpperCase();
    const banner = await prisma.banner.update({
      where: { id: req.params.id },
      data,
    });
    await audit({
      actorId: req.user.id, action: 'banner.update',
      targetType: 'Banner', targetId: banner.id,
      metadata: data, ipAddress: req.ip,
    });
    res.json({ banner });
  } catch (err) {
    if (err && err.code === 'P2025') return res.status(404).json({ error: 'Not found' });
    next(err);
  }
});

// DELETE /api/admin/banners/:id
router.delete('/admin/banners/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    await prisma.banner.delete({ where: { id: req.params.id } });
    await audit({
      actorId: req.user.id, action: 'banner.delete',
      targetType: 'Banner', targetId: req.params.id, ipAddress: req.ip,
    });
    res.json({ deleted: true });
  } catch (err) {
    if (err && err.code === 'P2025') return res.status(404).json({ error: 'Not found' });
    next(err);
  }
});

// GET /api/admin/banners/:id/stats — impression analytics
router.get('/admin/banners/:id/stats', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const banner = await prisma.banner.findUnique({ where: { id: req.params.id } });
    if (!banner) return res.status(404).json({ error: 'Not found' });

    const grouped = await prisma.bannerImpression.groupBy({
      by: ['kind'],
      where: { bannerId: banner.id },
      _count: { _all: true },
    });
    let views = 0;
    let clicks = 0;
    for (const g of grouped) {
      if (g.kind === 'view') views = g._count._all;
      else if (g.kind === 'click') clicks = g._count._all;
    }
    const ctr = views > 0 ? clicks / views : 0;

    // Last 30-day daily view counts. SQLite-friendly: fetch rows, bucket in JS.
    const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const rows = await prisma.bannerImpression.findMany({
      where: { bannerId: banner.id, kind: 'view', createdAt: { gte: since } },
      select: { createdAt: true },
    });
    const buckets = new Map();
    for (const r of rows) {
      const d = new Date(r.createdAt);
      const day = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
      buckets.set(day, (buckets.get(day) || 0) + 1);
    }
    const last30dayDailyViews = Array.from(buckets.entries())
      .map(([day, count]) => ({ day, count }))
      .sort((a, b) => a.day.localeCompare(b.day));

    res.json({ views, clicks, ctr, last30dayDailyViews });
  } catch (err) { next(err); }
});

module.exports = router;
