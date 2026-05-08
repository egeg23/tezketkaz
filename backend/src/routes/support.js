// Phase 10.2 — Customer support inbox.
//
// User endpoints (under /api/support/*):
//   POST   /tickets                      → create ticket
//   GET    /tickets/me                   → list own tickets
//   GET    /tickets/me/:ticketId         → ticket detail with messages
//   POST   /tickets/:ticketId/messages   → user reply
//   POST   /tickets/:ticketId/close      → user closes own ticket
//
// Admin endpoints (declared with absolute /admin/support/*):
//   GET    /admin/support/tickets
//   GET    /admin/support/tickets/:id
//   POST   /admin/support/tickets/:id/assign
//   PATCH  /admin/support/tickets/:id
//   POST   /admin/support/tickets/:id/messages
//   POST   /admin/support/tickets/:id/close
//   GET    /admin/support/stats
//
// Realtime: emits to socket room `support:<ticketId>`.
// Push: notifies the other party using `notifications.sendOrderEvent` with
// extended types `support_reply` / `support_resolved`.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware, requireAdmin } = require('../middleware/auth');
const notifications = require('../services/notifications');
const { audit } = require('../lib/audit');
const logger = require('../lib/logger');

const VALID_STATUSES = new Set(['open', 'in_progress', 'awaiting_user', 'closed', 'resolved']);
const VALID_PRIORITIES = new Set(['low', 'normal', 'high', 'urgent']);
const VALID_CATEGORIES = new Set(['order', 'payment', 'delivery', 'account', 'other']);

function clampStr(v, max) {
  if (v == null) return null;
  return String(v).slice(0, max);
}

async function loadTicket(ticketId, includeMessages = false) {
  return prisma.supportTicket.findUnique({
    where: { id: ticketId },
    include: includeMessages
      ? { messages: { orderBy: { createdAt: 'asc' } } }
      : undefined,
  });
}

function emitTicketEvent(req, ticketId, event, payload) {
  try {
    const io = req.app.get('io');
    if (io && typeof io.to === 'function') {
      io.to(`support:${ticketId}`).emit(event, payload);
    }
  } catch (err) {
    logger.warn({ err: err.message }, 'support socket emit failed');
  }
}

async function notifyOther(req, { recipientId, type, ticketId, body }) {
  if (!recipientId) return;
  try {
    const io = req.app.get('io');
    await notifications.sendOrderEvent(prisma, io, {
      userId: recipientId,
      type,
      data: { ticketId, preview: (body || '').slice(0, 80) },
    });
  } catch (err) {
    logger.warn({ err: err.message }, 'support push failed');
  }
}

// ─── User: POST /api/support/tickets ────────────────────────────────────────
router.post('/tickets', authMiddleware, async (req, res, next) => {
  try {
    const { subject, category, orderId, body } = req.body || {};
    const cleanSubject = clampStr(subject, 200);
    const cleanBody = clampStr(body, 8000);
    if (!cleanSubject) return res.status(400).json({ error: 'subject required' });
    if (!cleanBody) return res.status(400).json({ error: 'body required' });
    let cleanCategory = null;
    if (category) {
      if (!VALID_CATEGORIES.has(String(category))) {
        return res.status(400).json({ error: 'invalid category' });
      }
      cleanCategory = String(category);
    }
    const cleanOrderId = orderId ? String(orderId).slice(0, 100) : null;

    const now = new Date();
    const ticket = await prisma.supportTicket.create({
      data: {
        authorId: req.user.id,
        subject: cleanSubject,
        category: cleanCategory,
        orderId: cleanOrderId,
        status: 'open',
        priority: 'normal',
        lastReplyAt: now,
        lastReplyBy: 'user',
        messages: {
          create: [{
            senderId: req.user.id,
            senderRole: 'user',
            body: cleanBody,
          }],
        },
      },
      include: { messages: true },
    });

    res.status(201).json({ ticket });
  } catch (err) { next(err); }
});

// ─── User: GET /api/support/tickets/me ───────────────────────────────────────
router.get('/tickets/me', authMiddleware, async (req, res, next) => {
  try {
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const cursor = req.query.cursor ? String(req.query.cursor) : null;
    const where = { authorId: req.user.id };
    if (req.query.status && VALID_STATUSES.has(String(req.query.status))) {
      where.status = String(req.query.status);
    }
    const findArgs = {
      where,
      orderBy: [{ updatedAt: 'desc' }, { id: 'asc' }],
      take: limit + 1,
    };
    if (cursor) {
      findArgs.cursor = { id: cursor };
      findArgs.skip = 1;
    }
    const rows = await prisma.supportTicket.findMany(findArgs);
    const hasMore = rows.length > limit;
    const tickets = hasMore ? rows.slice(0, limit) : rows;
    res.json({
      tickets,
      nextCursor: hasMore ? tickets[tickets.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// ─── User: GET /api/support/tickets/me/:ticketId ─────────────────────────────
router.get('/tickets/me/:ticketId', authMiddleware, async (req, res, next) => {
  try {
    const ticket = await loadTicket(req.params.ticketId, true);
    if (!ticket) return res.status(404).json({ error: 'Not found' });
    if (ticket.authorId !== req.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    res.json({ ticket });
  } catch (err) { next(err); }
});

// ─── User: POST /api/support/tickets/:ticketId/messages ──────────────────────
router.post('/tickets/:ticketId/messages', authMiddleware, async (req, res, next) => {
  try {
    const ticket = await loadTicket(req.params.ticketId, false);
    if (!ticket) return res.status(404).json({ error: 'Not found' });
    if (ticket.authorId !== req.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    if (ticket.status === 'closed') {
      return res.status(400).json({ error: 'Ticket is closed' });
    }

    const { body, attachments } = req.body || {};
    const cleanBody = clampStr(body, 8000);
    if (!cleanBody) return res.status(400).json({ error: 'body required' });
    let attachmentsJson = null;
    if (Array.isArray(attachments) && attachments.length) {
      attachmentsJson = JSON.stringify(attachments.slice(0, 10).map((a) => String(a).slice(0, 1000)));
    }

    const now = new Date();
    const msg = await prisma.supportMessage.create({
      data: {
        ticketId: ticket.id,
        senderId: req.user.id,
        senderRole: 'user',
        body: cleanBody,
        attachments: attachmentsJson,
      },
    });

    // Transition awaiting_user → open on user reply.
    const nextStatus = ticket.status === 'awaiting_user' ? 'open' : ticket.status;
    await prisma.supportTicket.update({
      where: { id: ticket.id },
      data: {
        lastReplyAt: now,
        lastReplyBy: 'user',
        status: nextStatus,
      },
    });

    emitTicketEvent(req, ticket.id, 'support:message', msg);
    if (ticket.assigneeId) {
      await notifyOther(req, {
        recipientId: ticket.assigneeId,
        type: 'support_reply',
        ticketId: ticket.id,
        body: cleanBody,
      });
    }

    res.status(201).json({ message: msg });
  } catch (err) { next(err); }
});

// ─── User: POST /api/support/tickets/:ticketId/close ─────────────────────────
router.post('/tickets/:ticketId/close', authMiddleware, async (req, res, next) => {
  try {
    const ticket = await loadTicket(req.params.ticketId, false);
    if (!ticket) return res.status(404).json({ error: 'Not found' });
    if (ticket.authorId !== req.user.id) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    if (ticket.status === 'closed') {
      return res.json({ ticket });
    }
    const updated = await prisma.supportTicket.update({
      where: { id: ticket.id },
      data: { status: 'closed', closedAt: new Date() },
    });
    emitTicketEvent(req, ticket.id, 'support:closed', { ticketId: ticket.id });
    res.json({ ticket: updated });
  } catch (err) { next(err); }
});

module.exports = router;

// ─────────────────────────────────────────────────────────────────────────────
// Admin sub-router. Mounted at /api/admin/support by index.js — uses absolute
// paths declared via the parent admin router pattern.
// ─────────────────────────────────────────────────────────────────────────────
const adminRouter = require('express').Router();

// GET /api/admin/support/tickets
adminRouter.get('/tickets', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const limit = Math.min(200, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const cursor = req.query.cursor ? String(req.query.cursor) : null;
    const where = {};
    if (req.query.status && VALID_STATUSES.has(String(req.query.status))) {
      where.status = String(req.query.status);
    }
    if (req.query.priority && VALID_PRIORITIES.has(String(req.query.priority))) {
      where.priority = String(req.query.priority);
    }
    if (req.query.assigneeId) {
      where.assigneeId = String(req.query.assigneeId);
    }
    const q = req.query.q ? String(req.query.q).trim() : '';
    if (q) {
      where.OR = [
        { subject: { contains: q } },
        { id: { contains: q } },
      ];
    }
    const findArgs = {
      where,
      orderBy: [{ updatedAt: 'desc' }, { id: 'asc' }],
      take: limit + 1,
      include: {
        author: { select: { id: true, phone: true, name: true } },
        assignee: { select: { id: true, phone: true, name: true } },
      },
    };
    if (cursor) {
      findArgs.cursor = { id: cursor };
      findArgs.skip = 1;
    }
    const rows = await prisma.supportTicket.findMany(findArgs);
    const hasMore = rows.length > limit;
    const tickets = hasMore ? rows.slice(0, limit) : rows;
    res.json({
      tickets,
      nextCursor: hasMore ? tickets[tickets.length - 1].id : null,
    });
  } catch (err) { next(err); }
});

// GET /api/admin/support/stats
adminRouter.get('/stats', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const startOfDay = new Date(); startOfDay.setHours(0, 0, 0, 0);
    const [open, inProgress, awaitingUser, closedToday, resolvedToday] = await Promise.all([
      prisma.supportTicket.count({ where: { status: 'open' } }),
      prisma.supportTicket.count({ where: { status: 'in_progress' } }),
      prisma.supportTicket.count({ where: { status: 'awaiting_user' } }),
      prisma.supportTicket.count({ where: { status: 'closed', closedAt: { gte: startOfDay } } }),
      prisma.supportTicket.count({ where: { status: 'resolved', resolvedAt: { gte: startOfDay } } }),
    ]);
    res.json({
      open,
      in_progress: inProgress,
      awaiting_user: awaitingUser,
      closed_today: closedToday,
      resolved_today: resolvedToday,
    });
  } catch (err) { next(err); }
});

// GET /api/admin/support/tickets/:ticketId
adminRouter.get('/tickets/:ticketId', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const ticket = await prisma.supportTicket.findUnique({
      where: { id: req.params.ticketId },
      include: {
        messages: { orderBy: { createdAt: 'asc' } },
        author: { select: { id: true, phone: true, name: true, locale: true } },
        assignee: { select: { id: true, phone: true, name: true } },
      },
    });
    if (!ticket) return res.status(404).json({ error: 'Not found' });
    res.json({ ticket });
  } catch (err) { next(err); }
});

// POST /api/admin/support/tickets/:ticketId/assign
adminRouter.post('/tickets/:ticketId/assign', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const ticket = await loadTicket(req.params.ticketId, false);
    if (!ticket) return res.status(404).json({ error: 'Not found' });
    const { assigneeId } = req.body || {};
    if (assigneeId) {
      const assignee = await prisma.user.findUnique({ where: { id: String(assigneeId) } });
      if (!assignee) return res.status(400).json({ error: 'invalid assigneeId' });
    }
    const updated = await prisma.supportTicket.update({
      where: { id: ticket.id },
      data: {
        assigneeId: assigneeId ? String(assigneeId) : null,
        // Auto-bump from open → in_progress when first assigned.
        status: assigneeId && ticket.status === 'open' ? 'in_progress' : ticket.status,
      },
    });
    await audit({
      actorId: req.user.id,
      action: 'support.assign',
      targetType: 'SupportTicket',
      targetId: ticket.id,
      metadata: { assigneeId },
      ipAddress: req.ip,
    });
    res.json({ ticket: updated });
  } catch (err) { next(err); }
});

// PATCH /api/admin/support/tickets/:ticketId
adminRouter.patch('/tickets/:ticketId', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const ticket = await loadTicket(req.params.ticketId, false);
    if (!ticket) return res.status(404).json({ error: 'Not found' });
    const { status, priority, category } = req.body || {};
    const data = {};
    if (status != null) {
      if (!VALID_STATUSES.has(String(status))) {
        return res.status(400).json({ error: 'invalid status' });
      }
      data.status = String(status);
      if (data.status === 'closed' && !ticket.closedAt) data.closedAt = new Date();
      if (data.status === 'resolved' && !ticket.resolvedAt) data.resolvedAt = new Date();
    }
    if (priority != null) {
      if (!VALID_PRIORITIES.has(String(priority))) {
        return res.status(400).json({ error: 'invalid priority' });
      }
      data.priority = String(priority);
    }
    if (category != null) {
      if (category && !VALID_CATEGORIES.has(String(category))) {
        return res.status(400).json({ error: 'invalid category' });
      }
      data.category = category ? String(category) : null;
    }
    const updated = await prisma.supportTicket.update({
      where: { id: ticket.id },
      data,
    });
    await audit({
      actorId: req.user.id,
      action: 'support.update',
      targetType: 'SupportTicket',
      targetId: ticket.id,
      metadata: data,
      ipAddress: req.ip,
    });
    if (data.status === 'resolved') {
      await notifyOther(req, {
        recipientId: ticket.authorId,
        type: 'support_resolved',
        ticketId: ticket.id,
        body: ticket.subject,
      });
    }
    res.json({ ticket: updated });
  } catch (err) { next(err); }
});

// POST /api/admin/support/tickets/:ticketId/messages
adminRouter.post('/tickets/:ticketId/messages', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const ticket = await loadTicket(req.params.ticketId, false);
    if (!ticket) return res.status(404).json({ error: 'Not found' });
    const { body, attachments } = req.body || {};
    const cleanBody = clampStr(body, 8000);
    if (!cleanBody) return res.status(400).json({ error: 'body required' });
    let attachmentsJson = null;
    if (Array.isArray(attachments) && attachments.length) {
      attachmentsJson = JSON.stringify(attachments.slice(0, 10).map((a) => String(a).slice(0, 1000)));
    }

    const now = new Date();
    const msg = await prisma.supportMessage.create({
      data: {
        ticketId: ticket.id,
        senderId: req.user.id,
        senderRole: 'admin',
        body: cleanBody,
        attachments: attachmentsJson,
      },
    });

    // Transition open → awaiting_user on admin reply.
    const nextStatus = ticket.status === 'open' ? 'awaiting_user' : ticket.status;
    await prisma.supportTicket.update({
      where: { id: ticket.id },
      data: {
        lastReplyAt: now,
        lastReplyBy: 'admin',
        status: nextStatus,
        // If ticket has no assignee yet, the responding admin claims it.
        assigneeId: ticket.assigneeId || req.user.id,
      },
    });

    emitTicketEvent(req, ticket.id, 'support:message', msg);
    await notifyOther(req, {
      recipientId: ticket.authorId,
      type: 'support_reply',
      ticketId: ticket.id,
      body: cleanBody,
    });

    res.status(201).json({ message: msg });
  } catch (err) { next(err); }
});

// POST /api/admin/support/tickets/:ticketId/close
adminRouter.post('/tickets/:ticketId/close', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const ticket = await loadTicket(req.params.ticketId, false);
    if (!ticket) return res.status(404).json({ error: 'Not found' });
    const { reason } = req.body || {};
    const updated = await prisma.supportTicket.update({
      where: { id: ticket.id },
      data: {
        status: 'closed',
        closedAt: new Date(),
      },
    });
    await audit({
      actorId: req.user.id,
      action: 'support.close',
      targetType: 'SupportTicket',
      targetId: ticket.id,
      metadata: { reason },
      ipAddress: req.ip,
    });
    emitTicketEvent(req, ticket.id, 'support:closed', { ticketId: ticket.id, reason });
    res.json({ ticket: updated });
  } catch (err) { next(err); }
});

module.exports.adminRouter = adminRouter;
