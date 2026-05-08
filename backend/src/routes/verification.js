// Phase 6.5 — KYC verification document upload + admin review.
//
// User-facing routes are mounted under /api/verification/*; admin routes are
// mounted under /api/admin/verification/*. We expose a single Router that
// handles both and is mounted at /api in src/index.js.
//
// Storage: /uploads/verification/* served by the same static handler that
// serves product images. Files are validated for mimetype + size at upload.
//
// Auto-promotion: when a courier has approved docs covering ALL of the types
// listed in REQUIRED_COURIER_DOCS, we flip courierStatus -> 'approved' and
// isCourier=true. This is idempotent — running again is a no-op.

const router = require('express').Router();
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const prisma = require('../db');
const { authMiddleware, requireAdmin } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const { putFromMulterFile } = require('../lib/storage');

// ─── Config ─────────────────────────────────────────────────────────────────

// All courier docs that MUST be approved before we auto-promote courierStatus.
const REQUIRED_COURIER_DOCS = [
  'passport_front',
  'passport_back',
  'selfie',
  'self_employed_cert',
];

const ALLOWED_TYPES = new Set([
  'passport_front',
  'passport_back',
  'selfie',
  'self_employed_cert',
  'shop_license',
  'shop_tax_cert',
  'driver_license',
]);

// ─── Upload setup (mirrors routes/products.js) ──────────────────────────────
const UPLOAD_ROOT = path.resolve(__dirname, '../../uploads');
fs.mkdirSync(path.join(UPLOAD_ROOT, 'verification'), { recursive: true });

const docStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, path.join(UPLOAD_ROOT, 'verification')),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase().replace(/[^a-z0-9.]/g, '') || '.jpg';
    cb(null, `${Date.now()}-${Math.random().toString(36).slice(2, 8)}${ext}`);
  },
});

const uploadDoc = multer({
  storage: docStorage,
  limits: { fileSize: 8 * 1024 * 1024 }, // 8 MB
  fileFilter: (req, file, cb) => {
    if (!/^image\/(jpeg|png|webp)$/.test(file.mimetype)) {
      return cb(new Error('Only JPEG/PNG/WebP allowed'));
    }
    cb(null, true);
  },
});

// ─── Helpers ────────────────────────────────────────────────────────────────

async function maybePromoteCourier(userId) {
  const docs = await prisma.verificationDocument.findMany({
    where: { userId, status: 'approved', type: { in: REQUIRED_COURIER_DOCS } },
    select: { type: true },
  });
  const have = new Set(docs.map((d) => d.type));
  const allApproved = REQUIRED_COURIER_DOCS.every((t) => have.has(t));
  if (!allApproved) return false;

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) return false;
  if (user.courierStatus === 'approved' && user.isCourier) return false;

  await prisma.user.update({
    where: { id: userId },
    data: { courierStatus: 'approved', isCourier: true },
  });
  return true;
}

// ─── User: GET /api/verification/me ─────────────────────────────────────────
router.get('/verification/me', authMiddleware, async (req, res, next) => {
  try {
    const docs = await prisma.verificationDocument.findMany({
      where: { userId: req.user.id },
      orderBy: { createdAt: 'desc' },
    });
    res.json({ docs });
  } catch (err) { next(err); }
});

// ─── User: POST /api/verification/upload ────────────────────────────────────
// Multipart: `file` is the image, `type` is the doc type (form field).
router.post(
  '/verification/upload',
  authMiddleware,
  uploadDoc.single('file'),
  async (req, res, next) => {
    try {
      if (!req.file) return res.status(400).json({ error: 'file required' });
      const type = (req.body && req.body.type) || '';
      if (!ALLOWED_TYPES.has(type)) {
        // Best-effort cleanup of the orphaned upload.
        try { fs.unlinkSync(req.file.path); } catch { /* noop */ }
        return res.status(400).json({ error: 'invalid or missing type' });
      }
      // Phase 9 — storage abstraction (S3-or-local).
      const { url } = await putFromMulterFile(req.file, `verification/${req.file.filename}`);
      const doc = await prisma.verificationDocument.create({
        data: {
          userId: req.user.id,
          type,
          url,
          status: 'pending',
        },
      });
      res.status(201).json({ doc });
    } catch (err) { next(err); }
  },
);

// ─── User: DELETE /api/verification/:id ─────────────────────────────────────
// Owner can delete only own docs that are still pending.
router.delete('/verification/:id', authMiddleware, async (req, res, next) => {
  try {
    const doc = await prisma.verificationDocument.findUnique({ where: { id: req.params.id } });
    if (!doc) return res.status(404).json({ error: 'Not found' });
    if (doc.userId !== req.user.id) return res.status(403).json({ error: 'Forbidden' });
    if (doc.status !== 'pending') {
      return res.status(409).json({ error: 'Cannot delete reviewed doc' });
    }
    await prisma.verificationDocument.delete({ where: { id: doc.id } });
    // Best-effort cleanup of the file.
    if (doc.url && doc.url.startsWith('/uploads/verification/')) {
      const fname = path.basename(doc.url);
      try { fs.unlinkSync(path.join(UPLOAD_ROOT, 'verification', fname)); } catch { /* noop */ }
    }
    res.json({ deleted: true });
  } catch (err) { next(err); }
});

// ─── Admin: GET /api/admin/verification ─────────────────────────────────────
router.get('/admin/verification', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const { status, type } = req.query;
    const where = {};
    if (status) where.status = String(status);
    if (type) where.type = String(type);

    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const cursor = req.query.cursor || null;

    const findArgs = {
      where,
      orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
      take: limit + 1,
      include: {
        user: { select: { id: true, name: true, phone: true, courierStatus: true } },
      },
    };
    if (cursor) {
      findArgs.cursor = { id: String(cursor) };
      findArgs.skip = 1;
    }

    const rows = await prisma.verificationDocument.findMany(findArgs);
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    res.json({
      docs: page,
      nextCursor: hasMore ? page[page.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// ─── Admin: GET /api/admin/verification/:id ─────────────────────────────────
router.get('/admin/verification/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const doc = await prisma.verificationDocument.findUnique({
      where: { id: req.params.id },
      include: {
        user: {
          select: {
            id: true, name: true, phone: true, courierStatus: true,
            isCourier: true, isShop: true, isAdmin: true, createdAt: true,
          },
        },
      },
    });
    if (!doc) return res.status(404).json({ error: 'Not found' });
    res.json({ doc });
  } catch (err) { next(err); }
});

// ─── Admin: POST /api/admin/verification/:id/approve ────────────────────────
router.post(
  '/admin/verification/:id/approve',
  authMiddleware,
  requireAdmin,
  async (req, res, next) => {
    try {
      const existing = await prisma.verificationDocument.findUnique({ where: { id: req.params.id } });
      if (!existing) return res.status(404).json({ error: 'Not found' });

      const doc = await prisma.verificationDocument.update({
        where: { id: req.params.id },
        data: {
          status: 'approved',
          reviewedById: req.user.id,
          reviewedAt: new Date(),
          rejectionReason: null,
        },
      });

      let promoted = false;
      try {
        promoted = await maybePromoteCourier(doc.userId);
      } catch { /* noop */ }

      await audit({
        actorId: req.user.id,
        action: 'verification.approve',
        targetType: 'VerificationDocument',
        targetId: doc.id,
        metadata: { type: doc.type, userId: doc.userId, promoted },
        ipAddress: req.ip,
      });

      res.json({ doc, courierPromoted: promoted });
    } catch (err) { next(err); }
  },
);

// ─── Admin: POST /api/admin/verification/:id/reject ─────────────────────────
router.post(
  '/admin/verification/:id/reject',
  authMiddleware,
  requireAdmin,
  async (req, res, next) => {
    try {
      const { reason } = req.body || {};
      if (!reason || !String(reason).trim()) {
        return res.status(400).json({ error: 'reason required' });
      }
      const existing = await prisma.verificationDocument.findUnique({ where: { id: req.params.id } });
      if (!existing) return res.status(404).json({ error: 'Not found' });

      const doc = await prisma.verificationDocument.update({
        where: { id: req.params.id },
        data: {
          status: 'rejected',
          reviewedById: req.user.id,
          reviewedAt: new Date(),
          rejectionReason: String(reason).trim(),
        },
      });

      await audit({
        actorId: req.user.id,
        action: 'verification.reject',
        targetType: 'VerificationDocument',
        targetId: doc.id,
        metadata: { type: doc.type, userId: doc.userId, reason },
        ipAddress: req.ip,
      });

      res.json({ doc });
    } catch (err) { next(err); }
  },
);

module.exports = router;
module.exports.REQUIRED_COURIER_DOCS = REQUIRED_COURIER_DOCS;
