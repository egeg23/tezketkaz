-- Phase 9: GDPR (account deletion + data export) + OAuth identity columns.

-- ─── User: email, OAuth subjects, soft-delete flag ──────────────────────────
ALTER TABLE "User" ADD COLUMN "email" TEXT;
ALTER TABLE "User" ADD COLUMN "appleSubject" TEXT;
ALTER TABLE "User" ADD COLUMN "googleSubject" TEXT;
ALTER TABLE "User" ADD COLUMN "deletedAt" DATETIME;

CREATE UNIQUE INDEX "User_appleSubject_key" ON "User"("appleSubject");
CREATE UNIQUE INDEX "User_googleSubject_key" ON "User"("googleSubject");

-- ─── AccountDeletionRequest ─────────────────────────────────────────────────
CREATE TABLE "AccountDeletionRequest" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "reason" TEXT,
    "requestedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "scheduledFor" DATETIME NOT NULL,
    "completedAt" DATETIME,
    "cancelledAt" DATETIME,
    CONSTRAINT "AccountDeletionRequest_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "AccountDeletionRequest_status_scheduledFor_idx" ON "AccountDeletionRequest"("status", "scheduledFor");
CREATE INDEX "AccountDeletionRequest_userId_idx" ON "AccountDeletionRequest"("userId");

-- ─── DataExport ─────────────────────────────────────────────────────────────
CREATE TABLE "DataExport" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "fileUrl" TEXT,
    "expiresAt" DATETIME,
    "completedAt" DATETIME,
    "failedReason" TEXT,
    "requestedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "DataExport_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "DataExport_userId_status_idx" ON "DataExport"("userId", "status");
CREATE INDEX "DataExport_status_expiresAt_idx" ON "DataExport"("status", "expiresAt");
