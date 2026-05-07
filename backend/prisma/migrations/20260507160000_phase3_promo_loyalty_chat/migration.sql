-- Phase 3: promo codes, loyalty, reviews, chat, scheduled orders.

-- ─── User: referral fields ───────────────────────────────────────────────────
ALTER TABLE "User" ADD COLUMN "referralCode" TEXT;
ALTER TABLE "User" ADD COLUMN "referredById" TEXT;

CREATE UNIQUE INDEX "User_referralCode_key" ON "User"("referralCode");

-- ─── Order: promo + loyalty + scheduled fields ───────────────────────────────
ALTER TABLE "Order" ADD COLUMN "couponCode" TEXT;
ALTER TABLE "Order" ADD COLUMN "discount" REAL NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "loyaltyEarned" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "loyaltySpent" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "scheduledFor" DATETIME;

CREATE INDEX "Order_scheduledFor_idx" ON "Order"("scheduledFor");

-- ─── Coupon ──────────────────────────────────────────────────────────────────
CREATE TABLE "Coupon" (
    "code" TEXT NOT NULL PRIMARY KEY,
    "type" TEXT NOT NULL,
    "value" REAL NOT NULL DEFAULT 0,
    "minOrder" REAL,
    "maxDiscount" REAL,
    "validFrom" DATETIME NOT NULL,
    "validUntil" DATETIME NOT NULL,
    "usageLimit" INTEGER,
    "usagePerUser" INTEGER NOT NULL DEFAULT 1,
    "usedCount" INTEGER NOT NULL DEFAULT 0,
    "vertical" TEXT,
    "shopId" TEXT,
    "firstOrderOnly" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);

CREATE INDEX "Coupon_isActive_validFrom_validUntil_idx" ON "Coupon"("isActive", "validFrom", "validUntil");
CREATE INDEX "Coupon_vertical_idx" ON "Coupon"("vertical");
CREATE INDEX "Coupon_shopId_idx" ON "Coupon"("shopId");

-- ─── CouponRedemption ────────────────────────────────────────────────────────
CREATE TABLE "CouponRedemption" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "couponCode" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "discount" REAL NOT NULL,
    "redeemedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "CouponRedemption_couponCode_fkey" FOREIGN KEY ("couponCode") REFERENCES "Coupon"("code") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "CouponRedemption_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "CouponRedemption_couponCode_orderId_key" ON "CouponRedemption"("couponCode", "orderId");
CREATE INDEX "CouponRedemption_userId_idx" ON "CouponRedemption"("userId");
CREATE INDEX "CouponRedemption_orderId_idx" ON "CouponRedemption"("orderId");

-- ─── LoyaltyAccount ──────────────────────────────────────────────────────────
CREATE TABLE "LoyaltyAccount" (
    "userId" TEXT NOT NULL PRIMARY KEY,
    "tier" TEXT NOT NULL DEFAULT 'bronze',
    "points" INTEGER NOT NULL DEFAULT 0,
    "cashback" REAL NOT NULL DEFAULT 0,
    "lifetimeSpent" REAL NOT NULL DEFAULT 0,
    "updatedAt" DATETIME NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "LoyaltyAccount_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ─── LoyaltyTransaction ──────────────────────────────────────────────────────
CREATE TABLE "LoyaltyTransaction" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "delta" INTEGER NOT NULL,
    "orderId" TEXT,
    "metadata" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "LoyaltyTransaction_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX "LoyaltyTransaction_userId_createdAt_idx" ON "LoyaltyTransaction"("userId", "createdAt");
CREATE INDEX "LoyaltyTransaction_orderId_idx" ON "LoyaltyTransaction"("orderId");

-- ─── Review ──────────────────────────────────────────────────────────────────
CREATE TABLE "Review" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "orderId" TEXT NOT NULL,
    "reviewerId" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "targetId" TEXT NOT NULL,
    "rating" INTEGER NOT NULL,
    "text" TEXT,
    "photos" TEXT,
    "isVisible" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "Review_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "Review_reviewerId_fkey" FOREIGN KEY ("reviewerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "Review_orderId_reviewerId_targetType_targetId_key" ON "Review"("orderId", "reviewerId", "targetType", "targetId");
CREATE INDEX "Review_targetType_targetId_idx" ON "Review"("targetType", "targetId");
CREATE INDEX "Review_reviewerId_idx" ON "Review"("reviewerId");

-- ─── ChatMessage ─────────────────────────────────────────────────────────────
CREATE TABLE "ChatMessage" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "orderId" TEXT NOT NULL,
    "senderId" TEXT NOT NULL,
    "receiverId" TEXT NOT NULL,
    "text" TEXT,
    "imageUrl" TEXT,
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "readAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ChatMessage_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "ChatMessage_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "ChatMessage_receiverId_fkey" FOREIGN KEY ("receiverId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX "ChatMessage_orderId_createdAt_idx" ON "ChatMessage"("orderId", "createdAt");
CREATE INDEX "ChatMessage_receiverId_isRead_idx" ON "ChatMessage"("receiverId", "isRead");

-- ─── ScheduledOrder ──────────────────────────────────────────────────────────
CREATE TABLE "ScheduledOrder" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "orderId" TEXT NOT NULL,
    "scheduledFor" DATETIME NOT NULL,
    "reminderSentAt" DATETIME,
    "activatedAt" DATETIME,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "ScheduledOrder_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "ScheduledOrder_orderId_key" ON "ScheduledOrder"("orderId");
CREATE INDEX "ScheduledOrder_scheduledFor_status_idx" ON "ScheduledOrder"("scheduledFor", "status");

-- Backfill referralCode for existing users (8-char base36 from id hash).
-- Skipped here — generated on-demand by application code on first read.
