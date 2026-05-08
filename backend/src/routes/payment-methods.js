// Phase 6.1 — saved (tokenized) payment methods.
//
// Endpoints (all require auth):
//   GET    /api/payment-methods/me              — list active methods for the
//                                                 authenticated user.
//   POST   /api/payment-methods/me/tokenize     — start tokenize flow; returns
//                                                 redirectUrl + state.
//   POST   /api/payment-methods/me/confirm      — finalize after provider
//                                                 redirect. Dev/test mode
//                                                 accepts mockToken in body.
//   POST   /api/payment-methods/:id/default     — set as default (atomic).
//   DELETE /api/payment-methods/:id             — soft-delete (isActive=false).
//
// The provider tokenize call lives in the provider service (services/click.js,
// services/payme.js). In production the provider's webhook will hit a
// per-provider confirm endpoint (TBD); the generic /me/confirm here is the
// dev/test path and the post-redirect "I'm back" path the client calls.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');
const { audit } = require('../lib/audit');
const click = require('../services/click');
const payme = require('../services/payme');

const SUPPORTED_PROVIDERS = new Set(['click', 'payme', 'uzum']);

function sanitize(method) {
  if (!method) return null;
  return {
    id: method.id,
    provider: method.provider,
    brand: method.brand,
    last4: method.last4,
    expiryMonth: method.expiryMonth,
    expiryYear: method.expiryYear,
    isDefault: method.isDefault,
    isActive: method.isActive,
    createdAt: method.createdAt,
  };
}

// ─── GET /api/payment-methods/me ─────────────────────────────────────────────
router.get('/me', authMiddleware, async (req, res, next) => {
  try {
    const methods = await prisma.paymentMethod.findMany({
      where: { userId: req.user.id, isActive: true },
      orderBy: [{ isDefault: 'desc' }, { createdAt: 'desc' }],
    });
    res.json({ items: methods.map(sanitize) });
  } catch (err) { next(err); }
});

// ─── POST /api/payment-methods/me/tokenize ──────────────────────────────────
// Starts the provider tokenization flow. Returns a redirectUrl the client
// opens in a webview; the provider then either calls our webhook or the
// client calls /me/confirm with the resulting token.
router.post('/me/tokenize', authMiddleware, async (req, res, next) => {
  try {
    const { provider } = req.body || {};
    if (!provider || !SUPPORTED_PROVIDERS.has(provider)) {
      return res.status(400).json({ error: 'invalid_provider' });
    }
    let result;
    if (provider === 'click') {
      result = await click.tokenizeCard(req.user.id);
    } else if (provider === 'payme') {
      result = await payme.tokenizeCard(req.user.id);
    } else {
      // Uzum doesn't yet expose a tokenization API in our integration.
      return res.status(400).json({ error: 'provider_tokenization_unavailable' });
    }
    res.json(result);
  } catch (err) { next(err); }
});

// ─── POST /api/payment-methods/me/confirm ───────────────────────────────────
// Persist a saved payment method after the provider redirect.
//
// In dev/test mode the body carries the mockToken+display fields directly.
// In prod this endpoint is the post-redirect "I'm back" hook the app calls;
// the actual webhook from the provider lands at the per-provider callback,
// which writes the row authoritatively. We accept the body params here so
// the dev/test mode and the in-app re-fetch share one code path.
router.post('/me/confirm', authMiddleware, async (req, res, next) => {
  try {
    const { provider, mockToken, providerId, last4, brand, expiryMonth, expiryYear } = req.body || {};
    if (!provider || !SUPPORTED_PROVIDERS.has(provider)) {
      return res.status(400).json({ error: 'invalid_provider' });
    }
    const token = providerId || mockToken;
    if (!token) {
      return res.status(400).json({ error: 'token_required' });
    }

    const created = await prisma.$transaction(async (tx) => {
      const existing = await tx.paymentMethod.findFirst({
        where: { userId: req.user.id, isActive: true },
      });
      const isDefault = !existing; // first method auto-defaults
      return tx.paymentMethod.create({
        data: {
          userId: req.user.id,
          provider,
          providerId: token,
          brand: brand || null,
          last4: last4 ? String(last4).slice(-4) : null,
          expiryMonth: Number.isFinite(Number(expiryMonth)) ? Math.floor(Number(expiryMonth)) : null,
          expiryYear: Number.isFinite(Number(expiryYear)) ? Math.floor(Number(expiryYear)) : null,
          isDefault,
          isActive: true,
        },
      });
    });

    audit({
      actorId: req.user.id,
      action: 'payment_method.create',
      targetType: 'PaymentMethod',
      targetId: created.id,
      metadata: { provider, last4: created.last4 || null },
    });

    res.status(201).json({ method: sanitize(created) });
  } catch (err) { next(err); }
});

// ─── POST /api/payment-methods/:id/default ───────────────────────────────────
// Atomic: unset every other method's `isDefault`, then set this one true.
router.post('/:id/default', authMiddleware, async (req, res, next) => {
  try {
    const id = req.params.id;
    const method = await prisma.paymentMethod.findUnique({ where: { id } });
    if (!method || method.userId !== req.user.id || !method.isActive) {
      return res.status(404).json({ error: 'Not found' });
    }

    await prisma.$transaction(async (tx) => {
      await tx.paymentMethod.updateMany({
        where: { userId: req.user.id, isDefault: true, id: { not: id } },
        data: { isDefault: false },
      });
      await tx.paymentMethod.update({
        where: { id },
        data: { isDefault: true },
      });
    });

    audit({
      actorId: req.user.id,
      action: 'payment_method.set_default',
      targetType: 'PaymentMethod',
      targetId: id,
    });
    const updated = await prisma.paymentMethod.findUnique({ where: { id } });
    res.json({ method: sanitize(updated) });
  } catch (err) { next(err); }
});

// ─── DELETE /api/payment-methods/:id ─────────────────────────────────────────
// Soft-delete: keep history (orders may reference it) but stop showing it
// and prevent further charges.
router.delete('/:id', authMiddleware, async (req, res, next) => {
  try {
    const id = req.params.id;
    const method = await prisma.paymentMethod.findUnique({ where: { id } });
    if (!method || method.userId !== req.user.id) {
      return res.status(404).json({ error: 'Not found' });
    }
    if (!method.isActive) {
      return res.json({ ok: true });
    }
    await prisma.paymentMethod.update({
      where: { id },
      data: { isActive: false, isDefault: false },
    });
    audit({
      actorId: req.user.id,
      action: 'payment_method.delete',
      targetType: 'PaymentMethod',
      targetId: id,
    });
    res.json({ ok: true });
  } catch (err) { next(err); }
});

module.exports = router;
