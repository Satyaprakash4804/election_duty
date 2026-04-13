'use strict';

const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const { query, writeLog } = require('../config/db');
const { ok, err, loginRequired } = require('../middleware/auth');
const config = require('../config');

const SALT = config.passwordSalt;
function hashPassword(plain) {
  return crypto.createHash('sha256').update(plain + SALT).digest('hex');
}

// ── GET /api/staff/my-duty ────────────────────────────────────────────────────
router.get('/my-duty', loginRequired, async (req, res) => {
  try {
    const staffId = req.user.id;

    const rows = await query(`
      SELECT
        da.id AS duty_id, da.bus_no,
        ms.id AS center_id, ms.name AS center_name, ms.address AS center_address,
        ms.thana, ms.center_type, ms.latitude, ms.longitude,
        gp.id AS gp_id, s.id AS sector_id, z.id AS zone_id, sz.id AS super_zone_id,
        gp.name AS gp_name, gp.address AS gp_address,
        s.name AS sector_name,
        z.name AS zone_name, z.hq_address AS zone_hq,
        sz.name AS super_zone_name,
        u2.name AS assigned_by_name
      FROM duty_assignments da
      JOIN matdan_sthal ms    ON ms.id = da.sthal_id
      JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
      JOIN sectors s          ON s.id  = gp.sector_id
      JOIN zones z            ON z.id  = s.zone_id
      JOIN super_zones sz     ON sz.id = z.super_zone_id
      LEFT JOIN users u2      ON u2.id = da.assigned_by
      WHERE da.staff_id = ?
    `, [staffId]);

    if (!rows.length) return ok(res, null, 'No duty assigned yet');
    const row = rows[0];

    const [allStaff, sectorOfficers, zonalOfficers, superOfficers] = await Promise.all([
      query(`
        SELECT u.name, u.pno, u.mobile, u.thana, u.district, u.user_rank
        FROM duty_assignments da2 JOIN users u ON u.id=da2.staff_id
        WHERE da2.sthal_id=? ORDER BY u.name
      `, [row.center_id]),
      query(`
        SELECT COALESCE(u.name,so.name) AS name, COALESCE(u.pno,so.pno) AS pno,
               COALESCE(u.mobile,so.mobile) AS mobile, COALESCE(u.user_rank,so.user_rank) AS user_rank
        FROM sector_officers so LEFT JOIN users u ON u.id=so.user_id
        WHERE so.sector_id=?
      `, [row.sector_id]),
      query(`
        SELECT COALESCE(u.name,zo.name) AS name, COALESCE(u.pno,zo.pno) AS pno,
               COALESCE(u.mobile,zo.mobile) AS mobile, COALESCE(u.user_rank,zo.user_rank) AS user_rank
        FROM zonal_officers zo LEFT JOIN users u ON u.id=zo.user_id
        WHERE zo.zone_id=?
      `, [row.zone_id]),
      query(`
        SELECT COALESCE(u.name,ko.name) AS name, COALESCE(u.pno,ko.pno) AS pno,
               COALESCE(u.mobile,ko.mobile) AS mobile, COALESCE(u.user_rank,ko.user_rank) AS user_rank
        FROM kshetra_officers ko LEFT JOIN users u ON u.id=ko.user_id
        WHERE ko.super_zone_id=?
      `, [row.super_zone_id]),
    ]);

    return ok(res, {
      dutyId:         row.duty_id,
      busNo:          row.bus_no,
      centerId:       row.center_id,
      centerName:     row.center_name,
      centerAddress:  row.center_address,
      thana:          row.thana,
      centerType:     row.center_type,
      latitude:       row.latitude != null ? parseFloat(row.latitude) : null,
      longitude:      row.longitude != null ? parseFloat(row.longitude) : null,
      gpName:         row.gp_name,
      gpAddress:      row.gp_address,
      sectorName:     row.sector_name,
      zoneName:       row.zone_name,
      zoneHq:         row.zone_hq,
      superZoneName:  row.super_zone_name,
      assignedBy:     row.assigned_by_name,
      allStaff,
      sectorOfficers,
      zonalOfficers,
      superOfficers,
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── GET /api/staff/profile ────────────────────────────────────────────────────
router.get('/profile', loginRequired, async (req, res) => {
  try {
    const rows = await query(
      'SELECT id, name, pno, mobile, thana, district, user_rank, is_active FROM users WHERE id=?',
      [req.user.id]
    );
    if (!rows.length) return err(res, 'User not found', 404);
    const r = rows[0];
    return ok(res, {
      id:        r.id,
      name:      r.name,
      pno:       r.pno,
      mobile:    r.mobile,
      thana:     r.thana,
      district:  r.district,
      user_rank: r.user_rank,
      isActive:  Boolean(r.is_active),
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── POST /api/staff/change-password ──────────────────────────────────────────
router.post('/change-password', loginRequired, async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body || {};
    if (!newPassword || newPassword.length < 6)
      return err(res, 'पासवर्ड कम से कम 6 अक्षर का होना चाहिए');

    const rows = await query('SELECT password FROM users WHERE id=?', [req.user.id]);
    if (!rows.length) return err(res, 'User not found', 404);

    const currentHash = hashPassword(currentPassword || '');
    if (currentHash !== rows[0].password)
      return err(res, 'वर्तमान पासवर्ड गलत है', 401);

    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET password=? WHERE id=?', [hashPassword(newPassword), req.user.id]);
    return ok(res, null, 'पासवर्ड बदल दिया गया');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

module.exports = router;
