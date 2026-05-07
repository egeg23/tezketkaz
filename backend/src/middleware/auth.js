// Authentication & authorization middleware.
// Uses the JWT helpers in `../lib/jwt` (access-token verification with Redis
// blacklist), and Prisma user load including shop memberships. Role checks are
// secure-by-default — couriers MUST be both flagged AND `approved`.

const prisma = require('../db');
const jwtLib = require('../lib/jwt');
const logger = require('../lib/logger');

function unauthorized(res, message) {
  return res.status(401).json({ error: message });
}

function forbidden(res, message) {
  return res.status(403).json({ error: message });
}

async function loadUserFromToken(token) {
  const decoded = await jwtLib.verifyAccess(token);
  const user = await prisma.user.findUnique({
    where: { id: decoded.userId },
    include: { shopMemberships: { include: { shop: true } } },
  });
  return { decoded, user };
}

async function authMiddleware(req, res, next) {
  try {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      return unauthorized(res, 'Missing token');
    }
    const token = header.substring(7);
    let decoded;
    let user;
    try {
      ({ decoded, user } = await loadUserFromToken(token));
    } catch (err) {
      logger.warn({ err: err.message }, 'access token rejected');
      return unauthorized(res, 'Invalid token');
    }
    if (!user) return unauthorized(res, 'User not found');

    req.user = user;
    req.tokenJti = decoded.jti;
    req.tokenExp = decoded.exp;
    next();
  } catch (err) {
    next(err);
  }
}

async function optionalAuth(req, res, next) {
  try {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      return next();
    }
    const token = header.substring(7);
    try {
      const { decoded, user } = await loadUserFromToken(token);
      if (user) {
        req.user = user;
        req.tokenJti = decoded.jti;
        req.tokenExp = decoded.exp;
      }
    } catch (err) {
      // Optional auth — invalid token is silently ignored
      logger.debug?.({ err: err.message }, 'optionalAuth ignoring invalid token');
    }
    next();
  } catch (err) {
    next(err);
  }
}

function requireRole(role) {
  return (req, res, next) => {
    const user = req.user;
    if (!user) return unauthorized(res, 'Unauthorized');

    if (role === 'courier') {
      if (!user.isCourier || user.courierStatus !== 'approved') {
        return forbidden(res, 'Approved courier role required');
      }
      return next();
    }

    if (role === 'shop') {
      const hasMembership = Array.isArray(user.shopMemberships) && user.shopMemberships.length > 0;
      if (!user.isShop || !hasMembership) {
        return forbidden(res, 'Shop role required');
      }
      return next();
    }

    if (role === 'admin') {
      if (!user.isAdmin) {
        return forbidden(res, 'Admin role required');
      }
      return next();
    }

    return forbidden(res, 'Unknown role');
  };
}

const requireAdmin = requireRole('admin');

module.exports = {
  authMiddleware,
  optionalAuth,
  requireRole,
  requireAdmin,
};
