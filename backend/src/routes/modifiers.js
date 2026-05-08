// Routes for ProductModifierGroup + ProductModifierOption.
// Mounted under '/api' — endpoints declare absolute paths.
//
// Authorization: GETs are public; mutations require shop membership for the
// product's shop, or admin.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');

// ─── Helpers ────────────────────────────────────────────────────────────────
async function isShopMember(userId, shopId) {
  if (!userId || !shopId) return false;
  const m = await prisma.shopMember.findUnique({
    where: { userId_shopId: { userId, shopId } },
  });
  return !!m;
}

// Returns true if the request user is admin or a member of the product's shop.
async function userCanManageProduct(req, productId) {
  if (!req.user) return false;
  if (req.user.isAdmin) return true;
  const product = await prisma.product.findUnique({
    where: { id: productId },
    select: { shopId: true },
  });
  if (!product) return null; // signals "not found" to caller
  return isShopMember(req.user.id, product.shopId);
}

async function userCanManageGroup(req, groupId) {
  if (!req.user) return false;
  const group = await prisma.productModifierGroup.findUnique({
    where: { id: groupId },
    select: { productId: true },
  });
  if (!group) return null;
  return userCanManageProduct(req, group.productId);
}

async function userCanManageOption(req, optionId) {
  if (!req.user) return false;
  const opt = await prisma.productModifierOption.findUnique({
    where: { id: optionId },
    select: { groupId: true },
  });
  if (!opt) return null;
  return userCanManageGroup(req, opt.groupId);
}

function pickGroupFields(b, { partial = false } = {}) {
  const out = {};
  if ('nameUz' in b) out.nameUz = String(b.nameUz);
  if ('nameRu' in b) out.nameRu = String(b.nameRu);
  if ('nameEn' in b) out.nameEn = b.nameEn == null ? null : String(b.nameEn);
  if ('minSelect' in b) out.minSelect = parseInt(b.minSelect, 10);
  if ('maxSelect' in b) out.maxSelect = parseInt(b.maxSelect, 10);
  if ('sortOrder' in b) out.sortOrder = parseInt(b.sortOrder, 10);

  if (!partial) {
    if (out.minSelect == null || isNaN(out.minSelect)) out.minSelect = 0;
    if (out.maxSelect == null || isNaN(out.maxSelect)) out.maxSelect = 1;
    if (out.sortOrder == null || isNaN(out.sortOrder)) out.sortOrder = 0;
  }
  return out;
}

function validateGroupShape(data) {
  const errors = [];
  if (!data.nameUz || !String(data.nameUz).trim()) errors.push('nameUz required');
  if (!data.nameRu || !String(data.nameRu).trim()) errors.push('nameRu required');
  const min = data.minSelect ?? 0;
  const max = data.maxSelect ?? 1;
  if (Number.isNaN(min) || min < 0) errors.push('minSelect must be >= 0');
  if (Number.isNaN(max) || max < 0) errors.push('maxSelect must be >= 0');
  if (min > max) errors.push('minSelect must be <= maxSelect');
  return errors;
}

function pickOptionFields(b, { partial = false } = {}) {
  const out = {};
  if ('nameUz' in b) out.nameUz = String(b.nameUz);
  if ('nameRu' in b) out.nameRu = String(b.nameRu);
  if ('nameEn' in b) out.nameEn = b.nameEn == null ? null : String(b.nameEn);
  if ('priceDelta' in b) out.priceDelta = Number(b.priceDelta);
  if ('isAvailable' in b) out.isAvailable = Boolean(b.isAvailable);
  if ('sortOrder' in b) out.sortOrder = parseInt(b.sortOrder, 10);

  if (!partial) {
    if (out.priceDelta == null || isNaN(out.priceDelta)) out.priceDelta = 0;
    if (out.sortOrder == null || isNaN(out.sortOrder)) out.sortOrder = 0;
    if (out.isAvailable == null) out.isAvailable = true;
  }
  return out;
}

function validateOptionShape(data) {
  const errors = [];
  if (!data.nameUz || !String(data.nameUz).trim()) errors.push('nameUz required');
  if (!data.nameRu || !String(data.nameRu).trim()) errors.push('nameRu required');
  if (data.priceDelta != null && Number.isNaN(Number(data.priceDelta))) {
    errors.push('priceDelta must be a number');
  }
  return errors;
}

// ─── GET /api/products/:productId/modifier-groups ───────────────────────────
// Public — list groups + options sorted by sortOrder.
router.get('/products/:productId/modifier-groups', async (req, res, next) => {
  try {
    const product = await prisma.product.findUnique({
      where: { id: req.params.productId },
      select: { id: true },
    });
    if (!product) return res.status(404).json({ error: 'Product not found' });

    const groups = await prisma.productModifierGroup.findMany({
      where: { productId: req.params.productId },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
      include: {
        options: {
          orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
        },
      },
    });
    res.json({ groups });
  } catch (err) { next(err); }
});

// ─── POST /api/products/:productId/modifier-groups ──────────────────────────
router.post('/products/:productId/modifier-groups', authMiddleware, async (req, res, next) => {
  try {
    const allowed = await userCanManageProduct(req, req.params.productId);
    if (allowed === null) return res.status(404).json({ error: 'Product not found' });
    if (!allowed) return res.status(403).json({ error: 'Not a shop member' });

    const data = pickGroupFields(req.body || {});
    const errors = validateGroupShape(data);
    if (errors.length) return res.status(400).json({ error: errors.join('; ') });

    const group = await prisma.productModifierGroup.create({
      data: { ...data, productId: req.params.productId },
    });
    res.status(201).json({ group });
  } catch (err) { next(err); }
});

// ─── PATCH /api/modifier-groups/:groupId ────────────────────────────────────
router.patch('/modifier-groups/:groupId', authMiddleware, async (req, res, next) => {
  try {
    const allowed = await userCanManageGroup(req, req.params.groupId);
    if (allowed === null) return res.status(404).json({ error: 'Group not found' });
    if (!allowed) return res.status(403).json({ error: 'Not a shop member' });

    const existing = await prisma.productModifierGroup.findUnique({
      where: { id: req.params.groupId },
    });

    const patch = pickGroupFields(req.body || {}, { partial: true });
    // Validate combined min/max against existing values when only one changes.
    const merged = {
      nameUz: patch.nameUz ?? existing.nameUz,
      nameRu: patch.nameRu ?? existing.nameRu,
      minSelect: patch.minSelect ?? existing.minSelect,
      maxSelect: patch.maxSelect ?? existing.maxSelect,
    };
    const errors = validateGroupShape(merged);
    if (errors.length) return res.status(400).json({ error: errors.join('; ') });

    const group = await prisma.productModifierGroup.update({
      where: { id: req.params.groupId },
      data: patch,
    });
    res.json({ group });
  } catch (err) { next(err); }
});

// ─── DELETE /api/modifier-groups/:groupId ───────────────────────────────────
router.delete('/modifier-groups/:groupId', authMiddleware, async (req, res, next) => {
  try {
    const allowed = await userCanManageGroup(req, req.params.groupId);
    if (allowed === null) return res.status(404).json({ error: 'Group not found' });
    if (!allowed) return res.status(403).json({ error: 'Not a shop member' });

    // onDelete:Cascade in schema removes the options too.
    await prisma.productModifierGroup.delete({ where: { id: req.params.groupId } });
    res.json({ deleted: true });
  } catch (err) { next(err); }
});

// ─── POST /api/modifier-groups/:groupId/options ─────────────────────────────
router.post('/modifier-groups/:groupId/options', authMiddleware, async (req, res, next) => {
  try {
    const allowed = await userCanManageGroup(req, req.params.groupId);
    if (allowed === null) return res.status(404).json({ error: 'Group not found' });
    if (!allowed) return res.status(403).json({ error: 'Not a shop member' });

    const data = pickOptionFields(req.body || {});
    const errors = validateOptionShape(data);
    if (errors.length) return res.status(400).json({ error: errors.join('; ') });

    const option = await prisma.productModifierOption.create({
      data: { ...data, groupId: req.params.groupId },
    });
    res.status(201).json({ option });
  } catch (err) { next(err); }
});

// ─── PATCH /api/modifier-options/:optionId ──────────────────────────────────
router.patch('/modifier-options/:optionId', authMiddleware, async (req, res, next) => {
  try {
    const allowed = await userCanManageOption(req, req.params.optionId);
    if (allowed === null) return res.status(404).json({ error: 'Option not found' });
    if (!allowed) return res.status(403).json({ error: 'Not a shop member' });

    const data = pickOptionFields(req.body || {}, { partial: true });
    if ('priceDelta' in data && Number.isNaN(data.priceDelta)) {
      return res.status(400).json({ error: 'priceDelta must be a number' });
    }
    const option = await prisma.productModifierOption.update({
      where: { id: req.params.optionId },
      data,
    });
    res.json({ option });
  } catch (err) { next(err); }
});

// ─── DELETE /api/modifier-options/:optionId ─────────────────────────────────
router.delete('/modifier-options/:optionId', authMiddleware, async (req, res, next) => {
  try {
    const allowed = await userCanManageOption(req, req.params.optionId);
    if (allowed === null) return res.status(404).json({ error: 'Option not found' });
    if (!allowed) return res.status(403).json({ error: 'Not a shop member' });

    await prisma.productModifierOption.delete({ where: { id: req.params.optionId } });
    res.json({ deleted: true });
  } catch (err) { next(err); }
});

module.exports = router;
