'use strict';

const express = require('express');
const router = express.Router();
const { query, getPool } = require('../config/db');
const { adminRequired } = require('../middleware/auth');

// ── Helpers ───────────────────────────────────────────────────────────────────
function officer(r) {
  return { id: r.id, user_id: r.user_id, name: r.name || '', pno: r.pno || '', mobile: r.mobile || '', user_rank: r.user_rank || '' };
}

async function fetchOfficers(conn, table, fkCol, fkVal) {
  const [rows] = await conn.execute(`SELECT * FROM ${table} WHERE ${fkCol}=? ORDER BY id`, [fkVal]);
  return rows.map(officer);
}

async function fetchDutyOfficers(conn, sthalId) {
  const [rows] = await conn.execute(`
    SELECT u.id, u.name, u.pno, u.mobile, u.user_rank, u.thana, da.id AS duty_id, da.bus_no
    FROM duty_assignments da JOIN users u ON u.id=da.staff_id
    WHERE da.sthal_id=? ORDER BY u.name
  `, [sthalId]);
  return rows.map(r => ({
    id: r.duty_id,
    user_id: r.id,
    name: r.name || '',
    pno: r.pno || '',
    mobile: r.mobile || '',
    user_rank: r.user_rank || '',
    thana: r.thana || '',
    bus_no: r.bus_no || '',
  }));
}

async function fetchKendras(conn, sthalId) {
  const [rows] = await conn.execute('SELECT id, room_number FROM matdan_kendra WHERE matdan_sthal_id=? ORDER BY id', [sthalId]);
  return rows.map(r => ({ id: r.id, room_number: r.room_number || '' }));
}

async function ensureUser(conn, name, pno, mobile, rank, createdBy) {
  if (!pno) return null;
  const [[existing]] = await conn.execute('SELECT id FROM users WHERE pno=?', [pno]);
  if (existing) return existing.id;
  const [[byUsername]] = await conn.execute('SELECT id FROM users WHERE username=?', [pno]);
  const username = byUsername ? `${pno}_${createdBy}` : pno;
  const crypto = require('crypto');
  const SALT = 'election_2026_secure_key';
  const password = crypto.createHash('sha256').update(pno + SALT).digest('hex');
  const [result] = await conn.execute(
    `INSERT INTO users (name, pno, username, password, mobile, user_rank, role, is_active, created_by)
     VALUES (?,?,?,?,?,?,'staff',1,?)`,
    [name, pno, username, password, mobile, rank, createdBy]
  );
  return result.insertId;
}

async function insertOfficer(conn, table, fkCol, fkVal, o, adminId) {
  const name = (o.name || '').trim();
  const pno = (o.pno || '').trim();
  const mobile = (o.mobile || '').trim();
  const rank = (o.user_rank || o.rank || '').trim();
  let uid = o.user_id || o.userId || null;

  if (!uid) uid = await ensureUser(conn, name, pno, mobile, rank, adminId);

  const [result] = await conn.execute(
    `INSERT INTO ${table} (${fkCol}, user_id, name, pno, mobile, user_rank) VALUES (?,?,?,?,?,?)`,
    [fkVal, uid, name, pno, mobile, rank]
  );
  return result.insertId;
}

async function updateOfficerHelper(conn, oId, table, body, adminId) {
  const name = (body.name || '').trim();
  const pno = (body.pno || '').trim();
  const mobile = (body.mobile || '').trim();
  const rank = (body.user_rank || body.rank || '').trim();
  let uid = body.user_id || body.userId || null;

  if (!uid) uid = await ensureUser(conn, name, pno, mobile, rank, adminId);
  if (uid) {
    await conn.execute(
      `UPDATE users SET name=?, mobile=?, user_rank=? WHERE id=? AND role='staff'`,
      [name, mobile, rank, uid]
    );
  }
  await conn.execute(
    `UPDATE ${table} SET name=?, pno=?, mobile=?, user_rank=?, user_id=? WHERE id=?`,
    [name, pno, mobile, rank, uid, oId]
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  GET /api/admin/hierarchy/full  — Flutter app
// ══════════════════════════════════════════════════════════════════════════════
router.get('/full', adminRequired, async (req, res) => {
  const adminId = req.user?.id || null;
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    const [superZones] = adminId
      ? await conn.execute('SELECT * FROM super_zones ORDER BY id')
      : await conn.execute('SELECT * FROM super_zones ORDER BY id');

    const result = [];
    for (const sz of superZones) {
      const [zones] = await conn.execute('SELECT * FROM zones WHERE super_zone_id=? ORDER BY id', [sz.id]);
      const zoneList = [];
      for (const z of zones) {
        const [sectors] = await conn.execute('SELECT * FROM sectors WHERE zone_id=? ORDER BY id', [z.id]);
        const sectorList = [];
        for (const s of sectors) {
          const [gps] = await conn.execute('SELECT * FROM gram_panchayats WHERE sector_id=? ORDER BY id', [s.id]);
          const gpList = [];
          for (const gp of gps) {
            const [sthals] = await conn.execute('SELECT * FROM matdan_sthal WHERE gram_panchayat_id=? ORDER BY id', [gp.id]);
            const centerList = [];
            for (const ms of sthals) {
              const [kendras, dutyOfficers] = await Promise.all([
                fetchKendras(conn, ms.id),
                fetchDutyOfficers(conn, ms.id),
              ]);
              centerList.push({
                id: ms.id, name: ms.name || '', address: ms.address || '', thana: ms.thana || '',
                center_type: ms.center_type || 'C', bus_no: ms.bus_no || '',
                latitude: ms.latitude != null ? parseFloat(ms.latitude) : null,
                longitude: ms.longitude != null ? parseFloat(ms.longitude) : null,
                kendras, duty_officers: dutyOfficers,
              });
            }
            const gpThana = centerList.find(c => c.thana)?.thana || '';
            gpList.push({ id: gp.id, name: gp.name || '', address: gp.address || '', thana: gpThana, centers: centerList });
          }
          sectorList.push({
            id: s.id, name: s.name || '',
            officers: await fetchOfficers(conn, 'sector_officers', 'sector_id', s.id),
            panchayats: gpList,
          });
        }
        zoneList.push({
          id: z.id, name: z.name || '', hq_address: z.hq_address || '',
          officers: await fetchOfficers(conn, 'zonal_officers', 'zone_id', z.id),
          sectors: sectorList,
        });
      }
      result.push({
        id: sz.id, name: sz.name || '', district: sz.district || '', block: sz.block || '',
        officers: await fetchOfficers(conn, 'kshetra_officers', 'super_zone_id', sz.id),
        zones: zoneList,
      });
    }
    return res.json(result);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  } finally {
    conn.release();
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  GET /api/admin/hierarchy/full/h  — Web frontend (no auth required)
// ══════════════════════════════════════════════════════════════════════════════
router.get('/full/h', async (req, res) => {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    const [superZones] = await conn.execute('SELECT * FROM super_zones');
    for (const sz of superZones) {
      const [officers] = await conn.execute('SELECT * FROM kshetra_officers WHERE super_zone_id=?', [sz.id]);
      sz.officers = officers;
      const [zones] = await conn.execute('SELECT * FROM zones WHERE super_zone_id=?', [sz.id]);
      for (const z of zones) {
        const [zo] = await conn.execute('SELECT * FROM zonal_officers WHERE zone_id=?', [z.id]);
        z.officers = zo;
        const [sectors] = await conn.execute('SELECT * FROM sectors WHERE zone_id=?', [z.id]);
        for (const s of sectors) {
          const [so] = await conn.execute('SELECT * FROM sector_officers WHERE sector_id=?', [s.id]);
          s.officers = so;
          const [gps] = await conn.execute('SELECT * FROM gram_panchayats WHERE sector_id=?', [s.id]);
          for (const gp of gps) {
            const [centers] = await conn.execute('SELECT * FROM matdan_sthal WHERE gram_panchayat_id=?', [gp.id]);
            for (const c of centers) {
              const [kendras] = await conn.execute('SELECT * FROM matdan_kendra WHERE matdan_sthal_id=?', [c.id]);
              c.kendras = kendras;
              const [duty] = await conn.execute(`
                SELECT u.name, u.mobile, u.user_rank, u.pno, d.bus_no
                FROM duty_assignments d JOIN users u ON d.staff_id=u.id WHERE d.sthal_id=?
              `, [c.id]);
              c.duty_officers = duty;
            }
            gp.centers = centers;
          }
          s.panchayats = gps;
        }
        z.sectors = sectors;
      }
      sz.zones = zones;
    }
    return res.json(superZones);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  } finally {
    conn.release();
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  PATCH /api/admin/hierarchy/update  — Web frontend generic update
// ══════════════════════════════════════════════════════════════════════════════
const ALLOWED_FIELDS = {
  super_zones: ['name', 'block', 'district'],
  zones: ['name', 'hq_address'],
  sectors: ['name'],
  gram_panchayats: ['name', 'address', 'thana'],
  matdan_sthal: ['name', 'address', 'thana', 'center_type', 'bus_no'],
};

router.patch('/update', async (req, res) => {
  const { table, id, ...data } = req.body || {};
  if (!table || !id) return res.status(400).json({ error: 'Missing table or id' });
  const allowed = ALLOWED_FIELDS[table];
  if (!allowed) return res.status(400).json({ error: 'Unknown table' });
  const fields = Object.entries(data).filter(([k]) => allowed.includes(k));
  if (!fields.length) return res.status(400).json({ error: 'No valid fields' });
  const setClause = fields.map(([k]) => `${k}=?`).join(', ');
  const values = fields.map(([, v]) => v);
  const pool = await getPool();
  try {
    await pool.execute(`UPDATE \`${table}\` SET ${setClause} WHERE id=?`, [...values, id]);
    return res.json({ message: 'updated' });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  Individual shim routes (Flutter → /admin/hierarchy/…)
// ══════════════════════════════════════════════════════════════════════════════

async function dbDelete(table, id) {
  const pool = await getPool();
  await pool.execute(`DELETE FROM \`${table}\` WHERE id=?`, [id]);
}

async function dbUpdate(table, id, fields) {
  const pool = await getPool();
  const set = Object.keys(fields).map(k => `${k}=?`).join(', ');
  await pool.execute(`UPDATE \`${table}\` SET ${set} WHERE id=?`, [...Object.values(fields), id]);
}

router.delete('/super-zone/:id', adminRequired, async (req, res) => {
  try { await dbDelete('super_zones', req.params.id); return res.json({ status: 'ok', message: 'Super Zone deleted' }); }
  catch (e) { return res.status(500).json({ error: e.message }); }
});

router.put('/super-zone/:id', adminRequired, async (req, res) => {
  try {
    const { name = '', district = '', block = '' } = req.body || {};
    await dbUpdate('super_zones', req.params.id, { name, district, block });
    return res.json({ status: 'ok', message: 'Super Zone updated' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
});

router.delete('/sector/:id', adminRequired, async (req, res) => {
  try { await dbDelete('sectors', req.params.id); return res.json({ status: 'ok', message: 'Sector deleted' }); }
  catch (e) { return res.status(500).json({ error: e.message }); }
});

router.put('/sector/:id', adminRequired, async (req, res) => {
  try {
    await dbUpdate('sectors', req.params.id, { name: req.body?.name || '' });
    return res.json({ status: 'ok', message: 'Sector updated' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
});

router.delete('/sthal/:id', adminRequired, async (req, res) => {
  try { await dbDelete('matdan_sthal', req.params.id); return res.json({ status: 'ok', message: 'Sthal deleted' }); }
  catch (e) { return res.status(500).json({ error: e.message }); }
});

router.put('/sthal/:id', adminRequired, async (req, res) => {
  try {
    let center_type = ((req.body?.centerType || req.body?.center_type) || 'C').trim().toUpperCase();
    if (!['A++', 'A', 'B', 'C'].includes(center_type)) center_type = 'C';
    await dbUpdate('matdan_sthal', req.params.id, {
      name: (req.body?.name || '').trim(),
      address: (req.body?.address || '').trim(),
      thana: (req.body?.thana || '').trim(),
      center_type,
      bus_no: (req.body?.busNo || req.body?.bus_no || '').trim(),
    });
    return res.json({ status: 'ok', data: { center_type }, message: 'Sthal updated' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  KSHETRA OFFICERS  (super zone level)
//  GET  /hierarchy/super-zones/:szId/officers
//  POST /hierarchy/super-zones/:szId/officers
//  PUT  /hierarchy/kshetra-officers/:oId
//  DEL  /hierarchy/kshetra-officers/:oId
// ══════════════════════════════════════════════════════════════════════════════

router.get('/super-zones/:szId/officers', adminRequired, async (req, res) => {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    const officers = await fetchOfficers(conn, 'kshetra_officers', 'super_zone_id', req.params.szId);
    return res.json({ status: 'ok', data: { officers } });
  } catch (e) { return res.status(500).json({ error: e.message }); }
  finally { conn.release(); }
});

router.post('/super-zones/:szId/officers', adminRequired, async (req, res) => {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    const newId = await insertOfficer(conn, 'kshetra_officers', 'super_zone_id', req.params.szId, req.body || {}, req.user.id);
    await conn.commit?.();
    return res.status(201).json({ status: 'ok', data: { id: newId }, message: 'Officer added' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
  finally { conn.release(); }
});

router.put('/kshetra-officers/:oId', adminRequired, async (req, res) => {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    await updateOfficerHelper(conn, req.params.oId, 'kshetra_officers', req.body || {}, req.user.id);
    await conn.commit?.();
    return res.json({ status: 'ok', message: 'Updated' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
  finally { conn.release(); }
});

router.delete('/kshetra-officers/:oId', adminRequired, async (req, res) => {
  try { await dbDelete('kshetra_officers', req.params.oId); return res.json({ status: 'ok', message: 'Deleted' }); }
  catch (e) { return res.status(500).json({ error: e.message }); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ZONAL OFFICERS  (zone level)
//  GET  /hierarchy/zones/:zId/officers
//  POST /hierarchy/zones/:zId/officers
//  PUT  /hierarchy/zonal-officers/:oId
//  DEL  /hierarchy/zonal-officers/:oId
// ══════════════════════════════════════════════════════════════════════════════

router.get('/zones/:zId/officers', adminRequired, async (req, res) => {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    const officers = await fetchOfficers(conn, 'zonal_officers', 'zone_id', req.params.zId);
    return res.json({ status: 'ok', data: { officers } });
  } catch (e) { return res.status(500).json({ error: e.message }); }
  finally { conn.release(); }
});

router.post('/zones/:zId/officers', adminRequired, async (req, res) => {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    const newId = await insertOfficer(conn, 'zonal_officers', 'zone_id', req.params.zId, req.body || {}, req.user.id);
    await conn.commit?.();
    return res.status(201).json({ status: 'ok', data: { id: newId }, message: 'Officer added' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
  finally { conn.release(); }
});

router.put('/zonal-officers/:oId', adminRequired, async (req, res) => {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    await updateOfficerHelper(conn, req.params.oId, 'zonal_officers', req.body || {}, req.user.id);
    await conn.commit?.();
    return res.json({ status: 'ok', message: 'Updated' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
  finally { conn.release(); }
});

router.delete('/zonal-officers/:oId', adminRequired, async (req, res) => {
  try { await dbDelete('zonal_officers', req.params.oId); return res.json({ status: 'ok', message: 'Deleted' }); }
  catch (e) { return res.status(500).json({ error: e.message }); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  SECTOR OFFICERS  (sector level)
//  GET  /hierarchy/sectors/:sId/officers
//  POST /hierarchy/sectors/:sId/officers
//  PUT  /hierarchy/sector-officers/:oId
//  DEL  /hierarchy/sector-officers/:oId
// ══════════════════════════════════════════════════════════════════════════════

router.get('/sectors/:sId/officers', adminRequired, async (req, res) => {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    const officers = await fetchOfficers(conn, 'sector_officers', 'sector_id', req.params.sId);
    return res.json({ status: 'ok', data: { officers } });
  } catch (e) { return res.status(500).json({ error: e.message }); }
  finally { conn.release(); }
});

router.post('/sectors/:sId/officers', adminRequired, async (req, res) => {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    const newId = await insertOfficer(conn, 'sector_officers', 'sector_id', req.params.sId, req.body || {}, req.user.id);
    await conn.commit?.();
    return res.status(201).json({ status: 'ok', data: { id: newId }, message: 'Officer added' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
  finally { conn.release(); }
});

router.put('/sector-officers/:oId', adminRequired, async (req, res) => {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    await updateOfficerHelper(conn, req.params.oId, 'sector_officers', req.body || {}, req.user.id);
    await conn.commit?.();
    return res.json({ status: 'ok', message: 'Updated' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
  finally { conn.release(); }
});

router.delete('/sector-officers/:oId', adminRequired, async (req, res) => {
  try { await dbDelete('sector_officers', req.params.oId); return res.json({ status: 'ok', message: 'Deleted' }); }
  catch (e) { return res.status(500).json({ error: e.message }); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  REPLACE ALL OFFICERS for a node (bulk replace in one transaction)
//  POST /hierarchy/super-zones/:szId/officers/replace
//  POST /hierarchy/zones/:zId/officers/replace
//  POST /hierarchy/sectors/:sId/officers/replace
//  Body: { "officers": [ {name, pno, mobile, user_rank}, ... ] }
// ══════════════════════════════════════════════════════════════════════════════

async function replaceOfficers(table, fkCol, fkVal, officers, adminId) {
  const pool = await getPool();
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.execute(`DELETE FROM ${table} WHERE ${fkCol}=?`, [fkVal]);
    for (const o of officers) {
      if ((o.name || '').trim()) {
        await insertOfficer(conn, table, fkCol, fkVal, o, adminId);
      }
    }
    await conn.commit();
  } catch (e) {
    await conn.rollback();
    throw e;
  } finally {
    conn.release();
  }
}

router.post('/super-zones/:szId/officers/replace', adminRequired, async (req, res) => {
  try {
    await replaceOfficers('kshetra_officers', 'super_zone_id', req.params.szId, (req.body || {}).officers || [], req.user.id);
    return res.json({ status: 'ok', message: 'Officers replaced' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
});

router.post('/zones/:zId/officers/replace', adminRequired, async (req, res) => {
  try {
    await replaceOfficers('zonal_officers', 'zone_id', req.params.zId, (req.body || {}).officers || [], req.user.id);
    return res.json({ status: 'ok', message: 'Officers replaced' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
});

router.post('/sectors/:sId/officers/replace', adminRequired, async (req, res) => {
  try {
    await replaceOfficers('sector_officers', 'sector_id', req.params.sId, (req.body || {}).officers || [], req.user.id);
    return res.json({ status: 'ok', message: 'Officers replaced' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY ASSIGNMENTS
//  POST   /hierarchy/duties          — assign staff to a sthal
//  DELETE /hierarchy/duties/:dutyId  — remove a duty assignment
// ══════════════════════════════════════════════════════════════════════════════

router.post('/duties', adminRequired, async (req, res) => {
  const { staffId, centerId, busNo = '' } = req.body || {};
  if (!staffId || !centerId) return res.status(400).json({ error: 'staffId and centerId required' });
  const pool = await getPool();
  try {
    const [result] = await pool.execute(`
      INSERT INTO duty_assignments (staff_id, sthal_id, bus_no, assigned_by)
      VALUES (?,?,?,?)
      ON DUPLICATE KEY UPDATE
        sthal_id    = VALUES(sthal_id),
        bus_no      = VALUES(bus_no),
        assigned_by = VALUES(assigned_by)
    `, [staffId, centerId, busNo, req.user.id]);
    return res.status(201).json({ status: 'ok', data: { id: result.insertId }, message: 'Duty assigned' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
});

router.delete('/duties/:dutyId', adminRequired, async (req, res) => {
  try { await dbDelete('duty_assignments', req.params.dutyId); return res.json({ status: 'ok', message: 'Duty removed' }); }
  catch (e) { return res.status(500).json({ error: e.message }); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  AVAILABLE STAFF  (unassigned, paginated + searchable)
//  GET /hierarchy/staff/available?page=1&limit=30&q=search_term
// ══════════════════════════════════════════════════════════════════════════════

router.get('/staff/available', adminRequired, async (req, res) => {
  const q = (req.query.q || '').trim();
  const page = Math.max(1, parseInt(req.query.page || '1', 10));
  const limit = Math.min(200, Math.max(1, parseInt(req.query.limit || '30', 10)));
  const offset = (page - 1) * limit;
  const district = req.user?.district || '';

  const NOT_ASSIGNED = `
    NOT (
        EXISTS (SELECT 1 FROM duty_assignments  da WHERE da.staff_id  = u.id)
     OR EXISTS (SELECT 1 FROM kshetra_officers  ko WHERE ko.user_id   = u.id)
     OR EXISTS (SELECT 1 FROM zonal_officers    zo WHERE zo.user_id   = u.id)
     OR EXISTS (SELECT 1 FROM sector_officers   so WHERE so.user_id   = u.id)
    )
  `;

  const pool = await getPool();
  try {
    let searchClause = '';
    const baseParams = [district];
    if (q) {
      searchClause = 'AND (u.name LIKE ? OR u.pno LIKE ? OR u.thana LIKE ?)';
      const like = `%${q}%`;
      baseParams.push(like, like, like);
    }

    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(*) AS cnt FROM users u
       WHERE u.role='staff' AND u.is_active=1
         AND TRIM(LOWER(u.district)) = TRIM(LOWER(?))
         AND ${NOT_ASSIGNED} ${searchClause}`,
      baseParams
    );

    const [rows] = await pool.execute(
      `SELECT u.id, u.name, u.pno, u.mobile, u.thana, u.user_rank
       FROM users u
       WHERE u.role='staff' AND u.is_active=1
         AND TRIM(LOWER(u.district)) = TRIM(LOWER(?))
         AND ${NOT_ASSIGNED} ${searchClause}
       ORDER BY u.name
       LIMIT ? OFFSET ?`,
      [...baseParams, limit, offset]
    );

    return res.json({
      status: 'ok',
      data: {
        data: rows.map(r => ({ id: r.id, name: r.name || '', pno: r.pno || '', mobile: r.mobile || '', thana: r.thana || '', user_rank: r.user_rank || '' })),
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (e) { return res.status(500).json({ error: e.message }); }
});

module.exports = router;