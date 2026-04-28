'use strict';

const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const multer = require('multer');
const { parse: csvParse } = require('csv-parse/sync');
const { query, withTransaction, writeLog } = require('../config/db');
const { ok, err, adminRequired } = require('../middleware/auth');
const { pageParams, paginated } = require('../utils/pagination');
const config = require('../config');

// ── Constants ─────────────────────────────────────────────────────────────────
const SALT = config.passwordSalt;
const MAX_BATCH_ROWS    = 10_000;
const INSERT_CHUNK_SIZE = 200;
const HASH_WORKERS      = 8;

const RANK_HIERARCHY = ['SP', 'ASP', 'DSP', 'Inspector', 'SI', 'ASI', 'Head Constable', 'Constable'];

function fastHash(pno) {
  return crypto.createHash('sha256').update(pno + SALT).digest('hex');
}

function getLowerRank(rank) {
  const idx = RANK_HIERARCHY.indexOf(rank);
  return (idx >= 0 && idx < RANK_HIERARCHY.length - 1) ? RANK_HIERARCHY[idx + 1] : null;
}

function formatOfficer(r) {
  return { id: r.id, userId: r.user_id, name: r.name || '', pno: r.pno || '', mobile: r.mobile || '', rank: r.user_rank || '' };
}

function getAdminId(req) { return req.user.id; }

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT SHARING — core helpers (ported from Python)
//
//  Returns list of ALL admin IDs in the same district as the current admin.
//  Every route that filtered by admin_id=X now uses admin_id IN (district_ids)
//  so all admins in the same district share full read/write access.
// ══════════════════════════════════════════════════════════════════════════════

async function getDistrictAdminIds(req) {
  const district = (req.user.district || '').trim();
  const adminId  = getAdminId(req);

  if (!district) return [adminId];

  const pool = await require('../config/db').getPool();
  const [rows] = await pool.execute(
    "SELECT id FROM users WHERE role IN ('admin','super_admin') AND district = ?",
    [district]
  );
  const ids = rows.map(r => r.id);
  if (!ids.includes(adminId)) ids.push(adminId);
  return ids.length ? ids : [adminId];
}

/**
 * Returns { ph, params } for use in SQL IN clauses.
 * e.g. `WHERE admin_id IN (${ph})` with [...params]
 */
function districtPH(ids) {
  return { ph: ids.map(() => '?').join(','), params: ids };
}

// ── Insert or upsert officer helper ───────────────────────────────────────────
async function insertOfficer(conn, table, fkCol, fkVal, o, createdBy) {
  let uid    = o.userId || o.user_id || null;
  let name   = (o.name   || '').trim();
  let pno    = (o.pno    || '').trim();
  let mobile = (o.mobile || '').trim();
  let rank   = (o.rank   || '').trim();

  if (uid) {
    const [users] = await conn.execute(
      'SELECT name, pno, mobile, user_rank, is_armed FROM users WHERE id=?', [uid]
    );
    if (users.length) {
      const u = users[0];
      if (!name)   name   = u.name      || '';
      if (!pno)    pno    = u.pno       || '';
      if (!mobile) mobile = u.mobile    || '';
      if (!rank)   rank   = u.user_rank || '';
    }
  } else if (pno) {
    const [existing] = await conn.execute('SELECT id FROM users WHERE pno=?', [pno]);
    if (existing.length) {
      uid = existing[0].id;
    } else {
      const [usernameCheck] = await conn.execute('SELECT id FROM users WHERE username=?', [pno]);
      const username = usernameCheck.length ? `${pno}_off` : pno;
      const [ins] = await conn.execute(
        "INSERT INTO users (name,pno,username,password,mobile,user_rank,is_armed,role,is_active,created_by) VALUES (?,?,?,?,?,?,?,'staff',1,?)",
        [name, pno, username, fastHash(pno), mobile, rank, 0, createdBy]
      );
      uid = ins.insertId;
    }
  }

  const [result] = await conn.execute(
    `INSERT INTO ${table} (${fkCol}, user_id, name, pno, mobile, user_rank) VALUES (?,?,?,?,?,?)`,
    [fkVal, uid || null, name, pno, mobile, rank]
  );
  return result.insertId;
}

// ── Update officer helper ─────────────────────────────────────────────────────
async function updateOfficer(conn, table, officerId, body, createdBy) {
  const [existing] = await conn.execute(`SELECT user_id FROM ${table} WHERE id=?`, [officerId]);
  let uid    = body.userId || (existing.length ? existing[0].user_id : null);
  const name   = body.name   || '';
  const pno    = body.pno    || '';
  const mobile = body.mobile || '';
  const rank   = body.rank   || '';

  if (!uid && pno) {
    const [byPno] = await conn.execute('SELECT id FROM users WHERE pno=?', [pno]);
    if (byPno.length) {
      uid = byPno[0].id;
    } else {
      const [usernameCheck] = await conn.execute('SELECT id FROM users WHERE username=?', [pno]);
      const username = usernameCheck.length ? `${pno}_off` : pno;
      const [ins] = await conn.execute(
        "INSERT INTO users (name,pno,username,password,mobile,user_rank,role,is_active,created_by) VALUES (?,?,?,?,?,?,'staff',1,?)",
        [name, pno, username, fastHash(pno), mobile, rank, createdBy]
      );
      uid = ins.insertId;
    }
  }
  if (uid) {
    await conn.execute(
      "UPDATE users SET name=?, mobile=?, user_rank=? WHERE id=? AND role='staff'",
      [name, mobile, rank, uid]
    );
  }
  await conn.execute(
    `UPDATE ${table} SET name=?, pno=?, mobile=?, user_rank=?, user_id=? WHERE id=?`,
    [name, pno, mobile, rank, uid || null, officerId]
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  SUPER ZONES
// ══════════════════════════════════════════════════════════════════════════════

router.get('/super-zones', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search  = (req.query.q || '').trim();
    const pool    = await require('../config/db').getPool();
    const dIds    = await getDistrictAdminIds(req);
    const { ph, params: dParams } = districtPH(dIds);

    let whereExtra = '';
    const params = [...dParams];
    if (search) { whereExtra = 'AND sz.name LIKE ?'; params.push(`%${search}%`); }

    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(*) AS cnt FROM super_zones sz WHERE sz.admin_id IN (${ph}) ${whereExtra}`, params
    );
    const [zones] = await pool.execute(
      `SELECT sz.id, sz.name, sz.district, sz.block, COUNT(DISTINCT z.id) AS zone_count
       FROM super_zones sz LEFT JOIN zones z ON z.super_zone_id=sz.id
       WHERE sz.admin_id IN (${ph}) ${whereExtra}
       GROUP BY sz.id ORDER BY sz.id LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );
    if (!zones.length) return paginated(res, [], total, page, limit);

    const szIds = zones.map(z => z.id);
    const szPh  = szIds.map(() => '?').join(',');
    const [officers] = await pool.execute(
      `SELECT * FROM kshetra_officers WHERE super_zone_id IN (${szPh}) ORDER BY super_zone_id, id`, szIds
    );
    const officersBySz = {};
    officers.forEach(o => { (officersBySz[o.super_zone_id] = officersBySz[o.super_zone_id] || []).push(formatOfficer(o)); });

    const result = zones.map(sz => ({
      id: sz.id, name: sz.name || '', district: sz.district || '', block: sz.block || '',
      zoneCount: sz.zone_count, officers: officersBySz[sz.id] || [],
    }));
    return paginated(res, result, total, page, limit);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/super-zones', adminRequired, async (req, res) => {
  try {
    const { name, district, block, officers: offs = [] } = req.body || {};
    if (!name?.trim()) return err(res, 'name required');
    const adminId = getAdminId(req);
    const dist    = district || req.user.district || '';
    let szId;
    await withTransaction(async conn => {
      const [r] = await conn.execute(
        'INSERT INTO super_zones (name, district, block, admin_id) VALUES (?,?,?,?)',
        [name.trim(), dist, block || '', adminId]
      );
      szId = r.insertId;
      for (const o of offs) await insertOfficer(conn, 'kshetra_officers', 'super_zone_id', szId, o, adminId);
    });
    return ok(res, { id: szId, name: name.trim() }, 'Super Zone added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.put('/super-zones/:id', adminRequired, async (req, res) => {
  try {
    const szId = req.params.id;
    const { name = '', district = '', block = '', officers: offs = [] } = req.body || {};

    // DISTRICT SHARING: verify zone belongs to any admin in this district
    const dIds = await getDistrictAdminIds(req);
    const { ph, params: dParams } = districtPH(dIds);
    const pool = await require('../config/db').getPool();
    const [check] = await pool.execute(
      `SELECT id FROM super_zones WHERE id=? AND admin_id IN (${ph})`, [szId, ...dParams]
    );
    if (!check.length) return err(res, 'Not found or access denied', 403);

    await withTransaction(async conn => {
      await conn.execute(
        'UPDATE super_zones SET name=?, district=?, block=? WHERE id=?',
        [name, district, block, szId]
      );
      await conn.execute('DELETE FROM kshetra_officers WHERE super_zone_id=?', [szId]);
      for (const o of offs) await insertOfficer(conn, 'kshetra_officers', 'super_zone_id', szId, o, req.user.id);
    });
    return ok(res, null, 'Updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/super-zones/:id', adminRequired, async (req, res) => {
  try {
    const dIds = await getDistrictAdminIds(req);
    const { ph, params: dParams } = districtPH(dIds);
    const pool = await require('../config/db').getPool();
    await pool.execute(
      `DELETE FROM super_zones WHERE id=? AND admin_id IN (${ph})`, [req.params.id, ...dParams]
    );
    return ok(res, null, 'Deleted');
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/super-zones/:id/officers', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [officers] = await pool.execute(
      'SELECT * FROM kshetra_officers WHERE super_zone_id=? ORDER BY id', [req.params.id]
    );
    const district   = req.user.district || null;
    const staffSql   = district
      ? "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users WHERE role='staff' AND district=? AND is_active=1 ORDER BY name"
      : "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users WHERE role='staff' AND is_active=1 ORDER BY name";
    const [staff] = await pool.execute(staffSql, district ? [district] : []);
    return ok(res, {
      officers:       officers.map(formatOfficer),
      availableStaff: staff.map(r => ({ id: r.id, name: r.name || '', pno: r.pno || '', mobile: r.mobile || '', rank: r.user_rank || '', isArmed: !!r.is_armed })),
    });
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/super-zones/:id/officers', adminRequired, async (req, res) => {
  try {
    let newId, userId;
    await withTransaction(async conn => {
      newId = await insertOfficer(conn, 'kshetra_officers', 'super_zone_id', req.params.id, req.body || {}, req.user.id);
      const [row] = await conn.execute('SELECT user_id FROM kshetra_officers WHERE id=?', [newId]);
      userId = row.length ? row[0].user_id : null;
    });
    return ok(res, { id: newId, userId }, 'Officer added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.put('/kshetra-officers/:id', adminRequired, async (req, res) => {
  try {
    await withTransaction(async conn => {
      await updateOfficer(conn, 'kshetra_officers', req.params.id, req.body || {}, req.user.id);
    });
    return ok(res, null, 'Updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/kshetra-officers/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute('DELETE FROM kshetra_officers WHERE id=?', [req.params.id]);
    return ok(res, null, 'Deleted');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ZONES
// ══════════════════════════════════════════════════════════════════════════════

router.get('/super-zones/:szId/zones', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search = (req.query.q || '').trim();
    const pool   = await require('../config/db').getPool();

    // DISTRICT SHARING: verify sz belongs to any admin in this district
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const [szCheck] = await pool.execute(
      `SELECT id FROM super_zones WHERE id=? AND admin_id IN (${dPh})`,
      [req.params.szId, ...dParams]
    );
    if (!szCheck.length) return err(res, 'Not found or access denied', 403);

    const params = [req.params.szId];
    let whereExtra = '';
    if (search) { whereExtra = 'AND z.name LIKE ?'; params.push(`%${search}%`); }

    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(*) AS cnt FROM zones z WHERE z.super_zone_id=? ${whereExtra}`, params
    );
    const [zones] = await pool.execute(
      `SELECT z.id, z.name, z.hq_address, COUNT(DISTINCT s.id) AS sector_count
       FROM zones z LEFT JOIN sectors s ON s.zone_id=z.id
       WHERE z.super_zone_id=? ${whereExtra}
       GROUP BY z.id ORDER BY z.id LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );
    if (!zones.length) return paginated(res, [], total, page, limit);

    const zIds = zones.map(z => z.id);
    const zPh  = zIds.map(() => '?').join(',');
    const [officers] = await pool.execute(
      `SELECT * FROM zonal_officers WHERE zone_id IN (${zPh}) ORDER BY zone_id, id`, zIds
    );
    const officersByZone = {};
    officers.forEach(o => { (officersByZone[o.zone_id] = officersByZone[o.zone_id] || []).push(formatOfficer(o)); });

    const result = zones.map(z => ({
      id: z.id, name: z.name || '', hqAddress: z.hq_address || '',
      sectorCount: z.sector_count, officers: officersByZone[z.id] || [],
    }));
    return paginated(res, result, total, page, limit);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/super-zones/:szId/zones', adminRequired, async (req, res) => {
  try {
    const { name, hqAddress = '', officers: offs = [] } = req.body || {};
    if (!name?.trim()) return err(res, 'name required');

    // DISTRICT SHARING: verify sz is accessible to this district
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const pool = await require('../config/db').getPool();
    const [szCheck] = await pool.execute(
      `SELECT id FROM super_zones WHERE id=? AND admin_id IN (${dPh})`,
      [req.params.szId, ...dParams]
    );
    if (!szCheck.length) return err(res, 'Not found or access denied', 403);

    let zId;
    await withTransaction(async conn => {
      const [r] = await conn.execute(
        'INSERT INTO zones (name, hq_address, super_zone_id) VALUES (?,?,?)',
        [name.trim(), hqAddress, req.params.szId]
      );
      zId = r.insertId;
      for (const o of offs) await insertOfficer(conn, 'zonal_officers', 'zone_id', zId, o, req.user.id);
    });
    return ok(res, { id: zId, name: name.trim() }, 'Zone added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.put('/zones/:id', adminRequired, async (req, res) => {
  try {
    const { name = '', hqAddress = '', officers: offs = [] } = req.body || {};
    await withTransaction(async conn => {
      await conn.execute('UPDATE zones SET name=?, hq_address=? WHERE id=?', [name, hqAddress, req.params.id]);
      await conn.execute('DELETE FROM zonal_officers WHERE zone_id=?', [req.params.id]);
      for (const o of offs) await insertOfficer(conn, 'zonal_officers', 'zone_id', req.params.id, o, req.user.id);
    });
    return ok(res, null, 'Updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/zones/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute('DELETE FROM zones WHERE id=?', [req.params.id]);
    return ok(res, null, 'Deleted');
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/zones/:id/officers', adminRequired, async (req, res) => {
  try {
    const pool     = await require('../config/db').getPool();
    const [officers] = await pool.execute(
      'SELECT * FROM zonal_officers WHERE zone_id=? ORDER BY id', [req.params.id]
    );
    const district = req.user.district || null;
    const staffSql = district
      ? "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users WHERE role='staff' AND district=? AND is_active=1 ORDER BY name"
      : "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users WHERE role='staff' AND is_active=1 ORDER BY name";
    const [staff] = await pool.execute(staffSql, district ? [district] : []);
    return ok(res, {
      officers:       officers.map(formatOfficer),
      availableStaff: staff.map(r => ({ id: r.id, name: r.name || '', pno: r.pno || '', mobile: r.mobile || '', rank: r.user_rank || '', isArmed: !!r.is_armed })),
    });
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/zones/:id/officers', adminRequired, async (req, res) => {
  try {
    let newId, userId;
    await withTransaction(async conn => {
      newId = await insertOfficer(conn, 'zonal_officers', 'zone_id', req.params.id, req.body || {}, req.user.id);
      const [row] = await conn.execute('SELECT user_id FROM zonal_officers WHERE id=?', [newId]);
      userId = row.length ? row[0].user_id : null;
    });
    return ok(res, { id: newId, userId }, 'Officer added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.put('/zonal-officers/:id', adminRequired, async (req, res) => {
  try {
    await withTransaction(async conn => {
      await updateOfficer(conn, 'zonal_officers', req.params.id, req.body || {}, req.user.id);
    });
    return ok(res, null, 'Updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/zonal-officers/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute('DELETE FROM zonal_officers WHERE id=?', [req.params.id]);
    return ok(res, null, 'Deleted');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  SECTORS
// ══════════════════════════════════════════════════════════════════════════════

router.get('/zones/:zId/sectors', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search = (req.query.q || '').trim();
    const pool   = await require('../config/db').getPool();
    const params = [req.params.zId];
    let whereExtra = '';
    if (search) { whereExtra = 'AND s.name LIKE ?'; params.push(`%${search}%`); }

    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(*) AS cnt FROM sectors s WHERE s.zone_id=? ${whereExtra}`, params
    );
    const [sectors] = await pool.execute(
      `SELECT s.id, s.name, s.hq_address, COUNT(DISTINCT gp.id) AS gp_count
       FROM sectors s LEFT JOIN gram_panchayats gp ON gp.sector_id=s.id
       WHERE s.zone_id=? ${whereExtra}
       GROUP BY s.id ORDER BY s.id LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );
    if (!sectors.length) return paginated(res, [], total, page, limit);

    const sIds = sectors.map(s => s.id);
    const sPh  = sIds.map(() => '?').join(',');
    const [officers] = await pool.execute(
      `SELECT * FROM sector_officers WHERE sector_id IN (${sPh}) ORDER BY sector_id, id`, sIds
    );
    const officersBySector = {};
    officers.forEach(o => { (officersBySector[o.sector_id] = officersBySector[o.sector_id] || []).push(formatOfficer(o)); });

    const result = sectors.map(s => ({
      id: s.id, name: s.name || '', hqAddress: s.hq_address || '', gpCount: s.gp_count,
      officers: officersBySector[s.id] || [],
    }));
    return paginated(res, result, total, page, limit);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/zones/:zId/sectors', adminRequired, async (req, res) => {
  try {
    const { name, hqAddress = '', officers: offs = [] } = req.body || {};
    if (!name?.trim()) return err(res, 'name required');
    let sId;
    await withTransaction(async conn => {
      const [r] = await conn.execute(
        'INSERT INTO sectors (name, hq_address, zone_id) VALUES (?,?,?)',
        [name.trim(), hqAddress, req.params.zId]
      );
      sId = r.insertId;
      for (const o of offs) await insertOfficer(conn, 'sector_officers', 'sector_id', sId, o, req.user.id);
    });
    return ok(res, { id: sId, name: name.trim() }, 'Sector added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.put('/sectors/:id', adminRequired, async (req, res) => {
  try {
    const name    = (req.body?.name      || '').trim();
    const hq      = (req.body?.hqAddress || '').trim();
    const officers = req.body?.officers  || [];
    if (!name) return err(res, 'name required');
    await withTransaction(async conn => {
      await conn.execute('UPDATE sectors SET name=?, hq_address=? WHERE id=?', [name, hq, req.params.id]);
      await conn.execute('DELETE FROM sector_officers WHERE sector_id=?', [req.params.id]);
      for (const o of officers) await insertOfficer(conn, 'sector_officers', 'sector_id', req.params.id, o, req.user.id);
    });
    return ok(res, null, 'Sector + Officers Updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/sectors/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute('DELETE FROM sectors WHERE id=?', [req.params.id]);
    return ok(res, null, 'Deleted');
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/sectors/:id/officers', adminRequired, async (req, res) => {
  try {
    const pool     = await require('../config/db').getPool();
    const [officers] = await pool.execute(
      'SELECT * FROM sector_officers WHERE sector_id=? ORDER BY id', [req.params.id]
    );
    const district = req.user.district || null;
    const staffSql = district
      ? "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users WHERE role='staff' AND district=? AND is_active=1 ORDER BY name"
      : "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users WHERE role='staff' AND is_active=1 ORDER BY name";
    const [staff] = await pool.execute(staffSql, district ? [district] : []);
    return ok(res, {
      officers:       officers.map(formatOfficer),
      availableStaff: staff.map(r => ({ id: r.id, name: r.name || '', pno: r.pno || '', mobile: r.mobile || '', rank: r.user_rank || '', isArmed: !!r.is_armed })),
    });
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/sectors/:id/officers', adminRequired, async (req, res) => {
  try {
    let newId, userId;
    await withTransaction(async conn => {
      newId = await insertOfficer(conn, 'sector_officers', 'sector_id', req.params.id, req.body || {}, req.user.id);
      const [row] = await conn.execute('SELECT user_id FROM sector_officers WHERE id=?', [newId]);
      userId = row.length ? row[0].user_id : null;
    });
    return ok(res, { id: newId, userId }, 'Officer added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.put('/sector-officers/:id', adminRequired, async (req, res) => {
  try {
    await withTransaction(async conn => {
      await updateOfficer(conn, 'sector_officers', req.params.id, req.body || {}, req.user.id);
    });
    return ok(res, null, 'Updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/sector-officers/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute('DELETE FROM sector_officers WHERE id=?', [req.params.id]);
    return ok(res, null, 'Deleted');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  GRAM PANCHAYATS
// ══════════════════════════════════════════════════════════════════════════════

router.get('/sectors/:sId/gram-panchayats', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search = (req.query.q || '').trim();
    const pool   = await require('../config/db').getPool();
    const params = [req.params.sId];
    let whereExtra = '';
    if (search) { whereExtra = 'AND gp.name LIKE ?'; params.push(`%${search}%`); }

    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(*) AS cnt FROM gram_panchayats gp WHERE gp.sector_id=? ${whereExtra}`, params
    );
    const [rows] = await pool.execute(
      `SELECT gp.*, COUNT(ms.id) AS center_count
       FROM gram_panchayats gp LEFT JOIN matdan_sthal ms ON ms.gram_panchayat_id=gp.id
       WHERE gp.sector_id=? ${whereExtra}
       GROUP BY gp.id ORDER BY gp.id LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );
    const data = rows.map(r => ({ id: r.id, name: r.name || '', address: r.address || '', centerCount: r.center_count }));
    return paginated(res, data, total, page, limit);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/sectors/:sId/gram-panchayats', adminRequired, async (req, res) => {
  try {
    const { name, address = '' } = req.body || {};
    if (!name?.trim()) return err(res, 'name required');
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
      'INSERT INTO gram_panchayats (name, address, sector_id) VALUES (?,?,?)',
      [name.trim(), address, req.params.sId]
    );
    return ok(res, { id: r.insertId, name: name.trim() }, 'GP added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.put('/gram-panchayats/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute(
      'UPDATE gram_panchayats SET name=?, address=? WHERE id=?',
      [req.body?.name || '', req.body?.address || '', req.params.id]
    );
    return ok(res, null, 'Updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/gram-panchayats/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute('DELETE FROM gram_panchayats WHERE id=?', [req.params.id]);
    return ok(res, null, 'Deleted');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ELECTION CENTERS
// ══════════════════════════════════════════════════════════════════════════════

router.get('/gram-panchayats/:gpId/centers', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search  = (req.query.q || '').trim();
    const adminId = getAdminId(req);
    const pool    = await require('../config/db').getPool();
    const params  = [req.params.gpId];
    let whereExtra = '';
    if (search) { whereExtra = 'AND ms.name LIKE ?'; params.push(`%${search}%`); }

    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(*) AS cnt FROM matdan_sthal ms WHERE ms.gram_panchayat_id=? ${whereExtra}`, params
    );
    const [centers] = await pool.execute(
      `SELECT ms.*,
          (SELECT COUNT(*) FROM duty_assignments da WHERE da.sthal_id=ms.id) AS duty_count,
          (SELECT COUNT(*) FROM matdan_kendra mk WHERE mk.matdan_sthal_id=ms.id) AS room_count
       FROM matdan_sthal ms WHERE ms.gram_panchayat_id=? ${whereExtra}
       ORDER BY ms.name LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );
    if (!centers.length) return paginated(res, [], total, page, limit);

    const centerIds = centers.map(c => c.id);
    const cPh       = centerIds.map(() => '?').join(',');
    const [staffRows] = await pool.execute(
      `SELECT da.sthal_id, u.id, u.name, u.pno, u.mobile, u.user_rank
       FROM duty_assignments da JOIN users u ON u.id=da.staff_id
       WHERE da.sthal_id IN (${cPh}) ORDER BY da.sthal_id, u.name`, centerIds
    );
    const staffByCenter = {};
    staffRows.forEach(r => {
      (staffByCenter[r.sthal_id] = staffByCenter[r.sthal_id] || []).push(
        { id: r.id, name: r.name || '', pno: r.pno || '', rank: r.user_rank || '' }
      );
    });

    // DISTRICT SHARING: load rules from all admins in same district
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const [rulesRows] = await pool.execute(
      `SELECT sensitivity, user_rank, required_count FROM booth_staff_rules WHERE admin_id IN (${dPh})`,
      dParams
    );
    const rules = {};
    rulesRows.forEach(r => { (rules[r.sensitivity] = rules[r.sensitivity] || {})[r.user_rank] = r.required_count; });

    const data = centers.map(c => {
      const centerType   = c.center_type || 'C';
      const assigned     = staffByCenter[c.id] || [];
      const centerRules  = rules[centerType] || {};
      const rankCount    = {};
      assigned.forEach(s => { rankCount[s.rank] = (rankCount[s.rank] || 0) + 1; });
      const missing = [];
      for (const [rank, required] of Object.entries(centerRules)) {
        const have = rankCount[rank] || 0;
        if (have < required) missing.push({ rank, required, available: have, lowerRankSuggestion: getLowerRank(rank) });
      }
      return {
        id: c.id, name: c.name || '', address: c.address || '', thana: c.thana || '',
        centerType, busNo: c.bus_no || '',
        latitude:  c.latitude  != null ? parseFloat(c.latitude)  : null,
        longitude: c.longitude != null ? parseFloat(c.longitude) : null,
        dutyCount: c.duty_count, roomCount: c.room_count,
        assignedStaff: assigned, missingRanks: missing,
      };
    });
    return paginated(res, data, total, page, limit);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/gram-panchayats/:gpId/centers', adminRequired, async (req, res) => {
  try {
    const { name, address = '', thana = '', centerType = 'C', busNo = '', latitude, longitude } = req.body || {};
    if (!name?.trim()) return err(res, 'name required');
    const ct   = ['A++', 'A', 'B', 'C'].includes((centerType || '').trim().toUpperCase()) ? (centerType || '').trim().toUpperCase() : 'C';
    const pool = await require('../config/db').getPool();
    const [r]  = await pool.execute(
      'INSERT INTO matdan_sthal (name, address, gram_panchayat_id, thana, center_type, bus_no, latitude, longitude) VALUES (?,?,?,?,?,?,?,?)',
      [name.trim(), address.trim(), req.params.gpId, thana.trim(), ct, busNo.trim(), latitude || null, longitude || null]
    );
    return ok(res, { id: r.insertId, name: name.trim(), centerType: ct }, 'Center added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.put('/centers/:id', adminRequired, async (req, res) => {
  try {
    const { name = '', address = '', thana = '', centerType = 'C', busNo = '', latitude, longitude } = req.body || {};
    const ct   = ['A++', 'A', 'B', 'C'].includes((centerType || '').trim().toUpperCase()) ? (centerType || '').trim().toUpperCase() : 'C';
    const pool = await require('../config/db').getPool();
    await pool.execute(
      'UPDATE matdan_sthal SET name=?, address=?, thana=?, center_type=?, bus_no=?, latitude=?, longitude=? WHERE id=?',
      [name.trim(), address.trim(), thana.trim(), ct, busNo.trim(), latitude || null, longitude || null, req.params.id]
    );
    return ok(res, { centerType: ct }, 'Updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/centers/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute('DELETE FROM matdan_sthal WHERE id=?', [req.params.id]);
    return ok(res, null, 'Deleted');
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/centers/:id/clear-assignments', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [r]  = await pool.execute('DELETE FROM duty_assignments WHERE sthal_id=?', [req.params.id]);
    await writeLog('INFO', `Cleared ${r.affectedRows} assignments from center ${req.params.id}`, 'AutoAssign');
    return ok(res, { removed: r.affectedRows }, 'Assignments cleared');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ROOMS
// ══════════════════════════════════════════════════════════════════════════════

router.get('/centers/:id/rooms', adminRequired, async (req, res) => {
  try {
    const rows = await query('SELECT id, room_number FROM matdan_kendra WHERE matdan_sthal_id=? ORDER BY id', [req.params.id]);
    return ok(res, rows.map(r => ({ id: r.id, roomNumber: r.room_number || '' })));
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/centers/:id/rooms', adminRequired, async (req, res) => {
  try {
    const rn = (req.body?.roomNumber || '').trim();
    if (!rn) return err(res, 'roomNumber required');
    const pool = await require('../config/db').getPool();
    const [r]  = await pool.execute(
      'INSERT INTO matdan_kendra (room_number, matdan_sthal_id) VALUES (?,?)', [rn, req.params.id]
    );
    return ok(res, { id: r.insertId, roomNumber: rn }, 'Room added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/rooms/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute('DELETE FROM matdan_kendra WHERE id=?', [req.params.id]);
    return ok(res, null, 'Deleted');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  STAFF — paginated + search
//  DISTRICT SHARING: staff is visible to ALL admins across all districts
// ══════════════════════════════════════════════════════════════════════════════

router.get('/staff', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search     = (req.query.q      || '').trim();
    const assigned   = (req.query.assigned || '').trim().toLowerCase();
    const rankFilter = (req.query.rank   || '').trim();
    const armed      = (req.query.armed  || '').trim().toLowerCase();
    const pool       = await require('../config/db').getPool();

    const params = [];
    const whereParts = ["u.role='staff'"];

    if (search) {
      whereParts.push('(u.name LIKE ? OR u.pno LIKE ? OR u.mobile LIKE ? OR u.thana LIKE ? OR u.district LIKE ?)');
      const like = `%${search}%`;
      params.push(like, like, like, like, like);
    }
    if (rankFilter) { whereParts.push('u.user_rank=?'); params.push(rankFilter); }

    const OFFICER_EXISTS = `(
      EXISTS (SELECT 1 FROM duty_assignments da WHERE da.staff_id=u.id)
      OR EXISTS (SELECT 1 FROM kshetra_officers ko WHERE ko.user_id=u.id)
      OR EXISTS (SELECT 1 FROM zonal_officers zo WHERE zo.user_id=u.id)
      OR EXISTS (SELECT 1 FROM sector_officers so WHERE so.user_id=u.id)
    )`;
    if (assigned === 'yes') whereParts.push(OFFICER_EXISTS);
    else if (assigned === 'no') whereParts.push(`NOT ${OFFICER_EXISTS}`);

    if (armed === 'yes') whereParts.push('u.is_armed = 1');
    else if (armed === 'no') whereParts.push('u.is_armed = 0');

    const whereSQL = whereParts.join(' AND ');

    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(*) AS cnt FROM users u WHERE ${whereSQL}`, params
    );
    const [rows] = await pool.execute(
      `SELECT
         u.id, u.name, u.pno, u.mobile, u.thana, u.district, u.user_rank, u.is_armed,
         (SELECT ms.name FROM duty_assignments da JOIN matdan_sthal ms ON ms.id=da.sthal_id WHERE da.staff_id=u.id LIMIT 1) AS center_name,
         (SELECT sz.name FROM kshetra_officers ko JOIN super_zones sz ON sz.id=ko.super_zone_id WHERE ko.user_id=u.id LIMIT 1) AS sz_name,
         (SELECT z.name  FROM zonal_officers zo  JOIN zones z         ON z.id=zo.zone_id          WHERE zo.user_id=u.id  LIMIT 1) AS zone_name,
         (SELECT s.name  FROM sector_officers so JOIN sectors s        ON s.id=so.sector_id        WHERE so.user_id=u.id  LIMIT 1) AS sector_name
       FROM users u WHERE ${whereSQL} ORDER BY u.name LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );

    const data = rows.map(r => {
      let assignType = '', assignLabel = '';
      if (r.center_name)  { assignType = 'booth';   assignLabel = r.center_name; }
      else if (r.sz_name) { assignType = 'kshetra'; assignLabel = r.sz_name; }
      else if (r.zone_name)   { assignType = 'zone';   assignLabel = r.zone_name; }
      else if (r.sector_name) { assignType = 'sector'; assignLabel = r.sector_name; }
      return {
        id: r.id, name: r.name || '', pno: r.pno || '', mobile: r.mobile || '',
        thana: r.thana || '', district: r.district || '', rank: r.user_rank || '',
        isArmed: !!r.is_armed, isAssigned: !!assignType, assignType, assignLabel,
      };
    });
    return paginated(res, data, total, page, limit);
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/staff/search', adminRequired, async (req, res) => {
  try {
    const q     = (req.query.q     || '').trim();
    const armed = (req.query.armed || '').trim().toLowerCase();
    if (!q) return ok(res, []);
    const like = `%${q}%`;
    let armedClause = '';
    if (armed === 'yes') armedClause = ' AND is_armed = 1';
    else if (armed === 'no') armedClause = ' AND is_armed = 0';
    const pool  = await require('../config/db').getPool();
    const [rows] = await pool.execute(
      `SELECT id, name, pno, mobile, thana, user_rank, district, is_armed
       FROM users WHERE role='staff' ${armedClause}
       AND (name LIKE ? OR pno LIKE ? OR mobile LIKE ? OR district LIKE ?)
       ORDER BY name LIMIT 20`,
      [like, like, like, like]
    );
    return ok(res, rows.map(r => ({
      id: r.id, name: r.name || '', pno: r.pno || '', mobile: r.mobile || '',
      thana: r.thana || '', district: r.district || '', rank: r.user_rank || '',
      isArmed: !!r.is_armed,
    })));
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/staff/debug', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [[{ cnt: total }]] = await pool.execute("SELECT COUNT(*) AS cnt FROM users WHERE role='staff'");
    const [byDistrict] = await pool.execute(
      "SELECT LOWER(TRIM(district)) AS district_norm, COUNT(*) AS cnt FROM users WHERE role='staff' GROUP BY district_norm ORDER BY cnt DESC LIMIT 20"
    );
    const adminDistrict = (req.user.district || '').trim().toLowerCase();
    let matching = total;
    if (adminDistrict) {
      const [[m]] = await pool.execute(
        "SELECT COUNT(*) AS cnt FROM users WHERE role='staff' AND LOWER(TRIM(district))=?", [adminDistrict]
      );
      matching = m.cnt;
    }
    return ok(res, {
      adminDistrict: adminDistrict || '(not set)', totalStaffInDB: total, matchingDistrict: matching,
      byDistrict: byDistrict.map(r => ({ district: r.district_norm || '(empty)', count: r.cnt })),
      message: 'If matchingDistrict=0 but totalStaffInDB>0, district mismatch is still the bug',
    });
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/staff', adminRequired, async (req, res) => {
  try {
    const { name, pno, mobile = '', thana = '', rank = '' } = req.body || {};
    if (!name?.trim() || !pno?.trim()) return err(res, 'name and pno required');

    // Fixed is_armed parsing to match Python's logic exactly
    const isArmed = (
      [true, 1, '1', 'true'].includes(req.body.isArmed)  ||
      [true, 1, '1', 'true'].includes(req.body.is_armed) ||
      ['sastra', 'armed', 'yes'].includes(String(req.body.weapon || '').toLowerCase())
    ) ? 1 : 0;

    const adminId  = getAdminId(req);
    const pool     = await require('../config/db').getPool();
    const [existing] = await pool.execute('SELECT id FROM users WHERE pno=?', [pno.trim()]);
    if (existing.length) return err(res, `PNO ${pno} already registered`, 409);
    const [usernameCheck] = await pool.execute('SELECT id FROM users WHERE username=?', [pno.trim()]);
    const username = usernameCheck.length ? `${pno.trim()}_${adminId}` : pno.trim();
    const district = req.user.district || '';
    const [r] = await pool.execute(
      "INSERT INTO users (name,pno,username,password,mobile,thana,district,user_rank,is_armed,role,is_active,created_by) VALUES (?,?,?,?,?,?,?,?,?,'staff',1,?)",
      [name.trim(), pno.trim(), username, fastHash(pno.trim()), mobile, thana, district, rank, isArmed, adminId]
    );
    await writeLog('INFO', `Staff '${name}' PNO:${pno} added (is_armed=${isArmed}) by admin ${adminId}`, 'Staff');
    return ok(res, { id: r.insertId, name: name.trim(), pno: pno.trim(), isArmed: !!isArmed }, 'Staff added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  BULK UPLOAD — SSE streaming
// ══════════════════════════════════════════════════════════════════════════════

const ARMED_VALS = new Set(['1', 'yes', 'हाँ', 'han', 'sastra', 'सशस्त्र', 'armed', 'true']);

async function runBulkUpload(req, res) {
  const body      = req.body || {};
  const items     = body.staff || [];
  if (!items.length) return err(res, 'staff list empty');
  if (items.length > MAX_BATCH_ROWS) return err(res, `Too many rows. Max ${MAX_BATCH_ROWS} per upload.`);

  const district   = (req.user.district || '').trim();
  const adminId    = req.user.id;
  const totalInput = items.length;

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache, no-store');
  res.setHeader('X-Accel-Buffering', 'no');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  const sse = data => res.write(`data: ${JSON.stringify(data)}\n\n`);

  try {
    sse({ phase: 'parse', pct: 2, msg: 'Validating rows...' });
    const clean = []; const skipped = []; const seenPnos = new Set();

    for (let i = 0; i < items.length; i++) {
      const s   = items[i];
      const pno = String(s.pno  || '').trim();
      const name = String(s.name || '').trim();
      if (!pno || !name) { skipped.push(pno || `row_${i + 1}`); continue; }
      if (seenPnos.has(pno)) { skipped.push(pno); continue; }
      seenPnos.add(pno);

      // DISTRICT SHARING: district from CSV OR fallback to admin's district
      const armedRaw = String(s.sastra ?? s.armed ?? s.is_armed ?? '').trim().toLowerCase();
      clean.push({
        pno, name,
        rank:     String(s.rank     || '').trim(),
        mobile:   String(s.mobile   || '').trim(),
        thana:    String(s.thana    || '').trim(),
        dist:     (String(s.district || '').trim()) || district,
        is_armed: ARMED_VALS.has(armedRaw) ? 1 : 0,
      });
    }

    sse({ phase: 'parse', pct: 10, msg: `${clean.length} valid, ${skipped.length} skipped` });
    if (!clean.length) {
      sse({ phase: 'done', added: 0, skipped, total: totalInput, pct: 100, msg: '0 जोड़े गए' });
      return res.end();
    }

    sse({ phase: 'parse', pct: 15, msg: 'Duplicates जांच रहे हैं...' });
    const allPnos = clean.map(r => r.pno);
    const ph      = allPnos.map(() => '?').join(',');
    const pool    = await require('../config/db').getPool();
    const [existingPnoRows]      = await pool.execute(`SELECT pno      FROM users WHERE pno      IN (${ph})`, allPnos);
    const [existingUsernameRows] = await pool.execute(`SELECT username FROM users WHERE username IN (${ph})`, allPnos);
    const existingPnos      = new Set(existingPnoRows.map(r => r.pno));
    const existingUsernames = new Set(existingUsernameRows.map(r => r.username));
    sse({ phase: 'parse', pct: 22, msg: `${existingPnos.size} duplicates मिले` });

    const preInsert = [];
    for (const r of clean) {
      if (existingPnos.has(r.pno)) { skipped.push(r.pno); continue; }
      preInsert.push({ ...r, username: existingUsernames.has(r.pno) ? `${r.pno}_${adminId}` : r.pno });
    }
    sse({ phase: 'parse', pct: 25, msg: `${preInsert.length} rows insert होंगे` });
    if (!preInsert.length) {
      sse({ phase: 'done', added: 0, skipped, total: totalInput, pct: 100, msg: '0 जोड़े गए (सभी duplicate थे)' });
      return res.end();
    }

    sse({ phase: 'hash', pct: 25, msg: `0/${preInsert.length} passwords hash हो रहे हैं...` });
    const hashed = preInsert.map(r => fastHash(r.pno));
    sse({ phase: 'hash', pct: 55, msg: 'Hash पूर्ण। DB में insert हो रहा है...' });

    let added = 0;
    const conn = await pool.getConnection();
    try {
      await conn.execute('SET autocommit=1');
      for (let start = 0; start < preInsert.length; start += INSERT_CHUNK_SIZE) {
        const chunk       = preInsert.slice(start, start + INSERT_CHUNK_SIZE);
        const chunkHashes = hashed.slice(start, start + INSERT_CHUNK_SIZE);
        const values      = chunk.map((r, i) => [
          r.name, r.pno, r.username, chunkHashes[i],
          r.mobile, r.thana, r.dist, r.rank, r.is_armed, 'staff', 1, adminId,
        ]);
        const placeholders = values.map(() => '(?,?,?,?,?,?,?,?,?,?,?,?)').join(',');
        const [insRes] = await conn.execute(
          `INSERT IGNORE INTO users (name,pno,username,password,mobile,thana,district,user_rank,is_armed,role,is_active,created_by) VALUES ${placeholders}`,
          values.flat()
        );
        added += insRes.affectedRows || 0;
        const pct = 55 + Math.floor(((start + chunk.length) / preInsert.length) * 43);
        sse({ phase: 'insert', pct: Math.min(pct, 98), added, total: preInsert.length, msg: `Insert: ${added}/${preInsert.length}` });
      }
    } catch (e) {
      sse({ phase: 'error', message: `Insert error (after ${added} rows saved): ${e.message}` });
      return res.end();
    } finally {
      conn.release();
    }

    await writeLog('INFO', `Bulk: ${added} added, ${skipped.length} skipped (admin ${adminId})`, 'Import');
    sse({ phase: 'done', added, skipped, total: totalInput, pct: 100, msg: `${added} जोड़े गए, ${skipped.length} छोड़े गए` });
  } catch (e) {
    sse({ phase: 'error', message: e.message });
  }
  res.end();
}

router.post('/staff/bulk', adminRequired, runBulkUpload);

// ── Bulk CSV upload ───────────────────────────────────────────────────────────
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

router.post('/staff/bulk-csv', adminRequired, upload.single('file'), async (req, res) => {
  if (!req.file) return err(res, "CSV file required (field: 'file')");

  let content;
  try {
    content = req.file.buffer.toString('utf8').replace(/^\uFEFF/, '');
  } catch (e) {
    return err(res, `File encoding error: ${e.message}`);
  }

  let records;
  try {
    records = csvParse(content, { columns: true, skip_empty_lines: true, trim: true });
  } catch (e) {
    return err(res, `CSV parse error: ${e.message}`);
  }

  const items = [];
  for (const row of records) {
    const norm = {};
    for (const [k, v] of Object.entries(row)) norm[k.trim().toLowerCase()] = v;
    const pno  = norm['pno']  || norm['p.no'] || '';
    const name = norm['name'] || norm['नाम']  || '';
    if (!pno && !name) continue;
    const armedRaw = (norm['sastra'] || norm['armed'] || norm['weapon'] || norm['शस्त्र'] || '').trim().toLowerCase();
    items.push({
      pno:      pno.trim(),
      name:     name.trim(),
      mobile:   (norm['mobile']   || norm['mob']   || norm['phone'] || '').trim(),
      thana:    (norm['thana']    || norm['थाना']  || norm['ps']    || '').trim(),
      district: (norm['district'] || norm['dist']  || norm['जिला'] || '').trim(),
      rank:     (norm['rank']     || norm['post']  || norm['पद']   || '').trim(),
      is_armed: ARMED_VALS.has(armedRaw) ? 1 : 0,
    });
  }

  if (!items.length) return err(res, 'No valid rows found in CSV');

  // Properly delegate to the same SSE handler
  req.body = { staff: items };
  return runBulkUpload(req, res);
});

router.put('/staff/:id', adminRequired, async (req, res) => {
  try {
    const { name = '', pno = '', mobile = '', thana = '', rank = '' } = req.body || {};
    const isArmed = req.body.isArmed ? 1 : 0;
    const pool    = await require('../config/db').getPool();
    await pool.execute(
      "UPDATE users SET name=?,pno=?,mobile=?,thana=?,user_rank=?,is_armed=? WHERE id=? AND role='staff'",
      [name, pno, mobile, thana, rank, isArmed, req.params.id]
    );
    return ok(res, null, 'Staff updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/staff/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute("DELETE FROM users WHERE id=? AND role='staff'", [req.params.id]);
    return ok(res, null, 'Staff deleted');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/staff/:id/duty', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [r]  = await pool.execute('DELETE FROM duty_assignments WHERE staff_id=?', [req.params.id]);
    if (!r.affectedRows) return err(res, 'No duty found for this staff', 404);
    return ok(res, null, 'Duty removed');
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/staff/bulk-delete', adminRequired, async (req, res) => {
  try {
    const ids = req.body?.staffIds;
    if (!Array.isArray(ids) || !ids.length) return err(res, 'staffIds required');
    const ph   = ids.map(() => '?').join(',');
    const pool = await require('../config/db').getPool();
    const [r]  = await pool.execute(`DELETE FROM users WHERE id IN (${ph}) AND role='staff'`, ids);
    await writeLog('INFO', `Bulk delete: ${r.affectedRows} staff by admin ${getAdminId(req)}`, 'Staff');
    return ok(res, { deleted: r.affectedRows }, `${r.affectedRows} staff deleted`);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/staff/bulk-assign', adminRequired, async (req, res) => {
  try {
    const { staffIds: ids = [], centerId, busNo = '' } = req.body || {};
    if (!ids.length || !centerId) return err(res, 'staffIds and centerId required');
    const adminId = getAdminId(req);
    const pool    = await require('../config/db').getPool();
    let assigned  = 0;
    for (const sid of ids) {
      await pool.execute(
        'INSERT INTO duty_assignments (staff_id, sthal_id, bus_no, assigned_by) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE sthal_id=VALUES(sthal_id), bus_no=VALUES(bus_no), assigned_by=VALUES(assigned_by)',
        [sid, centerId, busNo, adminId]
      );
      assigned++;
    }
    await writeLog('INFO', `Bulk assign: ${assigned} staff → center ${centerId} by admin ${adminId}`, 'Duty');
    return ok(res, { assigned }, `${assigned} staff assigned`);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/staff/bulk-unassign', adminRequired, async (req, res) => {
  try {
    const ids = req.body?.staffIds;
    if (!Array.isArray(ids) || !ids.length) return err(res, 'staffIds required');
    const ph   = ids.map(() => '?').join(',');
    const pool = await require('../config/db').getPool();
    const [r]  = await pool.execute(`DELETE FROM duty_assignments WHERE staff_id IN (${ph})`, ids);
    return ok(res, { removed: r.affectedRows }, `${r.affectedRows} duties removed`);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY ASSIGNMENTS
// ══════════════════════════════════════════════════════════════════════════════

router.get('/duties', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const centerIdFilter = req.query.center_id ? parseInt(req.query.center_id, 10) : null;
    const search         = (req.query.q      || '').trim();
    const cardStatus     = (req.query.card   || '').trim().toLowerCase();
    const rankFilter     = (req.query.rank   || '').trim();
    const armedFilter    = (req.query.armed  || '').trim().toLowerCase();
    const pool           = await require('../config/db').getPool();

    // DISTRICT SHARING: show duties for all admins in same district
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const whereParts = [`sz.admin_id IN (${dPh})`];
    const params     = [...dParams];

    if (centerIdFilter) { whereParts.push('ms.id=?'); params.push(centerIdFilter); }
    if (search) {
      whereParts.push('(u.name LIKE ? OR u.pno LIKE ? OR ms.name LIKE ?)');
      const like = `%${search}%`;
      params.push(like, like, like);
    }
    if (cardStatus === 'downloaded') whereParts.push('da.card_downloaded > 0');
    else if (cardStatus === 'pending') whereParts.push('da.card_downloaded = 0');
    if (rankFilter)  { whereParts.push('LOWER(u.user_rank) = LOWER(?)'); params.push(rankFilter); }
    if (armedFilter === 'armed')   whereParts.push('u.is_armed = 1');
    else if (armedFilter === 'unarmed') whereParts.push('u.is_armed = 0');

    const whereSQL = whereParts.join(' AND ');

    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(*) AS cnt FROM duty_assignments da JOIN users u ON u.id=da.staff_id
       JOIN matdan_sthal ms ON ms.id=da.sthal_id JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
       JOIN sectors s ON s.id=gp.sector_id JOIN zones z ON z.id=s.zone_id
       JOIN super_zones sz ON sz.id=z.super_zone_id WHERE ${whereSQL}`, params
    );
    const [rows] = await pool.execute(
      `SELECT da.id, da.bus_no, da.card_downloaded,
         u.id AS staff_id, u.name, u.pno, u.mobile, u.is_armed, u.thana, u.user_rank, u.district,
         ms.id AS center_id, ms.name AS center_name, ms.center_type,
         gp.name AS gp_name,
         s.id AS sector_id, s.name AS sector_name,
         z.id AS zone_id, z.name AS zone_name,
         sz.id AS super_zone_id, sz.name AS super_zone_name, sz.block AS block_name
       FROM duty_assignments da
       JOIN users u ON u.id=da.staff_id JOIN matdan_sthal ms ON ms.id=da.sthal_id
       JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
       JOIN sectors s ON s.id=gp.sector_id JOIN zones z ON z.id=s.zone_id
       JOIN super_zones sz ON sz.id=z.super_zone_id
       WHERE ${whereSQL} ORDER BY ms.name, u.name LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );
    if (!rows.length) return paginated(res, [], total, page, limit);

    const szIds = [...new Set(rows.map(r => r.super_zone_id))];
    const zIds  = [...new Set(rows.map(r => r.zone_id))];
    const sIds  = [...new Set(rows.map(r => r.sector_id))];
    const cIds  = [...new Set(rows.map(r => r.center_id))];

    async function fetchMap(sql, ids) {
      if (!ids.length) return {};
      const ph    = ids.map(() => '?').join(',');
      const [arr] = await pool.execute(sql.replace('{ph}', ph), ids);
      const map   = {};
      arr.forEach(row => { const key = Object.values(row)[0]; (map[key] = map[key] || []).push(row); });
      return map;
    }

    const [superOffMap, zonalOffMap, sectorOffMap, sahyogiMap] = await Promise.all([
      fetchMap(`SELECT super_zone_id AS _fk, name, pno, mobile, user_rank FROM kshetra_officers WHERE super_zone_id IN ({ph})`, szIds),
      fetchMap(`SELECT zone_id AS _fk, name, pno, mobile, user_rank FROM zonal_officers WHERE zone_id IN ({ph})`, zIds),
      fetchMap(`SELECT sector_id AS _fk, name, pno, mobile, user_rank FROM sector_officers WHERE sector_id IN ({ph})`, sIds),
      fetchMap(`SELECT da2.sthal_id AS _fk, u2.name, u2.pno, u2.mobile, u2.thana, u2.user_rank, u2.district FROM duty_assignments da2 JOIN users u2 ON u2.id=da2.staff_id WHERE da2.sthal_id IN ({ph})`, cIds),
    ]);

    const strip  = list => (list || []).map(({ _fk, ...rest }) => rest);
    const result = rows.map(r => ({
      id: r.id, centerId: r.center_id,
      name: r.name || '', pno: r.pno || '', mobile: r.mobile || '',
      staffThana: r.thana || '', rank: r.user_rank || '', district: r.district || '',
      cardDownloaded: !!r.card_downloaded, isArmed: !!r.is_armed,
      centerName: r.center_name || '', gpName: r.gp_name || '',
      sectorName: r.sector_name || '', zoneName: r.zone_name || '',
      superZoneName: r.super_zone_name || '', blockName: r.block_name || '',
      busNo: r.bus_no || '',
      superOfficers:  strip(superOffMap[r.super_zone_id]),
      zonalOfficers:  strip(zonalOffMap[r.zone_id]),
      sectorOfficers: strip(sectorOffMap[r.sector_id]),
      sahyogi:        strip(sahyogiMap[r.center_id]),
    }));

    return paginated(res, result, total, page, limit);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/duties', adminRequired, async (req, res) => {
  const { staffId, centerId } = req.body || {};

  if (!staffId || !centerId) {
    return err(res, 'staffId and centerId required');
  }

  const pool = await require('../config/db').getPool();

  try {
    const conn = await pool.getConnection();
    try {
      // ✅ 1. Fetch election date (STRICT like Flask)
      const [[cfg]] = await conn.execute(
        "SELECT value FROM app_config WHERE `key`='electionDate' LIMIT 1"
      );

      if (!cfg || !cfg.value) {
        conn.release();
        return err(res, 'Election date not set by master', 400);
      }

      const electionDate = cfg.value;

      // ✅ 2. Validate center belongs to admin district (IMPORTANT)
      const district = req.user?.district || '';

      const [[center]] = await conn.execute(`
        SELECT ms.bus_no
        FROM matdan_sthal ms
        JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
        JOIN sectors s ON s.id = gp.sector_id
        JOIN zones z ON z.id = s.zone_id
        JOIN super_zones sz ON sz.id = z.super_zone_id
        WHERE ms.id = ? AND sz.district = ?
        LIMIT 1
      `, [centerId, district]);

      if (!center) {
        conn.release();
        return err(res, 'Center not found or not in your district', 403);
      }

      const busNo = center.bus_no || '';

      // ✅ 3. Insert / Update (same as Flask)
      await conn.execute(`
        INSERT INTO duty_assignments
          (staff_id, sthal_id, bus_no, assigned_by, election_date)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          sthal_id      = VALUES(sthal_id),
          bus_no        = VALUES(bus_no),
          assigned_by   = VALUES(assigned_by),
          election_date = VALUES(election_date)
      `, [
        staffId,
        centerId,
        busNo,
        req.user.id, // same as _admin_id()
        electionDate
      ]);

      await conn.commit();
      conn.release();

      // ✅ 4. Logging (same as Flask)
      const { writeLog } = require('../config/db');
      await writeLog(
        'INFO',
        `Duty: staff ${staffId} → center ${centerId} (Bus: ${busNo}, Date: ${electionDate})`,
        'Duty'
      );

      // ✅ 5. Response SAME as Flask
      return ok(res, {
        busNo,
        electionDate
      }, 'Duty assigned', 201);

    } catch (e) {
      conn.release();
      throw e;
    }
  } catch (e) {
    return err(res, e.message, 500);
  }
});


router.delete('/duties/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute('DELETE FROM duty_assignments WHERE id=?', [req.params.id]);
    return ok(res, null, 'Duty removed');
  } catch (e) { return err(res, e.message, 500); }
});

// PATCH attendance (missing from original JS)
router.patch('/duties/:id/attended', adminRequired, async (req, res) => {
  try {
    const attended = req.body?.attended ? 1 : 0;
    const pool     = await require('../config/db').getPool();
    await pool.execute('UPDATE duty_assignments SET attended=? WHERE id=?', [attended, req.params.id]);
    return ok(res, null, 'Attendance updated');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ALL CENTERS (map view)
// ══════════════════════════════════════════════════════════════════════════════

router.get('/centers/all', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search = (req.query.q || '').trim();
    const pool   = await require('../config/db').getPool();

    // DISTRICT SHARING: show centers for all admins in same district
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const params = [...dParams];
    let whereExtra = '';
    if (search) {
      whereExtra = 'AND (ms.name LIKE ? OR ms.thana LIKE ? OR gp.name LIKE ?)';
      const like = `%${search}%`;
      params.push(like, like, like);
    }

    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(DISTINCT ms.id) AS cnt FROM matdan_sthal ms
       JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
       JOIN sectors s ON s.id=gp.sector_id JOIN zones z ON z.id=s.zone_id
       JOIN super_zones sz ON sz.id=z.super_zone_id
       WHERE sz.admin_id IN (${dPh}) ${whereExtra}`, params
    );
    const [rows] = await pool.execute(
      `SELECT ms.id, ms.name, ms.address, ms.thana, ms.center_type, ms.bus_no,
              ms.latitude, ms.longitude,
              gp.name AS gp_name, s.name AS sector_name, z.name AS zone_name,
              sz.name AS super_zone_name, sz.block AS block_name,
              COUNT(da.id) AS duty_count
       FROM matdan_sthal ms
       JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
       JOIN sectors s ON s.id=gp.sector_id JOIN zones z ON z.id=s.zone_id
       JOIN super_zones sz ON sz.id=z.super_zone_id
       LEFT JOIN duty_assignments da ON da.sthal_id=ms.id
       WHERE sz.admin_id IN (${dPh}) ${whereExtra}
       GROUP BY ms.id ORDER BY ms.name LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );
    const data = rows.map(r => ({
      id: r.id, name: r.name || '', address: r.address || '', thana: r.thana || '',
      centerType: r.center_type || 'C', busNo: r.bus_no || '',
      latitude:  r.latitude  != null ? parseFloat(r.latitude)  : null,
      longitude: r.longitude != null ? parseFloat(r.longitude) : null,
      gpName: r.gp_name || '', sectorName: r.sector_name || '',
      zoneName: r.zone_name || '', superZoneName: r.super_zone_name || '',
      blockName: r.block_name || '', dutyCount: r.duty_count,
    }));
    return paginated(res, data, total, page, limit);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  OVERVIEW — district-wide aggregation (matches Python)
// ══════════════════════════════════════════════════════════════════════════════

router.get('/overview', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();

    // DISTRICT SHARING: aggregate for all admins in same district
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const [[[sz]], [[booths]], [[staff]], [[assigned]]] = await Promise.all([
      pool.execute(`SELECT COUNT(*) AS cnt FROM super_zones WHERE admin_id IN (${dPh})`, dParams),
      pool.execute(
        `SELECT COUNT(DISTINCT ms.id) AS cnt FROM matdan_sthal ms
         JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
         JOIN sectors s ON s.id=gp.sector_id JOIN zones z ON z.id=s.zone_id
         JOIN super_zones sz ON sz.id=z.super_zone_id WHERE sz.admin_id IN (${dPh})`, dParams
      ),
      // Staff count: ALL staff across all districts (matches Python)
      pool.execute("SELECT COUNT(*) AS cnt FROM users WHERE role='staff' AND is_active=1"),
      // Assigned duties: only at centers belonging to this district's admins (matches Python)
      pool.execute(
        `SELECT COUNT(*) AS cnt FROM duty_assignments da
         JOIN matdan_sthal ms ON ms.id=da.sthal_id
         JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
         JOIN sectors s ON s.id=gp.sector_id JOIN zones z ON z.id=s.zone_id
         JOIN super_zones sz ON sz.id=z.super_zone_id WHERE sz.admin_id IN (${dPh})`, dParams
      ),
    ]);

    return res.json({
      success: true,
      data: {
        superZones:    parseInt(sz.cnt    || 0),
        totalBooths:   parseInt(booths.cnt || 0),
        totalStaff:    parseInt(staff.cnt  || 0),
        assignedDuties: parseInt(assigned.cnt || 0),
      },
    });
  } catch (e) {
    await writeLog('ERROR', `overview error: ${e.message}`, 'Overview');
    return res.json({ success: true, data: { superZones: 0, totalBooths: 0, totalStaff: 0, assignedDuties: 0 } });
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  RULES — DISTRICT SHARING
//  Rules are saved per admin_id but read from ALL district admins combined.
// ══════════════════════════════════════════════════════════════════════════════

router.get('/rules', adminRequired, async (req, res) => {
  try {
    const sensitivity = (req.query.sensitivity || '').trim();
    const pool        = await require('../config/db').getPool();

    // DISTRICT SHARING: read rules from ALL admins in same district
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    let rows;
    if (sensitivity) {
      const [r] = await pool.execute(
        `SELECT sensitivity, user_rank AS \`rank\`, is_armed, required_count AS \`count\`
         FROM booth_staff_rules WHERE admin_id IN (${dPh}) AND sensitivity=? ORDER BY id`,
        [...dParams, sensitivity]
      );
      rows = r;
    } else {
      const [r] = await pool.execute(
        `SELECT sensitivity, user_rank AS \`rank\`, is_armed, required_count AS \`count\`
         FROM booth_staff_rules WHERE admin_id IN (${dPh})
         ORDER BY FIELD(sensitivity,'A++','A','B','C'), id`,
        dParams
      );
      rows = r;
    }

    const result = rows.map(r => ({
      rank: String(r.rank), count: parseInt(r.count), isArmed: !!r.is_armed,
      sensitivity: r.sensitivity,
    }));
    return ok(res, result);
  } catch (e) {
    await writeLog('WARN', `get_rules error: ${e.message}`, 'Rules');
    return ok(res, []);
  }
});

router.post('/rules', adminRequired, async (req, res) => {
  try {
    const { sensitivity, rules = [] } = req.body || {};
    if (!sensitivity) return err(res, 'sensitivity required');
    if (!['A++', 'A', 'B', 'C'].includes(sensitivity)) return err(res, 'sensitivity must be one of: A++, A, B, C');

    const adminId = getAdminId(req);
    const pool    = await require('../config/db').getPool();

    await pool.execute(`
      CREATE TABLE IF NOT EXISTS booth_staff_rules (
        id             INT AUTO_INCREMENT PRIMARY KEY,
        admin_id       INT  NOT NULL,
        sensitivity    ENUM('A++','A','B','C') NOT NULL,
        user_rank      VARCHAR(100) NOT NULL,
        is_armed       TINYINT(1)   NOT NULL DEFAULT 0,
        required_count INT          NOT NULL DEFAULT 1,
        created_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_admin       (admin_id),
        INDEX idx_sensitivity (sensitivity),
        FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    // DISTRICT SHARING: delete rules for ALL district admins before saving (prevents duplicates)
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    await withTransaction(async conn => {
      await conn.execute(
        `DELETE FROM booth_staff_rules WHERE admin_id IN (${dPh}) AND sensitivity=?`,
        [...dParams, sensitivity]
      );
      // Save new rules under current admin_id only
      for (const r of rules) {
        const rank = String(r.rank || '').trim();
        if (!rank) continue;
        const count   = parseInt(r.count || r.required_count || 1);
        const isArmed = ([true, 1, '1', 'true'].includes(r.isArmed) || [true, 1, '1', 'true'].includes(r.is_armed)) ? 1 : 0;
        await conn.execute(
          'INSERT INTO booth_staff_rules (admin_id, sensitivity, user_rank, is_armed, required_count) VALUES (?,?,?,?,?)',
          [adminId, sensitivity, rank, isArmed, count]
        );
      }
    });

    await writeLog('INFO', `Rules saved: sensitivity=${sensitivity}, ${rules.length} rules by admin ${adminId}`, 'Rules');
    return ok(res, null, `${sensitivity} rules saved`);
  } catch (e) {
    await writeLog('ERROR', `save_rules error: ${e.message}`, 'Rules');
    return err(res, `Save failed: ${e.message}`, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  AUTO ASSIGN — uses district-wide rules
// ══════════════════════════════════════════════════════════════════════════════

router.post('/auto-assign/:centerId', adminRequired, async (req, res) => {
  try {
    const { centerId }    = req.params;
    const customRulesRaw  = req.body?.customRules || [];
    const adminId         = getAdminId(req);
    const pool            = await require('../config/db').getPool();

    const [[center]] = await pool.execute('SELECT center_type, bus_no FROM matdan_sthal WHERE id=?', [centerId]);
    if (!center) return err(res, 'Center not found', 404);
    const sensitivity = (center.center_type || '').trim().toUpperCase();

    let rules;
    if (customRulesRaw.length) {
      rules = customRulesRaw.filter(r => r.rank).map(r => ({
        user_rank:      r.rank,
        required_count: parseInt(r.count, 10) || 1,
        is_armed:       parseInt(r.isArmed || r.is_armed || 0),
      }));
    } else {
      // DISTRICT SHARING: load rules from all admins in same district
      const dIds = await getDistrictAdminIds(req);
      const { ph: dPh, params: dParams } = districtPH(dIds);
      const [dbRules] = await pool.execute(
        `SELECT user_rank, required_count, is_armed FROM booth_staff_rules WHERE admin_id IN (${dPh}) AND sensitivity=?`,
        [...dParams, sensitivity]
      );
      rules = dbRules;
    }

    if (!rules.length) {
      return ok(res, {
        assigned: [], missing: [], lowerRankUsed: [], total: 0,
        message: `No rules set for ${sensitivity}. Set rules on Dashboard.`,
      });
    }

    const assignedList = [], missingList = [], lowerRankUsed = [];

    await withTransaction(async conn => {
      for (const rule of rules) {
        const rank    = rule.user_rank;
        const count   = rule.required_count;
        const isArmed = parseInt(rule.is_armed || 0);

        const [available] = await conn.execute(
          `SELECT id, name, pno, mobile, user_rank, is_armed
           FROM users WHERE role='staff' AND user_rank=? AND is_armed=? AND is_active=1
           AND NOT EXISTS (SELECT 1 FROM duty_assignments da WHERE da.staff_id=id)
           ORDER BY RAND() LIMIT ${count}`,
          [rank, isArmed]
        );

        let assignedForRank = [...available];
        let needed          = count - available.length;
        const lowerAssigned = [];

        if (needed > 0) {
          let lowerRank = getLowerRank(rank);
          while (lowerRank && needed > 0) {
            const [la] = await conn.execute(
              `SELECT id, name, pno, mobile, user_rank, is_armed
               FROM users WHERE role='staff' AND user_rank=? AND is_armed=? AND is_active=1
               AND NOT EXISTS (SELECT 1 FROM duty_assignments da WHERE da.staff_id=id)
               ORDER BY RAND() LIMIT ${needed}`,
              [lowerRank, isArmed]
            );
            if (la.length) {
              lowerAssigned.push(...la);
              needed -= la.length;
              lowerRankUsed.push({ requiredRank: rank, assignedRank: lowerRank, count: la.length, isArmed: !!isArmed });
            }
            lowerRank = getLowerRank(lowerRank);
          }
          const stillMissing = count - available.length - lowerAssigned.length;
          if (stillMissing > 0) {
            missingList.push({ rank, required: count, available: count - stillMissing, shortage: stillMissing, isArmed: !!isArmed });
          }
          for (const s of lowerAssigned) {
            await conn.execute(
              'INSERT IGNORE INTO duty_assignments (staff_id, sthal_id, assigned_by, bus_no) VALUES (?,?,?,?)',
              [s.id, centerId, adminId, center.bus_no]
            );
            assignedList.push({
              id: s.id, name: s.name || '', pno: s.pno || '', rank: s.user_rank || '',
              originalRank: rank, isLowerRank: true, isArmed: !!s.is_armed, bus_no: center.bus_no,
            });
          }
        }

        for (const s of assignedForRank) {
          await conn.execute(
            'INSERT IGNORE INTO duty_assignments (staff_id, sthal_id, assigned_by, bus_no) VALUES (?,?,?,?)',
            [s.id, centerId, adminId, center.bus_no]
          );
          assignedList.push({
            id: s.id, name: s.name || '', pno: s.pno || '', rank: s.user_rank || '',
            isLowerRank: false, isArmed: !!s.is_armed, bus_no: center.bus_no,
          });
        }

        if (!assignedForRank.length && needed === count) {
          if (!missingList.find(m => m.rank === rank)) {
            missingList.push({ rank, required: count, available: 0, shortage: count, isArmed: !!isArmed, lowerRankSuggestion: getLowerRank(rank) });
          }
        }
      }
    });

    await writeLog('INFO', `Auto-assign: ${assignedList.length} to center ${centerId} (missing: ${missingList.length}, lower: ${lowerRankUsed.length})`, 'AutoAssign');
    return ok(res, { assigned: assignedList, missing: missingList, lowerRankUsed, total: assignedList.length });
  } catch (e) { return err(res, e.message, 500); }
});

// ── Save officer to users ─────────────────────────────────────────────────────
router.post('/officers/save-to-users', adminRequired, async (req, res) => {
  try {
    const { name, pno, mobile = '', rank = '' } = req.body || {};
    if (!name?.trim() || !pno?.trim()) return err(res, 'name and pno required');
    const pool = await require('../config/db').getPool();
    const [existing] = await pool.execute('SELECT id FROM users WHERE pno=?', [pno.trim()]);
    if (existing.length) return ok(res, { id: existing[0].id, existed: true }, 'Already in users');
    const [usernameCheck] = await pool.execute('SELECT id FROM users WHERE username=?', [pno.trim()]);
    const username = usernameCheck.length ? `${pno.trim()}_${req.user.id}` : pno.trim();
    const district = req.user.district || '';
    const [r] = await pool.execute(
      "INSERT INTO users (name,pno,username,password,mobile,district,user_rank,is_armed,role,is_active,created_by) VALUES (?,?,?,?,?,?,?,?,'staff',1,?)",
      [name.trim(), pno.trim(), username, fastHash(pno.trim()), mobile, district, rank, 0, req.user.id]
    );
    await writeLog('INFO', `Officer '${name}' PNO:${pno} saved to users by admin ${req.user.id}`, 'Officer');
    return ok(res, { id: r.insertId, existed: false }, 'Officer saved to users', 201);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  SUPER ADMIN ROUTES (missing from original JS)
// ══════════════════════════════════════════════════════════════════════════════

// GET /super/admins — list all admins with booth/staff counts
router.get('/super/admins', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(`
      SELECT
        u.id, u.name, u.username, u.district, u.is_active, u.created_at,
        (SELECT COUNT(DISTINCT ms.id)
         FROM matdan_sthal ms
         JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
         JOIN sectors s ON s.id = gp.sector_id
         JOIN zones z ON z.id = s.zone_id
         JOIN super_zones sz ON sz.id = z.super_zone_id
         WHERE sz.admin_id = u.id
        ) AS totalBooths,
        (SELECT COUNT(*)
         FROM duty_assignments da
         JOIN users us ON us.id = da.staff_id
         WHERE us.created_by = u.id
        ) AS assignedStaff
      FROM users u
      WHERE u.role = 'admin'
      ORDER BY u.id DESC
    `);
    const data = rows.map(r => ({
      id: r.id, name: r.name, username: r.username, district: r.district,
      isActive: !!r.is_active, totalBooths: r.totalBooths || 0,
      assignedStaff: r.assignedStaff || 0, createdAt: r.created_at,
    }));
    return ok(res, data);
  } catch (e) { return err(res, e.message, 500); }
});

// GET /super/form-data — per-admin data counts (auth required, under /super/)
router.get('/super/form-data', adminRequired, async (req, res) => {
  try {
    const pool  = await require('../config/db').getPool();
    const [rows] = await pool.execute(`
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
      LEFT JOIN super_zones     sz ON sz.admin_id          = u.id
      LEFT JOIN zones            z ON z.super_zone_id      = sz.id
      LEFT JOIN sectors          s ON s.zone_id            = z.id
      LEFT JOIN gram_panchayats gp ON gp.sector_id         = s.id
      LEFT JOIN matdan_sthal    ms ON ms.gram_panchayat_id = gp.id
      WHERE u.role = 'admin'
      GROUP BY u.id ORDER BY u.id DESC
    `);
    return ok(res, rows);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  GOSWARA
// ══════════════════════════════════════════════════════════════════════════════

router.get('/goswara', adminRequired, async (req, res) => {
  const currentId   = req.user.id;
  const district    = (req.user.district || '').trim();
  const pool        = await require('../config/db').getPool();

  try {
    const [cfgRows] = await pool.execute(
      "SELECT `key`, value FROM app_config WHERE `key` IN ('electionDate', 'phase')"
    );
    const cfg = {};
    cfgRows.forEach(r => { cfg[r.key] = r.value; });

    // DISTRICT SHARING: always aggregate by district (any role, matches Python)
    let adminIds = [];
    if (district) {
      const [rows] = await pool.execute(
        "SELECT id FROM users WHERE role='admin' AND district=?", [district]
      );
      adminIds = rows.map(r => r.id);
    }
    if (!adminIds.length) adminIds = [currentId];

    const ph = adminIds.map(() => '?').join(',');

    const [rows] = await pool.execute(`
      SELECT
        sz.block AS block_name,
        COUNT(DISTINCT zo.id)     AS zonal_count,
        COUNT(DISTINCT so_off.id) AS sector_count,
        COUNT(DISTINCT gp.id)     AS gram_panchayat_count
      FROM super_zones sz
      LEFT JOIN zones z ON z.super_zone_id = sz.id
      LEFT JOIN zonal_officers zo ON zo.zone_id = z.id
      LEFT JOIN sectors s ON s.zone_id = z.id
      LEFT JOIN sector_officers so_off ON so_off.sector_id = s.id
      LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
      WHERE sz.admin_id IN (${ph})
        AND sz.block IS NOT NULL AND TRIM(sz.block) != ''
      GROUP BY sz.block ORDER BY sz.block
    `, adminIds);

    const [nyayRows] = await pool.execute(`
      SELECT block_name, SUM(nyay_count) AS nyay_count
      FROM goswara_nyay_panchayat WHERE admin_id IN (${ph})
      GROUP BY block_name
    `, adminIds);

    const nyayMap = {};
    nyayRows.forEach(r => { nyayMap[r.block_name] = parseInt(r.nyay_count || 0); });

    const data = rows.map(r => ({
      block_name:           r.block_name || '',
      zonal_count:          parseInt(r.zonal_count          || 0),
      sector_count:         parseInt(r.sector_count         || 0),
      nyay_panchayat_count: nyayMap[r.block_name]            || 0,
      gram_panchayat_count: parseInt(r.gram_panchayat_count || 0),
    }));

    return res.json({ success: true, electionDate: cfg.electionDate || '', phase: cfg.phase || '', data });
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/goswara/nyay-panchayat', adminRequired, async (req, res) => {
  try {
    const blockName = (req.body?.blockName || '').trim();
    const nyayCount = parseInt(req.body?.nyayCount || 0);
    if (!blockName) return err(res, 'blockName required');
    const pool = await require('../config/db').getPool();
    await pool.execute(
      `INSERT INTO goswara_nyay_panchayat (admin_id, block_name, nyay_count)
       VALUES (?,?,?)
       ON DUPLICATE KEY UPDATE nyay_count = VALUES(nyay_count)`,
      [req.user.id, blockName, nyayCount]
    );
    return ok(res, null, 'saved');
  } catch (e) { return err(res, e.message, 500); }
});

// ── form-data (public, no auth — kept for backward compat) ───────────────────
router.get('/form-data', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        u.id AS adminId, u.name AS adminName, u.district,
        COUNT(DISTINCT sz.id) AS superZones, COUNT(DISTINCT z.id) AS zones,
        COUNT(DISTINCT s.id) AS sectors,     COUNT(DISTINCT gp.id) AS gramPanchayats,
        COUNT(DISTINCT ms.id) AS centers,    MAX(ms.created_at) AS lastUpdated
      FROM users u
      LEFT JOIN super_zones     sz ON sz.admin_id          = u.id
      LEFT JOIN zones            z ON z.super_zone_id      = sz.id
      LEFT JOIN sectors          s ON s.zone_id            = z.id
      LEFT JOIN gram_panchayats gp ON gp.sector_id         = s.id
      LEFT JOIN matdan_sthal    ms ON ms.gram_panchayat_id = gp.id
      WHERE u.role = 'admin'
      GROUP BY u.id ORDER BY u.id DESC
    `);
    return res.json({ success: true, data: rows });
  } catch (e) {
    return res.status(500).json({ success: false, message: e.message });
  }
});

module.exports = router;