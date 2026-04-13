'use strict';

const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const { query, withTransaction, writeLog, hashPassword, verifyPassword } = require('../config/db');
const { ok, err, masterRequired } = require('../middleware/auth');
const config = require('../config');

// ── 1. GET /api/master/config ─────────────────────────────────────────────────
router.get('/config', masterRequired, async (req, res) => {
  try {
    const rows = await query('SELECT `key`, value FROM app_config');
    const cfg = {};
    rows.forEach(r => { cfg[r.key] = r.value; });
    return ok(res, cfg);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 2. POST /api/master/config ────────────────────────────────────────────────
router.post('/config', masterRequired, async (req, res) => {
  try {
    const body = req.body || {};
    if (!Object.keys(body).length) return err(res, 'Request body is empty');

    let pairs;
    if ('key' in body && 'value' in body && Object.keys(body).length === 2) {
      pairs = { [body.key]: body.value };
    } else {
      pairs = body;
    }

    await withTransaction(async conn => {
      for (const [k, v] of Object.entries(pairs)) {
        await conn.execute(
          'INSERT INTO app_config (`key`, value) VALUES (?,?) ON DUPLICATE KEY UPDATE value=VALUES(value)',
          [String(k), String(v)]
        );
      }
    });

    await writeLog('INFO', `Config updated: ${Object.keys(pairs).join(',')} by master`, 'Config');
    return ok(res, pairs, 'Config updated successfully');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 3. DELETE /api/master/config/:key ────────────────────────────────────────
router.delete('/config/:key', masterRequired, async (req, res) => {
  try {
    const [result] = await (await (require('../config/db').getPool()))
      .execute('DELETE FROM app_config WHERE `key`=?', [req.params.key]);
    if (!result.affectedRows) return err(res, 'Config key not found', 404);
    await writeLog('INFO', `Config key '${req.params.key}' deleted`, 'Config');
    return ok(res, null, `Config key '${req.params.key}' deleted`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 4. GET /api/master/super-admins ──────────────────────────────────────────
router.get('/super-admins', masterRequired, async (req, res) => {
  try {
    const rows = await query(`
      SELECT sa.id, sa.name, sa.username, sa.is_active, sa.created_at,
             COUNT(a.id) AS admins_under
      FROM users sa
      LEFT JOIN users a ON a.created_by=sa.id AND a.role='admin'
      WHERE sa.role='super_admin'
      GROUP BY sa.id ORDER BY sa.created_at DESC
    `);
    const cfgRows = await query('SELECT `key`, value FROM app_config');
    const cfg = {};
    cfgRows.forEach(r => { cfg[r.key] = r.value; });

    return ok(res, rows.map(r => ({
      id:          r.id,
      name:        r.name,
      username:    r.username,
      isActive:    Boolean(r.is_active),
      createdAt:   r.created_at,
      adminsUnder: r.admins_under,
      electionInfo: {
        state:        cfg.state || '',
        electionYear: cfg.electionYear || '',
        electionDate: cfg.electionDate || '',
        phase:        cfg.phase || '',
      },
    })));
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 5. POST /api/master/super-admins ─────────────────────────────────────────
router.post('/super-admins', masterRequired, async (req, res) => {
  try {
    const { name, username, password } = req.body || {};
    if (!name?.trim() || !username?.trim() || !password)
      return err(res, 'name, username and password are required');
    if (password.length < 6) return err(res, 'Password must be at least 6 characters');

    const existing = await query('SELECT id FROM users WHERE username=?', [username.trim()]);
    if (existing.length) return err(res, 'Username already taken', 409);

    const pool = await require('../config/db').getPool();
    const [result] = await pool.execute(
      "INSERT INTO users (name, username, password, role, is_active, created_by) VALUES (?,?,?,'super_admin',1,?)",
      [name.trim(), username.trim(), hashPassword(password), req.user.id]
    );
    await writeLog('INFO', `Super Admin '${name}' created by master`, 'Auth');
    return ok(res, { id: result.insertId, name: name.trim(), username: username.trim() }, 'Super Admin created', 201);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 6. GET /api/master/super-admins/:id ──────────────────────────────────────
router.get('/super-admins/:id', masterRequired, async (req, res) => {
  try {
    const rows = await query(
      "SELECT id, name, username, is_active, created_at FROM users WHERE id=? AND role='super_admin'",
      [req.params.id]
    );
    if (!rows.length) return err(res, 'Super Admin not found', 404);
    const r = rows[0];
    return ok(res, { id: r.id, name: r.name, username: r.username, isActive: Boolean(r.is_active), createdAt: r.created_at });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 7. PUT /api/master/super-admins/:id ──────────────────────────────────────
router.put('/super-admins/:id', masterRequired, async (req, res) => {
  try {
    const { name, username } = req.body || {};
    if (!name?.trim() || !username?.trim()) return err(res, 'name and username required');
    const id = req.params.id;

    const exists = await query("SELECT id FROM users WHERE id=? AND role='super_admin'", [id]);
    if (!exists.length) return err(res, 'Super Admin not found', 404);
    const dup = await query('SELECT id FROM users WHERE username=? AND id!=?', [username.trim(), id]);
    if (dup.length) return err(res, 'Username already taken', 409);

    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET name=?, username=? WHERE id=?', [name.trim(), username.trim(), id]);
    await writeLog('INFO', `Super Admin ID:${id} updated by master`, 'Auth');
    return ok(res, null, 'Super Admin updated');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 8. DELETE /api/master/super-admins/:id ───────────────────────────────────
router.delete('/super-admins/:id', masterRequired, async (req, res) => {
  try {
    const id = req.params.id;
    const rows = await query("SELECT name FROM users WHERE id=? AND role='super_admin'", [id]);
    if (!rows.length) return err(res, 'Super Admin not found', 404);
    const pool = await require('../config/db').getPool();
    await pool.execute("UPDATE users SET created_by=NULL WHERE created_by=? AND role='admin'", [id]);
    await pool.execute('DELETE FROM users WHERE id=?', [id]);
    await writeLog('WARN', `Super Admin '${rows[0].name}' (ID:${id}) deleted`, 'Auth');
    return ok(res, null, `Super Admin '${rows[0].name}' deleted`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 9. PATCH /api/master/super-admins/:id/status ─────────────────────────────
router.patch('/super-admins/:id/status', masterRequired, async (req, res) => {
  try {
    const { isActive } = req.body || {};
    if (isActive == null) return err(res, 'isActive field required');
    const id = req.params.id;
    const rows = await query("SELECT name FROM users WHERE id=? AND role='super_admin'", [id]);
    if (!rows.length) return err(res, 'Super Admin not found', 404);
    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET is_active=? WHERE id=?', [isActive ? 1 : 0, id]);
    const action = isActive ? 'activated' : 'deactivated';
    await writeLog('INFO', `Super Admin '${rows[0].name}' (ID:${id}) ${action}`, 'Auth');
    return ok(res, { id: Number(id), isActive: Boolean(isActive) }, `Super Admin ${action}`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 10. PATCH /api/master/super-admins/:id/reset-password ────────────────────
router.patch('/super-admins/:id/reset-password', masterRequired, async (req, res) => {
  try {
    const { password } = req.body || {};
    if (!password || password.length < 6) return err(res, 'Password must be at least 6 characters');
    const id = req.params.id;
    const rows = await query("SELECT id FROM users WHERE id=? AND role='super_admin'", [id]);
    if (!rows.length) return err(res, 'Super Admin not found', 404);
    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET password=? WHERE id=?', [hashPassword(password), id]);
    await writeLog('WARN', `Password reset for Super Admin ID:${id}`, 'Auth');
    return ok(res, null, 'Password reset successful');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 11. GET /api/master/admins ────────────────────────────────────────────────
router.get('/admins', masterRequired, async (req, res) => {
  try {
    const rows = await query(`
      SELECT u.id, u.name, u.username, u.district, u.is_active, u.created_at,
             creator.name AS created_by_name,
             (SELECT COUNT(*) FROM super_zones sz WHERE sz.admin_id=u.id) AS super_zone_count
      FROM users u
      LEFT JOIN users creator ON creator.id=u.created_by
      WHERE u.role='admin'
      ORDER BY u.created_at DESC
    `);
    return ok(res, rows.map(r => ({
      id:             r.id,
      name:           r.name,
      username:       r.username,
      district:       r.district || '',
      isActive:       Boolean(r.is_active),
      createdAt:      r.created_at,
      createdBy:      r.created_by_name || 'master',
      superZoneCount: r.super_zone_count,
    })));
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 12. POST /api/master/admins ───────────────────────────────────────────────
router.post('/admins', masterRequired, async (req, res) => {
  try {
    const { name, username, district, password } = req.body || {};
    if (!name?.trim() || !username?.trim() || !district?.trim() || !password)
      return err(res, 'name, username, district and password are all required');
    if (password.length < 6) return err(res, 'Password must be at least 6 characters');

    const dup = await query('SELECT id FROM users WHERE username=?', [username.trim()]);
    if (dup.length) return err(res, 'Username already taken', 409);

    const pool = await require('../config/db').getPool();
    const [result] = await pool.execute(
      "INSERT INTO users (name, username, password, role, district, is_active, created_by) VALUES (?,?,?,'admin',?,1,?)",
      [name.trim(), username.trim(), hashPassword(password), district.trim(), req.user.id]
    );
    await writeLog('INFO', `Admin '${name}' (district:${district}) created by master`, 'Auth');
    return ok(res, { id: result.insertId, name: name.trim(), username: username.trim(), district: district.trim() }, 'Admin created', 201);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 13. PUT /api/master/admins/:id ────────────────────────────────────────────
router.put('/admins/:id', masterRequired, async (req, res) => {
  try {
    const { name, username, district } = req.body || {};
    if (!name?.trim() || !username?.trim() || !district?.trim())
      return err(res, 'name, username and district required');
    const id = req.params.id;
    const rows = await query("SELECT id FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);
    const dup = await query('SELECT id FROM users WHERE username=? AND id!=?', [username.trim(), id]);
    if (dup.length) return err(res, 'Username already taken', 409);
    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET name=?, username=?, district=? WHERE id=?', [name.trim(), username.trim(), district.trim(), id]);
    await writeLog('INFO', `Admin ID:${id} updated by master`, 'Auth');
    return ok(res, null, 'Admin updated');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 14. DELETE /api/master/admins/:id ─────────────────────────────────────────
router.delete('/admins/:id', masterRequired, async (req, res) => {
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

// ── 15. PATCH /api/master/admins/:id/status ───────────────────────────────────
router.patch('/admins/:id/status', masterRequired, async (req, res) => {
  try {
    const { isActive } = req.body || {};
    if (isActive == null) return err(res, 'isActive field required');
    const id = req.params.id;
    const rows = await query("SELECT name FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);
    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET is_active=? WHERE id=?', [isActive ? 1 : 0, id]);
    const action = isActive ? 'activated' : 'deactivated';
    await writeLog('INFO', `Admin ID:${id} ${action}`, 'Auth');
    return ok(res, { id: Number(id), isActive: Boolean(isActive) }, `Admin ${action}`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 16. PATCH /api/master/admins/:id/reset-password ──────────────────────────
router.patch('/admins/:id/reset-password', masterRequired, async (req, res) => {
  try {
    const { password } = req.body || {};
    if (!password || password.length < 6) return err(res, 'Password must be at least 6 characters');
    const id = req.params.id;
    const rows = await query("SELECT id FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);
    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET password=? WHERE id=?', [hashPassword(password), id]);
    await writeLog('WARN', `Password reset for Admin ID:${id}`, 'Auth');
    return ok(res, null, 'Password reset successful');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 17. GET /api/master/overview ──────────────────────────────────────────────
router.get('/overview', masterRequired, async (req, res) => {
  try {
    const [[superAdmins], [admins], [staff], [booths], [duties], cfgRows] = await Promise.all([
      query("SELECT COUNT(*) AS cnt FROM users WHERE role='super_admin'"),
      query("SELECT COUNT(*) AS cnt FROM users WHERE role='admin'"),
      query("SELECT COUNT(*) AS cnt FROM users WHERE role='staff' AND is_active=1"),
      query('SELECT COUNT(*) AS cnt FROM matdan_sthal'),
      query('SELECT COUNT(*) AS cnt FROM duty_assignments'),
      query('SELECT `key`, value FROM app_config'),
    ]);
    const cfg = {};
    cfgRows.forEach(r => { cfg[r.key] = r.value; });
    return ok(res, {
      totalSuperAdmins: superAdmins.cnt,
      totalAdmins:      admins.cnt,
      totalStaff:       staff.cnt,
      totalBooths:      booths.cnt,
      assignedDuties:   duties.cnt,
      electionInfo: {
        state:        cfg.state || 'Not set',
        electionYear: cfg.electionYear || 'Not set',
        electionDate: cfg.electionDate || 'Not set',
        phase:        cfg.phase || 'Not set',
      },
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 18. GET /api/master/system-stats ─────────────────────────────────────────
router.get('/system-stats', masterRequired, async (req, res) => {
  try {
    const [sizeRow] = await query(`
      SELECT ROUND(SUM(data_length+index_length)/1024/1024,2) AS size_mb
      FROM information_schema.tables WHERE table_schema=DATABASE()
    `);
    const tables = ['users','duty_assignments','matdan_kendra','matdan_sthal','sectors','zones','super_zones','gram_panchayats'];
    let total = 0;
    for (const t of tables) {
      try {
        const [r] = await query(`SELECT COUNT(*) AS cnt FROM \`${t}\``);
        total += r.cnt;
      } catch {}
    }
    const [backupRow] = await query(
      "SELECT time FROM system_logs WHERE module='DB' AND message LIKE 'Database backup%' ORDER BY time DESC LIMIT 1"
    );
    const [firstLog] = await query('SELECT MIN(time) AS first FROM system_logs');
    let uptime = 'N/A';
    if (firstLog?.first) {
      const ms = Date.now() - new Date(firstLog.first).getTime();
      const d = Math.floor(ms / 86400000);
      const h = Math.floor((ms % 86400000) / 3600000);
      const m = Math.floor((ms % 3600000) / 60000);
      uptime = `${d}d ${h}h ${m}m`;
    }
    return ok(res, {
      dbSize:       sizeRow?.size_mb ? `${sizeRow.size_mb} MB` : 'N/A',
      totalRecords: total,
      uptime,
      lastBackup:   backupRow?.time ? new Date(backupRow.time).toLocaleString() : 'Never',
      backend:      'Node.js/Express',
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 19. GET /api/master/logs ──────────────────────────────────────────────────
router.get('/logs', masterRequired, async (req, res) => {
  try {
    const level  = (req.query.level || 'ALL').toUpperCase();
    const limit  = Math.min(parseInt(req.query.limit, 10) || 100, 500);
    const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);

    const rows = level === 'ALL'
      ? await query(`SELECT * FROM system_logs ORDER BY time DESC LIMIT ${limit} OFFSET ${offset}`, [])
      : await query(`SELECT * FROM system_logs WHERE level=? ORDER BY time DESC LIMIT ${limit} OFFSET ${offset}`, [level]);

    return ok(res, rows.map(r => ({
      id:      r.id,
      level:   r.level,
      message: r.message,
      module:  r.module,
      time:    r.time,
    })));
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 20. POST /api/master/db/backup ───────────────────────────────────────────
router.post('/db/backup', masterRequired, async (req, res) => {
  try {
    const backupDir = config.backup.backupDir;
    if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir, { recursive: true });

    const ts = new Date().toISOString().replace(/[:.]/g, '').replace('T', '_').slice(0, 15);
    const filename = path.join(backupDir, `election_db_${ts}.sql`);
    const mysqldump = config.backup.mysqldumpPath;

    const cmd = `${mysqldump} -u${config.db.user} -p${config.db.password} ${config.db.database} --result-file=${filename}`;

    await new Promise((resolve, reject) => {
      exec(cmd, (error, stdout, stderr) => {
        if (error) reject(new Error(stderr || error.message));
        else resolve();
      });
    });

    await writeLog('INFO', `Database backup created: ${path.basename(filename)}`, 'DB');
    return ok(res, { file: path.basename(filename) }, 'Backup completed');
  } catch (e) {
    if (e.message.includes('not found')) return err(res, 'mysqldump not found. Set MYSQLDUMP_PATH in .env', 500);
    return err(res, `Backup failed: ${e.message}`, 500);
  }
});

// ── 21. POST /api/master/db/flush-cache ──────────────────────────────────────
router.post('/db/flush-cache', masterRequired, async (req, res) => {
  await writeLog('INFO', 'Cache flushed by master', 'System');
  return ok(res, null, 'Cache flushed successfully');
});

// ── 22. POST /api/master/migrate ──────────────────────────────────────────────
router.post('/migrate', masterRequired, async (req, res) => {
  try {
    const { initDb } = require('../config/db');
    await initDb();
    await writeLog('INFO', 'Migration run by master', 'DB');
    return ok(res, { applied: [], skipped: [] }, 'Migration completed');
  } catch (e) {
    return err(res, `Migration error: ${e.message}`, 500);
  }
});

// ── 23. PATCH /api/master/change-password ────────────────────────────────────
router.patch('/change-password', masterRequired, async (req, res) => {
  try {
    const { oldPassword, newPassword } = req.body || {};
    if (!oldPassword || !newPassword) return err(res, 'oldPassword and newPassword required');
    if (newPassword.length < 6) return err(res, 'New password must be at least 6 characters');

    const rows = await query('SELECT password FROM users WHERE id=?', [req.user.id]);
    if (!rows.length || !verifyPassword(oldPassword, rows[0].password))
      return err(res, 'Current password is incorrect', 401);

    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE users SET password=? WHERE id=?', [hashPassword(newPassword), req.user.id]);
    await writeLog('INFO', `Master ID:${req.user.id} changed password`, 'Auth');
    return ok(res, null, 'Password changed successfully');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ── 24. GET /api/master/ping ──────────────────────────────────────────────────
router.get('/ping', (req, res) => ok(res, 'pong'));

module.exports = router;
