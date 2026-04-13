'use strict';

const express = require('express');
const router  = express.Router();
const { query, getPool, writeLog } = require('../config/db');
const { ok, err } = require('../middleware/auth');

let firebaseApp = null;

function getFirebaseApp() {
  if (firebaseApp) return firebaseApp;
  try {
    const admin = require('firebase-admin');
    if (admin.apps.length) { firebaseApp = admin.apps[0]; return firebaseApp; }
    const config = require('../config');
    const fs = require('fs');
    if (!fs.existsSync(config.firebase.serviceAccountPath)) return null;
    const serviceAccount = require(config.firebase.serviceAccountPath);
    firebaseApp = admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    return firebaseApp;
  } catch { return null; }
}

// ── POST /save-token ──────────────────────────────────────────────────────────
router.post('/save-token', async (req, res) => {
  try {
    const body       = req.body || {};
    const token      = body.token;
    const userId     = body.user_id;
    const userAgent  = body.user_agent || req.headers['user-agent'] || '';
    const deviceName = body.device_name || 'Unknown Device';

    if (!token || !userId) return err(res, 'Token or user_id missing');

    const ipAddress = req.ip || req.connection.remoteAddress || '';
    let browser = 'Unknown', osName = 'Unknown';

    try {
      const UAParser = require('ua-parser-js');
      const ua = UAParser(userAgent);
      browser = ua.browser?.name || 'Unknown';
      osName  = ua.os?.name      || 'Unknown';
    } catch {}

    const pool = await getPool();
    await pool.execute('UPDATE fcm_tokens SET is_active=0 WHERE user_id=?', [userId]);
    await pool.execute(
      `INSERT INTO fcm_tokens (user_id, token, device_name, browser, os, user_agent, ip_address, is_active)
       VALUES (?,?,?,?,?,?,?,1)
       ON DUPLICATE KEY UPDATE user_id=VALUES(user_id), device_name=VALUES(device_name),
         browser=VALUES(browser), os=VALUES(os), user_agent=VALUES(user_agent),
         ip_address=VALUES(ip_address), is_active=1`,
      [userId, token, deviceName, browser, osName, userAgent, ipAddress]
    );
    return ok(res, { status: 'saved' });
  } catch (e) {
    console.error('FCM SAVE ERROR:', e);
    return err(res, 'Server error', 500);
  }
});

// ── GET /send-notification ────────────────────────────────────────────────────
router.get('/send-notification', async (req, res) => {
  try {
    const app = getFirebaseApp();
    if (!app) return err(res, 'Firebase not configured', 503);

    const rows = await query('SELECT token FROM fcm_tokens WHERE is_active=1');
    if (!rows.length) return err(res, 'No active tokens found', 400);

    const admin    = require('firebase-admin');
    const messaging = admin.messaging(app);
    let success = 0, failed = 0;

    for (const row of rows) {
      try {
        await messaging.send({
          notification: { title: 'Election Update', body: 'Notification sent using DB tokens 🚀' },
          token: row.token,
        });
        success++;
      } catch (e) {
        console.error('❌ Error sending:', e.message);
        failed++;
      }
    }
    return ok(res, { message: 'Notification process completed', success, failed });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

module.exports = router;
