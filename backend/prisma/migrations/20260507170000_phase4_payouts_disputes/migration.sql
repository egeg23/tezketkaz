-- Phase 4: payouts, disputes, refund tracking on Order.

-- ─── Order: refund + dispute fields ──────────────────────────────────────────
ALTER TABLE "Order" ADD COLUMN "refundedAt" DATETIME;
ALTER TABLE "Order" ADD COLUMN "refundedAmount" REAL NOT NULL DEFAULT 0;
ALTER TABLE "Order" ADD COLUMN "refundReason" TEXT;

-- ─── Payout ──────────────────────────────────────────────────────────────────
CREATE TABLE "Payout" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "recipientType" TEXT NOT NULL,
    "recipientId" TEXT NOT NULL,
    "periodStart" DATETIME NOT NULL,
    "periodEnd" DATETIME NOT NULL,
    "grossAmount" REAL NOT NULL,
    "commission" REAL NOT NULL DEFAULT 0,
    "refundsTotal" REAL NOT NULL DEFAULT 0,
    "netAmount" REAL NOT NULL,
    "ordersCount" INTEGER NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "paidAt" DATETIME,
    "txnRef" TEXT,
    "notes" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);

CREATE UNIQUE INDEX "Payout_recipientType_recipientId_periodStart_key" ON "Payout"("recipientType", "recipientId", "periodStart");
CREATE INDEX "Payout_recipientType_status_idx" ON "Payout"("recipientType", "status");
CREATE INDEX "Payout_periodStart_idx" ON "Payout"("periodStart");

-- ─── Dispute ─────────────────────────────────────────────────────────────────
CREATE TABLE "Dispute" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "orderId" TEXT NOT NULL,
    "openedById" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "description" TEXT,
    "evidence" TEXT,
    "status" TEXT NOT NULL DEFAULT 'open',
    "resolution" TEXT,
    "refundAmount" REAL NOT NULL DEFAULT 0,
    "resolvedById" TEXT,
    "resolvedAt" DATETIME,
    "resolutionNote" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "Dispute_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "Dispute_orderId_key" ON "Dispute"("orderId");
CREATE INDEX "Dispute_status_idx" ON "Dispute"("status");
CREATE INDEX "Dispute_openedById_idx" ON "Dispute"("openedById");
