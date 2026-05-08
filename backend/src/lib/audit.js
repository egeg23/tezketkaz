// Lightweight audit-log writer. Failures must NEVER break the request flow.
const prisma = require('../db');
const logger = require('./logger');

async function audit({ actorId, action, targetType, targetId, metadata, ipAddress }) {
  try {
    await prisma.auditLog.create({
      data: {
        actorId: actorId || null,
        action,
        targetType: targetType || null,
        targetId: targetId || null,
        metadata: metadata ? JSON.stringify(metadata) : null,
        ipAddress: ipAddress || null,
      },
    });
  } catch (err) {
    logger.warn({ err, action }, 'audit log failed');
  }
}

module.exports = { audit };
