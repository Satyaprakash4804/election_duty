'use strict';

const jwt    = require('jsonwebtoken');
const config = require('../config');
const { query, writeLog } = require('../config/db');

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

// ── Extract bearer / cookie token ────────────────────────────────────────────
function extractToken(req) {
  const auth = req.headers.authorization || '';
  if (auth.startsWith('Bearer ')) return auth.slice(7);
  if (req.cookies && req.cookies.token) return req.cookies.token;
  return null;
}


// ── Token revocation check ───────────────────────────────────────────────────
// Master can call a "force-logout by role" endpoint that writes a timestamp
// into token_revocations. Any token issued BEFORE that timestamp is rejected.
async function isTokenRevoked(payload) {
  try {
    const { role, iat } = payload;
    if (!role || !iat) return false;

    const rows = await query(
      'SELECT revoke_before FROM token_revocations WHERE role = ? LIMIT 1',
      [role]
    );
    if (!rows || rows.length === 0) return false;

    return parseInt(iat) < parseInt(rows[0].revoke_before);
  } catch {
    return false; // Fail open on DB errors — never lock users out
  }
}


// ── Base guard factory ───────────────────────────────────────────────────────
function roleGuard(...allowedRoles) {
  return async (req, res, next) => {
    const token = extractToken(req);
    if (!token) return err(res, 'Missing or malformed token', 401);

    const payload = decodeToken(token);
    if (!payload) return err(res, 'Invalid or expired token', 401);

    // 🆕 Revocation check (force-logout by role)
    if (await isTokenRevoked(payload)) {
      return err(res, 'Session expired — please log in again', 401);
    }

    if (!allowedRoles.includes(payload.role)) {
      return err(res, `Access denied — requires one of: ${allowedRoles.join(', ')}`, 403);
    }

    req.user = payload;
    next();
  };
}

// ── Exported role guards ─────────────────────────────────────────────────────
const masterRequired     = roleGuard('master');
const superAdminRequired = roleGuard('master', 'super_admin');
const adminRequired      = roleGuard('master', 'super_admin', 'admin');
const loginRequired      = roleGuard('master', 'super_admin', 'admin', 'staff');


// ────────────────────────────────────────────────────────────────────────────
//  API REQUEST LOGGER
//  Wire up in app.js / server.js:
//    app.use(startRequestTimer);
//    app.use(logRequestEnd);          ← after_request equivalent
//    app.use(logException);           ← error-handler (4-arg)
// ────────────────────────────────────────────────────────────────────────────

/** Persist one row to api_request_logs. Never throws. */
async function writeApiLog({
  method, path, statusCode, durationMs,
  userId = null, username = null, role = null,
  ip = null, userAgent = null, requestBody = null,
  errorMessage = null,
}) {
  try {
    let level = 'INFO';
    if (statusCode >= 500) level = 'ERROR';
    else if (statusCode >= 400) level = 'WARN';

    if (requestBody && requestBody.length > 2000) {
      requestBody = requestBody.slice(0, 2000) + '…(truncated)';
    }

    await query(
      `INSERT INTO api_request_logs
         (method, path, status_code, duration_ms, user_id, username,
          role, ip_address, user_agent, request_body, error_message, level)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        method, (path || '').slice(0, 500), statusCode, durationMs,
        userId, username, role,
        ip, (userAgent || '').slice(0, 500),
        requestBody, errorMessage, level,
      ]
    );
  } catch {
    // Never let logging crash the app
  }
}

/** Best-effort extraction of user info from the incoming JWT. No throw. */
function extractUserFromRequest(req) {
  try {
    const token = extractToken(req);
    if (!token) return [null, null, null];
    const payload = decodeToken(token);
    if (!payload) return [null, null, null];
    return [payload.id ?? null, payload.username ?? null, payload.role ?? null];
  } catch {
    return [null, null, null];
  }
}

/** before-request middleware — stamps req._startAt */
function startRequestTimer(req, _res, next) {
  req._startAt = process.hrtime.bigint();
  next();
}

/** after-request middleware — logs every response */
async function logRequestEnd(req, res, next) {
  // Patch res.json so we can capture the status AFTER it is set
  const _json = res.json.bind(res);
  res.json = function (body) {
    res._logBody = body;
    return _json(body);
  };

  res.on('finish', async () => {
    try {
      const path = req.path || '';
      if (path === '/ping' || path.startsWith('/static')) return;

      const durationMs = req._startAt
        ? Number(process.hrtime.bigint() - req._startAt) / 1e6 | 0
        : 0;

      // Scrub passwords from logged body
      let bodyStr = null;
      if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
        try {
          if (req.is('json') && req.body && typeof req.body === 'object') {
            const safe = Object.fromEntries(
              Object.entries(req.body).map(([k, v]) =>
                [k, k.toLowerCase().includes('password') ? '***' : v]
              )
            );
            bodyStr = JSON.stringify(safe).slice(0, 2000);
          }
        } catch { /* ignore */ }
      }

      const [userId, username, role] = extractUserFromRequest(req);

      let errorMessage = null;
      if (res.statusCode >= 400 && res._logBody) {
        errorMessage = res._logBody.message || res._logBody.error || null;
      }

      await writeApiLog({
        method:       req.method,
        path,
        statusCode:   res.statusCode,
        durationMs,
        userId,
        username,
        role,
        ip:           req.ip || req.connection?.remoteAddress,
        userAgent:    req.headers['user-agent'],
        requestBody:  bodyStr,
        errorMessage,
      });
    } catch { /* never crash */ }
  });

  next();
}

/** Express error-handler — logs uncaught 500s */
async function logException(err, req, res, next) {
  try {
    const durationMs = req._startAt
      ? Number(process.hrtime.bigint() - req._startAt) / 1e6 | 0
      : 0;

    const [userId, username, role] = extractUserFromRequest(req);
    const stack = (err.stack || '').slice(0, 1500);

    await writeApiLog({
      method:       req.method,
      path:         (req.path || '').slice(0, 500),
      statusCode:   500,
      durationMs,
      userId,
      username,
      role,
      ip:           req.ip || req.connection?.remoteAddress,
      userAgent:    req.headers['user-agent'],
      requestBody:  null,
      errorMessage: `${err.name || 'Error'}: ${err.message}\n${stack}`,
    });
  } catch { /* never crash */ }

  // Pass to next error handler (or default Express 500)
  next(err);
}


module.exports = {
  // Response helpers
  ok,
  err,

  // Token utilities
  decodeToken,
  extractToken,
  isTokenRevoked,

  // Role guards
  masterRequired,
  superAdminRequired,
  adminRequired,
  loginRequired,

  // Request logging
  writeApiLog,
  startRequestTimer,
  logRequestEnd,
  logException,
};