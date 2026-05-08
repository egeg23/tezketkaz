// Hierarchical category CRUD (Phase 1).
//
// Public reads (list / tree / one), admin-only writes. Tree depth is capped at
// 4 to keep traversal cheap on SQLite.

const router = require('express').Router();
const prisma = require('../db');
const { authMiddleware, requireAdmin } = require('../middleware/auth');

const MAX_TREE_DEPTH = 4;

// ─── Helpers ────────────────────────────────────────────────────────────────
function pickCategoryFields(input) {
  const out = {};
  const fields = [
    'vertical', 'slug', 'nameUz', 'nameRu', 'nameEn',
    'parentId', 'shopId', 'iconUrl', 'sortOrder', 'isActive',
  ];
  for (const k of fields) {
    if (input[k] !== undefined) out[k] = input[k];
  }
  if (out.sortOrder !== undefined) {
    out.sortOrder = parseInt(out.sortOrder, 10) || 0;
  }
  if (out.isActive !== undefined) out.isActive = Boolean(out.isActive);
  // Empty strings → null for optional FKs
  if (out.parentId === '') out.parentId = null;
  if (out.shopId === '') out.shopId = null;
  if (out.iconUrl === '') out.iconUrl = null;
  if (out.nameEn === '') out.nameEn = null;
  return out;
}

function validateCreate(p) {
  const errors = [];
  if (!p.vertical || !String(p.vertical).trim()) errors.push('vertical required');
  if (!p.slug || !String(p.slug).trim()) errors.push('slug required');
  if (!p.nameUz || !String(p.nameUz).trim()) errors.push('nameUz required');
  if (!p.nameRu || !String(p.nameRu).trim()) errors.push('nameRu required');
  return errors;
}

// Build a nested tree from a flat list. Each node gets a `children` array.
function buildTree(rows, productCounts) {
  const byId = new Map();
  for (const r of rows) {
    byId.set(r.id, {
      id: r.id,
      slug: r.slug,
      nameUz: r.nameUz,
      nameRu: r.nameRu,
      nameEn: r.nameEn,
      iconUrl: r.iconUrl,
      sortOrder: r.sortOrder,
      vertical: r.vertical,
      parentId: r.parentId,
      productCount: productCounts.get(r.id) || 0,
      children: [],
    });
  }

  const roots = [];
  for (const r of rows) {
    const node = byId.get(r.id);
    if (r.parentId && byId.has(r.parentId)) {
      byId.get(r.parentId).children.push(node);
    } else {
      roots.push(node);
    }
  }

  // Cap depth to MAX_TREE_DEPTH (root = depth 1).
  function trim(node, depth) {
    if (depth >= MAX_TREE_DEPTH) {
      node.children = [];
      return;
    }
    node.children.sort(
      (a, b) => a.sortOrder - b.sortOrder || a.nameRu.localeCompare(b.nameRu),
    );
    for (const c of node.children) trim(c, depth + 1);
  }
  roots.sort(
    (a, b) => a.sortOrder - b.sortOrder || a.nameRu.localeCompare(b.nameRu),
  );
  for (const r of roots) trim(r, 1);
  return roots;
}

// ─── GET /api/categories ────────────────────────────────────────────────────
router.get('/', async (req, res, next) => {
  try {
    const { vertical, parentId, shopId, top } = req.query;
    const where = { isActive: true };
    if (vertical) where.vertical = vertical;
    if (shopId !== undefined) {
      where.shopId = shopId === '' || shopId === 'null' ? null : shopId;
    }

    if (parentId === 'null' || (parentId === undefined && top === '1')) {
      where.parentId = null;
    } else if (parentId !== undefined) {
      where.parentId = parentId;
    }

    const items = await prisma.category.findMany({
      where,
      orderBy: [{ sortOrder: 'asc' }, { nameRu: 'asc' }],
      include: { _count: { select: { products: true } } },
    });

    res.json({ categories: items });
  } catch (err) { next(err); }
});

// ─── GET /api/categories/tree ───────────────────────────────────────────────
router.get('/tree', async (req, res, next) => {
  try {
    const { vertical, shopId } = req.query;
    const where = { isActive: true };
    if (vertical) where.vertical = vertical;
    if (shopId !== undefined) {
      where.shopId = shopId === '' || shopId === 'null' ? null : shopId;
    }

    const rows = await prisma.category.findMany({
      where,
      orderBy: [{ sortOrder: 'asc' }, { nameRu: 'asc' }],
    });

    // Compute product counts for all category ids in one groupBy.
    const ids = rows.map((r) => r.id);
    const counts = new Map();
    if (ids.length > 0) {
      const grouped = await prisma.product.groupBy({
        by: ['categoryId'],
        where: { categoryId: { in: ids } },
        _count: { _all: true },
      });
      for (const g of grouped) {
        if (g.categoryId) counts.set(g.categoryId, g._count._all);
      }
    }

    const tree = buildTree(rows, counts);
    res.json({ tree });
  } catch (err) { next(err); }
});

// ─── GET /api/categories/:id ────────────────────────────────────────────────
router.get('/:id', async (req, res, next) => {
  try {
    const cat = await prisma.category.findUnique({
      where: { id: req.params.id },
      include: { _count: { select: { products: true, children: true } } },
    });
    if (!cat) return res.status(404).json({ error: 'Category not found' });
    res.json({ category: cat });
  } catch (err) { next(err); }
});

// ─── POST /api/categories ───────────────────────────────────────────────────
router.post('/', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const data = pickCategoryFields(req.body);
    const errors = validateCreate(data);
    if (errors.length) return res.status(400).json({ error: errors.join('; ') });

    if (data.parentId) {
      const parent = await prisma.category.findUnique({ where: { id: data.parentId } });
      if (!parent) return res.status(400).json({ error: 'parentId does not exist' });
    }

    // SQLite treats NULL as distinct in unique indexes, so global categories
    // (shopId=null) bypass the (slug, shopId) constraint. Pre-check explicitly.
    const dupe = await prisma.category.findFirst({
      where: { slug: data.slug, shopId: data.shopId ?? null },
    });
    if (dupe) {
      return res.status(409).json({ error: 'slug already exists for this shop' });
    }

    try {
      const created = await prisma.category.create({ data });
      return res.status(201).json({ category: created });
    } catch (e) {
      if (e.code === 'P2002') {
        return res.status(409).json({ error: 'slug already exists for this shop' });
      }
      throw e;
    }
  } catch (err) { next(err); }
});

// ─── PATCH /api/categories/:id ──────────────────────────────────────────────
router.patch('/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const existing = await prisma.category.findUnique({ where: { id: req.params.id } });
    if (!existing) return res.status(404).json({ error: 'Category not found' });

    const data = pickCategoryFields(req.body);

    if (data.parentId && data.parentId === req.params.id) {
      return res.status(400).json({ error: 'Category cannot be its own parent' });
    }
    if (data.parentId) {
      const parent = await prisma.category.findUnique({ where: { id: data.parentId } });
      if (!parent) return res.status(400).json({ error: 'parentId does not exist' });
    }

    // Pre-check slug uniqueness (NULL-aware, see POST comment).
    if (data.slug !== undefined) {
      const targetShopId = data.shopId !== undefined ? data.shopId : existing.shopId;
      const dupe = await prisma.category.findFirst({
        where: {
          slug: data.slug,
          shopId: targetShopId ?? null,
          NOT: { id: req.params.id },
        },
      });
      if (dupe) {
        return res.status(409).json({ error: 'slug already exists for this shop' });
      }
    }

    try {
      const updated = await prisma.category.update({
        where: { id: req.params.id },
        data,
      });
      return res.json({ category: updated });
    } catch (e) {
      if (e.code === 'P2002') {
        return res.status(409).json({ error: 'slug already exists for this shop' });
      }
      throw e;
    }
  } catch (err) { next(err); }
});

// ─── DELETE /api/categories/:id ─────────────────────────────────────────────
router.delete('/:id', authMiddleware, requireAdmin, async (req, res, next) => {
  try {
    const existing = await prisma.category.findUnique({
      where: { id: req.params.id },
      include: { _count: { select: { products: true, children: true } } },
    });
    if (!existing) return res.status(404).json({ error: 'Category not found' });

    if (existing._count.children > 0) {
      return res.status(409).json({
        error: 'Category has children — delete or reassign them first',
        reason: 'has_children',
        childrenCount: existing._count.children,
      });
    }
    if (existing._count.products > 0) {
      return res.status(409).json({
        error: 'Category has products — reassign them first',
        reason: 'has_products',
        productCount: existing._count.products,
      });
    }

    await prisma.category.delete({ where: { id: req.params.id } });
    res.json({ deleted: true });
  } catch (err) { next(err); }
});

module.exports = router;
