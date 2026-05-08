-- Phase 1: catalog (categories, modifiers), shop verticals, OrderItem modifier snapshot.

-- ─── Shop: vertical + delivery economics ─────────────────────────────────────
ALTER TABLE "Shop" ADD COLUMN "vertical" TEXT NOT NULL DEFAULT 'grocery';
ALTER TABLE "Shop" ADD COLUMN "deliveryBaseFee" REAL;
ALTER TABLE "Shop" ADD COLUMN "deliveryPerKm" REAL;
ALTER TABLE "Shop" ADD COLUMN "freeDeliveryKm" REAL;
ALTER TABLE "Shop" ADD COLUMN "minOrderAmount" REAL;

CREATE INDEX "Shop_vertical_idx" ON "Shop"("vertical");
CREATE INDEX "Shop_isActive_idx" ON "Shop"("isActive");

-- ─── Category (hierarchical) ─────────────────────────────────────────────────
CREATE TABLE "Category" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "parentId" TEXT,
    "vertical" TEXT NOT NULL,
    "shopId" TEXT,
    "slug" TEXT NOT NULL,
    "nameUz" TEXT NOT NULL,
    "nameRu" TEXT NOT NULL,
    "nameEn" TEXT,
    "iconUrl" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "Category_parentId_fkey" FOREIGN KEY ("parentId") REFERENCES "Category"("id") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "Category_slug_shopId_key" ON "Category"("slug", "shopId");
CREATE INDEX "Category_vertical_isActive_idx" ON "Category"("vertical", "isActive");
CREATE INDEX "Category_parentId_idx" ON "Category"("parentId");
CREATE INDEX "Category_shopId_idx" ON "Category"("shopId");

-- ─── Product: categoryId + searchText ────────────────────────────────────────
ALTER TABLE "Product" ADD COLUMN "categoryId" TEXT REFERENCES "Category"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Product" ADD COLUMN "searchText" TEXT;

CREATE INDEX "Product_categoryId_idx" ON "Product"("categoryId");
CREATE INDEX "Product_isAvailable_idx" ON "Product"("isAvailable");

-- ─── Modifier groups & options ───────────────────────────────────────────────
CREATE TABLE "ProductModifierGroup" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "productId" TEXT NOT NULL,
    "nameUz" TEXT NOT NULL,
    "nameRu" TEXT NOT NULL,
    "nameEn" TEXT,
    "minSelect" INTEGER NOT NULL DEFAULT 0,
    "maxSelect" INTEGER NOT NULL DEFAULT 1,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "ProductModifierGroup_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "ProductModifierGroup_productId_idx" ON "ProductModifierGroup"("productId");

CREATE TABLE "ProductModifierOption" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "groupId" TEXT NOT NULL,
    "nameUz" TEXT NOT NULL,
    "nameRu" TEXT NOT NULL,
    "nameEn" TEXT,
    "priceDelta" REAL NOT NULL DEFAULT 0,
    "isAvailable" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT "ProductModifierOption_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "ProductModifierGroup"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "ProductModifierOption_groupId_idx" ON "ProductModifierOption"("groupId");

-- ─── OrderItem: modifier snapshot + base price ───────────────────────────────
ALTER TABLE "OrderItem" ADD COLUMN "modifiers" TEXT;
ALTER TABLE "OrderItem" ADD COLUMN "basePrice" REAL;

-- Backfill searchText from existing names (lowercased) for LIKE-search.
UPDATE "Product" SET "searchText" = LOWER(COALESCE("name", '') || ' ' || COALESCE("nameUz", '') || ' ' || COALESCE("description", ''));
