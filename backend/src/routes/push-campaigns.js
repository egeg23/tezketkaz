// Phase 10.3 — admin push notification campaign routes.
//
// Admin sub-router (mounted at /api/admin/push-campaigns):
//   POST   /preview                 → body {audienceQuery} → {recipientCount}
//   GET    /                        → list (filter by status)
//   POST   /                        → create draft
//   GET    /:id                     → fetch one
//   PATCH  /:id                     → update draft
//   POST   /:id/send                → trigger send
//   POST   /:id/cancel              → cancel draft/scheduled
//   DELETE /:id                     → only drafts
//   GET    /:id/stats               → recipient/success/failure/openCount
//
// User sub-router (mounted at /api/push-campaigns):
//   POST   /:id/track-open          → user reports a tap (auth optional)

const adminRouter = require('express').Router();
const userRouter = require('express').Router();
const prisma = require('../db');
const { authMiddleware, requireAdmin, optionalAuth } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const pushCampaign = require('../services/pushCampaign');
const audienceQuery = require('../services/audienceQuery');
const logger = require('../lib/logger');

const VALID_STATUSES = new Set(['draft', 'scheduled', 'sending', 'sent', 'failed', 'cancelled']);

function clampStr(v, max) {
  if (v == null) return null;
  return String(v).slice(0, max);
}

function pickCampaignFields(body) {
  const out = {};
  const fields = [
    'titleUz', 'titleRu', 'titleEn', 'titleKk',
    'bodyUz', 'bodyRu', 'bodyEn', 'bodyKk',
    'deepLink',
  ];
  for (const f of fields) {
    if (body[f] !== undefined) out[f] = body[f] === null ? null : clampStr(body[f], 1000);
  }
  if (body.audienceQuery !== undefined) {
    if (typeof body.audienceQuery === 'string') {
      out.audienceQuery = body.audienceQuery.slice(0, 8000);
    } else {
      out.audienceQuery = JSON.stringify(body.audienceQuery || {}).slice(0, 8000);
    }
  }
  if (body.scheduledFor !== undefined) {
    if (body.scheduledFor === null) out.scheduledFor = null;
    else {
      const d = new Date(body.scheduledFor);
      if (Number.isNaN(d.getTime())) {
        throw Object.assign(new Error('invalid scheduledFor'), { status: 400 });
      }
      out.scheduledFor = d;
    }
  }
  return out;
}

// ─── POST /api/admin/push-campaigns/preview ──────────────────────────────────
adminRouter.post('/preview', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const spec = req.body?.audienceQuery ?? {};
    const { recipientCount } = await pushCampaign.preview(prisma, spec);
    res.json({ recipientCount });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/push-campaigns ───────────────────────────────────────────
adminRouter.get('/', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const limit = Math.min(200, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const where = {};
    if (req.query.status && VALID_STATUSES.has(String(req.query.status))) {
      where.status = String(req.query.status);
    }
    const campaigns = await prisma.pushCampaign.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
    res.json({ campaigns });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/push-campaigns ──────────────────────────────────────────
adminRouter.post('/', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const body = req.body || {};
    const titleUz = clampStr(body.titleUz, 1000);
    const titleRu = clampStr(body.titleRu, 1000);
    const bodyUz  = clampStr(body.bodyUz, 1000);
    const bodyRu  = clampStr(body.bodyRu, 1000);
    if (!titleUz || !titleRu) return res.status(400).json({ error: 'titleUz and titleRu required' });
    if (!bodyUz || !bodyRu)   return res.status(400).json({ error: 'bodyUz and bodyRu required' });

    const data = {
      titleUz, titleRu, bodyUz, bodyRu,
      titleEn: body.titleEn ? clampStr(body.titleEn, 1000) : null,
      titleKk: body.titleKk ? clampStr(body.titleKk, 1000) : null,
      bodyEn:  body.bodyEn  ? clampStr(body.bodyEn,  1000) : null,
      bodyKk:  body.bodyKk  ? clampStr(body.bodyKk,  1000) : null,
      deepLink: body.deepLink ? clampStr(body.deepLink, 1000) : null,
      audienceQuery: typeof body.audienceQuery === 'string'
        ? body.audienceQuery.slice(0, 8000)
        : JSON.stringify(body.audienceQuery || {}).slice(0, 8000),
      status: body.scheduledFor ? 'scheduled' : 'draft',
      createdById: req.user.id,
    };
    if (body.scheduledFor) {
      const d = new Date(body.scheduledFor);
      if (!Number.isNaN(d.getTime())) data.scheduledFor = d;
    }
    const campaign = await prisma.pushCampaign.create({ data });
    await audit({
      actorId: req.user.id,
      action: 'push_campaign.create',
      targetType: 'PushCampaign',
      targetId: campaign.id,
      ipAddress: req.ip,
    });
    res.status(201).json({ campaign });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/push-campaigns/:id ───────────────────────────────────────
adminRouter.get('/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const campaign = await prisma.pushCampaign.findUnique({ where: { id: req.params.id } });
    if (!campaign) return res.status(404).json({ error: 'Not found' });
    res.json({ campaign });
  } catch (err) { next(err); }
});

// ─── PATCH /api/admin/push-campaigns/:id ─────────────────────────────────────
adminRouter.patch('/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const existing = await prisma.pushCampaign.findUnique({ where: { id: req.params.id } });
    if (!existing) return res.status(404).json({ error: 'Not found' });
    if (!['draft', 'scheduled'].includes(existing.status)) {
      return res.status(400).json({ error: 'Only drafts or scheduled campaigns are editable' });
    }
    const data = pickCampaignFields(req.body || {});
    if (data.scheduledFor) data.status = 'scheduled';
    if (data.scheduledFor === null && existing.status === 'scheduled') data.status = 'draft';
    const campaign = await prisma.pushCampaign.update({ where: { id: existing.id }, data });
    res.json({ campaign });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/push-campaigns/:id/send ─────────────────────────────────
adminRouter.post('/:id/send', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const existing = await prisma.pushCampaign.findUnique({ where: { id: req.params.id } });
    if (!existing) return res.status(404).json({ error: 'Not found' });
    if (existing.status === 'sent')       return res.status(400).json({ error: 'Already sent' });
    if (existing.status === 'cancelled')  return res.status(400).json({ error: 'Cancelled' });
    if (existing.status === 'sending')    return res.status(400).json({ error: 'Already sending' });

    const campaign = await pushCampaign.send(prisma, existing.id);
    await audit({
      actorId: req.user.id,
      action: 'push_campaign.send',
      targetType: 'PushCampaign',
      targetId: campaign.id,
      ipAddress: req.ip,
    });
    res.json({ campaign });
  } catch (err) { next(err); }
});

// ─── POST /api/admin/push-campaigns/:id/cancel ───────────────────────────────
adminRouter.post('/:id/cancel', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const existing = await prisma.pushCampaign.findUnique({ where: { id: req.params.id } });
    if (!existing) return res.status(404).json({ error: 'Not found' });
    if (!['draft', 'scheduled'].includes(existing.status)) {
      return res.status(400).json({ error: 'Only draft/scheduled can be cancelled' });
    }
    const campaign = await prisma.pushCampaign.update({
      where: { id: existing.id },
      data: { status: 'cancelled' },
    });
    await audit({
      actorId: req.user.id,
      action: 'push_campaign.cancel',
      targetType: 'PushCampaign',
      targetId: campaign.id,
      ipAddress: req.ip,
    });
    res.json({ campaign });
  } catch (err) { next(err); }
});

// ─── DELETE /api/admin/push-campaigns/:id ────────────────────────────────────
adminRouter.delete('/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const existing = await prisma.pushCampaign.findUnique({ where: { id: req.params.id } });
    if (!existing) return res.status(404).json({ error: 'Not found' });
    if (existing.status !== 'draft') {
      return res.status(400).json({ error: 'Only drafts can be deleted' });
    }
    await prisma.pushCampaign.delete({ where: { id: existing.id } });
    await audit({
      actorId: req.user.id,
      action: 'push_campaign.delete',
      targetType: 'PushCampaign',
      targetId: existing.id,
      ipAddress: req.ip,
    });
    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/push-campaigns/:id/stats ─────────────────────────────────
adminRouter.get('/:id/stats', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const c = await prisma.pushCampaign.findUnique({ where: { id: req.params.id } });
    if (!c) return res.status(404).json({ error: 'Not found' });
    res.json({
      recipientCount: c.recipientCount,
      successCount: c.successCount,
      failureCount: c.failureCount,
      openCount: c.openCount,
      sentAt: c.sentAt,
      status: c.status,
    });
  } catch (err) { next(err); }
});

// ─── POST /api/push-campaigns/:id/track-open ─────────────────────────────────
// Auth optional — anonymous opens still count.
userRouter.post('/:id/track-open', optionalAuth, async (req, res, next) => {
  try {
    const updated = await pushCampaign.trackOpen(prisma, req.params.id);
    if (!updated) return res.status(404).json({ error: 'Not found' });
    res.json({ ok: true, openCount: updated.openCount });
  } catch (err) {
    logger.warn({ err: err.message }, 'push-campaign track-open failed');
    next(err);
  }
});

module.exports = { adminRouter, userRouter };
