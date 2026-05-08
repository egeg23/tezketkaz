-- Phase 7: subscription, banners, favorites, multi-country prep, VAT snapshot.

-- ─── User: country code (drives currency, VAT, payment provider mix) ────────
ALTER TABLE "User" ADD COLUMN "country" TEXT NOT NULL DEFAULT 'UZ';

-- ─── Order: VAT snapshot at order time ──────────────────────────────────────
ALTER TABLE "Order" ADD COLUMN "taxRate" REAL NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "taxAmount" REAL NOT NULL DEFAULT 0;

-- ─── Membership ─────────────────────────────────────────────────────────────
CREATE TABLE "Membership" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "tier" TEXT NOT NULL DEFAULT 'plus',
    "status" TEXT NOT NULL DEFAULT 'active',
    "currency" TEXT NOT NULL DEFAULT 'UZS',
    "periodAmount" REAL NOT NULL,
    "billingPeriod" TEXT NOT NULL DEFAULT 'monthly',
    "startedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "currentPeriodEnd" DATETIME NOT NULL,
    "cancelledAt" DATETIME,
    "failedRenewals" INTEGER NOT NULL DEFAULT 0,
    "lastChargeAt" DATETIME,
    "lastChargeError" TEXT,
    "autoRenew" BOOLEAN NOT NULL DEFAULT true,
    "paymentMethodId" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "Membership_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "Membership_userId_key" ON "Membership"("userId");
CREATE INDEX "Membership_status_currentPeriodEnd_idx" ON "Membership"("status", "currentPeriodEnd");

-- ─── Banner ─────────────────────────────────────────────────────────────────
CREATE TABLE "Banner" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "titleUz" TEXT NOT NULL,
    "titleRu" TEXT NOT NULL,
    "titleEn" TEXT,
    "subtitleUz" TEXT,
    "subtitleRu" TEXT,
    "subtitleEn" TEXT,
    "imageUrl" TEXT NOT NULL,
    "deepLink" TEXT,
    "vertical" TEXT NOT NULL DEFAULT 'all',
    "country" TEXT,
    "priority" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "validFrom" DATETIME,
    "validUntil" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);

CREATE INDEX "Banner_isActive_priority_idx" ON "Banner"("isActive", "priority");
CREATE INDEX "Banner_vertical_isActive_idx" ON "Banner"("vertical", "isActive");
CREATE INDEX "Banner_country_idx" ON "Banner"("country");

-- ─── BannerImpression ───────────────────────────────────────────────────────
CREATE TABLE "BannerImpression" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "bannerId" TEXT NOT NULL,
    "userId" TEXT,
    "kind" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "BannerImpression_bannerId_fkey" FOREIGN KEY ("bannerId") REFERENCES "Banner"("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "BannerImpression_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE INDEX "BannerImpression_bannerId_kind_createdAt_idx" ON "BannerImpression"("bannerId", "kind", "createdAt");
CREATE INDEX "BannerImpression_userId_kind_idx" ON "BannerImpression"("userId", "kind");

-- ─── Favorite ───────────────────────────────────────────────────────────────
CREATE TABLE "Favorite" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "productId" TEXT,
    "shopId" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Favorite_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "Favorite_userId_productId_key" ON "Favorite"("userId", "productId");
CREATE UNIQUE INDEX "Favorite_userId_shopId_key" ON "Favorite"("userId", "shopId");
CREATE INDEX "Favorite_userId_idx" ON "Favorite"("userId");
