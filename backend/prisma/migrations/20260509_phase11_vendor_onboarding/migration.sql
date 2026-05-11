-- Phase 11: multi-shop cart drafts + onboarding flag.

-- ─── User: onboarding milestone ─────────────────────────────────────────────
ALTER TABLE "User" ADD COLUMN "onboardedAt" DATETIME;

-- ─── CartDraft ──────────────────────────────────────────────────────────────
CREATE TABLE "CartDraft" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "shopId" TEXT NOT NULL,
    "payload" TEXT NOT NULL DEFAULT '[]',
    "couponCode" TEXT,
    "loyaltyPoints" INTEGER NOT NULL DEFAULT 0,
    "scheduledFor" DATETIME,
    "updatedAt" DATETIME NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "CartDraft_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "CartDraft_userId_shopId_key" ON "CartDraft"("userId", "shopId");
CREATE INDEX "CartDraft_userId_updatedAt_idx" ON "CartDraft"("userId", "updatedAt");
