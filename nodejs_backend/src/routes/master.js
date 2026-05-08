'use strict';

const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const { query, withTransaction, writeLog, hashPassword, verifyPassword, getPool } = require('../config/db');
const { ok, err , masterRequired} = require('../middleware/auth');
const config = require('../config');
const jwt = require('jsonwebtoken');

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Safely convert a Date value to ISO string, matching Python's .isoformat() */
function toISO(d) {
  if (!d) return null;
  return d instanceof Date ? d.toISOString() : d;
}

/**
 * Auto-archive any active election_configs whose election_date is before today.
 * Configs remain active ON the election day, archived from the next day onwards.
 * Returns count of newly archived rows.
 */
async function autoArchiveExpired(conn) {
  const [result] = await conn.execute(`
    UPDATE election_configs
       SET is_active = 0, is_archived = 1, archived_at = NOW()
     WHERE is_active = 1
       AND is_archived = 0
       AND election_date IS NOT NULL
       AND election_date < CURDATE()
  `);
  return result.affectedRows;
}

/**
 * Normalise an election_configs row into JSON-friendly object.
 * Matches Python's _serialize_election_config() exactly.
 */
function serializeElectionConfig(r) {
  return {
    id:           r.id,
    district:     r.district      || '',
    state:        r.state         || '',
    electionType: r.election_type || '',
    electionName: r.election_name || '',
    phase:        r.phase         || '',
    electionYear: r.election_year || '',
    electionDate: r.election_date
      ? (r.election_date instanceof Date
          ? r.election_date.toISOString().slice(0, 10)
          : String(r.election_date).slice(0, 10))
      : '',
    pratahSamay:  r.pratah_samay || '',
    sayaSamay:    r.saya_samay   || '',
    instructions: r.instructions || '',
    isActive:     Boolean(r.is_active),
    isArchived:   Boolean(r.is_archived),
    archivedAt:   r.archived_at ? toISO(r.archived_at) : null,
    createdAt:    r.created_at   ? toISO(r.created_at)  : null,
    updatedAt:    r.updated_at   ? toISO(r.updated_at)  : null,
  };
}


// ══════════════════════════════════════════════════════════════════════════════
//  0. POST /api/master/login
// ══════════════════════════════════════════════════════════════════════════════
router.post('/login', async (req, res) => {
  try {
    const { username, password } = req.body || {};
    if (!username?.trim() || !password)
      return err(res, 'Username and password required');

    const rows = await query(
      "SELECT * FROM users WHERE username=? AND role='master' AND is_active=1",
      [username.trim()]
    );
    if (!rows.length) return err(res, 'Invalid credentials', 401);

    const user = rows[0];
    if (!verifyPassword(password, user.password))
      return err(res, 'Invalid credentials', 401);

    // Explicit iat + exp in payload (matches Python exactly)
    const now = Math.floor(Date.now() / 1000);
    const payload = {
      id:       user.id,
      username: user.username,
      role:     'master',
      iat:      now,
      exp:      now + config.jwt.expiry,
    };
    const token = jwt.sign(payload, config.jwt.secret, { algorithm: 'HS256' });

    await writeLog('INFO', `Master '${username.trim()}' logged in`, 'Auth');
    return ok(res, { token, name: user.name, username: user.username }, 'Login successful');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  1. PATCH /api/master/change-password
// ══════════════════════════════════════════════════════════════════════════════
router.patch('/change-password', masterRequired, async (req, res) => {
  try {
    const { oldPassword, newPassword } = req.body || {};
    if (!oldPassword || !newPassword)
      return err(res, 'oldPassword and newPassword required');
    if (newPassword.length < 6)
      return err(res, 'New password must be at least 6 characters');

    const rows = await query('SELECT password FROM users WHERE id=?', [req.user.id]);
    if (!rows.length || !verifyPassword(oldPassword, rows[0].password))
      return err(res, 'Current password is incorrect', 401);

    const pool = await getPool();
    await pool.execute(
      'UPDATE users SET password=? WHERE id=?',
      [hashPassword(newPassword), req.user.id]
    );
    await writeLog('INFO', `Master ID:${req.user.id} changed password`, 'Auth');
    return ok(res, null, 'Password changed successfully');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  2. GET /api/master/config
// ══════════════════════════════════════════════════════════════════════════════
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

// ══════════════════════════════════════════════════════════════════════════════
//  3. POST /api/master/config
// ══════════════════════════════════════════════════════════════════════════════
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
    if (!Object.keys(pairs).length) return err(res, 'No config keys provided');

    await withTransaction(async conn => {
      for (const [k, v] of Object.entries(pairs)) {
        await conn.execute(
          'INSERT INTO app_config (`key`, value) VALUES (?,?) ON DUPLICATE KEY UPDATE value=VALUES(value)',
          [String(k), String(v)]
        );
      }
    });

    await writeLog('INFO', `Config updated: ${Object.keys(pairs).join(',')} by master ID:${req.user.id}`, 'Config');
    return ok(res, pairs, 'Config updated successfully');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  4. DELETE /api/master/config/:key
// ══════════════════════════════════════════════════════════════════════════════
router.delete('/config/:key', masterRequired, async (req, res) => {
  try {
    const pool = await getPool();
    const [result] = await pool.execute('DELETE FROM app_config WHERE `key`=?', [req.params.key]);
    if (!result.affectedRows) return err(res, 'Config key not found', 404);
    await writeLog('INFO', `Config key '${req.params.key}' deleted by master`, 'Config');
    return ok(res, null, `Config key '${req.params.key}' deleted`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  5. GET /api/master/election-configs
// ══════════════════════════════════════════════════════════════════════════════
router.get('/election-configs', masterRequired, async (req, res) => {
  try {
    const district        = (req.query.district || '').trim();
    const includeArchived = ['1', 'true', 'True'].includes(req.query.includeArchived);

    const pool = await getPool();
    const conn = await pool.getConnection();
    try {
      // Lazy auto-archive of expired configs (mirrors Python: commit only if rows changed)
      const archived = await autoArchiveExpired(conn);
      if (archived) await conn.commit();

      let sql    = 'SELECT * FROM election_configs WHERE 1=1';
      const params = [];
      if (district)        { sql += ' AND district = ?'; params.push(district); }
      if (!includeArchived) { sql += ' AND is_archived = 0'; }
      sql += ' ORDER BY is_active DESC, is_archived ASC, created_at DESC';

      const [rows] = await conn.execute(sql, params);
      return ok(res, rows.map(serializeElectionConfig));
    } finally {
      conn.release();
    }
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  6. GET /api/master/election-configs/active/:district
//     Any authenticated user may call this (not masterRequired).
//     MUST be declared BEFORE /election-configs/:id to avoid route conflict.
// ══════════════════════════════════════════════════════════════════════════════
router.get('/election-configs/active/:district', async (req, res) => {
  // Validate any logged-in JWT (not master-only) — mirrors Python exactly
  const auth  = req.headers.authorization || '';
  let token   = auth.startsWith('Bearer ') ? auth.slice(7) : req.cookies?.token;
  if (!token) return err(res, 'Missing token', 401);
  try {
    jwt.verify(token, config.jwt.secret, { algorithms: ['HS256'] });
  } catch {
    return err(res, 'Invalid or expired token', 401);
  }

  try {
    const district = req.params.district;
    const pool = await getPool();
    const conn = await pool.getConnection();
    try {
      const archived = await autoArchiveExpired(conn);
      if (archived) await conn.commit();

      const [rows] = await conn.execute(`
        SELECT * FROM election_configs
         WHERE district=? AND is_active=1 AND is_archived=0
         ORDER BY created_at DESC LIMIT 1
      `, [district]);
      if (!rows.length) return ok(res, null, 'No active config for this district');
      return ok(res, serializeElectionConfig(rows[0]));
    } finally {
      conn.release();
    }
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  7. POST /api/master/election-configs/auto-archive
//     MUST be declared BEFORE /election-configs/:id to avoid route conflict.
// ══════════════════════════════════════════════════════════════════════════════
router.post('/election-configs/auto-archive', masterRequired, async (req, res) => {
  try {
    const pool = await getPool();
    const conn = await pool.getConnection();
    try {
      const archived = await autoArchiveExpired(conn);
      await conn.commit();
      if (archived) {
        await writeLog('INFO', `Auto-archive: ${archived} expired configs moved to history`, 'ElectionConfig');
      }
      return ok(res, { archived }, `${archived} expired config(s) archived`);
    } finally {
      conn.release();
    }
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  8. GET /api/master/election-configs/:id
// ══════════════════════════════════════════════════════════════════════════════
router.get('/election-configs/:id', masterRequired, async (req, res) => {
  try {
    const rows = await query('SELECT * FROM election_configs WHERE id=?', [req.params.id]);
    if (!rows.length) return err(res, 'Config not found', 404);
    return ok(res, serializeElectionConfig(rows[0]));
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  9. POST /api/master/election-configs
// ══════════════════════════════════════════════════════════════════════════════
router.post('/election-configs', masterRequired, async (req, res) => {
  try {
    const body = req.body || {};

    let district     = (body.district     || '').trim();
    let state        = (body.state        || '').trim();
    let electionType = (body.electionType || '').trim();
    let electionName = (body.electionName || '').trim();
    let phase        = (body.phase        || '').trim();
    let year         = (body.electionYear || '').trim();
    let dateStr      = (body.electionDate || '').trim();
    let pratahSamay  = (body.pratahSamay  || '').trim();
    let sayaSamay    = (body.sayaSamay    || '').trim();
    let instructions = body.instructions  || '';

    if (!district)     return err(res, 'district is required');
    if (!electionType) return err(res, 'electionType is required');
    if (!year)         return err(res, 'electionYear is required');
    if (!dateStr)      return err(res, 'electionDate is required');

    if (!electionName) electionName = `${electionType} ${year}`;

    // Validate date format YYYY-MM-DD (mirrors Python's strptime check)
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr) || isNaN(new Date(dateStr).getTime()))
      return err(res, 'electionDate must be in YYYY-MM-DD format');

    const pool = await getPool();
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      // Auto-archive any date-expired configs
      await autoArchiveExpired(conn);

      // Archive any existing active config for this district
      const [archResult] = await conn.execute(`
        UPDATE election_configs
           SET is_active = 0, is_archived = 1, archived_at = NOW()
         WHERE district = ? AND is_active = 1 AND is_archived = 0
      `, [district]);
      const archivedCount = archResult.affectedRows;

      // Insert new active config
      const [insertResult] = await conn.execute(`
        INSERT INTO election_configs
            (district, state, election_type, election_name, phase,
             election_year, election_date, pratah_samay, saya_samay,
             instructions, is_active, is_archived, created_by)
        VALUES (?,?,?,?,?,?,?,?,?,?,1,0,?)
      `, [
        district, state, electionType, electionName, phase,
        year, dateStr, pratahSamay, sayaSamay, instructions, req.user.id,
      ]);
      const newId = insertResult.insertId;

      await conn.commit();
      await writeLog(
        'INFO',
        `Election config created for district '${district}' (archived ${archivedCount} previous) by master ID:${req.user.id}`,
        'ElectionConfig'
      );
      return ok(
        res,
        { id: newId, archivedPrevious: archivedCount },
        `Election config created for ${district}`,
        201
      );
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

// ══════════════════════════════════════════════════════════════════════════════
//  10. PUT /api/master/election-configs/:id
// ══════════════════════════════════════════════════════════════════════════════
router.put('/election-configs/:id', masterRequired, async (req, res) => {
  try {
    const cfgId = req.params.id;
    const body  = req.body || {};

    const rows = await query('SELECT * FROM election_configs WHERE id=?', [cfgId]);
    if (!rows.length)        return err(res, 'Config not found', 404);
    if (rows[0].is_archived) return err(res, 'Cannot edit archived config. Create a new one instead.', 400);

    // Build dynamic SET clause — mirrors Python's field_map exactly
    const fieldMap = {
      state:        'state',
      electionType: 'election_type',
      electionName: 'election_name',
      phase:        'phase',
      electionYear: 'election_year',
      pratahSamay:  'pratah_samay',
      sayaSamay:    'saya_samay',
      instructions: 'instructions',
    };

    const setClauses = [];
    const params     = [];

    for (const [bodyKey, col] of Object.entries(fieldMap)) {
      if (bodyKey in body) {
        setClauses.push(`${col}=?`);
        params.push(String(body[bodyKey] || '').trim());
      }
    }

    if ('electionDate' in body) {
      const dateStr = (body.electionDate || '').trim();
      if (dateStr) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr) || isNaN(new Date(dateStr).getTime()))
          return err(res, 'electionDate must be in YYYY-MM-DD format');
        setClauses.push('election_date=?');
        params.push(dateStr);
      }
    }

    if (!setClauses.length) return err(res, 'Nothing to update');

    params.push(cfgId);
    const pool = await getPool();
    await pool.execute(
      `UPDATE election_configs SET ${setClauses.join(', ')} WHERE id=?`,
      params
    );

    await writeLog('INFO', `Election config ID:${cfgId} updated by master`, 'ElectionConfig');
    return ok(res, null, 'Config updated');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  11. PATCH /api/master/election-configs/:id/archive
// ══════════════════════════════════════════════════════════════════════════════
router.patch('/election-configs/:id/archive', masterRequired, async (req, res) => {
  try {
    const cfgId = req.params.id;
    const rows  = await query('SELECT id, district FROM election_configs WHERE id=?', [cfgId]);
    if (!rows.length) return err(res, 'Config not found', 404);

    const pool = await getPool();
    await pool.execute(`
      UPDATE election_configs
         SET is_active=0, is_archived=1, archived_at=NOW()
       WHERE id=?
    `, [cfgId]);

    await writeLog(
      'INFO',
      `Election config ID:${cfgId} (dist:${rows[0].district}) archived by master`,
      'ElectionConfig'
    );
    return ok(res, null, 'Config archived');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  12. DELETE /api/master/election-configs/:id
// ══════════════════════════════════════════════════════════════════════════════
router.delete('/election-configs/:id', masterRequired, async (req, res) => {
  try {
    const cfgId = req.params.id;
    const pool  = await getPool();
    const [result] = await pool.execute('DELETE FROM election_configs WHERE id=?', [cfgId]);
    if (!result.affectedRows) return err(res, 'Config not found', 404);
    await writeLog('WARN', `Election config ID:${cfgId} DELETED by master`, 'ElectionConfig');
    return ok(res, null, 'Config deleted');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  13. GET /api/master/super-admins
// ══════════════════════════════════════════════════════════════════════════════
router.get('/super-admins', masterRequired, async (req, res) => {
  try {
    const rows = await query(`
      SELECT sa.id, sa.name, sa.username, sa.district, sa.is_active, sa.created_at,
             COUNT(a.id) AS admins_under
      FROM users sa
      LEFT JOIN users a ON a.created_by=sa.id AND a.role='admin'
      WHERE sa.role='super_admin'
      GROUP BY sa.id
      ORDER BY sa.created_at DESC
    `);
    return ok(res, rows.map(r => ({
      id:          r.id,
      name:        r.name,
      username:    r.username,
      district:    r.district || '',
      isActive:    Boolean(r.is_active),
      createdAt:   toISO(r.created_at),
      adminsUnder: r.admins_under,
    })));
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  14. POST /api/master/super-admins
// ══════════════════════════════════════════════════════════════════════════════
router.post('/super-admins', masterRequired, async (req, res) => {
  try {
    const { name, username, password, district } = req.body || {};
    if (!name?.trim() || !username?.trim() || !password || !district?.trim())
      return err(res, 'name, username, password and district are required');
    if (password.length < 6) return err(res, 'Password must be at least 6 characters');

    const existing = await query('SELECT id FROM users WHERE username=?', [username.trim()]);
    if (existing.length) return err(res, 'Username already taken', 409);

    const pool = await getPool();
    const [result] = await pool.execute(
      "INSERT INTO users (name, username, password, role, district, is_active, created_by) VALUES (?,?,?,'super_admin',?,1,?)",
      [name.trim(), username.trim(), hashPassword(password), district.trim(), req.user.id]
    );
    await writeLog('INFO', `Super Admin '${name.trim()}' created by master`, 'Auth');
    return ok(res, {
      id:       result.insertId,
      name:     name.trim(),
      username: username.trim(),
      district: district.trim(),
    }, 'Super Admin created', 201);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  15. GET /api/master/super-admins/:id
// ══════════════════════════════════════════════════════════════════════════════
router.get('/super-admins/:id', masterRequired, async (req, res) => {
  try {
    const rows = await query(
      "SELECT id, name, username, district, is_active, created_at FROM users WHERE id=? AND role='super_admin'",
      [req.params.id]
    );
    if (!rows.length) return err(res, 'Super Admin not found', 404);
    const r = rows[0];
    return ok(res, {
      id:        r.id,
      name:      r.name,
      username:  r.username,
      district:  r.district || '',
      isActive:  Boolean(r.is_active),
      createdAt: toISO(r.created_at),
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  16. PUT /api/master/super-admins/:id
// ══════════════════════════════════════════════════════════════════════════════
router.put('/super-admins/:id', masterRequired, async (req, res) => {
  try {
    const { name, username, district } = req.body || {};
    if (!name?.trim() || !username?.trim()) return err(res, 'name and username required');
    const id = req.params.id;

    const exists = await query("SELECT id FROM users WHERE id=? AND role='super_admin'", [id]);
    if (!exists.length) return err(res, 'Super Admin not found', 404);
    const dup = await query('SELECT id FROM users WHERE username=? AND id!=?', [username.trim(), id]);
    if (dup.length) return err(res, 'Username already taken', 409);

    const pool = await getPool();
    // Conditionally include district — mirrors Python exactly
    if (district?.trim()) {
      await pool.execute(
        'UPDATE users SET name=?, username=?, district=? WHERE id=?',
        [name.trim(), username.trim(), district.trim(), id]
      );
    } else {
      await pool.execute(
        'UPDATE users SET name=?, username=? WHERE id=?',
        [name.trim(), username.trim(), id]
      );
    }

    await writeLog('INFO', `Super Admin ID:${id} updated by master`, 'Auth');
    return ok(res, null, 'Super Admin updated');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  17. DELETE /api/master/super-admins/:id
// ══════════════════════════════════════════════════════════════════════════════
router.delete('/super-admins/:id', masterRequired, async (req, res) => {
  try {
    const id   = req.params.id;
    const rows = await query("SELECT name FROM users WHERE id=? AND role='super_admin'", [id]);
    if (!rows.length) return err(res, 'Super Admin not found', 404);
    const name = rows[0].name;

    const pool = await getPool();
    // Nullify created_by for any admins this super-admin created — mirrors Python exactly
    await pool.execute("UPDATE users SET created_by=NULL WHERE created_by=? AND role='admin'", [id]);
    await pool.execute('DELETE FROM users WHERE id=?', [id]);

    await writeLog('WARN', `Super Admin '${name}' (ID:${id}) deleted by master`, 'Auth');
    return ok(res, null, `Super Admin '${name}' deleted`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  18. PATCH /api/master/super-admins/:id/status
// ══════════════════════════════════════════════════════════════════════════════
router.patch('/super-admins/:id/status', masterRequired, async (req, res) => {
  try {
    const { isActive } = req.body || {};
    if (isActive == null) return err(res, 'isActive field required');
    const id   = req.params.id;
    const rows = await query("SELECT name FROM users WHERE id=? AND role='super_admin'", [id]);
    if (!rows.length) return err(res, 'Super Admin not found', 404);
    const pool = await getPool();
    await pool.execute('UPDATE users SET is_active=? WHERE id=?', [isActive ? 1 : 0, id]);
    const action = isActive ? 'activated' : 'deactivated';
    await writeLog('INFO', `Super Admin '${rows[0].name}' (ID:${id}) ${action} by master`, 'Auth');
    return ok(res, { id: Number(id), isActive: Boolean(isActive) }, `Super Admin ${action}`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  19. PATCH /api/master/super-admins/:id/reset-password
// ══════════════════════════════════════════════════════════════════════════════
router.patch('/super-admins/:id/reset-password', masterRequired, async (req, res) => {
  try {
    const { password } = req.body || {};
    if (!password || password.length < 6)
      return err(res, 'Password must be at least 6 characters');
    const id   = req.params.id;
    const rows = await query("SELECT id FROM users WHERE id=? AND role='super_admin'", [id]);
    if (!rows.length) return err(res, 'Super Admin not found', 404);
    const pool = await getPool();
    await pool.execute('UPDATE users SET password=? WHERE id=?', [hashPassword(password), id]);
    await writeLog('WARN', `Password reset for Super Admin ID:${id} by master`, 'Auth');
    return ok(res, null, 'Password reset successful');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  20. GET /api/master/admins
// ══════════════════════════════════════════════════════════════════════════════
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
      createdAt:      toISO(r.created_at),
      createdBy:      r.created_by_name || 'master',
      superZoneCount: r.super_zone_count,
    })));
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  21. POST /api/master/admins
// ══════════════════════════════════════════════════════════════════════════════
router.post('/admins', masterRequired, async (req, res) => {
  try {
    const { name, username, district, password } = req.body || {};
    if (!name?.trim() || !username?.trim() || !district?.trim() || !password)
      return err(res, 'name, username, district and password are all required');
    if (password.length < 6) return err(res, 'Password must be at least 6 characters');

    const dup = await query('SELECT id FROM users WHERE username=?', [username.trim()]);
    if (dup.length) return err(res, 'Username already taken', 409);

    const pool = await getPool();
    const [result] = await pool.execute(
      "INSERT INTO users (name, username, password, role, district, is_active, created_by) VALUES (?,?,?,'admin',?,1,?)",
      [name.trim(), username.trim(), hashPassword(password), district.trim(), req.user.id]
    );
    await writeLog('INFO', `Admin '${name.trim()}' (district:${district.trim()}) created directly by master`, 'Auth');
    return ok(res, {
      id:       result.insertId,
      name:     name.trim(),
      username: username.trim(),
      district: district.trim(),
    }, 'Admin created', 201);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  22. PUT /api/master/admins/:id
// ══════════════════════════════════════════════════════════════════════════════
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

    const pool = await getPool();
    await pool.execute(
      'UPDATE users SET name=?, username=?, district=? WHERE id=?',
      [name.trim(), username.trim(), district.trim(), id]
    );
    await writeLog('INFO', `Admin ID:${id} updated by master`, 'Auth');
    return ok(res, null, 'Admin updated');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  23. DELETE /api/master/admins/:id
//  NOTE: Python does NOT nullify created_by for admins' children — just deletes.
// ══════════════════════════════════════════════════════════════════════════════
router.delete('/admins/:id', masterRequired, async (req, res) => {
  try {
    const id   = req.params.id;
    const rows = await query("SELECT name FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);
    const name = rows[0].name;

    const pool = await getPool();
    await pool.execute('DELETE FROM users WHERE id=?', [id]);

    await writeLog('WARN', `Admin '${name}' (ID:${id}) deleted by master`, 'Auth');
    return ok(res, null, `Admin '${name}' deleted`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  24. PATCH /api/master/admins/:id/status
// ══════════════════════════════════════════════════════════════════════════════
router.patch('/admins/:id/status', masterRequired, async (req, res) => {
  try {
    const { isActive } = req.body || {};
    if (isActive == null) return err(res, 'isActive field required');
    const id   = req.params.id;
    const rows = await query("SELECT name FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);
    const pool = await getPool();
    await pool.execute('UPDATE users SET is_active=? WHERE id=?', [isActive ? 1 : 0, id]);
    const action = isActive ? 'activated' : 'deactivated';
    await writeLog('INFO', `Admin ID:${id} ${action} by master`, 'Auth');
    return ok(res, { id: Number(id), isActive: Boolean(isActive) }, `Admin ${action}`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  25. PATCH /api/master/admins/:id/reset-password
// ══════════════════════════════════════════════════════════════════════════════
router.patch('/admins/:id/reset-password', masterRequired, async (req, res) => {
  try {
    const { password } = req.body || {};
    if (!password || password.length < 6)
      return err(res, 'Password must be at least 6 characters');
    const id   = req.params.id;
    const rows = await query("SELECT id FROM users WHERE id=? AND role='admin'", [id]);
    if (!rows.length) return err(res, 'Admin not found', 404);
    const pool = await getPool();
    await pool.execute('UPDATE users SET password=? WHERE id=?', [hashPassword(password), id]);
    await writeLog('WARN', `Password reset for Admin ID:${id} by master`, 'Auth');
    return ok(res, null, 'Password reset successful');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  26. POST /api/master/force-logout
// ══════════════════════════════════════════════════════════════════════════════
router.post('/force-logout', masterRequired, async (req, res) => {
  try {
    const body = req.body || {};

    let roles = body.roles;
    if (!roles && body.role) roles = [body.role];
    if (!roles || !Array.isArray(roles))
      return err(res, "Provide 'roles' (list) or 'role' (string)");

    roles = roles.map(r => String(r).trim().toLowerCase()).filter(Boolean);
    const valid = new Set(['super_admin', 'admin', 'staff', 'master']);
    const bad   = roles.filter(r => !valid.has(r));
    if (bad.length)
      return err(res, `Invalid role(s): [${bad}]. Allowed: ${[...valid].sort().join(', ')}`);

    // Master self-protection — silently drop 'master' (mirrors Python exactly)
    if (roles.includes('master')) {
      roles = roles.filter(r => r !== 'master');
      await writeLog(
        'WARN',
        `Master ID:${req.user.id} attempted to force-logout 'master' — ignored (self-protection)`,
        'Auth'
      );
    }

    if (!roles.length)
      return err(res, 'No valid roles to revoke (master role cannot be force-logged-out)');

    const now    = Math.floor(Date.now() / 1000);
    const reason = (body.reason || '').trim().slice(0, 255);

    const pool = await getPool();
    for (const role of roles) {
      await pool.execute(`
        INSERT INTO token_revocations (role, revoke_before, revoked_by, reason)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            revoke_before = VALUES(revoke_before),
            revoked_by    = VALUES(revoked_by),
            reason        = VALUES(reason),
            created_at    = NOW()
      `, [role, now, req.user.id, reason]);
    }

    await writeLog('WARN', `Force-logout triggered for roles [${roles}] by master ID:${req.user.id}`, 'Auth');
    return ok(res, { roles, revokedBefore: now }, `All sessions for [${roles}] invalidated`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  27. GET /api/master/force-logout/status
// ══════════════════════════════════════════════════════════════════════════════
router.get('/force-logout/status', masterRequired, async (req, res) => {
  try {
    const rows = await query(
      'SELECT role, revoke_before, revoked_by, reason, created_at FROM token_revocations'
    );
    return ok(res, rows.map(r => ({
      role:         r.role,
      revokeBefore: r.revoke_before,
      revokedBy:    r.revoked_by,
      reason:       r.reason || '',
      createdAt:    toISO(r.created_at),
    })));
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  28. GET /api/master/overview
// ══════════════════════════════════════════════════════════════════════════════
router.get('/overview', masterRequired, async (req, res) => {
  try {
    const [
      [superAdmins],
      [admins],
      [staff],
      [booths],
      [duties],
      [activeConfigs],
      [archivedConfigs],
    ] = await Promise.all([
      query("SELECT COUNT(*) AS cnt FROM users WHERE role='super_admin'"),
      query("SELECT COUNT(*) AS cnt FROM users WHERE role='admin'"),
      query("SELECT COUNT(*) AS cnt FROM users WHERE role='staff' AND is_active=1"),
      query('SELECT COUNT(*) AS cnt FROM matdan_sthal'),
      query('SELECT COUNT(*) AS cnt FROM duty_assignments'),
      query("SELECT COUNT(*) AS cnt FROM election_configs WHERE is_active=1 AND is_archived=0"),
      query("SELECT COUNT(*) AS cnt FROM election_configs WHERE is_archived=1"),
    ]);
    return ok(res, {
      totalSuperAdmins:        superAdmins.cnt,
      totalAdmins:             admins.cnt,
      totalStaff:              staff.cnt,
      totalBooths:             booths.cnt,
      assignedDuties:          duties.cnt,
      activeElectionConfigs:   activeConfigs.cnt,
      archivedElectionConfigs: archivedConfigs.cnt,
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  29. GET /api/master/system-stats
// ══════════════════════════════════════════════════════════════════════════════
router.get('/system-stats', masterRequired, async (req, res) => {
  try {
    const [sizeRow] = await query(`
      SELECT ROUND(SUM(data_length+index_length)/1024/1024,2) AS size_mb
      FROM information_schema.tables WHERE table_schema=DATABASE()
    `);

    // Matches Python's table list exactly
    const tables = [
      'users', 'duty_assignments', 'matdan_kendra', 'matdan_sthal',
      'sectors', 'zones', 'super_zones', 'gram_panchayats',
      'election_configs', 'api_request_logs',
    ];
    let total = 0;
    for (const t of tables) {
      try {
        const [r] = await query(`SELECT COUNT(*) AS cnt FROM \`${t}\``);
        total += Number(r.cnt);
      } catch (_) { /* table may not exist yet — mirrors Python's bare except */ }
    }

    const [backupRow] = await query(
      "SELECT time FROM system_logs WHERE module='DB' AND message LIKE 'Database backup%' ORDER BY time DESC LIMIT 1"
    );
    const [firstLog] = await query('SELECT MIN(time) AS first FROM system_logs');

    let uptime = 'N/A';
    if (firstLog?.first) {
      const ms = Date.now() - new Date(firstLog.first).getTime();
      const d  = Math.floor(ms / 86400000);
      const h  = Math.floor((ms % 86400000) / 3600000);
      const m  = Math.floor((ms % 3600000) / 60000);
      uptime = `${d}d ${h}h ${m}m`;
    }

    // lastBackup formatted like Python: strftime("%d %b %Y %H:%M")
    let lastBackup = 'Never';
    if (backupRow?.time) {
      const d = new Date(backupRow.time);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      lastBackup = `${String(d.getUTCDate()).padStart(2,'0')} ${months[d.getUTCMonth()]} ${d.getUTCFullYear()} ${String(d.getUTCHours()).padStart(2,'0')}:${String(d.getUTCMinutes()).padStart(2,'0')}`;
    }

    return ok(res, {
      dbSize:       sizeRow?.size_mb ? `${sizeRow.size_mb} MB` : 'N/A',
      totalRecords: total,
      uptime,
      lastBackup,
      backend:      'Node.js/Express',
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  30. GET /api/master/logs
// ══════════════════════════════════════════════════════════════════════════════
router.get('/logs', masterRequired, async (req, res) => {
  try {
    const level  = (req.query.level || 'ALL').toUpperCase();
    const limit  = Math.min(parseInt(req.query.limit,  10) || 100, 500);
    const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);

    // Use parameterised placeholders for LIMIT/OFFSET to avoid injection
    let rows;
    if (level === 'ALL') {
      rows = await query(
        `SELECT * FROM system_logs ORDER BY time DESC LIMIT ${limit} OFFSET ${offset}`
      );
    } else {
      rows = await query(
        `SELECT * FROM system_logs WHERE level=? ORDER BY time DESC LIMIT ${limit} OFFSET ${offset}`,
        [level]
      );
    }

    return ok(res, rows.map(r => ({
      id:      r.id,
      level:   r.level,
      message: r.message,
      module:  r.module,
      time:    toISO(r.time),
    })));
  } catch (e) {
    console.log(e);
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  31. GET /api/master/api-logs
// ══════════════════════════════════════════════════════════════════════════════
router.get('/api-logs', masterRequired, async (req, res) => {
  try {
    const level  = (req.query.level  || 'ALL').toUpperCase();
    const method = (req.query.method || 'ALL').toUpperCase();
    const role   = (req.query.role   || 'ALL').toLowerCase();
    const status = (req.query.status || 'ALL').toLowerCase();
    const q      = (req.query.q      || '').trim();
    const limit  = Math.min(parseInt(req.query.limit,  10) || 100, 500);
    const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);

    const where  = [];
    const params = [];

    if (level !== 'ALL')  { where.push('level = ?');  params.push(level); }
    if (method !== 'ALL') { where.push('method = ?'); params.push(method); }
    if (role   !== 'all') { where.push('role = ?');   params.push(role); }

    if (status === '4xx') {
      where.push('status_code BETWEEN 400 AND 499');
    } else if (status === '5xx') {
      where.push('status_code BETWEEN 500 AND 599');
    } else if (status === '2xx') {
      where.push('status_code BETWEEN 200 AND 299');
    } else if (status !== 'all' && /^\d+$/.test(status)) {
      where.push('status_code = ?');
      params.push(parseInt(status, 10));
    }

    if (q) {
      where.push('(path LIKE ? OR username LIKE ? OR error_message LIKE ?)');
      const like = `%${q}%`;
      params.push(like, like, like);
    }

    const sqlWhere = where.length ? `WHERE ${where.join(' AND ')}` : '';

    // Separate params arrays so LIMIT/OFFSET are always parameterised
    const [countRow] = await query(
      `SELECT COUNT(*) AS cnt FROM api_request_logs ${sqlWhere}`,
      params
    );
    const rows = await query(
      `SELECT * FROM api_request_logs ${sqlWhere} ORDER BY created_at DESC LIMIT ${limit} OFFSET ${offset}`,
      [...params ]
    );

    return ok(res, {
      total:  countRow.cnt,
      limit,
      offset,
      items: rows.map(r => ({
        id:           r.id,
        method:       r.method,
        path:         r.path,
        statusCode:   r.status_code,
        durationMs:   r.duration_ms,
        userId:       r.user_id,
        username:     r.username      || '',
        role:         r.role          || '',
        ipAddress:    r.ip_address    || '',
        userAgent:    (r.user_agent   || '').slice(0, 120),
        requestBody:  r.request_body  || '',
        errorMessage: r.error_message || '',
        level:        r.level,
        createdAt:    toISO(r.created_at),
      })),
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  32. DELETE /api/master/api-logs/clear
//      MUST be declared BEFORE /api-logs/stats to avoid route conflicts.
// ══════════════════════════════════════════════════════════════════════════════
router.delete('/api-logs/clear', masterRequired, async (req, res) => {
  try {
    const days = parseInt(req.query.days, 10) || 30;
    const pool = await getPool();
    const [result] = await pool.execute(
      'DELETE FROM api_request_logs WHERE created_at < (NOW() - INTERVAL ? DAY)',
      [days]
    );
    const deleted = result.affectedRows;
    await writeLog('INFO', `API logs older than ${days}d cleared (${deleted} rows)`, 'DB');
    return ok(res, { deleted }, `Cleared ${deleted} log(s) older than ${days} days`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  33. GET /api/master/api-logs/stats
// ══════════════════════════════════════════════════════════════════════════════
router.get('/api-logs/stats', masterRequired, async (req, res) => {
  try {
    const [day] = await query(`
      SELECT
        SUM(CASE WHEN level='INFO'  THEN 1 ELSE 0 END) AS info_count,
        SUM(CASE WHEN level='WARN'  THEN 1 ELSE 0 END) AS warn_count,
        SUM(CASE WHEN level='ERROR' THEN 1 ELSE 0 END) AS error_count,
        COUNT(*) AS total
      FROM api_request_logs
      WHERE created_at > (NOW() - INTERVAL 24 HOUR)
    `);
    const top = await query(`
      SELECT path, COUNT(*) AS cnt
      FROM api_request_logs
      WHERE created_at > (NOW() - INTERVAL 1 HOUR)
      GROUP BY path ORDER BY cnt DESC LIMIT 5
    `);
    return ok(res, {
      last24h: {
        info:  parseInt(day?.info_count  || 0, 10),
        warn:  parseInt(day?.warn_count  || 0, 10),
        error: parseInt(day?.error_count || 0, 10),
        total: parseInt(day?.total       || 0, 10),
      },
      topPaths1h: top.map(r => ({ path: r.path, count: r.cnt })),
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  34. POST /api/master/db/backup
// ══════════════════════════════════════════════════════════════════════════════
router.post('/db/backup', masterRequired, async (req, res) => {
  try {
    const backupDir = config.backup?.backupDir || 'backups';
    if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir, { recursive: true });

    // Timestamp format mirrors Python: %Y%m%d_%H%M%S
    const now = new Date();
    const pad = n => String(n).padStart(2, '0');
    const ts  = `${now.getUTCFullYear()}${pad(now.getUTCMonth()+1)}${pad(now.getUTCDate())}_${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}`;
    const filename    = path.join(backupDir, `election_db_${ts}.sql`);
    const mysqldump   = (config.backup?.mysqldumpPath || 'mysqldump').replace(/^r?"?|"?$/g, '').trim();

    const cmd = `${mysqldump} -u${config.db.user} -p${config.db.password} ${config.db.database} --result-file=${filename}`;

    await new Promise((resolve, reject) => {
      exec(cmd, (error, _stdout, stderr) => {
        if (error) reject(new Error(stderr || error.message));
        else resolve();
      });
    });

    await writeLog('INFO', `Database backup created: ${path.basename(filename)}`, 'DB');
    return ok(res, { file: path.basename(filename) }, 'Backup completed');
  } catch (e) {
    if (e.message.toLowerCase().includes('not found') || e.message.toLowerCase().includes('enoent'))
      return err(res, 'mysqldump not found. Set MYSQLDUMP_PATH in config.', 500);
    return err(res, `Backup failed: ${e.message}`, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  35. POST /api/master/db/flush-cache
// ══════════════════════════════════════════════════════════════════════════════
router.post('/db/flush-cache', masterRequired, async (req, res) => {
  await writeLog('INFO', 'Cache flushed by master', 'System');
  return ok(res, null, 'Cache flushed successfully');
});

// ══════════════════════════════════════════════════════════════════════════════
//  36. POST /api/master/migrate
//  Mirrors Python: calls initDb() AND runMigrations(), returns runMigrations result.
// ══════════════════════════════════════════════════════════════════════════════
router.post('/migrate', masterRequired, async (req, res) => {
  try {
    const { initDb, runMigrations } = require('../config/db');
    await initDb();
    const result = await runMigrations();
    await writeLog('INFO', 'Migration run by master', 'DB');
    return ok(res, result, 'Migration completed');
  } catch (e) {
    return err(res, `Migration error: ${e.message}`, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  37. GET /api/master/ping  (no auth)
// ══════════════════════════════════════════════════════════════════════════════
router.get('/ping', (req, res) => ok(res, 'pong'));

module.exports = router;