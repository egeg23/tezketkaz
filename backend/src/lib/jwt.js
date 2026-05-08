// JWT helpers for access + refresh token issuance, verification, and rotation.
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const ms = require('./ms');
const env = require('../config/env');
const prisma = require('../db');
const redis = require('./redis');

const ACCESS_TTL = env.JWT_ACCESS_TTL;
const REFRESH_TTL = env.JWT_REFRESH_TTL;

function signAccess(userId) {
  const jti = uuidv4();
  const token = jwt.sign({ userId, type: 'access' }, env.JWT_SECRET, {
    expiresIn: ACCESS_TTL,
    jwtid: jti,
  });
  return { token, jti };
}

async function signRefresh(userId, { userAgent, ipAddress } = {}) {
  const jti = uuidv4();
  const expiresAt = new Date(Date.now() + ms(REFRESH_TTL));
  const token = jwt.sign({ userId, type: 'refresh' }, env.JWT_SECRET, {
    expiresIn: REFRESH_TTL,
    jwtid: jti,
  });
  await prisma.refreshToken.create({
    data: { userId, jti, expiresAt, userAgent, ipAddress },
  });
  return { token, jti, expiresAt };
}

async function verifyAccess(token) {
  const decoded = jwt.verify(token, env.JWT_SECRET);
  if (decoded.type && decoded.type !== 'access') {
    throw new Error('Wrong token type');
  }
  if (decoded.jti && (await redis.isJtiBlacklisted(decoded.jti))) {
    throw new Error('Token revoked');
  }
  return decoded;
}

async function verifyRefresh(token) {
  const decoded = jwt.verify(token, env.JWT_SECRET);
  if (decoded.type !== 'refresh') throw new Error('Wrong token type');

  const dbToken = await prisma.refreshToken.findUnique({ where: { jti: decoded.jti } });
  if (!dbToken) throw new Error('Refresh not found');
  if (dbToken.revokedAt) throw new Error('Refresh revoked');
  if (dbToken.expiresAt < new Date()) throw new Error('Refresh expired');

  return { decoded, dbToken };
}

async function rotateRefresh(oldDbToken, { userAgent, ipAddress } = {}) {
  const { token: newToken, jti: newJti, expiresAt } = await signRefresh(oldDbToken.userId, { userAgent, ipAddress });
  await prisma.refreshToken.update({
    where: { id: oldDbToken.id },
    data: { revokedAt: new Date(), replacedById: newJti },
  });
  return { token: newToken, jti: newJti, expiresAt };
}

async function revokeRefresh(jti) {
  try {
    await prisma.refreshToken.update({
      where: { jti },
      data: { revokedAt: new Date() },
    });
  } catch { /* not found — already gone */ }
}

async function revokeAllUserRefresh(userId) {
  await prisma.refreshToken.updateMany({
    where: { userId, revokedAt: null },
    data: { revokedAt: new Date() },
  });
}

async function blacklistAccessToken(token) {
  try {
    const decoded = jwt.decode(token);
    if (!decoded?.jti || !decoded?.exp) return;
    const ttl = decoded.exp - Math.floor(Date.now() / 1000);
    if (ttl > 0) await redis.blacklistJti(decoded.jti, ttl);
  } catch { /* ignore */ }
}

module.exports = {
  signAccess,
  signRefresh,
  verifyAccess,
  verifyRefresh,
  rotateRefresh,
  revokeRefresh,
  revokeAllUserRefresh,
  blacklistAccessToken,
};
