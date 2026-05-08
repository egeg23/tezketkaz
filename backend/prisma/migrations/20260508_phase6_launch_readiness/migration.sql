-- Phase 6: launch readiness — saved payment methods, working hours, KYC docs,
-- tipping, multi-currency framework.

-- ─── Shop: currency + working-hours back-ref ─────────────────────────────────
ALTER TABLE "Shop" ADD COLUMN "currency" TEXT NOT NULL DEFAULT 'UZS';

-- ─── ShopWorkingHours ────────────────────────────────────────────────────────
CREATE TABLE "ShopWorkingHours" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "shopId" TEXT NOT NULL,
    "dayOfWeek" INTEGER NOT NULL,
    "startsAt" TEXT NOT NULL,
    "endsAt" TEXT NOT NULL,
    "isClosed" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "ShopWorkingHours_shopId_fkey" FOREIGN KEY ("shopId") REFERENCES "Shop"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "ShopWorkingHours_shopId_dayOfWeek_idx" ON "ShopWorkingHours"("shopId", "dayOfWeek");

-- Backfill 7 rows per shop from the legacy openTime/closeTime fields so
-- isOpenNow() works immediately for existing data.
INSERT INTO "ShopWorkingHours" ("id", "shopId", "dayOfWeek", "startsAt", "endsAt", "isClosed", "updatedAt")
SELECT
    LOWER(HEX(RANDOMBLOB(16))) AS "id",
    s."id"                     AS "shopId",
    d."dayOfWeek"              AS "dayOfWeek",
    s."openTime"               AS "startsAt",
    s."closeTime"              AS "endsAt",
    false                      AS "isClosed",
    CURRENT_TIMESTAMP          AS "updatedAt"
FROM "Shop" s
CROSS JOIN (
    SELECT 0 AS "dayOfWeek" UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL
    SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6
) d;

-- ─── Order: tip + saved-payment-method linkage + currency snapshot ───────────
ALTER TABLE "Order" ADD COLUMN "tipAmount" REAL NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "tipPaidAt" DATETIME;
ALTER TABLE "Order" ADD COLUMN "paymentMethodId" TEXT REFERENCES "PaymentMethod"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Order" ADD COLUMN "currency" TEXT NOT NULL DEFAULT 'UZS';

-- ─── PaymentMethod ───────────────────────────────────────────────────────────
CREATE TABLE "PaymentMethod" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "providerId" TEXT,
    "brand" TEXT,
    "last4" TEXT,
    "expiryMonth" INTEGER,
    "expiryYear" INTEGER,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "PaymentMethod_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "PaymentMethod_userId_isActive_idx" ON "PaymentMethod"("userId", "isActive");

-- ─── VerificationDocument ────────────────────────────────────────────────────
CREATE TABLE "VerificationDocument" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "reviewedById" TEXT,
    "reviewedAt" DATETIME,
    "rejectionReason" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "VerificationDocument_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "VerificationDocument_userId_type_idx" ON "VerificationDocument"("userId", "type");
CREATE INDEX "VerificationDocument_status_idx" ON "VerificationDocument"("status");
