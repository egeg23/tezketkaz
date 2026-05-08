// Phase 10.1 — Group orders / split-bill HTTP routes.
//
// Mounted at /api/order-groups in src/index.js (after products, before
// payments). Auth-gated; mostly delegates to services/orderGroup.js for the
// actual logic. The route layer just maps Errors with `status` to HTTP
// responses and adds the membership-read guard for read endpoints.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const logger = require('../lib/logger');
const { queues } = require('../lib/queues');
const orderGroup = require('../services/orderGroup');

// Translate service-layer errors (with `status`) into JSON responses.
function send(res, err) {
  const status = err.status || err.statusCode || 500;
  const body = { error: err.message || 'Server error' };
  if (err.message && /charge_failed/.test(err.message) && err.message_) {
    body.message = err.message_;
  }
  return res.status(status).json(body);
}

// Hydrate a group's host name + member basics for buyer-facing list/detail.
async function loadGroupForUser(groupId, userId) {
  const group = await prisma.orderGroup.findUnique({
    where: { id: groupId },
    include: {
      host: { select: { id: true, name: true, phone: true } },
      members: {
        include: {
          user: { select: { id: true, name: true, phone: true } },
        },
        orderBy: { joinedAt: 'asc' },
      },
    },
  });
  if (!group) return { group: null, member: null };
  const member = group.members.find((m) => m.userId === userId) || null;
  return { group, member };
}

// ── POST /api/order-groups ─────────────────────────────────────────────────
// Host opens a new group order. Body: { shopId, paymentMode?, maxMembers?,
// expiresInMin? }.
router.post('/', authMiddleware, async (req, res) => {
  try {
    const { shopId, paymentMode, maxMembers, expiresInMin } = req.body || {};
    const result = await orderGroup.create(prisma, {
      hostUserId: req.user.id,
      shopId,
      paymentMode,
      maxMembers,
      expiresInMin,
    });
    audit({
      actorId: req.user.id,
      action: 'order_group.create',
      targetType: 'OrderGroup',
      targetId: result.group.id,
      metadata: { shopId, joinCode: result.group.joinCode, paymentMode: result.group.paymentMode },
    });
    res.status(201).json({ group: result.group, hostMembership: result.hostMembership });
  } catch (err) {
    return send(res, err);
  }
});

// ── GET /api/order-groups/me ───────────────────────────────────────────────
// Lists every group the caller hosts or is a member of. Most-recent first.
router.get('/me', authMiddleware, async (req, res) => {
  try {
    const memberships = await prisma.orderGroupMember.findMany({
      where: { userId: req.user.id },
      orderBy: { joinedAt: 'desc' },
      include: {
        group: {
          include: {
            host: { select: { id: true, name: true } },
            members: { select: { id: true, userId: true, status: true, amountOwed: true } },
          },
        },
      },
    });
    res.json({
      groups: memberships.map((m) => ({
        membership: {
          id: m.id,
          status: m.status,
          amountOwed: m.amountOwed,
          joinedAt: m.joinedAt,
          paidAt: m.paidAt,
        },
        group: m.group,
      })),
    });
  } catch (err) {
    logger.warn({ err: err.message }, 'order-groups list failed');
    res.status(500).json({ error: 'Server error' });
  }
});

// ── POST /api/order-groups/join ────────────────────────────────────────────
// Body: { joinCode }. Friend joins via shared code.
router.post('/join', authMiddleware, async (req, res) => {
  try {
    const { joinCode } = req.body || {};
    if (!joinCode) return res.status(400).json({ error: 'joinCode required' });
    const result = await orderGroup.join(prisma, {
      joinCode,
      userId: req.user.id,
    });
    audit({
      actorId: req.user.id,
      action: 'order_group.join',
      targetType: 'OrderGroup',
      targetId: result.group.id,
      metadata: { joinCode },
    });

    // Notify the host's room about the new member.
    try {
      const io = req.app.get('io');
      if (io) {
        io.to(`orderGroup:${result.group.id}`).emit('orderGroup:memberJoined', {
          member: result.member,
        });
      }
    } catch (_e) { /* noop */ }

    res.status(201).json({ group: result.group, member: result.member });
  } catch (err) {
    return send(res, err);
  }
});

// ── GET /api/order-groups/:groupId ─────────────────────────────────────────
// Membership-gated detail view. Anyone who's a member (incl. host) can read.
router.get('/:groupId', authMiddleware, async (req, res) => {
  try {
    const { group, member } = await loadGroupForUser(req.params.groupId, req.user.id);
    if (!group) return res.status(404).json({ error: 'group_not_found' });
    if (!member && group.hostUserId !== req.user.id) {
      return res.status(403).json({ error: 'not_a_member' });
    }
    res.json({ group, member });
  } catch (err) {
    logger.warn({ err: err.message }, 'order-groups detail failed');
    res.status(500).json({ error: 'Server error' });
  }
});

// ── POST /api/order-groups/:groupId/cancel ─────────────────────────────────
// Host (or sole-remaining member) cancels.
router.post('/:groupId/cancel', authMiddleware, async (req, res) => {
  try {
    const { reason } = req.body || {};
    const result = await orderGroup.cancel(prisma, {
      groupId: req.params.groupId,
      userId: req.user.id,
      reason,
    });
    audit({
      actorId: req.user.id,
      action: 'order_group.cancel',
      targetType: 'OrderGroup',
      targetId: result.group.id,
      metadata: { reason },
    });
    try {
      const io = req.app.get('io');
      if (io) {
        io.to(`orderGroup:${result.group.id}`).emit('orderGroup:cancelled', {
          reason: reason || null,
        });
      }
    } catch (_e) { /* noop */ }
    res.json({ group: result.group });
  } catch (err) {
    return send(res, err);
  }
});

// ── POST /api/order-groups/:groupId/leave ──────────────────────────────────
// Member declines / drops out of the group. Host can't leave their own group
// (they should cancel instead).
router.post('/:groupId/leave', authMiddleware, async (req, res) => {
  try {
    const group = await prisma.orderGroup.findUnique({
      where: { id: req.params.groupId },
    });
    if (!group) return res.status(404).json({ error: 'group_not_found' });
    if (group.hostUserId === req.user.id) {
      return res.status(400).json({ error: 'host_cannot_leave' });
    }
    if (!['open', 'locked'].includes(group.status)) {
      return res.status(409).json({ error: 'group_not_open' });
    }
    const member = await prisma.orderGroupMember.findUnique({
      where: { groupId_userId: { groupId: group.id, userId: req.user.id } },
    });
    if (!member) return res.status(403).json({ error: 'not_a_member' });
    if (member.status === 'paid') {
      return res.status(409).json({ error: 'already_paid' });
    }
    const updated = await prisma.orderGroupMember.update({
      where: { id: member.id },
      data: { status: 'declined', declinedAt: new Date() },
    });
    try {
      const io = req.app.get('io');
      if (io) {
        io.to(`orderGroup:${group.id}`).emit('orderGroup:memberJoined', {
          member: updated,
        });
      }
    } catch (_e) { /* noop */ }
    res.json({ member: updated });
  } catch (err) {
    logger.warn({ err: err.message }, 'order-groups leave failed');
    res.status(500).json({ error: 'Server error' });
  }
});

// ── PATCH /api/order-groups/:groupId/me/cart ───────────────────────────────
// Member updates their own cart while group is 'open'. Body: { cartJson }.
router.patch('/:groupId/me/cart', authMiddleware, async (req, res) => {
  try {
    const { cartJson } = req.body || {};
    const result = await orderGroup.setMemberCart(prisma, {
      groupId: req.params.groupId,
      userId: req.user.id,
      cartJson,
    });
    try {
      const io = req.app.get('io');
      if (io) {
        io.to(`orderGroup:${req.params.groupId}`).emit('orderGroup:cartUpdated', {
          userId: req.user.id,
          cartJson: result.member.cartJson,
          amountSubtotal: result.subtotal,
        });
      }
    } catch (_e) { /* noop */ }
    res.json({ member: result.member, subtotal: result.subtotal });
  } catch (err) {
    return send(res, err);
  }
});

// ── POST /api/order-groups/:groupId/lock ───────────────────────────────────
// Host locks the group. Per-member amounts are computed and snapshotted.
router.post('/:groupId/lock', authMiddleware, async (req, res) => {
  try {
    const result = await orderGroup.lock(prisma, {
      groupId: req.params.groupId,
      hostUserId: req.user.id,
    });
    audit({
      actorId: req.user.id,
      action: 'order_group.lock',
      targetType: 'OrderGroup',
      targetId: result.group.id,
      metadata: { groupSubtotal: result.groupSubtotal },
    });
    try {
      const io = req.app.get('io');
      if (io) {
        io.to(`orderGroup:${result.group.id}`).emit('orderGroup:locked', {
          group: result.group,
          members: result.members,
        });
      }
    } catch (_e) { /* noop */ }
    res.json({ group: result.group, members: result.members, groupSubtotal: result.groupSubtotal });
  } catch (err) {
    return send(res, err);
  }
});

// ── POST /api/order-groups/:groupId/me/pay ─────────────────────────────────
// Member confirms payment for their share via saved card.
// Body: { paymentMethodId }
router.post('/:groupId/me/pay', authMiddleware, async (req, res) => {
  try {
    const group = await prisma.orderGroup.findUnique({
      where: { id: req.params.groupId },
    });
    if (!group) return res.status(404).json({ error: 'group_not_found' });
    if (group.paymentMode === 'host') {
      // The host-pay endpoint is the right one to use here; reject to keep
      // payment semantics unambiguous.
      return res.status(400).json({ error: 'use_host_pay_endpoint' });
    }
    const { paymentMethodId } = req.body || {};
    const result = await orderGroup.memberPay(prisma, {
      groupId: req.params.groupId,
      userId: req.user.id,
      paymentMethodId,
      queues,
      io: req.app.get('io'),
    });
    audit({
      actorId: req.user.id,
      action: 'order_group.member_pay',
      targetType: 'OrderGroup',
      targetId: req.params.groupId,
      metadata: { amount: result.member.amountOwed, paymentMethodId },
    });
    res.json({
      member: result.member,
      group: result.group,
      order: result.order || null,
    });
  } catch (err) {
    return send(res, err);
  }
});

// ── POST /api/order-groups/:groupId/host-pay ───────────────────────────────
// Host pays the entire group total in one charge. Only valid in
// paymentMode='host'.
router.post('/:groupId/host-pay', authMiddleware, async (req, res) => {
  try {
    const group = await prisma.orderGroup.findUnique({
      where: { id: req.params.groupId },
    });
    if (!group) return res.status(404).json({ error: 'group_not_found' });
    if (group.hostUserId !== req.user.id) {
      return res.status(403).json({ error: 'not_host' });
    }
    if (group.paymentMode !== 'host') {
      return res.status(400).json({ error: 'not_host_pay_mode' });
    }
    const { paymentMethodId } = req.body || {};
    const result = await orderGroup.memberPay(prisma, {
      groupId: req.params.groupId,
      userId: req.user.id,
      paymentMethodId,
      queues,
      io: req.app.get('io'),
    });
    audit({
      actorId: req.user.id,
      action: 'order_group.host_pay',
      targetType: 'OrderGroup',
      targetId: req.params.groupId,
      metadata: { paymentMethodId },
    });
    res.json({
      member: result.member,
      group: result.group,
      order: result.order || null,
    });
  } catch (err) {
    return send(res, err);
  }
});

module.exports = router;
