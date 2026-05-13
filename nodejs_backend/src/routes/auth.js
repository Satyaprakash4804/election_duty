
const express = require('express');
const router  = express.Router();
const jwt     = require('jsonwebtoken');
const crypto  = require('crypto');
const { query, writeLog } = require('../config/db');
const { ok, err, loginRequired } = require('../middleware/auth');
const config  = require('../config');

const SALT = config.passwordSalt;
function hashPassword(plain) {
  return crypto.createHash('sha256').update(plain + SALT).digest('hex');
}

// ── POST /api/login ───────────────────────────────────────────────────────────
router.post('/login', async (req, res) => {
  try {
    const body     = req.body || {};
    const username = ((body.username || body.pno) || '').trim();
    const password = body.password || '';

    if (!username || !password) {
      return err(res, 'Username/PNO and password are required');
    }

    const rows = await query(
      'SELECT * FROM users WHERE (username = ? OR pno = ?) AND is_active = 1 LIMIT 1',
      [username, username]
    );

    const user = rows[0];
    if (!user) return err(res, 'Invalid credentials', 401);

    const hashedInput = hashPassword(password);
    if (hashedInput !== user.password) {
      await writeLog('WARN', `Failed login attempt for '${username}'`, 'Auth');
      return err(res, 'Invalid credentials', 401);
    }

    const now = Math.floor(Date.now() / 1000);
    const payload = {
      id:       user.id,
      username: user.username || user.pno,
      name:     user.name,
      role:     user.role,
      district: user.district || null,
      iat:      now,                                    // 🆕 explicit iat for revocation check
      exp:      now + config.jwt.expiry,
    };

    const token = jwt.sign(payload, config.jwt.secret, { algorithm: 'HS256' });
    await writeLog('INFO', `User '${user.name}' (${user.role}) logged in`, 'Auth');

    const responseData = {
      user: {
        id:       user.id,
        name:     user.name,
        username: user.username,
        pno:      user.pno,
        role:     user.role.toUpperCase(),
        district: user.district || null,
        mobile:   user.mobile  || null,
      },
      token,
    };

    const isWeb = body.platform === 'web';
    if (isWeb) {
      // Web → HttpOnly cookie (token still included in body for convenience)
      res.cookie('token', token, {
        httpOnly: true,
        secure:   config.app.isProd,
        sameSite: 'Lax',
        maxAge:   config.jwt.expiry * 1000,
      });
    }
    // Mobile → token in JSON body only (no cookie)
    return ok(res, responseData, 'Login successful');

  } catch (e) {
    console.error('Login error:', e);
    return err(res, 'Server error', 500);
  }
});

// ── POST /api/logout ──────────────────────────────────────────────────────────
router.post('/logout', (req, res) => {
  res.clearCookie('token');
  return ok(res, null, 'Logged out');
});

// ── GET /api/me ───────────────────────────────────────────────────────────────
router.get('/me', loginRequired, (req, res) => {
  return ok(res, req.user);
});

module.exports = router;