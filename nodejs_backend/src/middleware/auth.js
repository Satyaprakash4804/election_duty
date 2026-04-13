'use strict';

const jwt = require('jsonwebtoken');
const config = require('../config');

// ── Response helpers ─────────────────────────────────────────────────────────
const ok = (res, data = null, message = 'success', code = 200) =>
  res.status(code).json({ status: 'success', message, data });

const err = (res, message = 'error', code = 400) =>
  res.status(code).json({ status: 'error', message });

// ── Token decode ─────────────────────────────────────────────────────────────
function decodeToken(token) {
  try {
    return jwt.verify(token, config.jwt.secret);
  } catch {
    return null;
  }
}

// ── Extract bearer token ──────────────────────────────────────────────────────
function extractToken(req) {
  const auth = req.headers.authorization || '';
  if (auth.startsWith('Bearer ')) return auth.slice(7);
  // Also support cookie (web platform)
  if (req.cookies && req.cookies.token) return req.cookies.token;
  return null;
}

// ── Base guard factory ───────────────────────────────────────────────────────
function roleGuard(...allowedRoles) {
  return (req, res, next) => {
    const token = extractToken(req);
    if (!token) return err(res, 'Missing or malformed token', 401);

    const payload = decodeToken(token);
    if (!payload) return err(res, 'Invalid or expired token', 401);

    if (!allowedRoles.includes(payload.role)) {
      return err(res, `Access denied — requires one of: ${allowedRoles.join(', ')}`, 403);
    }

    req.user = payload;
    next();
  };
}

// ── Exported guards ──────────────────────────────────────────────────────────
const masterRequired    = roleGuard('master');
const superAdminRequired = roleGuard('master', 'super_admin');
const adminRequired     = roleGuard('master', 'super_admin', 'admin');
const loginRequired     = roleGuard('master', 'super_admin', 'admin', 'staff');

module.exports = {
  ok,
  err,
  decodeToken,
  extractToken,
  masterRequired,
  superAdminRequired,
  adminRequired,
  loginRequired,
};
