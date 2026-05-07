const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// ─── Phase-1 categories (idempotent via upsert on (slug, shopId) unique) ────
const SEED_CATEGORIES = [
  // grocery
  { vertical: 'grocery', slug: 'produce', nameUz: 'Sabzavot va mevalar', nameRu: 'Овощи и фрукты', sortOrder: 10 },
  { vertical: 'grocery', slug: 'meat-poultry', nameUz: "Go'sht/parranda", nameRu: 'Мясо/птица', sortOrder: 20 },
  { vertical: 'grocery', slug: 'dairy', nameUz: 'Sutli mahsulotlar', nameRu: 'Молочные продукты', sortOrder: 30 },
  // restaurant
  { vertical: 'restaurant', slug: 'pizza', nameUz: 'Pitsa', nameRu: 'Пицца', sortOrder: 10 },
  { vertical: 'restaurant', slug: 'burgers', nameUz: 'Burgerlar', nameRu: 'Бургеры', sortOrder: 20 },
  { vertical: 'restaurant', slug: 'sushi', nameUz: 'Sushi', nameRu: 'Суши', sortOrder: 30 },
  // pharmacy
  { vertical: 'pharmacy', slug: 'otc', nameUz: 'Retseptsiz', nameRu: 'Безрецептурные', sortOrder: 10 },
  { vertical: 'pharmacy', slug: 'vitamins', nameUz: 'Vitaminlar', nameRu: 'Витамины', sortOrder: 20 },
  { vertical: 'pharmacy', slug: 'hygiene', nameUz: 'Gigiyena', nameRu: 'Гигиена', sortOrder: 30 },
  // electronics
  { vertical: 'electronics', slug: 'accessories', nameUz: 'Aksessuarlar', nameRu: 'Аксессуары', sortOrder: 10 },
  { vertical: 'electronics', slug: 'chargers', nameUz: 'Quvvatlagichlar', nameRu: 'Зарядки', sortOrder: 20 },
  { vertical: 'electronics', slug: 'headphones', nameUz: 'Quloqchinlar', nameRu: 'Наушники', sortOrder: 30 },
];

async function seedCategories() {
  for (const c of SEED_CATEGORIES) {
    // (slug, shopId) is the unique. shopId=null for global categories — Prisma
    // can't put null inside a compound unique selector on SQLite, so we
    // emulate upsert with findFirst + create.
    const existing = await prisma.category.findFirst({
      where: { slug: c.slug, shopId: null },
    });
    if (existing) {
      await prisma.category.update({
        where: { id: existing.id },
        data: {
          vertical: c.vertical,
          nameUz: c.nameUz,
          nameRu: c.nameRu,
          sortOrder: c.sortOrder,
          isActive: true,
        },
      });
    } else {
      await prisma.category.create({ data: { ...c, shopId: null } });
    }
  }
}

async function main() {
  console.log('🌱 Seeding database...');

  // Categories are seeded every run (idempotent upsert) so the four-vertical
  // tree is always present even if user/shop seed was already applied.
  await seedCategories();
  console.log(`  ✓ ${SEED_CATEGORIES.length} categories upserted`);

  // Idempotent — skip rest of seed if seed users already exist.
  const existing = await prisma.user.findUnique({ where: { phone: '+998901234567' } });
  if (existing) {
    console.log('  ✓ Already seeded — skipping users/shop/orders');
    return;
  }

  // ─── Users ────────────────────────────────────────────────────────────────
  const buyer = await prisma.user.create({
    data: {
      phone: '+998901234567',
      name: 'Dilnoza X.',
      isBuyer: true,
    },
  });

  const courier = await prisma.user.create({
    data: {
      phone: '+998912345678',
      name: 'Bobur K.',
      isBuyer: true,
      isCourier: true,
      courierStatus: 'approved',
      stir: '123456789',
      passportSeries: 'AA1234567',
      rating: 4.9,
      ordersCount: 127,
    },
  });

  const shopOwner = await prisma.user.create({
    data: {
      phone: '+998933456789',
      name: 'Aziz Korzinka',
      isBuyer: true,
      isShop: true,
    },
  });

  // ─── Shop ────────────────────────────────────────────────────────────────
  const shop = await prisma.shop.create({
    data: {
      name: 'Korzinka — Yunusobod',
      description: 'Eng yaqin do\'koningiz, 15 daqiqada yetkazib berish',
      address: 'Toshkent, Yunusobod, 13-mavze, 5-uy',
      lat: 41.3617,
      lng: 69.2877,
      phone: '+998711234567',
      rating: 4.8,
    },
  });

  await prisma.shopMember.create({
    data: { userId: shopOwner.id, shopId: shop.id, role: 'owner' },
  });

  // ─── Products ────────────────────────────────────────────────────────────
  const productsData = [
    // Sabzavotlar
    { name: 'Pomidor', nameUz: 'Pomidor', price: 8500, unit: 'кг', category: 'produce',
      imageUrl: 'https://images.unsplash.com/photo-1546470427-e26264be0b0d?w=400' },
    { name: 'Kartoshka', nameUz: 'Kartoshka', price: 4200, discountPrice: 3500, unit: 'кг', category: 'produce',
      imageUrl: 'https://images.unsplash.com/photo-1518977676601-b53f82aba655?w=400' },
    { name: 'Bodring', nameUz: 'Bodring', price: 7000, unit: 'кг', category: 'produce',
      imageUrl: 'https://images.unsplash.com/photo-1622205313162-be1d5712a43f?w=400' },
    { name: 'Qovoq', nameUz: 'Qovoq', price: 5000, unit: 'кг', category: 'produce',
      imageUrl: 'https://images.unsplash.com/photo-1568584263162-b878fde82b5b?w=400' },
    { name: 'Sabzi', nameUz: 'Sabzi', price: 4500, unit: 'кг', category: 'produce',
      imageUrl: 'https://images.unsplash.com/photo-1582515073490-39981397c445?w=400' },
    { name: 'Piyoz', nameUz: 'Piyoz', price: 3500, unit: 'кг', category: 'produce',
      imageUrl: 'https://images.unsplash.com/photo-1620574387735-3624d75b2dbc?w=400' },

    // Go'sht
    { name: 'Mol go\'shti', nameUz: 'Mol go\'shti', price: 85000, unit: 'кг', category: 'meat',
      imageUrl: 'https://images.unsplash.com/photo-1603048297172-c92544798d5a?w=400' },
    { name: 'Tovuq go\'shti', nameUz: 'Tovuq', price: 42000, unit: 'кг', category: 'meat',
      imageUrl: 'https://images.unsplash.com/photo-1604503468506-a8da13d82791?w=400' },
    { name: 'Qo\'y go\'shti', nameUz: 'Qo\'y', price: 95000, unit: 'кг', category: 'meat',
      imageUrl: 'https://images.unsplash.com/photo-1551446591-142875a901a1?w=400' },

    // Sutlilar
    { name: 'Parmalat sut 1l', nameUz: 'Sut', price: 18000, unit: 'шт', category: 'dairy',
      imageUrl: 'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=400' },
    { name: 'Tuxum 10 ta', nameUz: 'Tuxum', price: 22000, unit: 'шт', category: 'dairy',
      imageUrl: 'https://images.unsplash.com/photo-1587486913049-53fc88980cfc?w=400' },
    { name: 'Pishloq', nameUz: 'Pishloq', price: 65000, unit: 'кг', category: 'dairy',
      imageUrl: 'https://images.unsplash.com/photo-1486297678162-eb2a19b0a32d?w=400' },
    { name: 'Smetana', nameUz: 'Smetana', price: 15000, unit: 'шт', category: 'dairy',
      imageUrl: 'https://images.unsplash.com/photo-1559561853-08451507cbe7?w=400' },

    // Non
    { name: 'Lepyoshka', nameUz: 'Non', price: 6000, unit: 'шт', category: 'bakery',
      imageUrl: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=400' },
    { name: 'Qatlama', nameUz: 'Qatlama', price: 8000, unit: 'шт', category: 'bakery',
      imageUrl: 'https://images.unsplash.com/photo-1568254183919-78a4f43a2877?w=400' },

    // Ichimliklar
    { name: 'Coca-Cola 1.5l', nameUz: 'Cola', price: 14000, unit: 'шт', category: 'drinks',
      imageUrl: 'https://images.unsplash.com/photo-1554866585-cd94860890b7?w=400' },
    { name: 'Suv 5l', nameUz: 'Suv', price: 8000, unit: 'шт', category: 'drinks',
      imageUrl: 'https://images.unsplash.com/photo-1564890369478-c89ca6d9cde9?w=400' },
    { name: 'Choy Lipton 100 paket', nameUz: 'Choy', price: 28000, unit: 'шт', category: 'drinks',
      imageUrl: 'https://images.unsplash.com/photo-1597481499750-3e6b22637e12?w=400' },

    // Oziq-ovqat
    { name: 'Guruch oqsuv 5kg', nameUz: 'Guruch', price: 75000, unit: 'шт', category: 'grocery',
      imageUrl: 'https://images.unsplash.com/photo-1586201375761-83865001e31c?w=400' },
    { name: 'Makaron 500g', nameUz: 'Makaron', price: 12000, unit: 'шт', category: 'grocery',
      imageUrl: 'https://images.unsplash.com/photo-1551892374-ecf8754cf8b0?w=400' },
    { name: 'Yog\' Oleyna 1l', nameUz: 'Yog\'', price: 28000, unit: 'шт', category: 'grocery',
      imageUrl: 'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?w=400' },
    { name: 'Shakar 1kg', nameUz: 'Shakar', price: 14000, unit: 'кг', category: 'grocery',
      imageUrl: 'https://images.unsplash.com/photo-1581400151483-fa3e5b03f4cf?w=400' },
  ];

  for (const p of productsData) {
    await prisma.product.create({ data: { ...p, shopId: shop.id, stock: 100 } });
  }

  // ─── Demo orders ──────────────────────────────────────────────────────────
  const products = await prisma.product.findMany({ where: { shopId: shop.id } });
  const pomidor = products.find(p => p.nameUz === 'Pomidor');
  const kartoshka = products.find(p => p.nameUz === 'Kartoshka');
  const sut = products.find(p => p.nameUz === 'Sut');

  // 1. New pending order — shop sees as new
  await prisma.order.create({
    data: {
      buyerId: buyer.id,
      customerName: buyer.name,
      customerPhone: buyer.phone,
      shopId: shop.id,
      deliveryAddress: 'Yunusobod, Sharaf Rashidov ko\'chasi, 25-uy, 3-qavat',
      customerComment: 'Eshik oldiga qo\'ying',
      paymentMethod: 'click',
      isPaid: true,
      subtotal: 21200,
      deliveryFee: 12000,
      total: 33200,
      status: 'pending',
      items: {
        create: [
          { productId: pomidor.id, productName: pomidor.name, quantity: 2, price: pomidor.price, total: pomidor.price * 2 },
          { productId: kartoshka.id, productName: kartoshka.name, quantity: 1, price: kartoshka.discountPrice, total: kartoshka.discountPrice },
        ],
      },
      createdAt: new Date(Date.now() - 2 * 60_000),
    },
  });

  // 2. Order being collected
  await prisma.order.create({
    data: {
      buyerId: buyer.id,
      customerName: buyer.name,
      customerPhone: buyer.phone,
      shopId: shop.id,
      deliveryAddress: 'Chilonzor, 9-kvartal, 44-uy',
      paymentMethod: 'payme',
      isPaid: true,
      subtotal: 54000,
      deliveryFee: 12000,
      total: 66000,
      status: 'collecting',
      orderNumber: 'K-246',
      acceptedAt: new Date(Date.now() - 6 * 60_000),
      items: {
        create: [
          { productId: sut.id, productName: sut.name, quantity: 3, price: sut.price, total: sut.price * 3 },
        ],
      },
      createdAt: new Date(Date.now() - 8 * 60_000),
    },
  });

  // 3. Ready for pickup — courier can grab
  await prisma.order.create({
    data: {
      buyerId: buyer.id,
      customerName: buyer.name,
      customerPhone: buyer.phone,
      shopId: shop.id,
      deliveryAddress: 'Yunusobod, Bog\'ishamol ko\'chasi, 12-uy',
      customerComment: 'Interkom 47',
      paymentMethod: 'cash',
      isPaid: false,
      subtotal: 18500,
      deliveryFee: 12000,
      total: 30500,
      status: 'readyForPickup',
      orderNumber: 'K-247',
      acceptedAt: new Date(Date.now() - 18 * 60_000),
      readyAt: new Date(Date.now() - 5 * 60_000),
      items: {
        create: [
          { productId: pomidor.id, productName: pomidor.name, quantity: 1, price: pomidor.price, total: pomidor.price },
          { productId: kartoshka.id, productName: kartoshka.name, quantity: 1, price: kartoshka.discountPrice, total: kartoshka.discountPrice },
          { productId: sut.id, productName: sut.name, quantity: 1, price: sut.price, total: sut.price },
        ],
      },
      createdAt: new Date(Date.now() - 18 * 60_000),
    },
  });

  // 4. Delivered (history)
  await prisma.order.create({
    data: {
      buyerId: buyer.id,
      customerName: buyer.name,
      customerPhone: buyer.phone,
      shopId: shop.id,
      courierId: courier.id,
      deliveryAddress: 'Yunusobod, 7-mavze, 12-uy',
      paymentMethod: 'click',
      isPaid: true,
      subtotal: 54000,
      deliveryFee: 12000,
      total: 66000,
      status: 'delivered',
      orderNumber: 'K-245',
      acceptedAt: new Date(Date.now() - 60 * 60_000),
      readyAt: new Date(Date.now() - 50 * 60_000),
      pickedUpAt: new Date(Date.now() - 40 * 60_000),
      deliveredAt: new Date(Date.now() - 30 * 60_000),
      items: {
        create: [
          { productId: sut.id, productName: sut.name, quantity: 3, price: sut.price, total: sut.price * 3 },
        ],
      },
      createdAt: new Date(Date.now() - 65 * 60_000),
    },
  });

  console.log(`✅ Created:
    Users: 3 (1 buyer, 1 courier, 1 shop owner)
    Shop: 1 (Korzinka — Yunusobod)
    Products: ${productsData.length}
    Orders: 4 (1 new, 1 collecting, 1 ready, 1 delivered)

  📱 Test logins:
    Buyer:   +998 90 123 45 67  (code: 123456)
    Courier: +998 91 234 56 78  (code: 123456)
    Shop:    +998 93 345 67 89  (code: 123456)
  `);
}

main()
  .catch(e => { console.error(e); process.exit(1); })
  .finally(() => prisma.$disconnect());
