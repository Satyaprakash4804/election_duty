'use strict';

const express = require('express');
const router = express.Router();
const { query, writeLog, hashPassword, getPool } = require('../config/db');
const { ok, err, superAdminRequired } = require('../middleware/auth');

// ── Helper ────────────────────────────────────────────────────────────────────
function getDistrict(req) {
  return (req.user?.district || '').trim();
}

// ══════════════════════════════════════════════════════════════════════════════
//  1. GET ALL ADMINS    GET /super/admins
//     Filtered by the super-admin's own district
// ══════════════════════════════════════════════════════════════════════════════
router.get('/admins', superAdminRequired, async (req, res) => {
  try {
    const district = getDistrict(req);
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
      FROM users u
      WHERE u.role='admin'
        AND TRIM(LOWER(u.district)) = TRIM(LOWER(?))
      ORDER BY u.created_at DESC
    `, [district]);

    return ok(res, rows.map(r => ({
      id:            r.id,
      name:          r.name,
      username:      r.username,
      district:      r.district,
      isActive:      Boolean(r.is_active),
      createdAt:     r.created_at,
      totalBooths:   r.total_booths   || 0,
      assignedStaff: r.assigned_staff || 0,
    })));
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  2. CREATE ADMIN      POST /super/admins
//     Mirrors Python exactly:
//       - checks body.district !== super-admin's district → 403
//       - checks username duplicate → "Username exists" (Python's exact message)
//       - no extra field-presence validation beyond what Python does
//       - returns ok(null, "Admin created") — no 201 body object
// ══════════════════════════════════════════════════════════════════════════════
router.post('/admins', superAdminRequired, async (req, res) => {
  try {
    const body     = req.body || {};
    const district = getDistrict(req);

    // Python: if body.get("district") != district → 403
    if (body.district !== district)
      return err(res, 'Cannot create admin for another district', 403);

    const dup = await query('SELECT id FROM users WHERE username=?', [body.username]);
    if (dup.length) return err(res, 'Username exists');

    const pool = await getPool();
    await pool.execute(
      "INSERT INTO users (name, username, password, role, district, is_active, created_by) VALUES (?,?,?,'admin',?,1,?)",
      [body.name, body.username, hashPassword(body.password), district, req.user.id]
    );

    return ok(res, null, 'Admin created');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  3. BULK DELETE       DELETE /super/admins/bulk
//     MUST be declared BEFORE /admins/:id to avoid route shadowing
// ══════════════════════════════════════════════════════════════════════════════
router.delete('/admins/bulk', superAdminRequired, async (req, res) => {
  try {
    const ids = req.body?.ids;
    if (!Array.isArray(ids) || !ids.length) return err(res, 'ids list required');

    const pool = await getPool();
    const ph   = ids.map(() => '?').join(',');
    await pool.execute(`DELETE FROM users WHERE id IN (${ph}) AND role='admin'`, ids);

    await writeLog('WARN', `Bulk delete admins: ${ids}`, 'Auth');
    return ok(res, null, 'Admins deleted successfully');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  4. GET SINGLE ADMIN  GET /super/admins/:id
// ══════════════════════════════════════════════════════════════════════════════
router.get('/admins/:id', superAdminRequired, async (req, res) => {
  try {
    const rows = await query(
      "SELECT id, name, username, district, is_active, created_at FROM users WHERE id=? AND role='admin'",
      [req.params.id]
    );
    if (!rows.length) return err(res, 'Admin not found', 404);
    const r = rows[0];
    return ok(res, {
      id:        r.id,
      name:      r.name,
      username:  r.username,
      district:  r.district,
      isActive:  Boolean(r.is_active),
      createdAt: r.created_at ? (r.created_at instanceof Date ? r.created_at.toISOString() : r.created_at) : null,
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  5. UPDATE ADMIN      PUT /super/admins/:id
// ══════════════════════════════════════════════════════════════════════════════
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

    const pool = await getPool();
    await pool.execute(
      'UPDATE users SET name=?, username=?, district=? WHERE id=?',
      [name.trim(), username.trim(), district.trim(), id]
    );

    await writeLog('INFO', `Admin updated ID:${id}`, 'Auth');
    return ok(res, null, 'Admin updated successfully');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  6. DELETE ADMIN      DELETE /super/admins/:id
// ══════════════════════════════════════════════════════════════════════════════
router.delete('/admins/:id', superAdminRequired, async (req, res) => {
  try {
    const id   = req.params.id;
    const rows = await query("SELECT name FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);

    const pool = await getPool();
    await pool.execute('DELETE FROM users WHERE id=?', [id]);

    await writeLog('WARN', `Admin '${rows[0].name}' (ID:${id}) deleted`, 'Auth');
    return ok(res, null, `Admin '${rows[0].name}' deleted`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  7. TOGGLE ACTIVE     PATCH /super/admins/:id/toggle
// ══════════════════════════════════════════════════════════════════════════════
router.patch('/admins/:id/toggle', superAdminRequired, async (req, res) => {
  try {
    const id   = req.params.id;
    const rows = await query("SELECT is_active FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);

    const newStatus = rows[0].is_active ? 0 : 1;
    const pool = await getPool();
    await pool.execute('UPDATE users SET is_active=? WHERE id=?', [newStatus, id]);

    await writeLog('INFO', `Admin status toggled ID:${id} -> ${newStatus}`, 'Auth');
    return ok(res, { isActive: Boolean(newStatus) }, 'Status updated');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  8. RESET PASSWORD    PATCH /super/admins/:id/reset-password
// ══════════════════════════════════════════════════════════════════════════════
router.patch('/admins/:id/reset-password', superAdminRequired, async (req, res) => {
  try {
    const { password } = req.body || {};
    if (!password || password.length < 6)
      return err(res, 'Password must be at least 6 characters');

    const id   = req.params.id;
    const rows = await query("SELECT id FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);

    const pool = await getPool();
    await pool.execute('UPDATE users SET password=? WHERE id=?', [hashPassword(password), id]);

    await writeLog('WARN', `Password reset for admin ID:${id}`, 'Auth');
    return ok(res, null, 'Password reset successful');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  9. OVERVIEW STATS    GET /super/overview
//     Filtered by the super-admin's own district
// ══════════════════════════════════════════════════════════════════════════════
router.get('/overview', superAdminRequired, async (req, res) => {
  try {
    const district = getDistrict(req);

    // Sequential queries — mirrors Python's structure exactly
    const [adminsRow] = await query(
      "SELECT COUNT(*) AS cnt FROM users WHERE role='admin' AND district=?",
      [district]
    );
    const [boothsRow] = await query(`
      SELECT COUNT(DISTINCT ms.id) AS cnt
      FROM matdan_sthal ms
      JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
      JOIN sectors s ON s.id=gp.sector_id
      JOIN zones z ON z.id=s.zone_id
      JOIN super_zones sz ON sz.id=z.super_zone_id
      WHERE sz.district=?
    `, [district]);
    const [dutiesRow] = await query(`
      SELECT COUNT(*) AS cnt
      FROM duty_assignments da
      JOIN matdan_sthal ms ON ms.id=da.sthal_id
      JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
      JOIN sectors s ON s.id=gp.sector_id
      JOIN zones z ON z.id=s.zone_id
      JOIN super_zones sz ON sz.id=z.super_zone_id
      WHERE sz.district=?
    `, [district]);
    const [staffRow] = await query(
      "SELECT COUNT(*) AS cnt FROM users WHERE role='staff' AND district=?",
      [district]
    );

    return ok(res, {
      totalAdmins:    adminsRow.cnt,
      totalBooths:    boothsRow.cnt,
      assignedDuties: dutiesRow.cnt,
      totalStaff:     staffRow.cnt,
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
// 10. FORM DATA SUMMARY  GET /super/form-data
//     Filtered by the super-admin's own district
// ══════════════════════════════════════════════════════════════════════════════
router.get('/form-data', superAdminRequired, async (req, res) => {
  try {
    const district = getDistrict(req);
    const rows = await query(`
      SELECT
        u.id            AS adminId,
        u.name          AS adminName,
        u.district,
        COUNT(DISTINCT sz.id)  AS superZones,
        COUNT(DISTINCT z.id)   AS zones,
        COUNT(DISTINCT s.id)   AS sectors,
        COUNT(DISTINCT gp.id)  AS gramPanchayats,
        COUNT(DISTINCT ms.id)  AS centers
      FROM users u
      LEFT JOIN super_zones     sz ON sz.admin_id          = u.id
      LEFT JOIN zones            z ON z.super_zone_id      = sz.id
      LEFT JOIN sectors          s ON s.zone_id            = z.id
      LEFT JOIN gram_panchayats gp ON gp.sector_id         = s.id
      LEFT JOIN matdan_sthal    ms ON ms.gram_panchayat_id = gp.id
      WHERE u.role='admin'
        AND TRIM(LOWER(u.district)) = TRIM(LOWER(?))
      GROUP BY u.id
      ORDER BY u.id DESC
    `, [district]);

    return ok(res, rows);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
// 11. GET UNLOCK REQUESTS   GET /super/unlock-requests
//     ✅ ADDED — was entirely missing from JS
//     Returns all unlock requests for super-zones in the super-admin's district.
// ══════════════════════════════════════════════════════════════════════════════
router.get('/unlock-requests', superAdminRequired, async (req, res) => {
  try {
    const district = getDistrict(req);
    const rows = await query(`
      SELECT r.*, sz.name AS super_zone_name, u.name AS admin_name
      FROM sz_unlock_requests r
      JOIN super_zones sz ON sz.id = r.super_zone_id
      JOIN users u ON u.id = r.requested_by
      WHERE sz.district = ?
      ORDER BY r.created_at DESC
    `, [district]);

    return ok(res, rows);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
// 12. HANDLE UNLOCK REQUEST  POST /super/unlock-requests/:id/action
//     ✅ ADDED — was entirely missing from JS
//     action: "approve" → unlocks the super-zone duty lock
//     action: "reject"  → reverts lock status back to 'locked'
// ══════════════════════════════════════════════════════════════════════════════
router.post('/unlock-requests/:id/action', superAdminRequired, async (req, res) => {
  try {
    const body   = req.body || {};
    const action = body.action;

    if (!['approve', 'reject'].includes(action))
      return err(res, 'Invalid action');

    const reqId = req.params.id;
    const pool  = await getPool();
    const conn  = await pool.getConnection();
    try {
      await conn.beginTransaction();

      // Fetch the pending request — mirrors Python's SELECT + status='pending' check
      const [rows] = await conn.execute(
        "SELECT * FROM sz_unlock_requests WHERE id=? AND status='pending'",
        [reqId]
      );
      if (!rows.length) {
        await conn.rollback();
        return err(res, 'Request not found');
      }
      const unlockReq = rows[0];

      let newStatus;
      if (action === 'approve') {
        // 🔓 UNLOCK — mirrors Python exactly
        await conn.execute(
          "UPDATE sz_duty_locks SET is_locked=0, status='unlocked' WHERE super_zone_id=?",
          [unlockReq.super_zone_id]
        );
        newStatus = 'approved';
      } else {
        newStatus = 'rejected';
        // 🔁 Revert status back to 'locked' — mirrors Python exactly
        await conn.execute(
          "UPDATE sz_duty_locks SET status='locked' WHERE super_zone_id=?",
          [unlockReq.super_zone_id]
        );
      }

      // Update the request record with new status + reviewer
      await conn.execute(
        'UPDATE sz_unlock_requests SET status=?, reviewed_by=? WHERE id=?',
        [newStatus, req.user.id, reqId]
      );

      await conn.commit();
      return ok(res, null, `Request ${newStatus}`);
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }
  } catch (e) {
    return err(res, e.message, 500);
  }
});

module.exports = router;