'use strict';

const express = require('express');
const router = express.Router();
const { query, writeLog, hashPassword } = require('../config/db');
const { ok, err, superAdminRequired } = require('../middleware/auth');

// ── GET /api/super/admins ─────────────────────────────────────────────────────
router.get('/admins', superAdminRequired, async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        u.id, u.name, u.username, u.district, u.is_active, u.created_at,
        (SELECT COUNT(*) FROM matdan_sthal ms
         JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
         JOIN sectors s ON s.id=gp.sector_id
         JOIN zones z ON z.id=s.zone_id
         JOIN super_zones sz ON sz.id=z.super_zone_id
         WHERE sz.admin_id=u.id) AS total_booths,
        (SELECT COUNT(*) FROM duty_assignments da
         JOIN matdan_sthal ms2 ON ms2.id=da.sthal_id
         JOIN gram_panchayats gp2 ON gp2.id=ms2.gram_panchayat_id
         JOIN sectors s2 ON s2.id=gp2.sector_id
         JOIN zones z2 ON z2.id=s2.zone_id
         JOIN super_zones sz2 ON sz2.id=z2.super_zone_id
         WHERE sz2.admin_id=u.id) AS assigned_staff
      FROM users u WHERE u.role='admin' ORDER BY u.created_at DESC
    `);
    return ok(res, rows.map(r => ({
      id:           r.id,
      name:         r.name,
      username:     r.username,
      district:     r.district,
      isActive:     Boolean(r.is_active),
      createdAt:    r.created_at,
      totalBooths:  r.total_booths || 0,
      assignedStaff: r.assigned_staff || 0,
    })));
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── POST /api/super/admins ────────────────────────────────────────────────────
router.post('/admins', superAdminRequired, async (req, res) => {
  try {
    const { name, username, district, password } = req.body || {};
    if (!name?.trim() || !username?.trim() || !district?.trim() || !password)
      return err(res, 'name, username, district, password are all required');
    if (password.length < 6) return err(res, 'Password must be at least 6 characters');

    const dup = await query('SELECT id FROM users WHERE username=?', [username.trim()]);
    if (dup.length) return err(res, 'Username already taken', 409);

    const pool = await require('../config/db').getPool();
    const [result] = await pool.execute(
      "INSERT INTO users (name, username, password, role, district, is_active, created_by) VALUES (?,?,?,'admin',?,1,?)",
      [name.trim(), username.trim(), hashPassword(password), district.trim(), req.user.id]
    );
    await writeLog('INFO', `Admin '${name}' created for district '${district}' by super admin ID:${req.user.id}`, 'Auth');
    return ok(res, { id: result.insertId, name: name.trim(), username: username.trim(), district: district.trim() }, 'Admin created successfully', 201);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── GET /api/super/admins/:id ─────────────────────────────────────────────────
router.get('/admins/:id', superAdminRequired, async (req, res) => {
  try {
    const rows = await query(
      "SELECT id, name, username, district, is_active, created_at FROM users WHERE id=? AND role='admin'",
      [req.params.id]
    );
    if (!rows.length) return err(res, 'Admin not found', 404);
    const r = rows[0];
    return ok(res, { id: r.id, name: r.name, username: r.username, district: r.district, isActive: Boolean(r.is_active), createdAt: r.created_at });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── PUT /api/super/admins/:id ─────────────────────────────────────────────────
router.put('/admins/:id', superAdminRequired, async (req, res) => {
  try {
    const { name, username, district } = req.body || {};
    if (!name?.trim() || !username?.trim() || !district?.trim())
      return err(res, 'name, username, district required');
    const id = req.params.id;
    const rows = await query("SELECT id FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);
    const dup = await query('SELECT id FROM users WHERE username=? AND id!=?', [username.trim(), id]);
    if (dup.length) return err(res, 'Username already taken', 409);
    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET name=?, username=?, district=? WHERE id=?', [name.trim(), username.trim(), district.trim(), id]);
    await writeLog('INFO', `Admin updated ID:${id}`, 'Auth');
    return ok(res, null, 'Admin updated successfully');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── DELETE /api/super/admins/:id ──────────────────────────────────────────────
router.delete('/admins/:id', superAdminRequired, async (req, res) => {
  try {
    const id = req.params.id;
    const rows = await query("SELECT name FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);
    const pool = await require('../config/db').getPool();
    await pool.execute('DELETE FROM users WHERE id=?', [id]);
    await writeLog('WARN', `Admin '${rows[0].name}' (ID:${id}) deleted`, 'Auth');
    return ok(res, null, `Admin '${rows[0].name}' deleted`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── PATCH /api/super/admins/:id/toggle ────────────────────────────────────────
router.patch('/admins/:id/toggle', superAdminRequired, async (req, res) => {
  try {
    const id = req.params.id;
    const rows = await query("SELECT is_active FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);
    const newStatus = rows[0].is_active ? 0 : 1;
    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET is_active=? WHERE id=?', [newStatus, id]);
    await writeLog('INFO', `Admin status toggled ID:${id} -> ${newStatus}`, 'Auth');
    return ok(res, { isActive: Boolean(newStatus) }, 'Status updated');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── PATCH /api/super/admins/:id/reset-password ────────────────────────────────
router.patch('/admins/:id/reset-password', superAdminRequired, async (req, res) => {
  try {
    const { password } = req.body || {};
    if (!password || password.length < 6) return err(res, 'Password must be at least 6 characters');
    const id = req.params.id;
    const rows = await query("SELECT id FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);
    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET password=? WHERE id=?', [hashPassword(password), id]);
    await writeLog('WARN', `Password reset for admin ID:${id}`, 'Auth');
    return ok(res, null, 'Password reset successful');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── DELETE /api/super/admins/bulk ─────────────────────────────────────────────
router.delete('/admins/bulk', superAdminRequired, async (req, res) => {
  try {
    const ids = req.body?.ids;
    if (!Array.isArray(ids) || !ids.length) return err(res, 'ids list required');
    const pool = await require('../config/db').getPool();
    const ph = ids.map(() => '?').join(',');
    await pool.execute(`DELETE FROM users WHERE id IN (${ph}) AND role='admin'`, ids);
    await writeLog('WARN', `Bulk delete admins: ${ids}`, 'Auth');
    return ok(res, null, 'Admins deleted successfully');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── GET /api/super/overview ───────────────────────────────────────────────────
router.get('/overview', superAdminRequired, async (req, res) => {
  try {
    const [[admins], [booths], [duties], [staff]] = await Promise.all([
      query("SELECT COUNT(*) AS cnt FROM users WHERE role='admin'"),
      query('SELECT COUNT(*) AS cnt FROM matdan_sthal'),
      query('SELECT COUNT(*) AS cnt FROM duty_assignments'),
      query("SELECT COUNT(*) AS cnt FROM users WHERE role='staff'"),
    ]);
    return ok(res, { totalAdmins: admins.cnt, totalBooths: booths.cnt, assignedDuties: duties.cnt, totalStaff: staff.cnt });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

//form data
router.get('/form-data', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        u.id            AS adminId,
        u.name          AS adminName,
        u.district,

        COUNT(DISTINCT sz.id)  AS superZones,
        COUNT(DISTINCT z.id)   AS zones,
        COUNT(DISTINCT s.id)   AS sectors,
        COUNT(DISTINCT gp.id)  AS gramPanchayats,
        COUNT(DISTINCT ms.id)  AS centers,

        MAX(ms.created_at)     AS lastUpdated

      FROM users u

      LEFT JOIN super_zones     sz ON sz.admin_id        = u.id
      LEFT JOIN zones            z ON z.super_zone_id    = sz.id
      LEFT JOIN sectors          s ON s.zone_id          = z.id
      LEFT JOIN gram_panchayats gp ON gp.sector_id       = s.id
      LEFT JOIN matdan_sthal    ms ON ms.gram_panchayat_id = gp.id

      WHERE u.role = 'admin'

      GROUP BY u.id
      ORDER BY u.id DESC
    `);

    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error('get_form_data error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
