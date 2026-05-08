// Phase 9.1 + 9.2 — GDPR routes (data export + account deletion).
//
// Mounted at /api/users/me/* alongside routes/users.js. The endpoints here
// are user-self-service: an authenticated buyer can request an export of all
// their data, list past exports, request account deletion (which soft-deletes
// the user and schedules a hard purge in 30 days), or cancel that request
// within the grace window.

const router = require('express').Router();
const prisma = require('../db');
const logger = require('../lib/logger');
const { authMiddleware } = require('../middleware/auth');
const dataExport = require('../services/dataExport');
const accountDeletion = require('../services/accountDeletion');

const GRACE_DAYS = 30;

function errResp(res, status, message) {
  return res.status(status).json({ error: message });
}

// Try to enqueue the export render via BullMQ; fall back to inline execution
// if Redis is disabled (dev/test path). Either way the API returns 202 with
// a status the client can poll.
async function runExport(userId) {
  // Run inline when no Redis. We don't currently have a `dataExports` queue
  // wired (low traffic, single-user payloads), so this is the default path
  // even in production. Switch to a BullMQ queue if exports start blocking.
  return dataExport.renderToFile(prisma, userId);
}

// ─── POST /api/users/me/export-data ─────────────────────────────────────────
// Kicks off a new data export. Runs synchronously (build + write JSON) in dev
// and most prod deployments — payloads are small (a few MB at most).
router.post('/me/export-data', authMiddleware, async (req, res, next) => {
  try {
    let row;
    try {
      row = await runExport(req.user.id);
    } catch (err) {
      logger.warn({ err: err.message, userId: req.user.id }, 'export-data failed');
      return errResp(res, 500, 'Export failed');
    }
    res.status(202).json({
      exportId: row.id,
      status: row.status,
      fileUrl: row.fileUrl || null,
      expiresAt: row.expiresAt || null,
    });
  } catch (err) { next(err); }
});

// ─── GET /api/users/me/exports ──────────────────────────────────────────────
router.get('/me/exports', authMiddleware, async (req, res, next) => {
  try {
    const rows = await prisma.dataExport.findMany({
      where: { userId: req.user.id },
      orderBy: { requestedAt: 'desc' },
      take: 20,
    });
    res.json({ exports: rows });
  } catch (err) { next(err); }
});

// ─── GET /api/users/me/exports/:id ──────────────────────────────────────────
// Returns 404 if the export belongs to another user (cross-user isolation),
// 410 Gone if expired.
router.get('/me/exports/:id', authMiddleware, async (req, res, next) => {
  try {
    const row = await prisma.dataExport.findUnique({ where: { id: req.params.id } });
    if (!row || row.userId !== req.user.id) return errResp(res, 404, 'Export not found');
    if (row.expiresAt && row.expiresAt < new Date()) {
      // Mark as expired so the next list call shows the right state.
      if (row.status !== 'expired') {
        try {
          await prisma.dataExport.update({
            where: { id: row.id },
            data: { status: 'expired' },
          });
        } catch { /* ignore */ }
      }
      return res.status(410).json({ error: 'Export expired', exportId: row.id });
    }
    res.json({ export: row });
  } catch (err) { next(err); }
});

// ─── POST /api/users/me/delete-account ──────────────────────────────────────
// Body: { reason?: string }
router.post('/me/delete-account', authMiddleware, async (req, res, next) => {
  try {
    const reason = typeof req.body?.reason === 'string' ? req.body.reason.slice(0, 500) : null;
    const result = await accountDeletion.request(prisma, req.user.id, reason, {
      ipAddress: req.ip || null,
    });
    res.status(202).json({
      request: result,
      message: `You can cancel within ${GRACE_DAYS} days.`,
      gracePeriodDays: GRACE_DAYS,
    });
  } catch (err) {
    if (err.status) return errResp(res, err.status, err.message);
    next(err);
  }
});

// ─── POST /api/users/me/delete-account/cancel ───────────────────────────────
router.post('/me/delete-account/cancel', authMiddleware, async (req, res, next) => {
  try {
    // Find the active pending request — there should be at most one.
    const active = await prisma.accountDeletionRequest.findFirst({
      where: { userId: req.user.id, status: 'pending' },
      orderBy: { requestedAt: 'desc' },
    });
    if (!active) return errResp(res, 404, 'No active deletion request');
    const result = await accountDeletion.cancel(prisma, active.id, req.user.id, {
      ipAddress: req.ip || null,
    });
    res.json({ request: result });
  } catch (err) {
    if (err.status) return errResp(res, err.status, err.message);
    next(err);
  }
});

// ─── GET /api/users/me/deletion-status ──────────────────────────────────────
router.get('/me/deletion-status', authMiddleware, async (req, res, next) => {
  try {
    const active = await prisma.accountDeletionRequest.findFirst({
      where: { userId: req.user.id, status: 'pending' },
      orderBy: { requestedAt: 'desc' },
    });
    res.json({ request: active || null });
  } catch (err) { next(err); }
});

module.exports = router;
