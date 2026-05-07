const jwt = require('jsonwebtoken');
const prisma = require('../db');

async function authMiddleware(req, res, next) {
  try {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Missing token' });
    }
    const token = header.substring(7);
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      include: { shopMemberships: { include: { shop: true } } },
    });
    if (!user) return res.status(401).json({ error: 'User not found' });
    req.user = user;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

function requireRole(role) {
  return (req, res, next) => {
    const user = req.user;
    if (!user) return res.status(401).json({ error: 'Unauthorized' });
    if (role === 'courier' && !user.isCourier) {
      return res.status(403).json({ error: 'Courier role required' });
    }
    if (role === 'shop' && !user.isShop) {
      return res.status(403).json({ error: 'Shop role required' });
    }
    next();
  };
}

module.exports = { authMiddleware, requireRole };
