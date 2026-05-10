-- Phase 10: group orders, customer support tickets, push campaigns.

-- ─── OrderGroup ─────────────────────────────────────────────────────────────
CREATE TABLE "OrderGroup" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "hostUserId" TEXT NOT NULL,
    "shopId" TEXT NOT NULL,
    "joinCode" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'open',
    "maxMembers" INTEGER,
    "paymentMode" TEXT NOT NULL DEFAULT 'split',
    "expiresAt" DATETIME NOT NULL,
    "lockedAt" DATETIME,
    "paidAt" DATETIME,
    "cancelledAt" DATETIME,
    "orderId" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "OrderGroup_hostUserId_fkey" FOREIGN KEY ("hostUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "OrderGroup_joinCode_key" ON "OrderGroup"("joinCode");
CREATE UNIQUE INDEX "OrderGroup_orderId_key" ON "OrderGroup"("orderId");
CREATE INDEX "OrderGroup_status_expiresAt_idx" ON "OrderGroup"("status", "expiresAt");
CREATE INDEX "OrderGroup_hostUserId_idx" ON "OrderGroup"("hostUserId");

-- ─── OrderGroupMember ───────────────────────────────────────────────────────
CREATE TABLE "OrderGroupMember" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "groupId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "cartJson" TEXT NOT NULL DEFAULT '[]',
    "amountOwed" REAL NOT NULL DEFAULT 0,
    "paymentMethodId" TEXT,
    "joinedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "paidAt" DATETIME,
    "declinedAt" DATETIME,
    CONSTRAINT "OrderGroupMember_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "OrderGroup"("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "OrderGroupMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "OrderGroupMember_groupId_userId_key" ON "OrderGroupMember"("groupId", "userId");
CREATE INDEX "OrderGroupMember_userId_status_idx" ON "OrderGroupMember"("userId", "status");

-- ─── SupportTicket ──────────────────────────────────────────────────────────
CREATE TABLE "SupportTicket" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "authorId" TEXT NOT NULL,
    "category" TEXT,
    "orderId" TEXT,
    "subject" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'open',
    "priority" TEXT NOT NULL DEFAULT 'normal',
    "assigneeId" TEXT,
    "closedAt" DATETIME,
    "resolvedAt" DATETIME,
    "lastReplyAt" DATETIME,
    "lastReplyBy" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "SupportTicket_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "SupportTicket_assigneeId_fkey" FOREIGN KEY ("assigneeId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE INDEX "SupportTicket_status_priority_idx" ON "SupportTicket"("status", "priority");
CREATE INDEX "SupportTicket_authorId_status_idx" ON "SupportTicket"("authorId", "status");
CREATE INDEX "SupportTicket_assigneeId_status_idx" ON "SupportTicket"("assigneeId", "status");

-- ─── SupportMessage ─────────────────────────────────────────────────────────
CREATE TABLE "SupportMessage" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "ticketId" TEXT NOT NULL,
    "senderId" TEXT NOT NULL,
    "senderRole" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "attachments" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "SupportMessage_ticketId_fkey" FOREIGN KEY ("ticketId") REFERENCES "SupportTicket"("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "SupportMessage_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX "SupportMessage_ticketId_createdAt_idx" ON "SupportMessage"("ticketId", "createdAt");

-- ─── PushCampaign ───────────────────────────────────────────────────────────
CREATE TABLE "PushCampaign" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "titleUz" TEXT NOT NULL,
    "titleRu" TEXT NOT NULL,
    "titleEn" TEXT,
    "titleKk" TEXT,
    "bodyUz" TEXT NOT NULL,
    "bodyRu" TEXT NOT NULL,
    "bodyEn" TEXT,
    "bodyKk" TEXT,
    "deepLink" TEXT,
    "audienceQuery" TEXT NOT NULL DEFAULT '{}',
    "status" TEXT NOT NULL DEFAULT 'draft',
    "scheduledFor" DATETIME,
    "sentAt" DATETIME,
    "recipientCount" INTEGER NOT NULL DEFAULT 0,
    "successCount" INTEGER NOT NULL DEFAULT 0,
    "failureCount" INTEGER NOT NULL DEFAULT 0,
    "openCount" INTEGER NOT NULL DEFAULT 0,
    "createdById" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);

CREATE INDEX "PushCampaign_status_scheduledFor_idx" ON "PushCampaign"("status", "scheduledFor");
