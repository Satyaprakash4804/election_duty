'use strict';

const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { query, writeLog } = require('../config/db');
const { ok, err, loginRequired } = require('../middleware/auth');
const config = require('../config');

const SALT = config.passwordSalt;
function hashPassword(plain) {
  return crypto.createHash('sha256').update(plain + SALT).digest('hex');
}

// ── POST /api/login ───────────────────────────────────────────────────────────
router.post('/login', async (req, res) => {
  try {
    const body = req.body || {};
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

    const payload = {
      id:       user.id,
      username: user.username || user.pno,
      name:     user.name,
      role:     user.role,
      district: user.district || null,
      exp:      Math.floor(Date.now() / 1000) + config.jwt.expiry,
    };

    const token = jwt.sign(payload, config.jwt.secret, { algorithm: 'HS256' });
    await writeLog('INFO', `User '${user.name}' (${user.role}) logged in`, 'Auth');

    const isWeb = body.platform === 'web';
    const responseData = {
      user: {
        id:       user.id,
        name:     user.name,
        username: user.username,
        pno:      user.pno,
        role:     user.role.toUpperCase(),
        district: user.district || null,
        mobile:   user.mobile || null,
      },
    };

    if (!isWeb) {
      // Mobile → return token in JSON
      responseData.token = token;
      return ok(res, responseData, 'Login successful');
    }

    // Web → set HttpOnly cookie
    res.cookie('token', token, {
      httpOnly: true,
      secure: config.app.isProd,
      sameSite: 'Lax',
      maxAge: config.jwt.expiry * 1000,
    });
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
