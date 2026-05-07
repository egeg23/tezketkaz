-- Phase 2: dispatcher, delivery zones, pricing rules, courier shifts.

-- ─── User: courier real-time state ───────────────────────────────────────────
ALTER TABLE "User" ADD COLUMN "isOnline" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "User" ADD COLUMN "lastSeenAt" DATETIME;
ALTER TABLE "User" ADD COLUMN "activeOrderId" TEXT;

CREATE INDEX "User_isOnline_courierStatus_idx" ON "User"("isOnline", "courierStatus");

-- ─── DeliveryZone ────────────────────────────────────────────────────────────
CREATE TABLE "DeliveryZone" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "shopId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "polygon" TEXT NOT NULL,
    "baseFee" REAL NOT NULL DEFAULT 12000,
    "perKmFee" REAL NOT NULL DEFAULT 2000,
    "freeKm" REAL NOT NULL DEFAULT 2,
    "minOrder" REAL NOT NULL DEFAULT 0,
    "startsAt" TEXT,
    "endsAt" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "DeliveryZone_shopId_fkey" FOREIGN KEY ("shopId") REFERENCES "Shop"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "DeliveryZone_shopId_isActive_idx" ON "DeliveryZone"("shopId", "isActive");

-- ─── CourierShift ────────────────────────────────────────────────────────────
CREATE TABLE "CourierShift" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "courierId" TEXT NOT NULL,
    "startedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" DATETIME,
    "zoneIds" TEXT,
    "totalEarned" REAL NOT NULL DEFAULT 0,
    "totalOrders" INTEGER NOT NULL DEFAULT 0,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "CourierShift_courierId_fkey" FOREIGN KEY ("courierId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX "CourierShift_courierId_endedAt_idx" ON "CourierShift"("courierId", "endedAt");

-- ─── PricingRule ─────────────────────────────────────────────────────────────
CREATE TABLE "PricingRule" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "vertical" TEXT,
    "zoneId" TEXT,
    "surgeFactor" REAL NOT NULL DEFAULT 1.0,
    "reason" TEXT NOT NULL,
    "validFrom" DATETIME NOT NULL,
    "validUntil" DATETIME NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX "PricingRule_vertical_isActive_validFrom_validUntil_idx" ON "PricingRule"("vertical", "isActive", "validFrom", "validUntil");

-- ─── DispatchOffer ───────────────────────────────────────────────────────────
CREATE TABLE "DispatchOffer" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "orderId" TEXT NOT NULL,
    "courierId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "score" REAL NOT NULL,
    "distanceKm" REAL,
    "expiresAt" DATETIME NOT NULL,
    "offeredAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "respondedAt" DATETIME,
    CONSTRAINT "DispatchOffer_courierId_fkey" FOREIGN KEY ("courierId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "DispatchOffer_orderId_courierId_key" ON "DispatchOffer"("orderId", "courierId");
CREATE INDEX "DispatchOffer_orderId_status_idx" ON "DispatchOffer"("orderId", "status");
CREATE INDEX "DispatchOffer_courierId_offeredAt_idx" ON "DispatchOffer"("courierId", "offeredAt");
