-- Phase 8: stacked dispatch, tip estimate, instant payout.

-- ─── OrderBatch (created first so Order.batchId FK target exists) ───────────
CREATE TABLE "OrderBatch" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "courierId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "totalDeliveries" INTEGER NOT NULL,
    "deliveriesCompleted" INTEGER NOT NULL DEFAULT 0,
    "estimatedReward" REAL NOT NULL DEFAULT 0,
    "pickedUpAt" DATETIME,
    "completedAt" DATETIME,
    "cancelledAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);

CREATE INDEX "OrderBatch_courierId_status_idx" ON "OrderBatch"("courierId", "status");
CREATE INDEX "OrderBatch_status_idx" ON "OrderBatch"("status");

-- ─── DispatchOffer: tip estimate + batch link ───────────────────────────────
ALTER TABLE "DispatchOffer" ADD COLUMN "tipEstimate" REAL NOT NULL DEFAULT 0;
ALTER TABLE "DispatchOffer" ADD COLUMN "batchId" TEXT;

CREATE INDEX "DispatchOffer_batchId_idx" ON "DispatchOffer"("batchId");

-- ─── Order: stacked-dispatch batch link + sequence ──────────────────────────
ALTER TABLE "Order" ADD COLUMN "batchId" TEXT REFERENCES "OrderBatch"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Order" ADD COLUMN "batchSequence" INTEGER;

-- ─── Payout: instant-payout fields ──────────────────────────────────────────
ALTER TABLE "Payout" ADD COLUMN "requestedAt" DATETIME;
ALTER TABLE "Payout" ADD COLUMN "source" TEXT NOT NULL DEFAULT 'weekly';
