-- Phase 0: security & FCM foundations
-- Adds: User.isAdmin, User.locale, User.notificationPrefs, OtpCode.attempts,
--       Address (entrance, floor, apartment, intercom, instructions),
--       FcmToken, RefreshToken, AuditLog, ProcessedWebhook.

-- ─── User: new columns ───────────────────────────────────────────────────────
ALTER TABLE "User" ADD COLUMN "isAdmin" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "User" ADD COLUMN "locale" TEXT NOT NULL DEFAULT 'uz';
ALTER TABLE "User" ADD COLUMN "notificationPrefs" TEXT;

CREATE INDEX "User_isAdmin_idx" ON "User"("isAdmin");
CREATE INDEX "User_isCourier_courierStatus_idx" ON "User"("isCourier", "courierStatus");

-- ─── OtpCode: track attempts for brute-force defence ─────────────────────────
ALTER TABLE "OtpCode" ADD COLUMN "attempts" INTEGER NOT NULL DEFAULT 0;

-- ─── Address: detailed delivery instructions ─────────────────────────────────
ALTER TABLE "Address" ADD COLUMN "entrance" TEXT;
ALTER TABLE "Address" ADD COLUMN "floor" TEXT;
ALTER TABLE "Address" ADD COLUMN "apartment" TEXT;
ALTER TABLE "Address" ADD COLUMN "intercom" TEXT;
ALTER TABLE "Address" ADD COLUMN "instructions" TEXT;

-- ─── FcmToken ────────────────────────────────────────────────────────────────
CREATE TABLE "FcmToken" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "lastSeenAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "FcmToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "FcmToken_token_key" ON "FcmToken"("token");
CREATE INDEX "FcmToken_userId_idx" ON "FcmToken"("userId");

-- ─── RefreshToken ────────────────────────────────────────────────────────────
CREATE TABLE "RefreshToken" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "jti" TEXT NOT NULL,
    "expiresAt" DATETIME NOT NULL,
    "revokedAt" DATETIME,
    "replacedById" TEXT,
    "userAgent" TEXT,
    "ipAddress" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "RefreshToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "RefreshToken_jti_key" ON "RefreshToken"("jti");
CREATE INDEX "RefreshToken_userId_idx" ON "RefreshToken"("userId");
CREATE INDEX "RefreshToken_expiresAt_idx" ON "RefreshToken"("expiresAt");

-- ─── AuditLog ────────────────────────────────────────────────────────────────
CREATE TABLE "AuditLog" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "actorId" TEXT,
    "action" TEXT NOT NULL,
    "targetType" TEXT,
    "targetId" TEXT,
    "metadata" TEXT,
    "ipAddress" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "AuditLog_actorId_fkey" FOREIGN KEY ("actorId") REFERENCES "User" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE INDEX "AuditLog_actorId_idx" ON "AuditLog"("actorId");
CREATE INDEX "AuditLog_targetType_targetId_idx" ON "AuditLog"("targetType", "targetId");
CREATE INDEX "AuditLog_createdAt_idx" ON "AuditLog"("createdAt");

-- ─── ProcessedWebhook (idempotency for payment callbacks) ────────────────────
CREATE TABLE "ProcessedWebhook" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "provider" TEXT NOT NULL,
    "externalId" TEXT NOT NULL,
    "orderId" TEXT,
    "payload" TEXT NOT NULL,
    "result" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX "ProcessedWebhook_provider_externalId_key" ON "ProcessedWebhook"("provider", "externalId");
CREATE INDEX "ProcessedWebhook_orderId_idx" ON "ProcessedWebhook"("orderId");
