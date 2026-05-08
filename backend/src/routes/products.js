const router = require('express').Router();
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const xlsx = require('xlsx');
const prisma = require('../db');
const { authMiddleware } = require('../middleware/auth');

// ─── Upload setup ───────────────────────────────────────────────────────────
const UPLOAD_ROOT = path.resolve(__dirname, '../../uploads');
fs.mkdirSync(path.join(UPLOAD_ROOT, 'products'), { recursive: true });

const imageStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, path.join(UPLOAD_ROOT, 'products')),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase().replace(/[^a-z0-9.]/g, '') || '.jpg';
    cb(null, `${Date.now()}-${Math.random().toString(36).slice(2, 8)}${ext}`);
  },
});
const uploadImage = multer({
  storage: imageStorage,
  limits: { fileSize: 8 * 1024 * 1024 }, // 8 MB
  fileFilter: (req, file, cb) => {
    if (!/^image\/(jpeg|png|webp|gif)$/.test(file.mimetype)) {
      return cb(new Error('Only JPEG/PNG/WebP/GIF allowed'));
    }
    cb(null, true);
  },
});

const uploadSheet = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

// ─── Helpers ────────────────────────────────────────────────────────────────
async function requireShopMember(req, shopId) {
  const member = await prisma.shopMember.findUnique({
    where: { userId_shopId: { userId: req.user.id, shopId } },
  });
  return !!member;
}

const ALLOWED_FIELDS = [
  'name', 'nameUz', 'description', 'ingredients',
  'price', 'discountPrice', 'unit', 'category',
  'imageUrl', 'isAvailable', 'stock',
  'categoryId',
];

function pickProductFields(input) {
  const out = {};
  for (const k of ALLOWED_FIELDS) {
    if (input[k] !== undefined) out[k] = input[k];
  }
  // Coerce numeric fields
  if (out.price !== undefined) out.price = Number(out.price);
  if (out.discountPrice === '' || out.discountPrice === null) out.discountPrice = null;
  else if (out.discountPrice !== undefined) out.discountPrice = Number(out.discountPrice);
  if (out.stock !== undefined) out.stock = parseInt(out.stock, 10) || 0;
  if (out.isAvailable !== undefined) out.isAvailable = Boolean(out.isAvailable);
  if (out.categoryId === '' || out.categoryId === null) out.categoryId = null;
  return out;
}

// Lower-cased composite of name + nameUz + description for LIKE-search.
function buildSearchText(p) {
  const parts = [p.name, p.nameUz, p.description].filter(Boolean).map((s) => String(s));
  return parts.join(' ').toLowerCase();
}

// Decode a base64url-ish JSON cursor; returns null on any failure.
function decodeCursor(cursor) {
  if (!cursor) return null;
  try {
    const json = Buffer.from(String(cursor), 'base64').toString('utf8');
    return JSON.parse(json);
  } catch {
    return null;
  }
}
function encodeCursor(obj) {
  return Buffer.from(JSON.stringify(obj), 'utf8').toString('base64');
}

function validateProduct(p) {
  const errors = [];
  if (!p.name || !String(p.name).trim()) errors.push('name required');
  if (!p.nameUz || !String(p.nameUz).trim()) errors.push('nameUz required');
  if (p.price == null || isNaN(p.price) || p.price < 0) errors.push('price must be positive number');
  if (!p.unit) errors.push('unit required (кг/шт/л)');
  if (!p.category) errors.push('category required');
  if (!p.imageUrl) errors.push('imageUrl required (use placeholder if no image)');
  return errors;
}

// ─── GET /api/products ──────────────────────────────────────────────────────
// Public catalogue. Supports filtering, search, sort, cursor pagination.
//   q          — full-text on `searchText` (lowercased LIKE)
//   shopId     — single shop
//   categoryId — structured category (Phase 1)
//   category   — legacy free-text category (back-compat)
//   vertical   — joins Shop.vertical
//   priceMin/priceMax
//   isAvailable — default true
//   sort       — new (default) | price_asc | price_desc | rating
//   cursor     — base64({createdAt, id}) for "new"; base64({offset}) otherwise
//   limit      — default 20, max 100
router.get('/', async (req, res, next) => {
  try {
    const {
      q, shopId, categoryId, category, vertical,
      priceMin, priceMax, sort, cursor,
    } = req.query;

    const limit = Math.min(parseInt(req.query.limit, 10) || 20, 100);

    const where = {};
    if (req.query.isAvailable === undefined) {
      where.isAvailable = true;
    } else {
      where.isAvailable = req.query.isAvailable === 'true' || req.query.isAvailable === '1';
    }
    if (shopId) where.shopId = shopId;
    if (categoryId) where.categoryId = categoryId;
    if (category && category !== 'all') where.category = category;
    if (vertical) where.shop = { vertical };

    if (priceMin !== undefined || priceMax !== undefined) {
      where.price = {};
      if (priceMin !== undefined && priceMin !== '') where.price.gte = Number(priceMin);
      if (priceMax !== undefined && priceMax !== '') where.price.lte = Number(priceMax);
    }

    if (q && String(q).trim()) {
      const needle = String(q).toLowerCase();
      // Prefer searchText, but fall back to name/nameUz so legacy rows still match.
      where.OR = [
        { searchText: { contains: needle } },
        { name: { contains: needle } },
        { nameUz: { contains: needle } },
      ];
    }

    const sortKey = sort || 'new';
    const include = {
      categoryRef: { select: { id: true, nameRu: true, nameUz: true } },
    };
    if (sortKey === 'rating') include.shop = { select: { rating: true } };

    let items = [];
    let nextCursor = null;

    if (sortKey === 'new') {
      // Cursor on (createdAt desc, id desc).
      const c = decodeCursor(cursor);
      const cursorWhere = (c && c.createdAt && c.id)
        ? {
            OR: [
              { createdAt: { lt: new Date(c.createdAt) } },
              {
                AND: [
                  { createdAt: new Date(c.createdAt) },
                  { id: { lt: c.id } },
                ],
              },
            ],
          }
        : null;

      const finalWhere = cursorWhere ? { AND: [where, cursorWhere] } : where;

      items = await prisma.product.findMany({
        where: finalWhere,
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: limit + 1,
        include,
      });
      if (items.length > limit) {
        const last = items[limit - 1];
        items = items.slice(0, limit);
        nextCursor = encodeCursor({ createdAt: last.createdAt.toISOString(), id: last.id });
      }
    } else {
      // Offset-based fallback. SQLite can't easily order by relation field,
      // so for "rating" we fetch a broader set and sort/page in JS.
      const c = decodeCursor(cursor);
      const offset = (c && Number.isFinite(c.offset)) ? Math.max(0, c.offset) : 0;

      let orderBy;
      let postSort = null;
      if (sortKey === 'price_asc') orderBy = [{ price: 'asc' }, { id: 'asc' }];
      else if (sortKey === 'price_desc') orderBy = [{ price: 'desc' }, { id: 'desc' }];
      else if (sortKey === 'rating') {
        // Stable secondary order; final sort done in JS.
        orderBy = [{ createdAt: 'desc' }];
        postSort = (a, b) => (b.shop?.rating || 0) - (a.shop?.rating || 0);
      } else {
        orderBy = [{ createdAt: 'desc' }];
      }

      const fetched = await prisma.product.findMany({
        where,
        orderBy,
        skip: offset,
        take: limit + 1,
        include,
      });
      items = fetched;
      if (postSort) items.sort(postSort);
      if (items.length > limit) {
        items = items.slice(0, limit);
        nextCursor = encodeCursor({ offset: offset + limit });
      }
    }

    res.json({ items, products: items, nextCursor });
  } catch (err) { next(err); }
});

// ─── GET /api/products/featured ────────────────────────────────────────────
router.get('/featured', async (req, res, next) => {
  try {
    const products = await prisma.product.findMany({
      where: { isAvailable: true },
      take: 8,
      orderBy: { createdAt: 'desc' },
    });
    res.json({ products });
  } catch (err) { next(err); }
});

// ─── GET /api/products/shop/:shopId ─────────────────────────────────────────
// Owner view — includes unavailable items, requires membership
router.get('/shop/:shopId', authMiddleware, async (req, res, next) => {
  try {
    if (!(await requireShopMember(req, req.params.shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }
    const products = await prisma.product.findMany({
      where: { shopId: req.params.shopId },
      orderBy: { createdAt: 'desc' },
    });
    res.json({ products });
  } catch (err) { next(err); }
});

// ─── GET /api/products/template ─────────────────────────────────────────────
// Download CSV/XLSX template for bulk import
router.get('/template', (req, res) => {
  const format = (req.query.format || 'csv').toLowerCase();
  const headers = ['name', 'nameUz', 'description', 'ingredients', 'price', 'discountPrice', 'unit', 'category', 'imageUrl', 'stock'];
  const example = ['Pomidor', 'Pomidor', 'Свежие томаты', '', 12000, '', 'кг', 'produce', 'https://example.com/pomidor.jpg', 100];

  if (format === 'xlsx') {
    const ws = xlsx.utils.aoa_to_sheet([headers, example]);
    ws['!cols'] = headers.map(() => ({ wch: 18 }));
    const wb = xlsx.utils.book_new();
    xlsx.utils.book_append_sheet(wb, ws, 'products');
    const buf = xlsx.write(wb, { type: 'buffer', bookType: 'xlsx' });
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename="products_template.xlsx"');
    res.send(buf);
  } else {
    const csv = [headers.join(','), example.map(v => `"${v}"`).join(',')].join('\n');
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="products_template.csv"');
    res.send(csv);
  }
});

// ─── POST /api/products/upload-image ────────────────────────────────────────
// Gated to shop members + admins so random buyers can't fill /uploads with
// junk. Buyers occasionally upload images for chat/reviews via dedicated
// endpoints — those carry their own gating.
router.post('/upload-image', authMiddleware, uploadImage.single('image'), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No file' });
    if (!req.user.isAdmin) {
      const member = await prisma.shopMember.findFirst({
        where: { userId: req.user.id },
        select: { id: true },
      });
      if (!member) {
        // Discard the uploaded file so we don't accumulate orphans.
        try { fs.unlinkSync(req.file.path); } catch { /* noop */ }
        return res.status(403).json({ error: 'Shop membership required' });
      }
    }
    const url = `/uploads/products/${req.file.filename}`;
    res.json({ url, filename: req.file.filename, size: req.file.size });
  } catch (err) { next(err); }
});

// ─── POST /api/products ─────────────────────────────────────────────────────
// Create single product
router.post('/', authMiddleware, async (req, res, next) => {
  try {
    const { shopId } = req.body;
    if (!shopId) return res.status(400).json({ error: 'shopId required' });
    if (!(await requireShopMember(req, shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }
    const data = pickProductFields(req.body);
    const errors = validateProduct(data);
    if (errors.length) return res.status(400).json({ error: errors.join('; ') });

    if (data.categoryId) {
      const cat = await prisma.category.findUnique({ where: { id: data.categoryId } });
      if (!cat) return res.status(400).json({ error: 'categoryId does not exist' });
    }

    data.searchText = buildSearchText(data);

    const product = await prisma.product.create({
      data: { ...data, shopId },
    });
    res.status(201).json({ product });
  } catch (err) { next(err); }
});

// ─── PATCH /api/products/:id ────────────────────────────────────────────────
router.patch('/:id', authMiddleware, async (req, res, next) => {
  try {
    const product = await prisma.product.findUnique({ where: { id: req.params.id } });
    if (!product) return res.status(404).json({ error: 'Not found' });
    if (!(await requireShopMember(req, product.shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }
    const data = pickProductFields(req.body);

    if (data.categoryId) {
      const cat = await prisma.category.findUnique({ where: { id: data.categoryId } });
      if (!cat) return res.status(400).json({ error: 'categoryId does not exist' });
    }

    // Re-build searchText if any of its source fields were touched.
    if (data.name !== undefined || data.nameUz !== undefined || data.description !== undefined) {
      data.searchText = buildSearchText({
        name: data.name ?? product.name,
        nameUz: data.nameUz ?? product.nameUz,
        description: data.description ?? product.description,
      });
    }

    const updated = await prisma.product.update({
      where: { id: req.params.id },
      data,
    });
    res.json({ product: updated });
  } catch (err) { next(err); }
});

// ─── DELETE /api/products/:id ───────────────────────────────────────────────
// Soft delete: mark as unavailable. Hard delete via ?hard=1 (won't work if product has past orders)
router.delete('/:id', authMiddleware, async (req, res, next) => {
  try {
    const product = await prisma.product.findUnique({ where: { id: req.params.id } });
    if (!product) return res.status(404).json({ error: 'Not found' });
    if (!(await requireShopMember(req, product.shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }
    let hardDeleteRefused = false;
    if (req.query.hard === '1') {
      try {
        await prisma.product.delete({ where: { id: req.params.id } });
        return res.json({ deleted: true });
      } catch (e) {
        // Foreign-key constraint (past OrderItems) — fall back to soft
        // delete and tell the client what happened so the UI can explain.
        hardDeleteRefused = true;
        if (e?.code !== 'P2003' && e?.code !== 'P2014') {
          // Unexpected error — log it.
          // eslint-disable-next-line global-require
          require('../lib/logger').warn(
            { err: e.message, productId: req.params.id },
            'hard-delete failed unexpectedly',
          );
        }
      }
    }
    await prisma.product.update({
      where: { id: req.params.id },
      data: { isAvailable: false },
    });
    res.json({ deleted: false, archived: true, hardDeleteRefused });
  } catch (err) { next(err); }
});

// ─── POST /api/products/bulk ────────────────────────────────────────────────
// JSON array — useful for API integrations
router.post('/bulk', authMiddleware, async (req, res, next) => {
  try {
    const { shopId, items } = req.body;
    if (!shopId || !Array.isArray(items)) {
      return res.status(400).json({ error: 'shopId and items[] required' });
    }
    if (!(await requireShopMember(req, shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }
    const results = { created: 0, errors: [] };
    for (let i = 0; i < items.length; i++) {
      const data = pickProductFields(items[i]);
      const errs = validateProduct(data);
      if (errs.length) {
        results.errors.push({ row: i + 1, error: errs.join('; ') });
        continue;
      }
      try {
        data.searchText = buildSearchText(data);
        await prisma.product.create({ data: { ...data, shopId } });
        results.created++;
      } catch (e) {
        results.errors.push({ row: i + 1, error: e.message });
      }
    }
    res.json(results);
  } catch (err) { next(err); }
});

// ─── POST /api/products/import ──────────────────────────────────────────────
// Multipart upload of XLSX/CSV
router.post('/import', authMiddleware, uploadSheet.single('file'), async (req, res, next) => {
  try {
    const { shopId } = req.body;
    if (!shopId) return res.status(400).json({ error: 'shopId required' });
    if (!req.file) return res.status(400).json({ error: 'file required' });
    if (!(await requireShopMember(req, shopId))) {
      return res.status(403).json({ error: 'Not a shop member' });
    }

    let rows;
    try {
      const wb = xlsx.read(req.file.buffer, { type: 'buffer' });
      const sheet = wb.Sheets[wb.SheetNames[0]];
      rows = xlsx.utils.sheet_to_json(sheet, { defval: '' });
    } catch (e) {
      return res.status(400).json({ error: 'Cannot parse file: ' + e.message });
    }

    const dryRun = req.body.dryRun === '1' || req.body.dryRun === 'true';
    const results = { total: rows.length, created: 0, errors: [], preview: [] };

    for (let i = 0; i < rows.length; i++) {
      const data = pickProductFields(rows[i]);
      const errs = validateProduct(data);
      if (errs.length) {
        results.errors.push({ row: i + 2, error: errs.join('; '), data: rows[i] });
        continue;
      }
      if (dryRun) {
        results.preview.push({ row: i + 2, ...data });
        continue;
      }
      try {
        data.searchText = buildSearchText(data);
        await prisma.product.create({ data: { ...data, shopId } });
        results.created++;
      } catch (e) {
        results.errors.push({ row: i + 2, error: e.message });
      }
    }
    res.json(results);
  } catch (err) { next(err); }
});

module.exports = router;
