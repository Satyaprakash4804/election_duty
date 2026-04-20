'use strict';

const express = require('express');
const router  = express.Router();
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
    SELECT u.id, u.name, u.pno, u.mobile, u.user_rank, u.thana, da.bus_no
    FROM duty_assignments da JOIN users u ON u.id=da.staff_id
    WHERE da.sthal_id=? ORDER BY u.name
  `, [sthalId]);
  return rows.map(r => ({ id: r.id, name: r.name||'', pno: r.pno||'', mobile: r.mobile||'', user_rank: r.user_rank||'', thana: r.thana||'', bus_no: r.bus_no||'' }));
}

async function fetchKendras(conn, sthalId) {
  const [rows] = await conn.execute('SELECT id, room_number FROM matdan_kendra WHERE matdan_sthal_id=? ORDER BY id', [sthalId]);
  return rows.map(r => ({ id: r.id, room_number: r.room_number || '' }));
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
                id: ms.id, name: ms.name||'', address: ms.address||'', thana: ms.thana||'',
                center_type: ms.center_type||'C', bus_no: ms.bus_no||'',
                latitude:  ms.latitude  != null ? parseFloat(ms.latitude)  : null,
                longitude: ms.longitude != null ? parseFloat(ms.longitude) : null,
                kendras, duty_officers: dutyOfficers,
              });
            }
            const gpThana = centerList.find(c => c.thana)?.thana || '';
            gpList.push({ id: gp.id, name: gp.name||'', address: gp.address||'', thana: gpThana, centers: centerList });
          }
          sectorList.push({
            id: s.id, name: s.name||'',
            officers: await fetchOfficers(conn, 'sector_officers', 'sector_id', s.id),
            panchayats: gpList,
          });
        }
        zoneList.push({
          id: z.id, name: z.name||'', hq_address: z.hq_address||'',
          officers: await fetchOfficers(conn, 'zonal_officers', 'zone_id', z.id),
          sectors: sectorList,
        });
      }
      result.push({
        id: sz.id, name: sz.name||'', district: sz.district||'', block: sz.block||'',
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
  super_zones:      ['name', 'block', 'district'],
  zones:            ['name', 'hq_address'],
  sectors:          ['name'],
  gram_panchayats:  ['name', 'address', 'thana'],
  matdan_sthal:     ['name', 'address', 'thana', 'center_type', 'bus_no'],
};

router.patch('/update', async (req, res) => {
  const { table, id, ...data } = req.body || {};
  if (!table || !id) return res.status(400).json({ error: 'Missing table or id' });
  const allowed = ALLOWED_FIELDS[table];
  if (!allowed) return res.status(400).json({ error: 'Unknown table' });
  const fields = Object.entries(data).filter(([k]) => allowed.includes(k));
  if (!fields.length) return res.status(400).json({ error: 'No valid fields' });
  const setClause = fields.map(([k]) => `${k}=?`).join(', ');
  const values    = fields.map(([, v]) => v);
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
    const { name='', address='', thana='', center_type='C', bus_no='' } = req.body || {};
    await dbUpdate('matdan_sthal', req.params.id, { name, address, thana, center_type, bus_no });
    return res.json({ status: 'ok', message: 'Sthal updated' });
  } catch (e) { return res.status(500).json({ error: e.message }); }
});

module.exports = router;
