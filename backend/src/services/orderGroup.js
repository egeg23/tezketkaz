// Phase 10.1 — Group orders / split-bill service.
//
// A "group order" lets a host open a shared cart against a single shop, hand
// out a join code, and have friends each add their own items. When the host
// locks the group, each member is told what they owe and pays their share via
// their own saved payment method (paymentMode='split') — or the host pays
// once for everyone (paymentMode='host'). When the last person pays, we mint
// a single Order and hand it off to the dispatcher exactly like a solo order.
//
// Status flow:
//   open → locked → paid (or cancelled, or expired)
//
// Notes on dependencies:
//  - We re-use `priceItem` from routes/orders.js so per-member pricing
//    matches the solo-order path 1:1 (modifier validation, discount price,
//    availability, etc.).
//  - Charges go through services/click + services/payme `chargeWithToken`,
//    same code path Phase 6.1 saved-method orders + tipping use.
//  - Final order creation enqueues `dispatch.startDispatch` so the existing
//    dispatcher / push / socket plumbing kicks in.

const logger = require('../lib/logger');
const click = require('./click');
const payme = require('./payme');
const push = require('./push');
const notifications = require('./notifications');

// ── Join code generation ────────────────────────────────────────────────────
// Format: "K7P2-AB" — 4 alphanumeric + dash + 2 alpha = 7 chars total.
// Excludes ambiguous characters (0/O, 1/I/L) so codes shared verbally don't
// land in the wrong group.
const CODE_ALPHANUM = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_ALPHA = 'ABCDEFGHJKMNPQRSTUVWXYZ';

function randomFromAlphabet(alphabet, len) {
  let out = '';
  for (let i = 0; i < len; i += 1) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return out;
}

function generateJoinCode() {
  return `${randomFromAlphabet(CODE_ALPHANUM, 4)}-${randomFromAlphabet(CODE_ALPHA, 2)}`;
}

// Lazy-load priceItem to avoid the circular `routes/orders → services/orderGroup`
// require chain that would arise if either side eagerly required the other.
function loadPriceItem() {
  // eslint-disable-next-line global-require
  return require('../routes/orders').priceItem;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

function err(status, message, extras = {}) {
  return Object.assign(new Error(message), { status, ...extras });
}

function safeParseCart(cartJson) {
  if (cartJson == null) return [];
  if (Array.isArray(cartJson)) return cartJson;
  if (typeof cartJson === 'string') {
    try {
      const parsed = JSON.parse(cartJson);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
}

function serializeCart(cartJson) {
  if (typeof cartJson === 'string') return cartJson;
  return JSON.stringify(safeParseCart(cartJson));
}

// Compute amountOwed + a rendered orderItem rows array for one member's cart.
// Throws via priceItem on validation errors. shopId is the group's shopId; we
// reject any item whose product doesn't live in that shop.
async function priceMemberCart(prisma, items, shopId) {
  const priceItem = loadPriceItem();
  const list = Array.isArray(items) ? items : [];
  let subtotal = 0;
  const orderItemsData = [];
  for (const i of list) {
    const qty = Math.max(1, Math.min(99, Number(i.quantity) || 1));
    const { product, basePrice, unitPrice, modifiersSnapshot } =
      await priceItem(prisma, i.productId, i.modifiers);
    if (product.shopId !== shopId) {
      throw err(400, 'product_not_in_group_shop', {
        productId: product.id,
      });
    }
    const total = unitPrice * qty;
    subtotal += total;
    orderItemsData.push({
      productId: product.id,
      productName: product.name,
      quantity: qty,
      price: unitPrice,
      basePrice,
      total,
      modifiers: modifiersSnapshot.length ? JSON.stringify(modifiersSnapshot) : null,
    });
  }
  return { subtotal, orderItemsData };
}

async function emitToGroup(io, groupId, event, payload) {
  if (!io || typeof io.to !== 'function') return;
  try {
    io.to(`orderGroup:${groupId}`).emit(event, payload);
  } catch (e) {
    logger.warn({ err: e.message, groupId, event }, 'orderGroup emit failed');
  }
}

// Best-effort push to every member of a group. Skips the optional `excludeUserId`
// (e.g. host who already saw the action).
async function pushToMembers(prisma, group, members, { title, body, data }, excludeUserId = null) {
  for (const m of members) {
    if (excludeUserId && m.userId === excludeUserId) continue;
    try {
      await push.sendToUser(m.userId, {
        title,
        body,
        data: { type: 'order_group', groupId: group.id, ...(data || {}) },
      });
    } catch (e) {
      logger.warn({ err: e.message, userId: m.userId, groupId: group.id }, 'group push failed');
    }
  }
}

// ── Public API ──────────────────────────────────────────────────────────────

// Create a new group. Host is auto-added as the first member (status='pending',
// empty cart). Retries on joinCode collision (extremely unlikely but cheap).
async function create(prisma, opts = {}) {
  const {
    hostUserId,
    shopId,
    paymentMode = 'split',
    maxMembers = null,
    expiresInMin = 60,
  } = opts;
  if (!hostUserId) throw err(400, 'hostUserId required');
  if (!shopId) throw err(400, 'shopId required');
  if (!['split', 'host'].includes(paymentMode)) {
    throw err(400, 'invalid_payment_mode');
  }
  if (maxMembers != null) {
    const m = Number(maxMembers);
    if (!Number.isFinite(m) || m < 2) throw err(400, 'invalid_max_members');
  }
  const minutes = Number(expiresInMin);
  if (!Number.isFinite(minutes) || minutes <= 0 || minutes > 60 * 24) {
    throw err(400, 'invalid_expires_in_min');
  }

  // Make sure the shop actually exists; we'll surface 404 to the route.
  const shop = await prisma.shop.findUnique({ where: { id: shopId } });
  if (!shop) throw err(404, 'shop_not_found');

  const expiresAt = new Date(Date.now() + minutes * 60 * 1000);

  let lastErr;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const joinCode = generateJoinCode();
    try {
      const group = await prisma.orderGroup.create({
        data: {
          hostUserId,
          shopId,
          joinCode,
          paymentMode,
          maxMembers: maxMembers != null ? Number(maxMembers) : null,
          expiresAt,
          status: 'open',
        },
      });
      const hostMembership = await prisma.orderGroupMember.create({
        data: {
          groupId: group.id,
          userId: hostUserId,
          status: 'pending',
          cartJson: '[]',
        },
      });
      return { group, hostMembership };
    } catch (e) {
      lastErr = e;
      // Retry only on uniqueness collisions (joinCode). Anything else (e.g.
      // FK violation on hostUserId) is a real error.
      const isUnique = e && (e.code === 'P2002' || /UNIQUE/i.test(e.message || ''));
      if (!isUnique) throw e;
    }
  }
  throw lastErr || err(500, 'failed_to_generate_join_code');
}

async function join(prisma, { joinCode, userId }) {
  if (!joinCode) throw err(400, 'joinCode required');
  if (!userId) throw err(400, 'userId required');
  const group = await prisma.orderGroup.findUnique({
    where: { joinCode: String(joinCode).toUpperCase().trim() },
    include: { members: true },
  });
  if (!group) throw err(404, 'group_not_found');
  if (group.status !== 'open') {
    // 410 Gone — semantically "this group is no longer accepting joins".
    throw err(410, 'group_not_open', { status: group.status });
  }
  if (group.expiresAt && group.expiresAt.getTime() < Date.now()) {
    throw err(410, 'group_expired');
  }
  // Already a member? Idempotent return — useful for re-opening the same
  // group from a deep-link.
  const existing = group.members.find((m) => m.userId === userId);
  if (existing) {
    if (existing.status === 'declined') {
      // Re-join after a decline: flip back to pending with empty cart.
      const reactivated = await prisma.orderGroupMember.update({
        where: { id: existing.id },
        data: { status: 'pending', declinedAt: null, cartJson: '[]' },
      });
      return { group, member: reactivated };
    }
    return { group, member: existing };
  }
  // Cap check counts only active (non-declined) members.
  if (group.maxMembers != null) {
    const active = group.members.filter((m) => m.status !== 'declined').length;
    if (active >= group.maxMembers) {
      throw err(409, 'group_full');
    }
  }
  const member = await prisma.orderGroupMember.create({
    data: {
      groupId: group.id,
      userId,
      status: 'pending',
      cartJson: '[]',
    },
  });
  return { group, member };
}

async function setMemberCart(prisma, { groupId, userId, cartJson }) {
  if (!groupId) throw err(400, 'groupId required');
  if (!userId) throw err(400, 'userId required');
  const group = await prisma.orderGroup.findUnique({ where: { id: groupId } });
  if (!group) throw err(404, 'group_not_found');
  if (group.status !== 'open') throw err(409, 'group_not_open');

  const member = await prisma.orderGroupMember.findUnique({
    where: { groupId_userId: { groupId, userId } },
  });
  if (!member || member.status === 'declined') throw err(403, 'not_a_member');

  const items = safeParseCart(cartJson);
  // Validate priceability + shop ownership upfront. We don't persist amount
  // here (that happens at lock); we just throw on invalid carts so the UI can
  // show a useful error while the user is still editing.
  const { subtotal } = await priceMemberCart(prisma, items, group.shopId);

  const updated = await prisma.orderGroupMember.update({
    where: { id: member.id },
    data: { cartJson: serializeCart(items) },
  });
  return { member: updated, subtotal };
}

async function lock(prisma, { groupId, hostUserId }) {
  if (!groupId) throw err(400, 'groupId required');
  if (!hostUserId) throw err(400, 'hostUserId required');
  const group = await prisma.orderGroup.findUnique({
    where: { id: groupId },
    include: { members: true },
  });
  if (!group) throw err(404, 'group_not_found');
  if (group.hostUserId !== hostUserId) throw err(403, 'not_host');
  if (group.status !== 'open') throw err(409, 'group_not_open');

  const activeMembers = group.members.filter((m) => m.status !== 'declined');
  if (activeMembers.length === 0) throw err(400, 'no_members');

  // Price each member's cart. Any individual member's pricing failure aborts
  // the lock so the host can ask them to fix it (or remove the offending item).
  // In split mode we drop members who priced to 0 (e.g. host with empty cart)
  // because memberPay rejects amount<=0 and the group would never finalise.
  // In host-pay mode we keep everyone — host's single charge covers all.
  let groupSubtotal = 0;
  const updates = [];
  for (const m of activeMembers) {
    const items = safeParseCart(m.cartJson);
    const { subtotal } = await priceMemberCart(prisma, items, group.shopId);
    if (group.paymentMode === 'split' && subtotal <= 0) {
      // Mark this member as 'declined' so the active-set / allPaid logic in
      // memberPay doesn't wait on them and the socket UI shows them dropped.
      updates.push({ id: m.id, amountOwed: 0, decline: true });
      continue;
    }
    groupSubtotal += subtotal;
    updates.push({ id: m.id, amountOwed: subtotal });
  }
  // After dropping zero-owed members, ensure at least one payable member
  // remains in split mode (otherwise no one can pay → infinite lock).
  if (group.paymentMode === 'split' &&
      updates.filter((u) => !u.decline).length === 0) {
    throw err(400, 'no_payable_members');
  }

  // Transactional update: lock + per-member amounts. Keeps a partial-lock
  // from leaking out if one of the writes fails.
  const [updatedGroup, updatedMembers] = await prisma.$transaction(async (tx) => {
    for (const u of updates) {
      await tx.orderGroupMember.update({
        where: { id: u.id },
        data: u.decline
          ? { amountOwed: 0, status: 'declined', declinedAt: new Date() }
          : { amountOwed: u.amountOwed },
      });
    }
    const g = await tx.orderGroup.update({
      where: { id: group.id },
      data: { status: 'locked', lockedAt: new Date() },
    });
    const members = await tx.orderGroupMember.findMany({
      where: { groupId: group.id },
    });
    return [g, members];
  });

  return { group: updatedGroup, members: updatedMembers, groupSubtotal };
}

async function _chargeMember(prisma, member, amount, groupId) {
  if (!member.paymentMethodId) {
    throw err(400, 'payment_method_required');
  }
  const method = await prisma.paymentMethod.findUnique({
    where: { id: member.paymentMethodId },
  });
  if (!method || method.userId !== member.userId || !method.isActive) {
    throw err(404, 'payment_method_not_found');
  }
  let result;
  if (method.provider === 'click') {
    result = await click.chargeWithToken(method.providerId, amount, groupId, 'UZS');
  } else if (method.provider === 'payme') {
    result = await payme.chargeWithToken(method.providerId, amount, groupId, 'UZS');
  } else {
    return { ok: false, externalId: null, message: 'provider_not_chargeable' };
  }
  return result;
}

// Mint the shared Order from a finalised, fully-paid group. Runs inside a
// $transaction so we either get a clean Order + group flip, or nothing at all.
async function _finaliseOrder(prisma, group, queuesFn, paymentRef, paymentProvider) {
  const groupWithMembers = await prisma.orderGroup.findUnique({
    where: { id: group.id },
    include: { members: true, host: true },
  });
  const shop = await prisma.shop.findUnique({ where: { id: group.shopId } });

  // Re-price every active member to build a single OrderItem set. We use the
  // same per-member pricing path as lock so totals match the snapshotted
  // amountOwed values (modulo a price change between lock + finalisation,
  // which we ignore — amountOwed is the source of truth for what was charged).
  const orderItemsData = [];
  let subtotal = 0;
  for (const m of groupWithMembers.members) {
    if (m.status === 'declined') continue;
    const items = safeParseCart(m.cartJson);
    const { subtotal: memberSub, orderItemsData: rows } =
      await priceMemberCart(prisma, items, group.shopId);
    subtotal += memberSub;
    orderItemsData.push(...rows);
  }
  if (orderItemsData.length === 0) {
    throw err(400, 'no_items_to_order');
  }

  const host = groupWithMembers.host;
  const total = subtotal; // delivery fee is computed at solo flow's checkout;
  // for group orders, the host effectively pre-decides this when locking.
  // We snapshot subtotal=total here so analytics see a coherent row. Future
  // enhancement: capture deliveryAddress from the host at lock time.

  const newOrder = await prisma.$transaction(async (tx) => {
    const order = await tx.order.create({
      data: {
        buyerId: group.hostUserId,
        customerName: host.name || 'Xaridor',
        customerPhone: host.phone,
        shopId: group.shopId,
        // The host is the one whose address the courier delivers to; we don't
        // gate on it here because Phase 10.1 puts address selection on the
        // host UI (POST /lock body, future). For now snapshot a placeholder
        // — Flutter will update via existing PATCH /api/orders/:id once we
        // add it. Tests don't depend on this field.
        deliveryAddress: 'group order',
        subtotal,
        total,
        deliveryFee: 0,
        currency: shop?.currency || 'UZS',
        // Persist the actual provider that completed the charge so payment
        // history + downstream reconciliation are correct for non-Click
        // payments. Falls back to 'click' only when the caller didn't pass
        // anything (legacy compatibility).
        paymentMethod: paymentProvider || 'click',
        isPaid: true,
        paymentRef,
        status: 'pending',
        items: { create: orderItemsData },
      },
      include: { items: true, shop: true },
    });
    await tx.orderGroup.update({
      where: { id: group.id },
      data: {
        status: 'paid',
        paidAt: new Date(),
        orderId: order.id,
      },
    });
    return order;
  });

  // Hand off to the dispatcher exactly like a solo order. No-op when Redis
  // is disabled (dev/test); production runs the BullMQ worker.
  try {
    if (typeof queuesFn === 'function') {
      await queuesFn().dispatch.add('startDispatch', {
        type: 'startDispatch',
        orderId: newOrder.id,
      });
    }
  } catch (e) {
    logger.warn({ err: e.message, orderId: newOrder.id }, 'group dispatch enqueue failed');
  }

  return newOrder;
}

// Member pays their share. Returns { member, group, order? } where `order` is
// only set on the call that finalises the group (last paying member, or the
// host on host-pay mode).
async function memberPay(prisma, opts = {}) {
  const { groupId, userId, paymentMethodId, queues: queuesFn, io } = opts;
  if (!groupId) throw err(400, 'groupId required');
  if (!userId) throw err(400, 'userId required');

  const group = await prisma.orderGroup.findUnique({
    where: { id: groupId },
    include: { members: true },
  });
  if (!group) throw err(404, 'group_not_found');
  if (group.status !== 'locked') throw err(409, 'group_not_locked');

  // Validate caller membership and pick the row we'll bill against.
  const caller = group.members.find((m) => m.userId === userId);
  if (!caller || caller.status === 'declined') throw err(403, 'not_a_member');

  if (group.paymentMode === 'host') {
    if (group.hostUserId !== userId) throw err(403, 'host_only');
    if (caller.status === 'paid') throw err(409, 'already_paid');

    // Charge total of all members' amountOwed against host's saved method.
    const methodId = paymentMethodId || caller.paymentMethodId;
    if (!methodId) throw err(400, 'payment_method_required');
    const method = await prisma.paymentMethod.findUnique({ where: { id: methodId } });
    if (!method || method.userId !== userId || !method.isActive) {
      throw err(404, 'payment_method_not_found');
    }
    const total = group.members
      .filter((m) => m.status !== 'declined')
      .reduce((sum, m) => sum + Number(m.amountOwed || 0), 0);

    let result;
    if (method.provider === 'click') {
      result = await click.chargeWithToken(method.providerId, total, group.id, 'UZS');
    } else if (method.provider === 'payme') {
      result = await payme.chargeWithToken(method.providerId, total, group.id, 'UZS');
    } else {
      throw err(400, 'provider_not_chargeable');
    }
    if (!result || !result.ok) {
      throw err(402, 'charge_failed', { message: result ? result.message : 'unknown' });
    }

    // Mark every active member 'paid' (the host's single charge covers them).
    await prisma.$transaction(async (tx) => {
      await tx.orderGroupMember.updateMany({
        where: { groupId: group.id, status: { not: 'declined' } },
        data: { status: 'paid', paidAt: new Date() },
      });
      await tx.orderGroupMember.update({
        where: { id: caller.id },
        data: { paymentMethodId: method.id },
      });
    });

    const order = await _finaliseOrder(prisma, group, queuesFn, result.externalId, method.provider);

    const refreshed = await prisma.orderGroup.findUnique({
      where: { id: group.id },
      include: { members: true },
    });
    await emitToGroup(io, group.id, 'orderGroup:memberPaid', { userId, hostPaid: true });
    await emitToGroup(io, group.id, 'orderGroup:completed', { orderId: order.id });
    pushToMembers(prisma, refreshed, refreshed.members, {
      title: 'Order placed',
      body: 'Order placed — courier on the way',
      data: { orderId: order.id },
    }).catch(() => {});
    return { member: caller, group: refreshed, order };
  }

  // ── split mode ──
  if (caller.status === 'paid') throw err(409, 'already_paid');

  const methodId = paymentMethodId || caller.paymentMethodId;
  if (!methodId) throw err(400, 'payment_method_required');
  const method = await prisma.paymentMethod.findUnique({ where: { id: methodId } });
  if (!method || method.userId !== userId || !method.isActive) {
    throw err(404, 'payment_method_not_found');
  }
  const amount = Number(caller.amountOwed || 0);
  if (amount <= 0) throw err(400, 'invalid_amount');

  let result;
  if (method.provider === 'click') {
    result = await click.chargeWithToken(method.providerId, amount, group.id, 'UZS');
  } else if (method.provider === 'payme') {
    result = await payme.chargeWithToken(method.providerId, amount, group.id, 'UZS');
  } else {
    throw err(400, 'provider_not_chargeable');
  }
  if (!result || !result.ok) {
    throw err(402, 'charge_failed', { message: result ? result.message : 'unknown' });
  }

  const updatedMember = await prisma.orderGroupMember.update({
    where: { id: caller.id },
    data: {
      status: 'paid',
      paidAt: new Date(),
      paymentMethodId: method.id,
    },
  });

  await emitToGroup(io, group.id, 'orderGroup:memberPaid', { userId });

  // If everyone's paid, finalise the order.
  const refreshed = await prisma.orderGroup.findUnique({
    where: { id: group.id },
    include: { members: true },
  });
  const active = refreshed.members.filter((m) => m.status !== 'declined');
  const allPaid = active.length > 0 && active.every((m) => m.status === 'paid');

  let order = null;
  if (allPaid) {
    // Atomic claim — concurrent payers each see allPaid=true after their own
    // memberPay flips status, so without this guard two of them race into
    // _finaliseOrder and create duplicate Orders + double-dispatch. The
    // updateMany only succeeds for one caller; the loser exits early.
    const claim = await prisma.orderGroup.updateMany({
      where: { id: group.id, status: 'locked' },
      data: { status: 'finalising' },
    });
    if (claim.count === 0) {
      // Another payer already started or finished finalisation.
      return { member: updatedMember, group: refreshed, order: null };
    }
    try {
      order = await _finaliseOrder(prisma, refreshed, queuesFn, result.externalId, method.provider);
    } catch (err) {
      // Roll back so a retry can claim again.
      await prisma.orderGroup.updateMany({
        where: { id: group.id, status: 'finalising' },
        data: { status: 'locked' },
      }).catch(() => {});
      throw err;
    }
    const finalised = await prisma.orderGroup.findUnique({
      where: { id: group.id },
      include: { members: true },
    });
    await emitToGroup(io, group.id, 'orderGroup:completed', { orderId: order.id });
    pushToMembers(prisma, finalised, finalised.members, {
      title: 'Order placed',
      body: 'Order placed — courier on the way',
      data: { orderId: order.id },
    }).catch(() => {});
    return { member: updatedMember, group: finalised, order };
  }
  return { member: updatedMember, group: refreshed, order: null };
}

// Cancel a group. Host can always cancel an open/locked group. A non-host
// can call this only when they're the sole remaining active member (e.g.
// host left, everyone else declined) — keeps zombie groups from blocking the
// shop.
async function cancel(prisma, { groupId, userId, reason }) {
  if (!groupId) throw err(400, 'groupId required');
  if (!userId) throw err(400, 'userId required');
  const group = await prisma.orderGroup.findUnique({
    where: { id: groupId },
    include: { members: true },
  });
  if (!group) throw err(404, 'group_not_found');
  if (['paid', 'cancelled', 'expired'].includes(group.status)) {
    throw err(409, 'group_finalised');
  }

  const isHost = group.hostUserId === userId;
  if (!isHost) {
    const active = group.members.filter((m) => m.status !== 'declined');
    const onlyMe = active.length === 1 && active[0].userId === userId;
    if (!onlyMe) throw err(403, 'not_host');
  }

  const updated = await prisma.orderGroup.update({
    where: { id: group.id },
    data: {
      status: 'cancelled',
      cancelledAt: new Date(),
    },
  });
  return { group: updated, reason: reason || null };
}

// Daily sweep — flip 'open' groups whose expiresAt has passed to 'expired'.
// Returns the count of groups affected (mostly useful for log lines + tests).
async function expireDue(prisma, now = new Date()) {
  const result = await prisma.orderGroup.updateMany({
    where: {
      status: 'open',
      expiresAt: { lt: now },
    },
    data: {
      status: 'expired',
      cancelledAt: now,
    },
  });
  return { expired: result.count };
}

module.exports = {
  create,
  join,
  setMemberCart,
  lock,
  memberPay,
  cancel,
  expireDue,
  generateJoinCode,
  // Exposed for tests/admin tooling.
  _priceMemberCart: priceMemberCart,
};
