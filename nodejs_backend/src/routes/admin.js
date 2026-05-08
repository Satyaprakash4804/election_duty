'use strict';

const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const multer = require('multer');
const { parse: csvParse } = require('csv-parse/sync');
const { query, withTransaction, writeLog } = require('../config/db');
const { ok, err, adminRequired, loginRequired } = require('../middleware/auth');
const { pageParams, paginated } = require('../utils/pagination');
const config = require('../config');

// ── Constants ─────────────────────────────────────────────────────────────────
const SALT = config.passwordSalt;
const MAX_BATCH_ROWS = 10_000;
const INSERT_CHUNK_SIZE = 200;
const HASH_WORKERS = 8;
const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 200;

const RANK_HIERARCHY = ['SP', 'ASP', 'DSP', 'Inspector', 'SI', 'ASI', 'Head Constable', 'Constable'];

const VALID_SENS = ['A++', 'A', 'B', 'C'];

// ── Default district duty types (14 fixed) ────────────────────────────────────
const DEFAULT_DISTRICT_DUTIES = [
  ['cluster_mobile', 'क्लस्टर मोबाईल', 10],
  ['thana_mobile', 'थाना मोबाईल', 20],
  ['thana_reserve', 'थाना रिजर्व', 30],
  ['thana_extra_mobile', 'थाना अतिरिक्त मोबाईल', 40],
  ['sector_pol_mag_mobile', 'सैक्टर पुलिस / मजिस्ट्रेट मोबाईल', 50],
  ['zonal_pol_mag_mobile', 'जोनल पुलिस / मजिस्ट्रेट मोबाईल', 60],
  ['sdm_co_mobile', 'एसडीएम / सीओ मोबाईल', 70],
  ['chowki_mobile', 'चौकी मोबाईल', 80],
  ['barrier_picket', 'बैरियर / पिकैट', 90],
  ['evm_security', 'ईवीएम सुरक्षा', 100],
  ['adm_sp_mobile', 'एडीएम / एसपी मोबाईल', 110],
  ['dm_sp_mobile', 'डीएम / एसपी मोबाईल', 120],
  ['observer_security', 'पर्यवेक्षक सुरक्षा', 130],
  ['hq_reserve', 'मुख्यालय रिजर्व', 140],
];

const DEFAULT_DUTY_KEYS = new Set(DEFAULT_DISTRICT_DUTIES.map(([dt]) => dt));

// ── Rank assign order (matches Flask RANK_ASSIGN_ORDER) ───────────────────────
const RANK_ASSIGN_ORDER = [
  ['SI', 1, 'si_armed_count'],
  ['SI', 0, 'si_unarmed_count'],
  ['Head Constable', 1, 'hc_armed_count'],
  ['Head Constable', 0, 'hc_unarmed_count'],
  ['Constable', 1, 'const_armed_count'],
  ['Constable', 0, 'const_unarmed_count'],
  ['Constable', 1, 'aux_armed_count'],
  ['Constable', 0, 'aux_unarmed_count'],
];

// ── Utility helpers ───────────────────────────────────────────────────────────
function fastHash(pno) {
  return crypto.createHash('sha256').update(pno + SALT).digest('hex');
}

function getLowerRank(rank) {
  const idx = RANK_HIERARCHY.indexOf(rank);
  return (idx >= 0 && idx < RANK_HIERARCHY.length - 1) ? RANK_HIERARCHY[idx + 1] : null;
}

function formatOfficer(r) {
  return {
    id: r.id,
    userId: r.user_id,
    name: r.name || '',
    pno: r.pno || '',
    mobile: r.mobile || '',
    rank: r.user_rank || '',
  };
}

function getAdminId(req) { return req.user.id; }

function normalizeRule(r) {
  return {
    booth_count: r.boothCount,
    si_armed_count: r.siArmedCount || 0,
    si_unarmed_count: r.siUnarmedCount || 0,
    hc_armed_count: r.hcArmedCount || 0,
    hc_unarmed_count: r.hcUnarmedCount || 0,
    const_armed_count: r.constArmedCount || 0,
    const_unarmed_count: r.constUnarmedCount || 0,
    aux_armed_count: r.auxArmedCount || 0,
    aux_unarmed_count: r.auxUnarmedCount || 0,
    pac_count: r.pacCount || 0,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT SHARING — core helpers (matches Flask exactly)
// ══════════════════════════════════════════════════════════════════════════════

async function getDistrictAdminIds(req) {
  const district = (req.user.district || '').trim();
  const adminId = getAdminId(req);
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

function districtPH(ids) {
  return { ph: ids.map(() => '?').join(','), params: ids };
}

// ── Pick random staff for auto-assign (matches Flask _pick_random_staff) ──────
async function pickRandomStaff(pool, rank, isArmed, count, excludeIds) {
  if (count <= 0) return [];
  if (excludeIds.size > 0) {
    const exArr = [...excludeIds];
    const exPh = exArr.map(() => '?').join(',');
    const [rows] = await pool.execute(
      `SELECT id FROM users WHERE role='staff' AND user_rank=? AND is_armed=? AND is_active=1
       AND id NOT IN (${exPh}) ORDER BY RAND() LIMIT ${count}`,
      [rank, isArmed, ...exArr]
    );
    return rows.map(r => r.id);
  } else {
    const [rows] = await pool.execute(
      `SELECT id FROM users WHERE role='staff' AND user_rank=? AND is_armed=? AND is_active=1
       ORDER BY RAND() LIMIT ${count}`,
      [rank, isArmed]
    );
    return rows.map(r => r.id);
  }
}

// ── Staff list helper ─────────────────────────────────────────────────────────
async function getStaffList(conn, district) {
  let rows;
  if (district) {
    [rows] = await conn.execute(
      "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users WHERE role='staff' AND district=? AND is_active=1 ORDER BY name",
      [district]
    );
  } else {
    [rows] = await conn.execute(
      "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users WHERE role='staff' AND is_active=1 ORDER BY name"
    );
  }
  return rows.map(r => ({
    id: r.id, name: r.name || '', pno: r.pno || '',
    mobile: r.mobile || '', rank: r.user_rank || '', isArmed: !!r.is_armed,
  }));
}

// ── Insert officer helper ─────────────────────────────────────────────────────
async function insertOfficer(conn, table, fkCol, fkVal, o, createdBy) {
  let uid = o.userId || o.user_id || null;
  let name = (o.name || '').trim();
  let pno = (o.pno || '').trim();
  let mobile = (o.mobile || '').trim();
  let rank = (o.rank || '').trim();

  if (uid) {
    const [users] = await conn.execute(
      'SELECT name, pno, mobile, user_rank, is_armed FROM users WHERE id=?', [uid]
    );
    if (users.length) {
      const u = users[0];
      if (!name) name = u.name || '';
      if (!pno) pno = u.pno || '';
      if (!mobile) mobile = u.mobile || '';
      if (!rank) rank = u.user_rank || '';
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
  let uid = body.userId || (existing.length ? existing[0].user_id : null);
  const name = body.name || '';
  const pno = body.pno || '';
  const mobile = body.mobile || '';
  const rank = body.rank || '';

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

// ── Serialize helpers ─────────────────────────────────────────────────────────
function serializeBoothRule(r) {
  return {
    boothCount: r.booth_count,
    siArmedCount: r.si_armed_count,
    siUnarmedCount: r.si_unarmed_count,
    hcArmedCount: r.hc_armed_count,
    hcUnarmedCount: r.hc_unarmed_count,
    constArmedCount: r.const_armed_count,
    constUnarmedCount: r.const_unarmed_count,
    auxArmedCount: r.aux_armed_count,
    auxUnarmedCount: r.aux_unarmed_count,
    pacCount: parseFloat(r.pac_count || 0),
  };
}

function serializeDistrictRule(r) {
  return {
    dutyType: r.duty_type,
    dutyLabelHi: r.duty_label_hi || '',
    sankhya: r.sankhya,
    siArmedCount: r.si_armed_count,
    siUnarmedCount: r.si_unarmed_count,
    hcArmedCount: r.hc_armed_count,
    hcUnarmedCount: r.hc_unarmed_count,
    constArmedCount: r.const_armed_count,
    constUnarmedCount: r.const_unarmed_count,
    auxArmedCount: r.aux_armed_count,
    auxUnarmedCount: r.aux_unarmed_count,
    pacCount: parseFloat(r.pac_count || 0),
    sortOrder: r.sort_order,
    isDefault: DEFAULT_DUTY_KEYS.has(r.duty_type),
  };
}

// ── Job progress helper ───────────────────────────────────────────────────────
async function updateJobProgress(pool, jobId, doneTypes, assigned, skipped) {
  try {
    await pool.execute(
      'UPDATE district_duty_jobs SET done_types=?, assigned=?, skipped=?, updated_at=NOW() WHERE id=?',
      [doneTypes, assigned, skipped, jobId]
    );
  } catch (e) { /* silent */ }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BACKGROUND JOBS
// ══════════════════════════════════════════════════════════════════════════════

async function autoAssignInternal(superZoneId, adminId) {
  const pool = await require('../config/db').getPool();
  const conn = await pool.getConnection();
  try {
    await conn.execute(`
      DELETE da FROM duty_assignments da
      JOIN matdan_sthal ms ON ms.id = da.sthal_id
      JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
      JOIN sectors s ON s.id = gp.sector_id
      JOIN zones z ON z.id = s.zone_id
      WHERE z.super_zone_id=?
    `, [superZoneId]);

    const [centers] = await conn.execute(`
      SELECT ms.id, ms.center_type, ms.booth_count
      FROM matdan_sthal ms
      JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
      JOIN sectors s ON s.id = gp.sector_id
      JOIN zones z ON z.id = s.zone_id
      WHERE z.super_zone_id=?
    `, [superZoneId]);

    for (const c of centers) {
      const boothCount = Math.min(c.booth_count, 15);
      const [ruleRows] = await conn.execute(`
        SELECT * FROM booth_rules WHERE admin_id=? AND sensitivity=? AND booth_count=?
      `, [adminId, c.center_type, boothCount]);
      const rule = ruleRows[0];
      if (!rule) continue;

      const assign = async (rank, armed, count) => {
        if (count <= 0) return;
        const [staff] = await conn.execute(`
          SELECT id FROM users WHERE role='staff' AND user_rank=? AND is_armed=? AND is_active=1
          AND id NOT IN (SELECT staff_id FROM duty_assignments)
          LIMIT ${count}
        `, [rank, armed]);
        for (const s of staff) {
          await conn.execute(
            'INSERT INTO duty_assignments (staff_id, sthal_id, assigned_by) VALUES (?,?,?)',
            [s.id, c.id, adminId]
          );
        }
      };

      await assign('SI', 1, rule.si_armed_count);
      await assign('SI', 0, rule.si_unarmed_count);
      await assign('Head Constable', 1, rule.hc_armed_count);
      await assign('Head Constable', 0, rule.hc_unarmed_count);
      await assign('Constable', 1, rule.const_armed_count);
      await assign('Constable', 0, rule.const_unarmed_count);
      await assign('Constable', 1, rule.aux_armed_count);
      await assign('Constable', 0, rule.aux_unarmed_count);
    }

    await conn.commit();
  } finally {
    conn.release();
  }
}

async function runAutoAssignJob(jobId, superZoneId, adminId) {
  const pool = await require('../config/db').getPool();
  console.log(`🚀 AUTO ASSIGN STARTED superZoneId=${superZoneId}`);
  try {
    await pool.execute("UPDATE sz_assign_jobs SET status='running' WHERE id=?", [jobId]);
    console.log('👉 Calling autoAssignInternal');
    await autoAssignInternal(superZoneId, adminId);
    console.log('✅ Auto assign completed');
    await pool.execute("UPDATE sz_assign_jobs SET status='done' WHERE id=?", [jobId]);
  } catch (e) {
    console.error('❌ AUTO ASSIGN ERROR:', e);
    await pool.execute(
      "UPDATE sz_assign_jobs SET status='error', error_msg=? WHERE id=?",
      [String(e.message), jobId]
    );
  }
}

// ── District auto-assign — matches Flask _run_auto_assign exactly ─────────────
async function runAutoAssignDistrict(jobId, adminId, onlyDutyType) {
  const pool = await require('../config/db').getPool();
  console.log(`🚀 DISTRICT AUTO ASSIGN STARTED — job=${jobId} admin=${adminId}${onlyDutyType ? ' duty=' + onlyDutyType : ''}`);

  const usedStaffIds = new Set();
  const shortageReport = {};

  try {
    await pool.execute(
      "UPDATE district_duty_jobs SET status='running', updated_at=NOW() WHERE id=?",
      [jobId]
    );

    // Resolve district
    const [[userRow]] = await pool.execute('SELECT district FROM users WHERE id=?', [adminId]);
    const district = (userRow?.district || '').trim();

    let dIds = [adminId];
    if (district) {
      const [rows] = await pool.execute(
        "SELECT id FROM users WHERE role IN ('admin','super_admin') AND district=?",
        [district]
      );
      dIds = rows.map(r => r.id);
      if (!dIds.includes(adminId)) dIds.push(adminId);
    }
    const dPh = dIds.map(() => '?').join(',');

    // Pre-load already-assigned staff district-wide
    const [alreadyRows] = await pool.execute(
      `SELECT DISTINCT staff_id FROM district_duty_assignments WHERE admin_id IN (${dPh})`,
      dIds
    );
    alreadyRows.forEach(r => usedStaffIds.add(r.staff_id));

    // Load rules
    let rules;
    if (onlyDutyType) {
      [rules] = await pool.execute(
        `SELECT * FROM district_rules WHERE admin_id IN (${dPh}) AND duty_type=?`,
        [...dIds, onlyDutyType]
      );
    } else {
      [rules] = await pool.execute(
        `SELECT * FROM district_rules WHERE admin_id IN (${dPh}) ORDER BY sort_order, duty_type`,
        dIds
      );
    }

    await pool.execute(
      'UPDATE district_duty_jobs SET total_types=? WHERE id=?',
      [rules.length, jobId]
    );

    let totalAssigned = 0, totalSkipped = 0, doneTypes = 0;

    for (const rule of rules) {
      const dutyType = rule.duty_type;
      const dutyLabel = rule.duty_label_hi || dutyType;
      const sankhya = parseInt(rule.sankhya || 0);

      shortageReport[dutyType] = {
        label: dutyLabel,
        shortages: [],
        batches_made: 0,
        batches_target: sankhya,
      };

      if (sankhya <= 0) {
        doneTypes++;
        await updateJobProgress(pool, jobId, doneTypes, totalAssigned, totalSkipped);
        continue;
      }

      // Next batch number
      const [[{ mx }]] = await pool.execute(
        `SELECT COALESCE(MAX(batch_no), 0) AS mx FROM district_duty_assignments WHERE admin_id IN (${dPh}) AND duty_type=?`,
        [...dIds, dutyType]
      );
      let nextBatchNo = (mx || 0) + 1;
      const existingBatches = nextBatchNo - 1;
      const batchesToMake = sankhya - existingBatches;

      shortageReport[dutyType].batches_made = existingBatches;

      if (batchesToMake <= 0) {
        doneTypes++;
        await updateJobProgress(pool, jobId, doneTypes, totalAssigned, totalSkipped);
        continue;
      }

      for (let b = 0; b < batchesToMake; b++) {
        const batchStaff = [];
        const batchShort = [];
        const batchUsedLocal = new Set();

        for (const [rank, isArmed, col] of RANK_ASSIGN_ORDER) {
          const needed = parseInt(rule[col] || 0);
          if (needed <= 0) continue;

          const excludes = new Set([...usedStaffIds, ...batchUsedLocal]);
          const picked = await pickRandomStaff(pool, rank, isArmed, needed, excludes);

          if (picked.length < needed) {
            batchShort.push({
              rank, armed: !!isArmed, missing: needed - picked.length, rankCol: col,
            });
          }

          picked.forEach(sid => { batchStaff.push(sid); batchUsedLocal.add(sid); });
        }

        // STRICT: if any shortage, abandon batch
        if (batchShort.length) {
          for (const sh of batchShort) {
            const key = `${sh.rank}|${sh.armed}`;
            const existing = shortageReport[dutyType].shortages.find(
              x => x.rank === sh.rank && x.armed === sh.armed
            );
            if (existing) {
              existing.missing = Math.max(existing.missing, sh.missing);
            } else {
              shortageReport[dutyType].shortages.push({ rank: sh.rank, armed: sh.armed, missing: sh.missing });
            }
          }
          totalSkipped++;
          break;
        }

        // Insert batch
        try {
          await pool.execute(
            `INSERT INTO district_duty_assignments (admin_id, duty_type, batch_no, staff_id, assigned_by) VALUES ${batchStaff.map(() => '(?,?,?,?,?)').join(',')}`,
            batchStaff.flatMap(sid => [adminId, dutyType, nextBatchNo, sid, adminId])
          );
          batchStaff.forEach(sid => usedStaffIds.add(sid));
          totalAssigned += batchStaff.length;
          nextBatchNo++;
          shortageReport[dutyType].batches_made++;
          await updateJobProgress(pool, jobId, doneTypes, totalAssigned, totalSkipped);
        } catch (e) {
          await writeLog('ERROR', `Batch insert failed for ${dutyType}: ${e.message}`, 'DistrictAutoAssign');
          totalSkipped++;
          break;
        }
      }

      doneTypes++;
      await updateJobProgress(pool, jobId, doneTypes, totalAssigned, totalSkipped);
    }

    const reportJson = JSON.stringify(shortageReport);
    await pool.execute(
      "UPDATE district_duty_jobs SET status='done', done_types=?, assigned=?, skipped=?, error_msg=?, updated_at=NOW() WHERE id=?",
      [doneTypes, totalAssigned, totalSkipped, reportJson, jobId]
    );

    await writeLog('INFO',
      `Auto-assign done: ${totalAssigned} assigned, ${totalSkipped} batches skipped${onlyDutyType ? ' [duty=' + onlyDutyType + ']' : ''} (admin ${adminId})`,
      'DistrictAutoAssign'
    );
    console.log(`✅ DISTRICT AUTO ASSIGN FINISHED — job=${jobId}`);
  } catch (e) {
    await writeLog('ERROR', `Auto-assign error: ${e.message}`, 'DistrictAutoAssign');
    try {
      await pool.execute(
        "UPDATE district_duty_jobs SET status='error', error_msg=?, updated_at=NOW() WHERE id=?",
        [`ERROR: ${e.message}`, jobId]
      );
    } catch (_) { /* silent */ }
  }
}

// ── Serialize job status (shared helper) ──────────────────────────────────────
function serializeJobStatus(job) {
  const total = job.total_types || 0;
  const done = job.done_types || 0;
  let pct = total > 0 ? Math.floor((done / total) * 100) : 0;
  if (job.status === 'done') pct = 100;

  let shortageReport = null;
  let errorMsg = '';
  const raw = job.error_msg || '';
  if (job.status === 'done' && raw && raw.trim().startsWith('{')) {
    try { shortageReport = JSON.parse(raw); } catch (_) { errorMsg = raw; }
  } else {
    errorMsg = raw;
  }

  return {
    jobId: job.id, status: job.status,
    totalTypes: total, doneTypes: done,
    assigned: job.assigned || 0, skipped: job.skipped || 0,
    pct, errorMsg, shortageReport,
    createdAt: String(job.created_at), updatedAt: String(job.updated_at),
  };
}

// ══════════════════════════════════════════════════════════════════════════════
//  ASSIGNMENT JOB ROUTES
// ══════════════════════════════════════════════════════════════════════════════

router.post('/assign/start/:superZoneId', adminRequired, async (req, res) => {
  try {
    const superZoneId = req.params.superZoneId;
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
      'INSERT INTO sz_assign_jobs (super_zone_id, created_by) VALUES (?,?)',
      [superZoneId, req.user.id]
    );
    const jobId = r.insertId;
    setImmediate(() => runAutoAssignJob(jobId, superZoneId, req.user.id));
    return ok(res, { jobId }, 'Assignment started');
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/assign/status/:jobId', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [[job]] = await pool.execute(
      'SELECT * FROM sz_assign_jobs WHERE id=?', [req.params.jobId]
    );
    return ok(res, job || {});
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  LOCK / UNLOCK ROUTES
// ══════════════════════════════════════════════════════════════════════════════

router.post('/lock/:superZoneId', adminRequired, async (req, res) => {
  try {
    const { reason = '' } = req.body || {};
    const pool = await require('../config/db').getPool();
    await pool.execute(`
      INSERT INTO sz_duty_locks (super_zone_id, is_locked, status, unlock_reason)
      VALUES (?,1,'locked',?)
      ON DUPLICATE KEY UPDATE is_locked=1, status='locked', unlock_reason=?
    `, [req.params.superZoneId, reason, reason]);
    return ok(res, null, 'Locked');
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/unlock/request', adminRequired, async (req, res) => {
  try {
    const { superZoneId, reason = '' } = req.body || {};
    const pool = await require('../config/db').getPool();
    await pool.execute(
      'INSERT INTO sz_unlock_requests (super_zone_id, requested_by, reason) VALUES (?,?,?)',
      [superZoneId, req.user.id, reason]
    );
    await pool.execute(
      "UPDATE sz_duty_locks SET status='unlock_requested' WHERE super_zone_id=?",
      [superZoneId]
    );
    return ok(res, null, 'Unlock request sent');
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/unlock/approve/:reqId', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [[unlockReq]] = await pool.execute(
      'SELECT super_zone_id FROM sz_unlock_requests WHERE id=?', [req.params.reqId]
    );
    if (!unlockReq) return err(res, 'Request not found');
    await pool.execute(
      "UPDATE sz_unlock_requests SET status='approved', reviewed_by=? WHERE id=?",
      [req.user.id, req.params.reqId]
    );
    await pool.execute(
      "UPDATE sz_duty_locks SET is_locked=0, status='unlocked' WHERE super_zone_id=?",
      [unlockReq.super_zone_id]
    );
    return ok(res, null, 'Unlocked successfully');
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/unlock/reject/:reqId', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute(
      "UPDATE sz_unlock_requests SET status='rejected', reviewed_by=? WHERE id=?",
      [req.user.id, req.params.reqId]
    );
    return ok(res, null, 'Request rejected');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  SUPER ZONES — now uses district sharing like Flask
// ══════════════════════════════════════════════════════════════════════════════

router.get('/super-zones', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    // Fetch super zones with center count + lock status (matches Flask)
    const [rows] = await pool.execute(`
      SELECT
        sz.id,
        sz.name,
        sz.district,
        sz.block,
        COUNT(DISTINCT ms.id) AS center_count,
        COALESCE(l.is_locked, 0) AS is_locked
      FROM super_zones sz
      LEFT JOIN zones z              ON z.super_zone_id    = sz.id
      LEFT JOIN sectors s            ON s.zone_id          = z.id
      LEFT JOIN gram_panchayats gp   ON gp.sector_id       = s.id
      LEFT JOIN matdan_sthal ms      ON ms.gram_panchayat_id = gp.id
      LEFT JOIN sz_duty_locks l      ON l.super_zone_id    = sz.id
      WHERE sz.admin_id IN (${dPh})
      GROUP BY sz.id
      ORDER BY sz.id
    `, dParams);

    if (!rows.length) return ok(res, []);

    // Fetch officers for these super zones in one query
    const szIds = rows.map(r => r.id);
    const szPh = szIds.map(() => '?').join(',');
    const [officerRows] = await pool.execute(
      `SELECT * FROM kshetra_officers WHERE super_zone_id IN (${szPh}) ORDER BY super_zone_id, id`,
      szIds
    );
    const officersBySz = {};
    officerRows.forEach(o => {
      (officersBySz[o.super_zone_id] = officersBySz[o.super_zone_id] || []).push(formatOfficer(o));
    });

    const result = rows.map(r => ({
      id: r.id,
      name: r.name || '',
      district: r.district || '',
      block: r.block || '',
      center_count: r.center_count || 0,
      is_locked: parseInt(r.is_locked || 0),
      officers: officersBySz[r.id] || [],
    }));

    return ok(res, result);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/super-zones', adminRequired, async (req, res) => {
  try {
    const { name, district, block, officers: offs = [] } = req.body || {};
    if (!name?.trim()) return err(res, 'name required');
    const adminId = getAdminId(req);
    const dist = district || req.user.district || '';
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
    const staff = await getStaffList(pool, req.user.district || null);
    return ok(res, { officers: officers.map(formatOfficer), availableStaff: staff });
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

router.get('/super-zones/:id/job-status', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(
      'SELECT * FROM sz_assign_jobs WHERE super_zone_id=? ORDER BY id DESC LIMIT 1',
      [req.params.id]
    );
    return ok(res, rows[0] || {});
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ZONES
// ══════════════════════════════════════════════════════════════════════════════

router.get('/super-zones/:szId/zones', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search = (req.query.q || '').trim();
    const pool = await require('../config/db').getPool();
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
    const zPh = zIds.map(() => '?').join(',');
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
    const pool = await require('../config/db').getPool();
    const [officers] = await pool.execute(
      'SELECT * FROM zonal_officers WHERE zone_id=? ORDER BY id', [req.params.id]
    );
    const staff = await getStaffList(pool, req.user.district || null);
    return ok(res, { officers: officers.map(formatOfficer), availableStaff: staff });
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
    const pool = await require('../config/db').getPool();
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
    const sPh = sIds.map(() => '?').join(',');
    const [officers] = await pool.execute(
      `SELECT * FROM sector_officers WHERE sector_id IN (${sPh}) ORDER BY sector_id, id`, sIds
    );
    const officersBySector = {};
    officers.forEach(o => { (officersBySector[o.sector_id] = officersBySector[o.sector_id] || []).push(formatOfficer(o)); });

    const result = sectors.map(s => ({
      id: s.id, name: s.name || '', hqAddress: s.hq_address || '',
      gpCount: s.gp_count, officers: officersBySector[s.id] || [],
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
    const name = (req.body?.name || '').trim();
    const hq = (req.body?.hqAddress || '').trim();
    const officers = req.body?.officers || [];
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
    const pool = await require('../config/db').getPool();
    const [officers] = await pool.execute(
      'SELECT * FROM sector_officers WHERE sector_id=? ORDER BY id', [req.params.id]
    );
    const staff = await getStaffList(pool, req.user.district || null);
    return ok(res, { officers: officers.map(formatOfficer), availableStaff: staff });
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
    const pool = await require('../config/db').getPool();
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

router.post('/gram-panchayats/:gpId/centers', adminRequired, async (req, res) => {
  try {
    const { name, address = '', thana = '', busNo = '', centerType, boothCount: rawBc, latitude, longitude } = req.body || {};
    if (!name || !centerType) return err(res, 'name and centerType required');

    let boothCount = parseInt(rawBc || 1);
    if (isNaN(boothCount) || boothCount < 1) boothCount = 1;

    let centerId;
    await withTransaction(async conn => {
      const [r] = await conn.execute(`
        INSERT INTO matdan_sthal
        (gram_panchayat_id, name, address, thana, bus_no, center_type, booth_count, latitude, longitude)
        VALUES (?,?,?,?,?,?,?,?,?)
      `, [req.params.gpId, name, address, thana, busNo, centerType, boothCount, latitude || null, longitude || null]);
      centerId = r.insertId;

      await conn.execute('DELETE FROM matdan_kendra WHERE matdan_sthal_id=?', [centerId]);
      for (let i = 1; i <= boothCount; i++) {
        await conn.execute(
          'INSERT INTO matdan_kendra (matdan_sthal_id, room_number) VALUES (?,?)',
          [centerId, String(i)]
        );
      }
    });

    return ok(res, { centerId, boothCount }, 'Center created with rooms', 201);
  } catch (e) {
    console.error('❌ CREATE CENTER ERROR:', e);
    return err(res, `Create failed: ${e.message}`, 500);
  }
});

router.get('/gram-panchayats/:gpId/centers', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search = (req.query.q || '').trim();
    const pool = await require('../config/db').getPool();
    const params = [req.params.gpId];
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
    const cPh = centerIds.map(() => '?').join(',');
    const [staffRows] = await pool.execute(
      `SELECT da.sthal_id, u.id, u.name, u.pno, u.mobile, u.user_rank
       FROM duty_assignments da JOIN users u ON u.id=da.staff_id
       WHERE da.sthal_id IN (${cPh})`, centerIds
    );
    const staffByCenter = {};
    staffRows.forEach(r => {
      (staffByCenter[r.sthal_id] = staffByCenter[r.sthal_id] || []).push(
        { id: r.id, name: r.name || '', pno: r.pno || '', mobile: r.mobile || '', rank: r.user_rank || '' }
      );
    });

    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    let rules = {};
    try {
      const [rulesRows] = await pool.execute(
        `SELECT sensitivity, user_rank, required_count FROM booth_rules WHERE admin_id IN (${dPh})`,
        dParams
      );
      rulesRows.forEach(r => { (rules[r.sensitivity] = rules[r.sensitivity] || {})[r.user_rank] = r.required_count; });
    } catch (e) {
      console.warn('⚠ RULE FETCH ERROR:', e.message);
    }

    const data = centers.map(c => {
      try {
        const centerType = c.center_type || 'C';
        const assigned = staffByCenter[c.id] || [];
        const rankCount = {};
        assigned.forEach(s => { if (s.rank) rankCount[s.rank] = (rankCount[s.rank] || 0) + 1; });
        const centerRules = rules[centerType] || {};
        const missing = [];
        for (const [rank, required] of Object.entries(centerRules)) {
          const have = rankCount[rank] || 0;
          if (have < required) missing.push({ rank, required, available: have, lowerRankSuggestion: getLowerRank(rank) });
        }
        return {
          id: c.id, name: c.name || '', address: c.address || '', thana: c.thana || '',
          centerType, boothCount: parseInt(c.booth_count || 1), busNo: c.bus_no || '',
          latitude: c.latitude != null ? parseFloat(c.latitude) : null,
          longitude: c.longitude != null ? parseFloat(c.longitude) : null,
          dutyCount: parseInt(c.duty_count || 0), roomCount: parseInt(c.room_count || 0),
          assignedStaff: assigned, missingRanks: missing,
        };
      } catch (e) {
        console.warn('⚠ CENTER FORMAT ERROR:', e.message);
        return null;
      }
    }).filter(Boolean);

    return paginated(res, data, total, page, limit);
  } catch (e) {
    console.error('❌ GET CENTERS ERROR:', e);
    return err(res, `Server error: ${e.message}`, 500);
  }
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
    const [r] = await pool.execute('DELETE FROM duty_assignments WHERE sthal_id=?', [req.params.id]);
    await writeLog('INFO', `Cleared ${r.affectedRows} assignments from center ${req.params.id}`, 'AutoAssign');
    return ok(res, { removed: r.affectedRows }, 'Assignments cleared');
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/center/:id/custom-rule', adminRequired, async (req, res) => {
  try {
    const { ruleId = null } = req.body || {};
    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE matdan_sthal SET custom_rule_id=? WHERE id=?', [ruleId, req.params.id]);
    return ok(res, null, 'Custom rule applied');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ROOMS
// ══════════════════════════════════════════════════════════════════════════════

router.get('/centers/:id/rooms', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(
      'SELECT id, room_number FROM matdan_kendra WHERE matdan_sthal_id=? ORDER BY id', [req.params.id]
    );
    return ok(res, rows.map(r => ({ id: r.id, roomNumber: r.room_number || '' })));
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/centers/:id/rooms', adminRequired, async (req, res) => {
  try {
    const rn = (req.body?.roomNumber || '').trim();
    if (!rn) return err(res, 'roomNumber required');
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
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
//  STAFF
// ══════════════════════════════════════════════════════════════════════════════

router.get('/staff', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search = (req.query.q || '').trim();
    const assigned = (req.query.assigned || '').trim().toLowerCase();
    const rankFilter = (req.query.rank || '').trim();
    const armed = (req.query.armed || '').trim().toLowerCase();
    const pool = await require('../config/db').getPool();

    const params = [];
    const whereParts = ["u.role='staff'"];

    if (search) {
      whereParts.push('(u.name LIKE ? OR u.pno LIKE ? OR u.mobile LIKE ? OR u.thana LIKE ? OR u.district LIKE ?)');
      const like = `%${search}%`;
      params.push(like, like, like, like, like);
    }
    if (rankFilter) { whereParts.push('u.user_rank=?'); params.push(rankFilter); }

    // Matches Flask OFFICER_EXISTS — includes district_duty_assignments
    const OFFICER_EXISTS = `(
      EXISTS (SELECT 1 FROM duty_assignments da WHERE da.staff_id=u.id)
      OR EXISTS (SELECT 1 FROM kshetra_officers ko WHERE ko.user_id=u.id)
      OR EXISTS (SELECT 1 FROM zonal_officers zo WHERE zo.user_id=u.id)
      OR EXISTS (SELECT 1 FROM sector_officers so WHERE so.user_id=u.id)
      OR EXISTS (SELECT 1 FROM district_duty_assignments dda WHERE dda.staff_id=u.id)
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
         (SELECT z.name  FROM zonal_officers zo  JOIN zones z ON z.id=zo.zone_id WHERE zo.user_id=u.id LIMIT 1) AS zone_name,
         (SELECT s.name  FROM sector_officers so JOIN sectors s ON s.id=so.sector_id WHERE so.user_id=u.id LIMIT 1) AS sector_name,
         (SELECT dda.duty_type FROM district_duty_assignments dda WHERE dda.staff_id=u.id LIMIT 1) AS district_duty
       FROM users u WHERE ${whereSQL} ORDER BY u.name LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );

    const data = rows.map(r => {
      let assignType = '', assignLabel = '';
      // District duty has highest priority (matches Flask)
      if (r.district_duty) { assignType = 'district'; assignLabel = r.district_duty; }
      else if (r.center_name) { assignType = 'booth'; assignLabel = r.center_name; }
      else if (r.sz_name) { assignType = 'kshetra'; assignLabel = r.sz_name; }
      else if (r.zone_name) { assignType = 'zone'; assignLabel = r.zone_name; }
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
    const q = (req.query.q || '').trim();
    const armed = (req.query.armed || '').trim().toLowerCase();
    if (!q) return ok(res, []);
    const like = `%${q}%`;
    let armedClause = '';
    if (armed === 'yes') armedClause = ' AND is_armed = 1';
    else if (armed === 'no') armedClause = ' AND is_armed = 0';
    const pool = await require('../config/db').getPool();
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
    const name = (req.body?.name || '').trim();
    const pno = (req.body?.pno || '').trim();
    if (!name || !pno) return err(res, 'name and pno required');

    const isArmed = (
      [true, 1, '1', 'true'].includes(req.body.isArmed) ||
      [true, 1, '1', 'true'].includes(req.body.is_armed) ||
      ['sastra', 'armed', 'yes'].includes(String(req.body.weapon || '').toLowerCase())
    ) ? 1 : 0;

    const adminId = getAdminId(req);
    const pool = await require('../config/db').getPool();
    const [existing] = await pool.execute('SELECT id FROM users WHERE pno=?', [pno]);
    if (existing.length) return err(res, `PNO ${pno} already registered`, 409);

    const [usernameCheck] = await pool.execute('SELECT id FROM users WHERE username=?', [pno]);
    const username = usernameCheck.length ? `${pno}_${adminId}` : pno;
    const district = req.user.district || '';

    const [r] = await pool.execute(
      "INSERT INTO users (name,pno,username,password,mobile,thana,district,user_rank,is_armed,role,is_active,created_by) VALUES (?,?,?,?,?,?,?,?,?,'staff',1,?)",
      [name, pno, username, fastHash(pno),
        (req.body?.mobile || '').trim(), (req.body?.thana || '').trim(),
        district, (req.body?.rank || '').trim(), isArmed, adminId]
    );
    await writeLog('INFO', `Staff '${name}' PNO:${pno} added (is_armed=${isArmed}) by admin ${adminId}`, 'Staff');
    return ok(res, { id: r.insertId, name, pno, isArmed: !!isArmed }, 'Staff added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  BULK UPLOAD — SSE streaming
// ══════════════════════════════════════════════════════════════════════════════

const ARMED_VALS = new Set(['1', 'yes', 'हाँ', 'han', 'sastra', 'सशस्त्र', 'armed', 'true']);

async function runBulkUpload(req, res) {
  const items = (req.body?.staff || []);
  const district = (req.user.district || '').trim();
  const adminId = req.user.id;
  const totalInput = items.length;

  if (!items.length) return err(res, 'staff list empty');
  if (items.length > MAX_BATCH_ROWS) return err(res, `Too many rows. Max ${MAX_BATCH_ROWS} per upload.`);

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache, no-store');
  res.setHeader('X-Accel-Buffering', 'no');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  const sse = data => res.write(`data: ${JSON.stringify(data)}\n\n`);

  try {
    sse({ phase: 'parse', pct: 2, msg: 'Validating rows...' });
    const clean = [], skipped = [];
    const seenPnos = new Set();

    for (let i = 0; i < items.length; i++) {
      const s = items[i];
      const pno = String(s.pno || '').trim();
      const name = String(s.name || '').trim();
      if (!pno || !name) { skipped.push(pno || `row_${i + 1}`); continue; }
      if (seenPnos.has(pno)) { skipped.push(pno); continue; }
      seenPnos.add(pno);
      const armedRaw = String(s.sastra ?? s.armed ?? s.is_armed ?? '').trim().toLowerCase();
      clean.push({
        pno, name,
        rank: String(s.rank || '').trim(),
        mobile: String(s.mobile || '').trim(),
        thana: String(s.thana || '').trim(),
        dist: (String(s.district || '').trim()) || district,
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
    const ph = allPnos.map(() => '?').join(',');
    const pool = await require('../config/db').getPool();
    const [existingPnoRows] = await pool.execute(`SELECT pno FROM users WHERE pno IN (${ph})`, allPnos);
    const [existingUsernameRows] = await pool.execute(`SELECT username FROM users WHERE username IN (${ph})`, allPnos);
    const existingPnos = new Set(existingPnoRows.map(r => r.pno));
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
        const chunk = preInsert.slice(start, start + INSERT_CHUNK_SIZE);
        const chunkHashes = hashed.slice(start, start + INSERT_CHUNK_SIZE);
        const values = chunk.map((r, i) => [
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

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

router.post('/staff/bulk-csv', adminRequired, upload.single('file'), async (req, res) => {
  if (!req.file) return err(res, "CSV file required (field: 'file')");
  let content;
  try { content = req.file.buffer.toString('utf8').replace(/^\uFEFF/, ''); }
  catch (e) { return err(res, `File encoding error: ${e.message}`); }

  let records;
  try { records = csvParse(content, { columns: true, skip_empty_lines: true, trim: true }); }
  catch (e) { return err(res, `CSV parse error: ${e.message}`); }

  const items = [];
  for (const row of records) {
    const norm = {};
    for (const [k, v] of Object.entries(row)) norm[k.trim().toLowerCase()] = v;
    const pno = norm['pno'] || norm['p.no'] || '';
    const name = norm['name'] || norm['नाम'] || '';
    if (!pno && !name) continue;
    const armedRaw = (norm['sastra'] || norm['armed'] || norm['weapon'] || norm['शस्त्र'] || '').trim().toLowerCase();
    items.push({
      pno: pno.trim(), name: name.trim(),
      mobile: (norm['mobile'] || norm['mob'] || norm['phone'] || '').trim(),
      thana: (norm['thana'] || norm['थाना'] || norm['ps'] || '').trim(),
      district: (norm['district'] || norm['dist'] || norm['जिला'] || '').trim(),
      rank: (norm['rank'] || norm['post'] || norm['पद'] || '').trim(),
      is_armed: ARMED_VALS.has(armedRaw) ? 1 : 0,
    });
  }
  if (!items.length) return err(res, 'No valid rows found in CSV');
  req.body = { staff: items };
  return runBulkUpload(req, res);
});

router.put('/staff/:id', adminRequired, async (req, res) => {
  try {
    const { name = '', pno = '', mobile = '', thana = '', rank = '' } = req.body || {};
    const isArmed = req.body?.isArmed ? 1 : 0;
    const pool = await require('../config/db').getPool();
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
    const [[duty]] = await pool.execute(
      'SELECT sthal_id FROM duty_assignments WHERE staff_id=? LIMIT 1', [req.params.id]
    );
    console.log('DUTY FETCH:', duty);
    if (!duty) return err(res, 'No duty assigned');

    const sthalId = duty.sthal_id;
    const [[lock]] = await pool.execute(`
      SELECT z.super_zone_id, IFNULL(l.is_locked, 0) AS is_locked
      FROM matdan_sthal c
      JOIN gram_panchayats gp ON c.gram_panchayat_id = gp.id
      JOIN sectors s ON gp.sector_id = s.id
      JOIN zones z ON s.zone_id = z.id
      LEFT JOIN sz_duty_locks l ON l.super_zone_id = z.super_zone_id
      WHERE c.id=?
    `, [sthalId]);
    console.log('LOCK CHECK RESULT:', lock);

    if (lock && lock.is_locked === 1) return err(res, '❌ Locked Super Zone. Cannot remove duty.');

    await pool.execute('DELETE FROM duty_assignments WHERE staff_id=?', [req.params.id]);
    return ok(res, { message: 'Duty removed' });
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/staff/bulk-delete', adminRequired, async (req, res) => {
  try {
    const ids = req.body?.staffIds;
    if (!Array.isArray(ids) || !ids.length) return err(res, 'staffIds required');
    const ph = ids.map(() => '?').join(',');
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(`DELETE FROM users WHERE id IN (${ph}) AND role='staff'`, ids);
    await writeLog('INFO', `Bulk delete: ${r.affectedRows} staff by admin ${getAdminId(req)}`, 'Staff');
    return ok(res, { deleted: r.affectedRows }, `${r.affectedRows} staff deleted`);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/staff/bulk-assign', adminRequired, async (req, res) => {
  try {
    const { staffIds: ids = [], centerId, busNo = '' } = req.body || {};
    if (!ids.length || !centerId) return err(res, 'staffIds and centerId required');
    const adminId = getAdminId(req);
    const pool = await require('../config/db').getPool();
    let assigned = 0;
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
    const ph = ids.map(() => '?').join(',');
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(`DELETE FROM duty_assignments WHERE staff_id IN (${ph})`, ids);
    return ok(res, { removed: r.affectedRows }, `${r.affectedRows} duties removed`);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY ASSIGNMENTS — now returns electionConfig like Flask
// ══════════════════════════════════════════════════════════════════════════════

router.get('/duties', adminRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const centerIdFilter = req.query.center_id ? parseInt(req.query.center_id, 10) : null;
    const search     = (req.query.q      || '').trim();
    // ── NEW filter params ────────────────────────────────────────────────
    const armedParam = (req.query.armed  || '').trim().toLowerCase(); // 'yes' | 'no' | ''
    const cardParam  = (req.query.card   || '').trim().toLowerCase(); // 'downloaded' | 'pending' | ''
    const rankParam  = (req.query.rank   || '').trim();               // 'SI' | 'Head Constable' | ...
 
    const pool = await require('../config/db').getPool();
 
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const adminDistrict = (req.user.district || '').trim();
 
    // ── 1. Active election config (unchanged) ─────────────────────────────
    let electionCfg = null;
    if (adminDistrict) {
      const [cfgRows] = await pool.execute(`
        SELECT id, district, state, election_type, election_name, phase,
               election_year, election_date, pratah_samay, saya_samay, instructions
        FROM election_configs
        WHERE district=? AND is_active=1 AND is_archived=0
        ORDER BY updated_at DESC, id DESC LIMIT 1
      `, [adminDistrict]);
      if (cfgRows.length) {
        const c = cfgRows[0];
        electionCfg = {
          id:           c.id,
          district:     c.district      || '',
          state:        c.state         || '',
          electionType: c.election_type || '',
          electionName: c.election_name || '',
          phase:        c.phase         || '',
          electionYear: c.election_year || '',
          electionDate: c.election_date ? String(c.election_date) : '',
          pratahSamay:  c.pratah_samay  || '',
          sayaSamay:    c.saya_samay    || '',
          instructions: c.instructions  || '',
        };
      }
    }
 
    // ── 2. Build WHERE ────────────────────────────────────────────────────
    const whereParts = [`sz.admin_id IN (${dPh})`];
    const params     = [...dParams];
 
    if (centerIdFilter) {
      whereParts.push('ms.id=?');
      params.push(centerIdFilter);
    }
 
    if (search) {
      whereParts.push('(u.name LIKE ? OR u.pno LIKE ? OR ms.name LIKE ?)');
      const like = `%${search}%`;
      params.push(like, like, like);
    }
 
    // ── NEW: armed filter ─────────────────────────────────────────────────
    if (armedParam === 'yes') {
      whereParts.push('u.is_armed = 1');
    } else if (armedParam === 'no') {
      whereParts.push('u.is_armed = 0');
    }
 
    // ── NEW: card downloaded filter ───────────────────────────────────────
    if (cardParam === 'downloaded') {
      whereParts.push('da.card_downloaded = 1');
    } else if (cardParam === 'pending') {
      whereParts.push('(da.card_downloaded = 0 OR da.card_downloaded IS NULL)');
    }
 
    // ── NEW: rank filter ──────────────────────────────────────────────────
    if (rankParam) {
      whereParts.push('u.user_rank = ?');
      params.push(rankParam);
    }
 
    const whereSQL = whereParts.join(' AND ');
 
    // ── 3. Count ──────────────────────────────────────────────────────────
    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(*) AS cnt
       FROM duty_assignments da
       JOIN users u        ON u.id  = da.staff_id
       JOIN matdan_sthal ms ON ms.id = da.sthal_id
       JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
       JOIN sectors s  ON s.id  = gp.sector_id
       JOIN zones   z  ON z.id  = s.zone_id
       JOIN super_zones sz ON sz.id = z.super_zone_id
       WHERE ${whereSQL}`,
      params
    );
 
    // ── 4. Page rows ──────────────────────────────────────────────────────
    const [rows] = await pool.execute(
      `SELECT da.id, da.bus_no, da.card_downloaded,
              u.id AS staff_id, u.name, u.pno, u.mobile,
              u.thana, u.user_rank, u.district, u.is_armed,
              ms.id AS center_id, ms.name AS center_name,
              ms.center_type, ms.booth_count,
              gp.name AS gp_name,
              s.id  AS sector_id,     s.name  AS sector_name,
              z.id  AS zone_id,       z.name  AS zone_name,
              sz.id AS super_zone_id, sz.name AS super_zone_name,
              sz.block AS block_name
       FROM duty_assignments da
       JOIN users u         ON u.id  = da.staff_id
       JOIN matdan_sthal ms  ON ms.id = da.sthal_id
       JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
       JOIN sectors s  ON s.id  = gp.sector_id
       JOIN zones   z  ON z.id  = s.zone_id
       JOIN super_zones sz ON sz.id = z.super_zone_id
       WHERE ${whereSQL}
       ORDER BY ms.name, u.name
       LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );
 
    if (!rows.length) {
      return res.json({
        success: true,
        data: {
          data: [], total, page, limit,
          totalPages: limit > 0 ? Math.ceil(total / limit) : 0,
          electionConfig: electionCfg,
        },
      });
    }
 
    // ── 5. Bulk fetch officers / sahyogi (unchanged) ──────────────────────
    const szIds = [...new Set(rows.map(r => r.super_zone_id))];
    const zIds  = [...new Set(rows.map(r => r.zone_id))];
    const sIds  = [...new Set(rows.map(r => r.sector_id))];
    const cIds  = [...new Set(rows.map(r => r.center_id))];
 
    async function fetchMap(sql, ids) {
      if (!ids.length) return {};
      const ph = ids.map(() => '?').join(',');
      const [arr] = await pool.execute(sql.replace('{ph}', ph), ids);
      const map = {};
      arr.forEach(row => {
        const key = Object.values(row)[0];
        (map[key] = map[key] || []).push(row);
      });
      return map;
    }
 
    const [superOffMap, zonalOffMap, sectorOffMap, sahyogiMap] = await Promise.all([
      fetchMap(
        'SELECT super_zone_id AS _fk, name, pno, mobile, user_rank FROM kshetra_officers WHERE super_zone_id IN ({ph})',
        szIds
      ),
      fetchMap(
        'SELECT zone_id AS _fk, name, pno, mobile, user_rank FROM zonal_officers WHERE zone_id IN ({ph})',
        zIds
      ),
      fetchMap(
        'SELECT sector_id AS _fk, name, pno, mobile, user_rank FROM sector_officers WHERE sector_id IN ({ph})',
        sIds
      ),
      fetchMap(
        `SELECT da2.sthal_id AS _fk,
                u2.name, u2.pno, u2.mobile, u2.thana,
                u2.user_rank, u2.district, u2.is_armed
         FROM duty_assignments da2
         JOIN users u2 ON u2.id = da2.staff_id
         WHERE da2.sthal_id IN ({ph})`,
        cIds
      ),
    ]);
 
    const strip = list => (list || []).map(({ _fk, ...rest }) => rest);
 
    const result = rows.map(r => ({
      id:             r.id,
      centerId:       r.center_id,
      name:           r.name           || '',
      pno:            r.pno            || '',
      mobile:         r.mobile         || '',
      staffThana:     r.thana          || '',
      rank:           r.user_rank      || '',
      district:       r.district       || '',
      isArmed:        !!r.is_armed,
      centerName:     r.center_name    || '',
      gpName:         r.gp_name        || '',
      sectorName:     r.sector_name    || '',
      zoneName:       r.zone_name      || '',
      superZoneName:  r.super_zone_name || '',
      blockName:      r.block_name     || '',
      busNo:          r.bus_no         || '',
      cardDownloaded: !!(r.card_downloaded),
      superOfficers:  strip(superOffMap[r.super_zone_id]),
      zonalOfficers:  strip(zonalOffMap[r.zone_id]),
      sectorOfficers: strip(sectorOffMap[r.sector_id]),
      sahyogi:        strip(sahyogiMap[r.center_id]),
    }));
 
    // ── 6. Return with electionConfig (unchanged) ─────────────────────────
    return res.json({
      success: true,
      data: {
        data: result,
        total, page, limit,
        totalPages: limit > 0 ? Math.ceil(total / limit) : 0,
        electionConfig: electionCfg,
      },
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

router.post('/duties', adminRequired, async (req, res) => {
  try {
    console.log('REQUEST BODY:', req.body);
    const staffId = req.body?.staffId || req.body?.staff_id;
    const sthalId = req.body?.centerId || req.body?.center_id || req.body?.sthal_id;
    const mode = req.body?.mode;

    if (!staffId || !sthalId) return err(res, `Missing data: staffId=${staffId}, centerId=${sthalId}`);

    const pool = await require('../config/db').getPool();
    const conn = await pool.getConnection();
    try {
      const [[center]] = await conn.execute('SELECT id FROM matdan_sthal WHERE id=?', [sthalId]);
      if (!center) { conn.release(); return err(res, `Invalid centerId: ${sthalId}`); }

      const [[lockRow]] = await conn.execute(`
        SELECT c.id AS center, IFNULL(l.is_locked, 0) AS is_locked
        FROM matdan_sthal c
        LEFT JOIN gram_panchayats gp ON c.gram_panchayat_id = gp.id
        LEFT JOIN sectors s ON gp.sector_id = s.id
        LEFT JOIN zones z ON s.zone_id = z.id
        LEFT JOIN sz_duty_locks l ON l.super_zone_id = z.super_zone_id
        WHERE c.id=?
      `, [sthalId]);
      console.log('DEBUG CENTER:', lockRow);
      if (lockRow && lockRow.is_locked === 1) {
        conn.release();
        return err(res, '❌ This Super Zone is LOCKED. Cannot assign duty.');
      }

      const [[staff]] = await conn.execute('SELECT id FROM users WHERE id=?', [staffId]);
      if (!staff) { conn.release(); return err(res, `Invalid staffId: ${staffId}`); }

      const [[dupCheck]] = await conn.execute(
        'SELECT id FROM duty_assignments WHERE staff_id=? AND sthal_id=?', [staffId, sthalId]
      );
      if (dupCheck) { conn.release(); return err(res, '⚠️ Staff already assigned to this center'); }

      await conn.execute(
        'INSERT INTO duty_assignments (staff_id, sthal_id, mode, assigned_by) VALUES (?,?,?,?)',
        [staffId, sthalId, mode || null, req.user.id]
      );
      conn.release();
      return ok(res, { message: '✅ Duty assigned successfully' });
    } catch (e) {
      conn.release();
      console.error('ERROR:', e.message);
      return err(res, `Server error: ${e.message}`, 500);
    }
  } catch (e) {
    console.log(`error ${e}`);
    return err(res, e.message, 500);
  }
});

router.delete('/duties/:id', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [[duty]] = await pool.execute(
      'SELECT sthal_id FROM duty_assignments WHERE id=?', [req.params.id]
    );
    if (!duty) return err(res, 'Duty not found');

    const [[lock]] = await pool.execute(`
      SELECT IFNULL(l.is_locked, 0) AS is_locked
      FROM matdan_sthal c
      JOIN gram_panchayats gp ON c.gram_panchayat_id = gp.id
      JOIN sectors s ON gp.sector_id = s.id
      JOIN zones z ON s.zone_id = z.id
      LEFT JOIN sz_duty_locks l ON l.super_zone_id = z.super_zone_id
      WHERE c.id=?
    `, [duty.sthal_id]);

    if (lock && lock.is_locked === 1) return err(res, 'Locked — cannot remove');

    await pool.execute('DELETE FROM duty_assignments WHERE id=?', [req.params.id]);
    return ok(res, null, 'Deleted successfully');
  } catch (e) { return err(res, e.message, 500); }
});

router.patch('/duties/:id/attended', adminRequired, async (req, res) => {
  try {
    const attended = req.body?.attended ? 1 : 0;
    const pool = await require('../config/db').getPool();
    await pool.execute('UPDATE duty_assignments SET attended=? WHERE id=?', [attended, req.params.id]);
    return ok(res, null, 'Attendance updated');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  MANUAL ASSIGN / SWAP / RESERVE / CENTER STAFF
// ══════════════════════════════════════════════════════════════════════════════

router.post('/assign', adminRequired, async (req, res) => {
  try {
    const staffId = req.body?.staffId;
    const sthalId = req.body?.centerId;
    if (!staffId || !sthalId) return err(res, 'staffId and centerId required');

    const pool = await require('../config/db').getPool();
    const [[existing]] = await pool.execute(
      'SELECT id FROM duty_assignments WHERE staff_id=?', [staffId]
    );
    if (existing) return err(res, 'Staff already assigned');

    await pool.execute(
      'INSERT INTO duty_assignments (staff_id, sthal_id, assigned_by) VALUES (?,?,?)',
      [staffId, sthalId, req.user.id]
    );
    return ok(res, null, 'Staff assigned');
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/swap', adminRequired, async (req, res) => {
  try {
    const { removeStaffId, addStaffId, centerId: sthalId } = req.body || {};
    const pool = await require('../config/db').getPool();

    const [[szRow]] = await pool.execute(`
      SELECT z.super_zone_id FROM matdan_sthal ms
      JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
      JOIN sectors s ON s.id = gp.sector_id
      JOIN zones z ON z.id = s.zone_id
      WHERE ms.id=?
    `, [sthalId]);

    if (szRow) {
      const [[lockRow]] = await pool.execute(
        'SELECT is_locked FROM sz_duty_locks WHERE super_zone_id=?', [szRow.super_zone_id]
      );
      if (lockRow && lockRow.is_locked) return err(res, 'Zone is locked');
    }

    await pool.execute(
      'DELETE FROM duty_assignments WHERE staff_id=? AND sthal_id=?', [removeStaffId, sthalId]
    );

    const [[alreadyAssigned]] = await pool.execute(
      'SELECT id FROM duty_assignments WHERE staff_id=?', [addStaffId]
    );
    if (alreadyAssigned) return err(res, 'New staff already assigned');

    await pool.execute(
      'INSERT INTO duty_assignments (staff_id, sthal_id, assigned_by) VALUES (?,?,?)',
      [addStaffId, sthalId, req.user.id]
    );
    return ok(res, null, 'Swapped successfully');
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/reserve-staff', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(`
      SELECT id, name, user_rank, mobile FROM users
      WHERE role='staff' AND is_active=1
      AND id NOT IN (SELECT staff_id FROM duty_assignments)
      ORDER BY name ASC
    `);
    return ok(res, rows);
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/center/:sthalId/staff', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(`
      SELECT u.id, u.name, u.user_rank, u.mobile
      FROM duty_assignments da JOIN users u ON u.id=da.staff_id
      WHERE da.sthal_id=?
    `, [req.params.sthalId]);
    return ok(res, rows);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  AUTO ASSIGN (super zone level) + REFRESH
// ══════════════════════════════════════════════════════════════════════════════

router.post('/auto-assign/:superZoneId', adminRequired, async (req, res) => {
  try {
    const superZoneId = req.params.superZoneId;
    const pool = await require('../config/db').getPool();

    const [[lock]] = await pool.execute(
      'SELECT is_locked FROM sz_duty_locks WHERE super_zone_id=?', [superZoneId]
    );
    if (lock && lock.is_locked) return err(res, 'Duties are locked for this Super Zone');

    await pool.execute(`
      DELETE da FROM duty_assignments da
      JOIN matdan_sthal ms ON ms.id = da.sthal_id
      JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
      JOIN sectors s ON s.id = gp.sector_id
      JOIN zones z ON s.zone_id = z.id
      WHERE z.super_zone_id=?
    `, [superZoneId]);

    const [centers] = await pool.execute(`
      SELECT ms.id, ms.center_type, ms.booth_count
      FROM matdan_sthal ms
      JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
      JOIN sectors s ON s.id = gp.sector_id
      JOIN zones z ON s.zone_id = z.id
      WHERE z.super_zone_id=?
    `, [superZoneId]);

    for (const c of centers) {
      const boothCount = Math.min(c.booth_count, 15);
      const [[rule]] = await pool.execute(`
        SELECT * FROM booth_rules WHERE admin_id=? AND sensitivity=? AND booth_count=?
      `, [req.user.id, c.center_type, boothCount]);

      if (!rule) {
        await writeLog('WARNING', `No rule for ${c.center_type} booth ${boothCount}`, 'AutoAssign');
        continue;
      }

      const assign = async (rank, armed, count) => {
        if (count <= 0) return;
        const [staff] = await pool.execute(`
          SELECT id FROM users WHERE role='staff' AND user_rank=? AND is_armed=? AND is_active=1
          AND id NOT IN (SELECT staff_id FROM duty_assignments)
          LIMIT ${count}
        `, [rank, armed]);
        for (const s of staff) {
          await pool.execute(
            'INSERT INTO duty_assignments (staff_id, sthal_id, assigned_by) VALUES (?,?,?)',
            [s.id, c.id, req.user.id]
          );
        }
      };

      await assign('SI', 1, rule.si_armed_count);
      await assign('SI', 0, rule.si_unarmed_count);
      await assign('Head Constable', 1, rule.hc_armed_count);
      await assign('Head Constable', 0, rule.hc_unarmed_count);
      await assign('Constable', 1, rule.const_armed_count);
      await assign('Constable', 0, rule.const_unarmed_count);
      await assign('Constable', 1, rule.aux_armed_count);
      await assign('Constable', 0, rule.aux_unarmed_count);
    }

    return ok(res, null, 'Auto assignment completed');
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/refresh/:superZoneId', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [[lock]] = await pool.execute(
      'SELECT is_locked FROM sz_duty_locks WHERE super_zone_id=?', [req.params.superZoneId]
    );
    if (lock && lock.is_locked) return err(res, 'Duties are locked');

    await pool.execute(`
      DELETE da FROM duty_assignments da
      JOIN matdan_sthal ms ON ms.id = da.sthal_id
      JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
      JOIN sectors s ON s.id = gp.sector_id
      JOIN zones z ON s.zone_id = z.id
      WHERE z.super_zone_id=?
    `, [req.params.superZoneId]);

    return ok(res, null, 'All staff moved to reserve');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ALL CENTERS (map view)
// ══════════════════════════════════════════════════════════════════════════════

router.get('/centers/all', loginRequired, async (req, res) => {
  try {
    const { page, limit, offset } = pageParams(req.query);
    const search = (req.query.q || '').trim();
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const countParams = [...dParams];
    let whereExtra = '';
    if (search) {
      whereExtra = 'AND (ms.name LIKE ? OR ms.thana LIKE ? OR gp.name LIKE ?)';
      const like = `%${search}%`;
      countParams.push(like, like, like);
    }

    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(DISTINCT ms.id) AS cnt
       FROM matdan_sthal ms
       JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
       JOIN sectors s          ON s.id  = gp.sector_id
       JOIN zones z            ON z.id  = s.zone_id
       JOIN super_zones sz     ON sz.id = z.super_zone_id
       WHERE sz.admin_id IN (${dPh}) ${whereExtra}`,
      countParams
    );

    const dataParams = [...dParams];
    if (search) {
      const like = `%${search}%`;
      dataParams.push(like, like, like);
    }

    const [rows] = await pool.execute(
      `SELECT
         ms.id, ms.name, ms.address, ms.thana, ms.center_type, ms.booth_count,
         ms.bus_no, ms.latitude, ms.longitude,
         gp.name   AS gp_name,
         s.name    AS sector_name,
         z.name    AS zone_name,
         sz.name   AS super_zone_name,
         sz.block  AS block_name,
         COALESCE(l.is_locked, 0) AS is_locked,
         COUNT(da.id) AS duty_count
       FROM matdan_sthal ms
       JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
       JOIN sectors s          ON s.id  = gp.sector_id
       JOIN zones z            ON z.id  = s.zone_id
       JOIN super_zones sz     ON sz.id = z.super_zone_id
       LEFT JOIN sz_duty_locks l    ON l.super_zone_id = z.super_zone_id
       LEFT JOIN duty_assignments da ON da.sthal_id    = ms.id
       WHERE sz.admin_id IN (${dPh}) ${whereExtra}
       GROUP BY ms.id
       ORDER BY ms.name
       LIMIT ${limit} OFFSET ${offset}`,
      dataParams
    );

    if (!rows.length) return paginated(res, [], total, page, limit);

    // Batch-fetch booth rules
    const pairSet = new Map();
    for (const r of rows) {
      const bc = Math.min(parseInt(r.booth_count || 1), 15);
      const key = `${r.center_type || 'C'}__${bc}`;
      if (!pairSet.has(key)) pairSet.set(key, { sensitivity: r.center_type || 'C', boothCount: bc });
    }
    const pairs = [...pairSet.values()];
    const ruleMap = new Map();
    if (pairs.length) {
      const pairConditions = pairs.map(() => '(br.sensitivity = ? AND br.booth_count = ?)').join(' OR ');
      const pairParams = [];
      for (const { sensitivity, boothCount } of pairs) pairParams.push(sensitivity, boothCount);
      const [ruleRows] = await pool.execute(
        `SELECT br.sensitivity, br.booth_count,
                br.si_armed_count, br.si_unarmed_count,
                br.hc_armed_count, br.hc_unarmed_count,
                br.const_armed_count, br.const_unarmed_count,
                br.aux_armed_count, br.aux_unarmed_count, br.pac_count
         FROM booth_rules br
         WHERE br.admin_id IN (${dPh}) AND (${pairConditions})
         ORDER BY br.booth_count`,
        [...dParams, ...pairParams]
      );
      for (const br of ruleRows) {
        const key = `${br.sensitivity}__${br.booth_count}`;
        ruleMap.set(key, {
          siArmedCount: br.si_armed_count, siUnarmedCount: br.si_unarmed_count,
          hcArmedCount: br.hc_armed_count, hcUnarmedCount: br.hc_unarmed_count,
          constArmedCount: br.const_armed_count, constUnarmedCount: br.const_unarmed_count,
          auxArmedCount: br.aux_armed_count, auxUnarmedCount: br.aux_unarmed_count,
          pacCount: parseFloat(br.pac_count || 0),
        });
      }
    }

    const data = rows.map(r => {
      const bc = Math.min(parseInt(r.booth_count || 1), 15);
      const ctype = r.center_type || 'C';
      return {
        id: r.id, name: r.name || '', address: r.address || '', thana: r.thana || '',
        centerType: ctype, boothCount: parseInt(r.booth_count || 1), busNo: r.bus_no || '',
        latitude: r.latitude != null ? parseFloat(r.latitude) : null,
        longitude: r.longitude != null ? parseFloat(r.longitude) : null,
        gpName: r.gp_name || '', sectorName: r.sector_name || '',
        zoneName: r.zone_name || '', superZoneName: r.super_zone_name || '',
        blockName: r.block_name || '',
        dutyCount: parseInt(r.duty_count || 0), isLocked: Boolean(r.is_locked),
        boothRule: ruleMap.get(`${ctype}__${bc}`) || null,
      };
    });

    return paginated(res, data, total, page, limit);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  OVERVIEW
// ══════════════════════════════════════════════════════════════════════════════

router.get('/overview', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
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
      pool.execute("SELECT COUNT(*) AS cnt FROM users WHERE role='staff' AND is_active=1"),
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
        superZones: parseInt(sz.cnt || 0),
        totalBooths: parseInt(booths.cnt || 0),
        totalStaff: parseInt(staff.cnt || 0),
        assignedDuties: parseInt(assigned.cnt || 0),
      },
    });
  } catch (e) {
    await writeLog('ERROR', `overview error: ${e.message}`, 'Overview');
    return res.json({ success: true, data: { superZones: 0, totalBooths: 0, totalStaff: 0, assignedDuties: 0 } });
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  OFFICERS SAVE TO USERS
// ══════════════════════════════════════════════════════════════════════════════

router.post('/officers/save-to-users', adminRequired, async (req, res) => {
  try {
    const name = (req.body?.name || '').trim();
    const pno = (req.body?.pno || '').trim();
    const mobile = (req.body?.mobile || '').trim();
    const rank = (req.body?.rank || '').trim();
    if (!name || !pno) return err(res, 'name and pno required');

    const pool = await require('../config/db').getPool();
    const [[existing]] = await pool.execute('SELECT id FROM users WHERE pno=?', [pno]);
    if (existing) return ok(res, { id: existing.id, existed: true }, 'Already in users');

    const [[usernameCheck]] = await pool.execute('SELECT id FROM users WHERE username=?', [pno]);
    const username = usernameCheck ? `${pno}_${req.user.id}` : pno;
    const district = req.user.district || '';
    const [r] = await pool.execute(
      "INSERT INTO users (name,pno,username,password,mobile,district,user_rank,is_armed,role,is_active,created_by) VALUES (?,?,?,?,?,?,?,?,'staff',1,?)",
      [name, pno, username, fastHash(pno), mobile, district, rank, 0, req.user.id]
    );
    await writeLog('INFO', `Officer '${name}' PNO:${pno} saved to users by admin ${req.user.id}`, 'Officer');
    return ok(res, { id: r.insertId, existed: false }, 'Officer saved to users', 201);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  SUPER ADMIN ROUTES
// ══════════════════════════════════════════════════════════════════════════════

router.get('/super/admins', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(`
      SELECT
        u.id, u.name, u.username, u.district, u.is_active, u.created_at,
        (SELECT COUNT(*) FROM matdan_sthal ms
         WHERE ms.gram_panchayat_id IN (
           SELECT gp.id FROM gram_panchayats gp
           JOIN sectors s ON s.id=gp.sector_id
           JOIN zones z ON z.id=s.zone_id
           JOIN super_zones sz ON sz.id=z.super_zone_id
           WHERE sz.admin_id=u.id
         )
        ) AS totalBooths,
        (SELECT COUNT(*) FROM duty_assignments da
         JOIN users us ON us.id=da.staff_id WHERE us.created_by=u.id
        ) AS assignedStaff
      FROM users u WHERE u.role='admin' ORDER BY u.id DESC
    `);
    return ok(res, rows.map(r => ({
      id: r.id, name: r.name, username: r.username, district: r.district,
      isActive: !!r.is_active, totalBooths: r.totalBooths || 0,
      assignedStaff: r.assignedStaff || 0, createdAt: r.created_at,
    })));
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/super/form-data', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(`
      SELECT u.id AS adminId, u.name AS adminName, u.district,
             COUNT(DISTINCT sz.id) AS superZones, COUNT(DISTINCT z.id) AS zones,
             COUNT(DISTINCT s.id) AS sectors,     COUNT(DISTINCT gp.id) AS gramPanchayats,
             COUNT(DISTINCT ms.id) AS centers,    MAX(ms.created_at) AS lastUpdated
      FROM users u
      LEFT JOIN super_zones     sz ON sz.admin_id          = u.id
      LEFT JOIN zones            z ON z.super_zone_id      = sz.id
      LEFT JOIN sectors          s ON s.zone_id            = z.id
      LEFT JOIN gram_panchayats gp ON gp.sector_id         = s.id
      LEFT JOIN matdan_sthal    ms ON ms.gram_panchayat_id = gp.id
      WHERE u.role='admin' GROUP BY u.id ORDER BY u.id DESC
    `);
    return ok(res, rows);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  CONFIG
// ══════════════════════════════════════════════════════════════════════════════

router.get('/config', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute('SELECT `key`, value FROM app_config');
    const result = {};
    rows.forEach(r => { result[r.key] = r.value; });
    return ok(res, result);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH RULES (मानक v2)
// ══════════════════════════════════════════════════════════════════════════════

router.get('/booth-rules', loginRequired, async (req, res) => {
  try {
    const sens = (req.query.sensitivity || '').trim();
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    let rows;
    if (sens) {
      if (!VALID_SENS.includes(sens)) return err(res, 'invalid sensitivity');
      [rows] = await pool.execute(
        `SELECT * FROM booth_rules WHERE admin_id IN (${dPh}) AND sensitivity=? ORDER BY booth_count`,
        [...dParams, sens]
      );
    } else {
      [rows] = await pool.execute(
        `SELECT * FROM booth_rules WHERE admin_id IN (${dPh}) ORDER BY FIELD(sensitivity,'A++','A','B','C'), booth_count`,
        dParams
      );
    }

    const grouped = { 'A++': [], 'A': [], 'B': [], 'C': [] };
    rows.forEach(r => { (grouped[r.sensitivity] = grouped[r.sensitivity] || []).push(serializeBoothRule(r)); });
    return ok(res, grouped);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/booth-rules', adminRequired, async (req, res) => {
  try {
    const { sensitivity, rules = [] } = req.body || {};
    const sens = (sensitivity || '').trim();
    if (!VALID_SENS.includes(sens)) return err(res, 'sensitivity must be A++, A, B, or C');
    if (!Array.isArray(rules)) return err(res, 'rules must be a list');

    const adminId = getAdminId(req);
    const pool = await require('../config/db').getPool();

    const [lockRows] = await pool.execute(`
      SELECT is_locked FROM sz_duty_locks
      WHERE super_zone_id IN (SELECT id FROM super_zones WHERE admin_id=?)
      LIMIT 1
    `, [adminId]);
    if (lockRows.length && lockRows[0].is_locked) return err(res, 'Rules locked. Cannot modify.');

    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    await withTransaction(async conn => {
      await conn.execute(
        `DELETE FROM booth_rules WHERE admin_id IN (${dPh}) AND sensitivity=?`,
        [...dParams, sens]
      );
      for (const raw of rules) {
        const r = normalizeRule(raw);
        const bc = parseInt(r.booth_count || 0);
        if (bc < 1 || bc > 15) continue;

        const total = r.si_armed_count + r.si_unarmed_count +
          r.hc_armed_count + r.hc_unarmed_count +
          r.const_armed_count + r.const_unarmed_count +
          r.aux_armed_count + r.aux_unarmed_count;
        if (total === 0) continue;
        if (total > 50) continue;

        await conn.execute(`
          INSERT INTO booth_rules
            (admin_id, sensitivity, booth_count,
             si_armed_count, si_unarmed_count,
             hc_armed_count, hc_unarmed_count,
             const_armed_count, const_unarmed_count,
             aux_armed_count, aux_unarmed_count,
             pac_count)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
        `, [
          adminId, sens, bc,
          r.si_armed_count, r.si_unarmed_count,
          r.hc_armed_count, r.hc_unarmed_count,
          r.const_armed_count, r.const_unarmed_count,
          r.aux_armed_count, r.aux_unarmed_count,
          parseFloat(r.pac_count || 0),
        ]);
      }
    });

    await writeLog('INFO', `Booth rules saved: ${sens}, ${rules.length} rows by admin ${adminId}`, 'Rules');
    return ok(res, null, `${sens} मानक saved`);
  } catch (e) {
    await writeLog('ERROR', `save_booth_rules: ${e.message}`, 'Rules');
    return err(res, `Save failed: ${e.message}`, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH RULE CENTER COUNTS
// ══════════════════════════════════════════════════════════════════════════════

router.get('/booth-rules/center-counts', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(`
      SELECT
        ms.id AS center_id, ms.name AS center_name,
        COUNT(DISTINCT mk.id)      AS room_count,
        COUNT(DISTINCT da.staff_id) AS staff_count
      FROM matdan_sthal ms
      LEFT JOIN matdan_kendra mk ON mk.matdan_sthal_id = ms.id
      LEFT JOIN duty_assignments da ON da.sthal_id = ms.id
      GROUP BY ms.id, ms.name ORDER BY ms.name
    `);
    return ok(res, rows.map(r => ({
      centerId: r.center_id, centerName: r.center_name || '',
      roomCount: r.room_count || 0, staffCount: r.staff_count || 0,
    })));
  } catch (e) {
    console.error('❌ CENTER COUNT ERROR:', e);
    return err(res, e.message, 500);
  }
});

// NEW: matches Flask /booth-rules/center-counts-by-type
router.get('/booth-rules/center-counts-by-type', loginRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const [rows] = await pool.execute(`
      SELECT
        ms.center_type,
        LEAST(ms.booth_count, 15) AS booth_bucket,
        COUNT(ms.id)              AS center_count
      FROM matdan_sthal ms
      JOIN gram_panchayats gp ON gp.id  = ms.gram_panchayat_id
      JOIN sectors          s  ON s.id   = gp.sector_id
      JOIN zones            z  ON z.id   = s.zone_id
      JOIN super_zones      sz ON sz.id  = z.super_zone_id
      WHERE sz.admin_id IN (${dPh})
        AND ms.center_type IN ('A++', 'A', 'B', 'C')
        AND ms.booth_count >= 1
      GROUP BY ms.center_type, booth_bucket
      ORDER BY ms.center_type, booth_bucket
    `, dParams);

    const result = { 'A++': {}, 'A': {}, 'B': {}, 'C': {} };
    for (const sens of ['A++', 'A', 'B', 'C']) {
      for (let bc = 1; bc <= 15; bc++) result[sens][String(bc)] = 0;
    }
    for (const row of rows) {
      const ct = row.center_type;
      const bucket = parseInt(row.booth_bucket || 1);
      const count = parseInt(row.center_count || 0);
      if (result[ct] && bucket >= 1 && bucket <= 15) {
        result[ct][String(bucket)] += count;
      }
    }

    return ok(res, result);
  } catch (e) { return err(res, e.message, 500); }
});

// NEW: matches Flask /booth-rules/center-counts-summary
router.get('/booth-rules/center-counts-summary', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(`
      SELECT
        ms.id           AS center_id,
        ms.name         AS center_name,
        ms.center_type,
        ms.booth_count,
        COUNT(DISTINCT mk.id)       AS room_count,
        COUNT(DISTINCT da.staff_id) AS staff_count
      FROM matdan_sthal ms
      LEFT JOIN matdan_kendra mk    ON mk.matdan_sthal_id = ms.id
      LEFT JOIN duty_assignments da ON da.sthal_id        = ms.id
      GROUP BY ms.id, ms.name, ms.center_type, ms.booth_count
      ORDER BY ms.name
    `);
    return ok(res, rows.map(r => ({
      centerId: r.center_id, centerName: r.center_name || '',
      centerType: r.center_type, boothCount: parseInt(r.booth_count || 1),
      roomCount: parseInt(r.room_count || 0), staffCount: parseInt(r.staff_count || 0),
    })));
  } catch (e) {
    console.error('❌ CENTER COUNT SUMMARY ERROR:', e);
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT RULES (जनपदीय मानक)
// ══════════════════════════════════════════════════════════════════════════════

router.get('/district-rules', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const [rows] = await pool.execute(
      `SELECT * FROM district_rules WHERE admin_id IN (${dPh}) ORDER BY sort_order, id`,
      dParams
    );

    const savedMap = {};
    rows.forEach(r => { savedMap[r.duty_type] = r; });

    const result = [];
    for (const [dt, label, order] of DEFAULT_DISTRICT_DUTIES) {
      if (savedMap[dt]) {
        result.push(serializeDistrictRule(savedMap[dt]));
      } else {
        result.push({
          dutyType: dt, dutyLabelHi: label, sankhya: 0,
          siArmedCount: 0, siUnarmedCount: 0,
          hcArmedCount: 0, hcUnarmedCount: 0,
          constArmedCount: 0, constUnarmedCount: 0,
          auxArmedCount: 0, auxUnarmedCount: 0,
          pacCount: 0.0, sortOrder: order, isDefault: true,
        });
      }
    }
    for (const r of rows) {
      if (!DEFAULT_DUTY_KEYS.has(r.duty_type)) result.push(serializeDistrictRule(r));
    }

    return ok(res, result);
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/district-rules', adminRequired, async (req, res) => {
  try {
    const { rules = [] } = req.body || {};
    if (!Array.isArray(rules)) return err(res, 'rules must be a list');

    const adminId = getAdminId(req);
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    await withTransaction(async conn => {
      await conn.execute(
        `DELETE FROM district_rules WHERE admin_id IN (${dPh})`, dParams
      );
      for (const r of rules) {
        const dutyType = (r.dutyType || '').trim();
        if (!dutyType) continue;
        await conn.execute(`
          INSERT INTO district_rules
            (admin_id, duty_type, duty_label_hi, sankhya,
             si_armed_count, si_unarmed_count,
             hc_armed_count, hc_unarmed_count,
             const_armed_count, const_unarmed_count,
             aux_armed_count, aux_unarmed_count,
             pac_count, sort_order)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        `, [
          adminId, dutyType,
          (r.dutyLabelHi || '').trim(),
          parseInt(r.sankhya || 0),
          parseInt(r.siArmedCount || 0), parseInt(r.siUnarmedCount || 0),
          parseInt(r.hcArmedCount || 0), parseInt(r.hcUnarmedCount || 0),
          parseInt(r.constArmedCount || 0), parseInt(r.constUnarmedCount || 0),
          parseInt(r.auxArmedCount || 0), parseInt(r.auxUnarmedCount || 0),
          parseFloat(r.pacCount || 0),
          parseInt(r.sortOrder || 0),
        ]);
      }
    });

    return ok(res, null, 'जनपदीय मानक saved');
  } catch (e) {
    await writeLog('ERROR', `save_district_rules: ${e.message}`, 'Rules');
    return err(res, `Save failed: ${e.message}`, 500);
  }
});

// NEW: PATCH /district-rules/:dutyType/adjust — matches Flask adjust_district_rule
router.put('/district-rules/:dutyType/adjust', adminRequired, async (req, res) => {
  try {
    const { dutyType } = req.params;
    const body = req.body || {};
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const fields = [], values = [];
    const fieldMap = [
      ['siArmedCount', 'si_armed_count'],
      ['siUnarmedCount', 'si_unarmed_count'],
      ['hcArmedCount', 'hc_armed_count'],
      ['hcUnarmedCount', 'hc_unarmed_count'],
      ['constArmedCount', 'const_armed_count'],
      ['constUnarmedCount', 'const_unarmed_count'],
      ['auxArmedCount', 'aux_armed_count'],
      ['auxUnarmedCount', 'aux_unarmed_count'],
    ];
    for (const [camel, snake] of fieldMap) {
      if (camel in body) { fields.push(`${snake}=?`); values.push(parseInt(body[camel] || 0)); }
    }
    if ('sankhya' in body && body.sankhya !== null) {
      fields.push('sankhya=?');
      values.push(parseInt(body.sankhya));
    }
    if (!fields.length) return err(res, 'No fields to update');

    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
      `UPDATE district_rules SET ${fields.join(', ')} WHERE admin_id IN (${dPh}) AND duty_type=?`,
      [...values, ...dParams, dutyType]
    );
    if (!r.affectedRows) return err(res, 'Duty type not found', 404);
    await writeLog('INFO', `Manak adjusted for ${dutyType} by admin ${getAdminId(req)}`, 'Rules');
    return ok(res, null, 'मानक updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.patch('/district-rules/:dutyType/adjust', adminRequired, async (req, res) => {
  try {
    const { dutyType } = req.params;
    const body = req.body || {};
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const fields = [], values = [];
    const fieldMap = [
      ['siArmedCount', 'si_armed_count'], ['siUnarmedCount', 'si_unarmed_count'],
      ['hcArmedCount', 'hc_armed_count'], ['hcUnarmedCount', 'hc_unarmed_count'],
      ['constArmedCount', 'const_armed_count'], ['constUnarmedCount', 'const_unarmed_count'],
      ['auxArmedCount', 'aux_armed_count'], ['auxUnarmedCount', 'aux_unarmed_count'],
    ];
    for (const [camel, snake] of fieldMap) {
      if (camel in body) { fields.push(`${snake}=?`); values.push(parseInt(body[camel] || 0)); }
    }
    if ('sankhya' in body && body.sankhya !== null) {
      fields.push('sankhya=?'); values.push(parseInt(body.sankhya));
    }
    if (!fields.length) return err(res, 'No fields to update');

    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
      `UPDATE district_rules SET ${fields.join(', ')} WHERE admin_id IN (${dPh}) AND duty_type=?`,
      [...values, ...dParams, dutyType]
    );
    if (!r.affectedRows) return err(res, 'Duty type not found', 404);
    await writeLog('INFO', `Manak adjusted for ${dutyType} by admin ${getAdminId(req)}`, 'Rules');
    return ok(res, null, 'मानक updated');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  CUSTOM DUTY TYPE MANAGEMENT
// ══════════════════════════════════════════════════════════════════════════════

router.post('/district-rules/custom', adminRequired, async (req, res) => {
  try {
    const labelHi = (req.body?.labelHi || '').trim();
    if (!labelHi) return err(res, 'labelHi required');

    const safe = labelHi.toLowerCase().replace(/[^a-z0-9]/g, '_').substring(0, 30);
    const dutyType = `custom_${safe}_${Date.now() % 100000}`;
    const adminId = getAdminId(req);
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const [[{ mx }]] = await pool.execute(
      `SELECT COALESCE(MAX(sort_order), 140) AS mx FROM district_rules WHERE admin_id IN (${dPh})`,
      dParams
    );
    const sortOrder = (mx || 140) + 10;

    await pool.execute(`
      INSERT INTO district_rules
        (admin_id, duty_type, duty_label_hi, sankhya,
         si_armed_count, si_unarmed_count, hc_armed_count, hc_unarmed_count,
         const_armed_count, const_unarmed_count, aux_armed_count, aux_unarmed_count,
         pac_count, sort_order)
      VALUES (?,?,?,0,0,0,0,0,0,0,0,0,0,?)
    `, [adminId, dutyType, labelHi, sortOrder]);

    return ok(res, {
      dutyType, dutyLabelHi: labelHi, sortOrder, isDefault: false,
      sankhya: 0,
      siArmedCount: 0, siUnarmedCount: 0, hcArmedCount: 0, hcUnarmedCount: 0,
      constArmedCount: 0, constUnarmedCount: 0, auxArmedCount: 0, auxUnarmedCount: 0,
      pacCount: 0.0,
    }, 'Custom duty type added', 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.put('/district-rules/custom/:dutyType', adminRequired, async (req, res) => {
  try {
    if (DEFAULT_DUTY_KEYS.has(req.params.dutyType)) return err(res, 'Cannot rename a default duty type', 400);
    const labelHi = (req.body?.labelHi || '').trim();
    if (!labelHi) return err(res, 'labelHi required');

    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
      `UPDATE district_rules SET duty_label_hi=? WHERE duty_type=? AND admin_id IN (${dPh})`,
      [labelHi, req.params.dutyType, ...dParams]
    );
    if (!r.affectedRows) return err(res, 'Duty type not found', 404);
    return ok(res, null, 'Renamed');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/district-rules/custom/:dutyType', adminRequired, async (req, res) => {
  try {
    if (DEFAULT_DUTY_KEYS.has(req.params.dutyType)) return err(res, 'Cannot delete a default duty type', 400);
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
      `DELETE FROM district_rules WHERE duty_type=? AND admin_id IN (${dPh})`,
      [req.params.dutyType, ...dParams]
    );
    if (!r.affectedRows) return err(res, 'Duty type not found', 404);
    return ok(res, null, 'Deleted');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY ASSIGNMENTS
// ══════════════════════════════════════════════════════════════════════════════

router.get('/district-duty/summary', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const [rulesRows] = await pool.execute(
      `SELECT duty_type, duty_label_hi, sankhya, sort_order FROM district_rules WHERE admin_id IN (${dPh}) ORDER BY sort_order`,
      dParams
    );
    const [countRows] = await pool.execute(
      `SELECT dda.duty_type,
              COUNT(DISTINCT dda.staff_id) AS total_assigned,
              COUNT(DISTINCT dda.batch_no) AS batch_count,
              MAX(dda.batch_no)            AS max_batch
       FROM district_duty_assignments dda WHERE dda.admin_id IN (${dPh})
       GROUP BY dda.duty_type`,
      dParams
    );
    const counts = {};
    countRows.forEach(r => { counts[r.duty_type] = r; });

    const result = {};
    rulesRows.forEach(r => {
      const cnt = counts[r.duty_type] || {};
      result[r.duty_type] = {
        dutyType: r.duty_type, dutyLabelHi: r.duty_label_hi || '',
        sankhya: r.sankhya || 0,
        totalAssigned: parseInt(cnt.total_assigned || 0),
        batchCount: parseInt(cnt.batch_count || 0),
        maxBatch: parseInt(cnt.max_batch || 0),
      };
    });
    return ok(res, result);
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/district-duty/:dutyType/batches', adminRequired, async (req, res) => {
  try {
    const { dutyType } = req.params;
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const [batchesRaw] = await pool.execute(
      `SELECT dda.batch_no, COUNT(DISTINCT dda.staff_id) AS staff_count
       FROM district_duty_assignments dda
       WHERE dda.admin_id IN (${dPh}) AND dda.duty_type=?
       GROUP BY dda.batch_no ORDER BY dda.batch_no`,
      [...dParams, dutyType]
    );
    if (!batchesRaw.length) return ok(res, []);

    const batchNumbers = batchesRaw.map(b => b.batch_no);
    const bPh = batchNumbers.map(() => '?').join(',');
    const [rows] = await pool.execute(
      `SELECT dda.id AS assignment_id, dda.batch_no, dda.bus_no, dda.note, dda.created_at,
              u.id, u.name, u.pno, u.mobile, u.user_rank, u.thana, u.district, u.is_armed
       FROM district_duty_assignments dda JOIN users u ON u.id=dda.staff_id
       WHERE dda.admin_id IN (${dPh}) AND dda.duty_type=? AND dda.batch_no IN (${bPh})
       ORDER BY dda.batch_no, u.name`,
      [...dParams, dutyType, ...batchNumbers]
    );

    const staffByBatch = {};
    rows.forEach(r => {
      (staffByBatch[r.batch_no] = staffByBatch[r.batch_no] || []).push({
        assignmentId: r.assignment_id, id: r.id,
        name: r.name || '', pno: r.pno || '', mobile: r.mobile || '',
        rank: r.user_rank || '', thana: r.thana || '', district: r.district || '',
        isArmed: !!r.is_armed, busNo: r.bus_no || '', note: r.note || '',
      });
    });

    const result = batchesRaw.map(b => ({
      batchNo: b.batch_no, staffCount: b.staff_count, staff: staffByBatch[b.batch_no] || [],
    }));
    return ok(res, result);
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/district-duty/:dutyType/batch/:batchNo', adminRequired, async (req, res) => {
  try {
    const { dutyType, batchNo } = req.params;
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const [rows] = await pool.execute(
      `SELECT dda.id AS assignment_id, dda.bus_no, dda.note, dda.created_at,
              u.id, u.name, u.pno, u.mobile, u.user_rank, u.thana, u.district, u.is_armed
       FROM district_duty_assignments dda JOIN users u ON u.id=dda.staff_id
       WHERE dda.admin_id IN (${dPh}) AND dda.duty_type=? AND dda.batch_no=?
       ORDER BY u.name`,
      [...dParams, dutyType, batchNo]
    );
    return ok(res, rows.map(r => ({
      assignmentId: r.assignment_id, id: r.id,
      name: r.name || '', pno: r.pno || '', mobile: r.mobile || '',
      rank: r.user_rank || '', thana: r.thana || '', district: r.district || '',
      isArmed: !!r.is_armed, busNo: r.bus_no || '', note: r.note || '',
    })));
  } catch (e) { return err(res, e.message, 500); }
});

router.post('/district-duty/:dutyType/assign', adminRequired, async (req, res) => {
  try {
    const { dutyType } = req.params;
    const { staffIds = [], busNo = '', note = '' } = req.body || {};
    if (!staffIds.length) return err(res, 'staffIds required');

    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const adminId = getAdminId(req);

    const [[{ mx }]] = await pool.execute(
      `SELECT COALESCE(MAX(batch_no), 0) AS mx FROM district_duty_assignments WHERE admin_id IN (${dPh}) AND duty_type=?`,
      [...dParams, dutyType]
    );
    const batchNo = (mx || 0) + 1;

    let assigned = 0, skipped = 0;
    const already = [];

    for (const sid of staffIds) {
      try {
        await pool.execute(
          'INSERT INTO district_duty_assignments (admin_id, duty_type, batch_no, staff_id, assigned_by, bus_no, note) VALUES (?,?,?,?,?,?,?)',
          [adminId, dutyType, batchNo, sid, adminId, busNo, note]
        );
        assigned++;
      } catch (e) {
        const [[u]] = await pool.execute('SELECT name FROM users WHERE id=?', [sid]);
        already.push(u ? u.name : `id:${sid}`);
        skipped++;
      }
    }

    await writeLog('INFO', `District duty '${dutyType}' batch ${batchNo}: ${assigned} assigned by admin ${adminId}`, 'DistrictDuty');
    return ok(res, { batchNo, assigned, skipped, alreadyAssigned: already }, `Batch ${batchNo} created with ${assigned} staff`, 201);
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/district-duty/assignment/:assignmentId', adminRequired, async (req, res) => {
  try {
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
      `DELETE FROM district_duty_assignments WHERE id=? AND admin_id IN (${dPh})`,
      [req.params.assignmentId, ...dParams]
    );
    if (!r.affectedRows) return err(res, 'Assignment not found or access denied', 404);
    return ok(res, null, 'Removed');
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/district-duty/:dutyType/batch/:batchNo', adminRequired, async (req, res) => {
  try {
    const { dutyType, batchNo } = req.params;
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
      `DELETE FROM district_duty_assignments WHERE admin_id IN (${dPh}) AND duty_type=? AND batch_no=?`,
      [...dParams, dutyType, batchNo]
    );
    return ok(res, { removed: r.affectedRows }, `Batch ${batchNo} deleted`);
  } catch (e) { return err(res, e.message, 500); }
});

router.delete('/district-duty/:dutyType/clear', adminRequired, async (req, res) => {
  try {
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
      `DELETE FROM district_duty_assignments WHERE admin_id IN (${dPh}) AND duty_type=?`,
      [...dParams, req.params.dutyType]
    );
    return ok(res, { removed: r.affectedRows }, 'All assignments cleared');
  } catch (e) { return err(res, e.message, 500); }
});

router.patch('/district-duty/:dutyType/batch/:batchNo', adminRequired, async (req, res) => {
  try {
    const { dutyType, batchNo } = req.params;
    const busNo = (req.body?.busNo || '').trim();
    const note = (req.body?.note || '').trim();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const pool = await require('../config/db').getPool();
    await pool.execute(
      `UPDATE district_duty_assignments SET bus_no=?, note=? WHERE admin_id IN (${dPh}) AND duty_type=? AND batch_no=?`,
      [busNo, note, ...dParams, dutyType, batchNo]
    );
    return ok(res, null, 'Batch updated');
  } catch (e) { return err(res, e.message, 500); }
});

router.get('/district-duty/:dutyType/available-staff', adminRequired, async (req, res) => {
  try {
    const { dutyType } = req.params;
    const { page, limit, offset } = pageParams(req.query);
    const search = (req.query.q || '').trim();
    const rankFilter = (req.query.rank || '').trim();
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    const params = [];
    const whereParts = [
      "u.role='staff'", "u.is_active=1",
      `u.id NOT IN (SELECT staff_id FROM district_duty_assignments WHERE admin_id IN (${dPh}) AND duty_type=?)`,
    ];
    params.push(...dParams, dutyType);

    if (search) {
      whereParts.push('(u.name LIKE ? OR u.pno LIKE ? OR u.mobile LIKE ?)');
      const like = `%${search}%`;
      params.push(like, like, like);
    }
    if (rankFilter) { whereParts.push('u.user_rank=?'); params.push(rankFilter); }

    const whereSQL = whereParts.join(' AND ');
    const [[{ cnt: total }]] = await pool.execute(
      `SELECT COUNT(*) AS cnt FROM users u WHERE ${whereSQL}`, params
    );
    const [rows] = await pool.execute(
      `SELECT u.id, u.name, u.pno, u.mobile, u.user_rank, u.thana, u.district, u.is_armed
       FROM users u WHERE ${whereSQL} ORDER BY u.name LIMIT ${limit} OFFSET ${offset}`,
      [...params]
    );
    return paginated(res, rows.map(r => ({
      id: r.id, name: r.name || '', pno: r.pno || '', mobile: r.mobile || '',
      rank: r.user_rank || '', thana: r.thana || '', district: r.district || '',
      isArmed: !!r.is_armed,
    })), total, page, limit);
  } catch (e) { return err(res, e.message, 500); }
});

// NEW: GET /district-duty/:dutyType/availability — matches Flask
router.get('/district-duty/:dutyType/availability', adminRequired, async (req, res) => {
  try {
    const { dutyType } = req.params;
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    // 1. Current rule
    const [ruleRows] = await pool.execute(
      `SELECT * FROM district_rules WHERE admin_id IN (${dPh}) AND duty_type=?`,
      [...dParams, dutyType]
    );
    if (!ruleRows.length) return err(res, `Duty type '${dutyType}' not found`, 404);
    const rule = ruleRows[0];
    const sankhya = parseInt(rule.sankhya || 0);

    // 2. Already assigned to THIS duty grouped by rank+armed
    const [assignedRows] = await pool.execute(
      `SELECT u.user_rank AS rank_name, u.is_armed AS is_armed_flag, COUNT(*) AS cnt
       FROM district_duty_assignments dda JOIN users u ON u.id=dda.staff_id
       WHERE dda.admin_id IN (${dPh}) AND dda.duty_type=?
       GROUP BY u.user_rank, u.is_armed`,
      [...dParams, dutyType]
    );
    const assignedMap = {};
    assignedRows.forEach(r => { assignedMap[`${r.rank_name || ''}|${parseInt(r.is_armed_flag || 0)}`] = parseInt(r.cnt || 0); });

    // 3. Total active staff by rank+armed
    const [totalRows] = await pool.execute(
      `SELECT user_rank AS rank_name, is_armed AS is_armed_flag, COUNT(*) AS cnt
       FROM users WHERE role='staff' AND is_active=1 GROUP BY user_rank, is_armed`
    );
    const totalMap = {};
    totalRows.forEach(r => {
      const k = `${(r.rank_name || '').trim()}|${parseInt(r.is_armed_flag || 0)}`;
      if (k.split('|')[0]) totalMap[k] = parseInt(r.cnt || 0);
    });

    // 4. Locked into ANY district duty district-wide
    const [lockedRows] = await pool.execute(
      `SELECT u.user_rank AS rank_name, u.is_armed AS is_armed_flag, COUNT(DISTINCT u.id) AS cnt
       FROM district_duty_assignments dda JOIN users u ON u.id=dda.staff_id
       WHERE dda.admin_id IN (${dPh}) GROUP BY u.user_rank, u.is_armed`,
      dParams
    );
    const lockedMap = {};
    lockedRows.forEach(r => {
      const k = `${(r.rank_name || '').trim()}|${parseInt(r.is_armed_flag || 0)}`;
      lockedMap[k] = parseInt(r.cnt || 0);
    });

    // Build breakdown (8 slots)
    const SLOTS = [
      ['SI', 1, 'siArmedCount', 'si_armed_count', 'SI', 'सशस्त्र'],
      ['SI', 0, 'siUnarmedCount', 'si_unarmed_count', 'SI', 'निःशस्त्र'],
      ['Head Constable', 1, 'hcArmedCount', 'hc_armed_count', 'HC', 'सशस्त्र'],
      ['Head Constable', 0, 'hcUnarmedCount', 'hc_unarmed_count', 'HC', 'निःशस्त्र'],
      ['Constable', 1, 'constArmedCount', 'const_armed_count', 'Const', 'सशस्त्र'],
      ['Constable', 0, 'constUnarmedCount', 'const_unarmed_count', 'Const', 'निःशस्त्र'],
      ['Constable', 1, 'auxArmedCount', 'aux_armed_count', 'Aux', 'सशस्त्र'],
      ['Constable', 0, 'auxUnarmedCount', 'aux_unarmed_count', 'Aux', 'निःशस्त्र'],
    ];

    const breakdown = SLOTS.map(([rank, armed, _camel, snake, labelShort, labelArmed]) => {
      const key = `${rank}|${armed}`;
      const perBatch = parseInt(rule[snake] || 0);
      const required = perBatch * sankhya;
      const assigned = assignedMap[key] || 0;
      const totalInSystem = totalMap[key] || 0;
      const lockedElsewhere = lockedMap[key] || 0;
      const freeInSystem = Math.max(0, totalInSystem - lockedElsewhere);
      const gap = Math.max(0, required - assigned);
      return { rank, armed: !!armed, ruleField: snake, labelShort, labelArmed, perBatch, required, assigned, gap, totalInSystem, freeInSystem };
    });

    const rankPool = {};
    for (const [k, tot] of Object.entries(totalMap)) {
      const [rank, armedStr] = k.split('|');
      const armed = parseInt(armedStr);
      const locked = lockedMap[k] || 0;
      rankPool[k] = { rank, armed: !!armed, total: tot, free: Math.max(0, tot - locked) };
    }

    return ok(res, {
      dutyType, dutyLabelHi: rule.duty_label_hi || dutyType,
      sankhya, breakdown,
      availablePool: Object.values(rankPool),
    });
  } catch (e) { return err(res, e.message, 500); }
});

// NEW: POST /district-duty/:dutyType/auto-assign-override — matches Flask
router.post('/district-duty/:dutyType/auto-assign-override', adminRequired, async (req, res) => {
  try {
    const { dutyType } = req.params;
    const { perBatch = {}, syncManak = true } = req.body || {};
    if (!perBatch || typeof perBatch !== 'object' || !Object.keys(perBatch).length) {
      return err(res, 'perBatch is required');
    }

    const adminId = req.user.id;
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    // Verify rule exists
    const [ruleRows] = await pool.execute(
      `SELECT * FROM district_rules WHERE admin_id IN (${dPh}) AND duty_type=?`,
      [...dParams, dutyType]
    );
    if (!ruleRows.length) return err(res, `Duty type '${dutyType}' not found`, 404);
    const rule = ruleRows[0];
    const sankhya = parseInt(rule.sankhya || 0);

    // Next batch number
    const [[{ mx }]] = await pool.execute(
      `SELECT COALESCE(MAX(batch_no), 0) AS mx FROM district_duty_assignments WHERE admin_id IN (${dPh}) AND duty_type=?`,
      [...dParams, dutyType]
    );
    let nextBatch = (mx || 0) + 1;
    const existingBatches = nextBatch - 1;
    const batchesToMake = sankhya - existingBatches;

    if (batchesToMake <= 0) {
      return ok(res, { assigned: 0, batchesMade: 0, shortages: [], manakUpdated: false }, 'Already complete — no batches to add');
    }

    // Pre-load used staff
    const [usedRows] = await pool.execute(
      `SELECT DISTINCT staff_id FROM district_duty_assignments WHERE admin_id IN (${dPh})`, dParams
    );
    const usedIds = new Set(usedRows.map(r => r.staff_id));

    const OVERRIDE_MAP = [
      ['siArmedCount', 'SI', 1, 'si_armed_count'],
      ['siUnarmedCount', 'SI', 0, 'si_unarmed_count'],
      ['hcArmedCount', 'Head Constable', 1, 'hc_armed_count'],
      ['hcUnarmedCount', 'Head Constable', 0, 'hc_unarmed_count'],
      ['constArmedCount', 'Constable', 1, 'const_armed_count'],
      ['constUnarmedCount', 'Constable', 0, 'const_unarmed_count'],
      ['auxArmedCount', 'Constable', 1, 'aux_armed_count'],
      ['auxUnarmedCount', 'Constable', 0, 'aux_unarmed_count'],
    ];

    const totalPerBatch = OVERRIDE_MAP.reduce((s, [k]) => s + parseInt(perBatch[k] || 0), 0);
    if (totalPerBatch === 0) return err(res, 'perBatch must include at least one rank with count > 0');

    let totalAssigned = 0, batchesMade = 0, shortages = [];

    for (let b = 0; b < batchesToMake; b++) {
      const batchLocal = new Set();
      const batchPicks = [];
      const batchShort = [];

      for (const [camel, rank, armed, _col] of OVERRIDE_MAP) {
        const want = parseInt(perBatch[camel] || 0);
        if (want <= 0) continue;
        const excludes = new Set([...usedIds, ...batchLocal]);
        const picked = await pickRandomStaff(pool, rank, armed, want, excludes);
        if (picked.length < want) {
          batchShort.push({ rank, armed: !!armed, missing: want - picked.length });
        }
        picked.forEach(sid => { batchPicks.push(sid); batchLocal.add(sid); });
      }

      if (batchShort.length) { shortages = batchShort; break; }

      try {
        if (batchPicks.length > 0) {
          const placeholders = batchPicks.map(() => '(?,?,?,?,?)').join(',');
          await pool.execute(
            `INSERT INTO district_duty_assignments (admin_id, duty_type, batch_no, staff_id, assigned_by) VALUES ${placeholders}`,
            batchPicks.flatMap(sid => [adminId, dutyType, nextBatch, sid, adminId])
          );
        }
        batchPicks.forEach(sid => usedIds.add(sid));
        totalAssigned += batchPicks.length;
        nextBatch++;
        batchesMade++;
      } catch (e) {
        await writeLog('ERROR', `override insert ${dutyType}: ${e.message}`, 'DistrictDuty');
        shortages = [{ rank: 'DB_ERROR', armed: false, missing: batchesToMake - batchesMade, error: e.message }];
        break;
      }
    }

    let manakUpdated = false;
    if (syncManak && batchesMade > 0) {
      try {
        await pool.execute(
          `UPDATE district_rules
           SET si_armed_count=?, si_unarmed_count=?,
               hc_armed_count=?, hc_unarmed_count=?,
               const_armed_count=?, const_unarmed_count=?,
               aux_armed_count=?, aux_unarmed_count=?
           WHERE admin_id IN (${dPh}) AND duty_type=?`,
          [
            parseInt(perBatch.siArmedCount || 0), parseInt(perBatch.siUnarmedCount || 0),
            parseInt(perBatch.hcArmedCount || 0), parseInt(perBatch.hcUnarmedCount || 0),
            parseInt(perBatch.constArmedCount || 0), parseInt(perBatch.constUnarmedCount || 0),
            parseInt(perBatch.auxArmedCount || 0), parseInt(perBatch.auxUnarmedCount || 0),
            ...dParams, dutyType,
          ]
        );
        manakUpdated = true;
      } catch (e) {
        await writeLog('WARN', `Manak sync failed for ${dutyType}: ${e.message}`, 'DistrictDuty');
      }
    }

    await writeLog('INFO',
      `Override auto-assign for ${dutyType}: ${totalAssigned} staff in ${batchesMade} batches (admin ${adminId})`,
      'DistrictDuty'
    );

    return ok(res, {
      assigned: totalAssigned, batchesMade,
      batchesTarget: batchesToMake, shortages, manakUpdated,
    }, `${batchesMade} batches assigned`);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY AUTO-ASSIGN
// ══════════════════════════════════════════════════════════════════════════════

// POST /district-duty/auto-assign/start — all duty types
router.post('/district-duty/auto-assign/start', adminRequired, async (req, res) => {
  try {
    const adminId = req.user.id;
    const pool = await require('../config/db').getPool();
    const [r] = await pool.execute(
      "INSERT INTO district_duty_jobs (admin_id, status, created_by) VALUES (?,?,?)",
      [adminId, 'pending', adminId]
    );
    const jobId = r.insertId;
    setImmediate(() => runAutoAssignDistrict(jobId, adminId, null));
    return ok(res, { jobId, status: 'started' });
  } catch (e) { return err(res, e.message, 500); }
});

// NEW: POST /district-duty/:dutyType/auto-assign — single duty type
router.post('/district-duty/:dutyType/auto-assign', adminRequired, async (req, res) => {
  try {
    const { dutyType } = req.params;
    const adminId = req.user.id;
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);

    // Verify duty type exists
    const [check] = await pool.execute(
      `SELECT id FROM district_rules WHERE admin_id IN (${dPh}) AND duty_type=?`,
      [...dParams, dutyType]
    );
    if (!check.length) return err(res, `Duty type '${dutyType}' not found`, 404);

    const [r] = await pool.execute(
      "INSERT INTO district_duty_jobs (admin_id, status, created_by) VALUES (?,?,?)",
      [adminId, 'pending', adminId]
    );
    const jobId = r.insertId;
    setImmediate(() => runAutoAssignDistrict(jobId, adminId, dutyType));
    return ok(res, { jobId, status: 'started', dutyType });
  } catch (e) { return err(res, e.message, 500); }
});

// GET /district-duty/auto-assign/status/:jobId
router.get('/district-duty/auto-assign/status/:jobId', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const [[job]] = await pool.execute(
      `SELECT id, status, total_types, done_types, assigned, skipped, error_msg, created_at, updated_at
       FROM district_duty_jobs WHERE id=? AND admin_id IN (${dPh})`,
      [req.params.jobId, ...dParams]
    );
    if (!job) return err(res, 'Job not found', 404);
    return ok(res, serializeJobStatus(job));
  } catch (e) { return err(res, e.message, 500); }
});

// GET /district-duty/auto-assign/latest
router.get('/district-duty/auto-assign/latest', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const [jobs] = await pool.execute(
      `SELECT id, status, total_types, done_types, assigned, skipped, error_msg, created_at, updated_at
       FROM district_duty_jobs WHERE admin_id IN (${dPh}) ORDER BY id DESC LIMIT 1`,
      dParams
    );
    if (!jobs.length) return ok(res, null);
    return ok(res, serializeJobStatus(jobs[0]));
  } catch (e) { return err(res, e.message, 500); }
});

// DELETE /district-duty/auto-assign/clear-all
router.delete('/district-duty/auto-assign/clear-all', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const dIds = await getDistrictAdminIds(req);
    const { ph: dPh, params: dParams } = districtPH(dIds);
    const [r] = await pool.execute(
      `DELETE FROM district_duty_assignments WHERE admin_id IN (${dPh})`, dParams
    );
    await writeLog('INFO', `All district duty assignments cleared (${r.affectedRows} rows) by admin ${getAdminId(req)}`, 'DistrictAutoAssign');
    return ok(res, { removed: r.affectedRows }, 'All district assignments cleared');
  } catch (e) { return err(res, e.message, 500); }
});

// NEW: POST /district-duty/refresh/:dutyType — matches Flask refresh_duty_type
router.post('/district-duty/refresh/:dutyType', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    await pool.execute(
      'DELETE FROM district_duty_assignments WHERE duty_type=?', [req.params.dutyType]
    );
    return ok(res, null, 'Cleared');
  } catch (e) { return err(res, e.message, 500); }
});

// Legacy: GET /district-duty/:dutyType — matches Flask get_duty_type_data
router.get('/district-duty/:dutyType', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [batches] = await pool.execute(
      `SELECT batch_no, COUNT(*) AS total FROM district_duty_assignments WHERE duty_type=? GROUP BY batch_no`,
      [req.params.dutyType]
    );
    return ok(res, batches);
  } catch (e) { return err(res, e.message, 500); }
});

// Legacy: GET /district-duty/:dutyType/:batch — matches Flask get_batch_staff
router.get('/district-duty/:dutyType/:batch', adminRequired, async (req, res) => {
  try {
    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(
      `SELECT u.id, u.name, u.user_rank, u.mobile, u.is_armed
       FROM district_duty_assignments da JOIN users u ON u.id=da.staff_id
       WHERE da.duty_type=? AND da.batch_no=?`,
      [req.params.dutyType, req.params.batch]
    );
    return ok(res, rows);
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  GOSWARA — now reads from election_configs like Flask
// ══════════════════════════════════════════════════════════════════════════════

router.get('/goswara', adminRequired, async (req, res) => {
  const currentId = req.user.id;
  const district = (req.user.district || '').trim();
  const pool = await require('../config/db').getPool();

  try {
    // Election config from election_configs table (matches Flask)
    let electionDate = '', phase = '';
    if (district) {
      const [cfgRows] = await pool.execute(`
        SELECT election_date, phase FROM election_configs
        WHERE district=? AND is_active=1 AND is_archived=0
        ORDER BY id DESC LIMIT 1
      `, [district]);
      if (cfgRows.length) {
        electionDate = cfgRows[0].election_date ? String(cfgRows[0].election_date) : '';
        phase = String(cfgRows[0].phase || '');
      }
    }

    // District admin IDs
    let adminIds = [currentId];
    if (district) {
      const [rows] = await pool.execute(
        "SELECT id FROM users WHERE role IN ('admin','super_admin') AND district=?", [district]
      );
      adminIds = rows.map(r => r.id);
      if (!adminIds.includes(currentId)) adminIds.push(currentId);
      if (!adminIds.length) adminIds = [currentId];
    }
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

    const [nyayRows] = await pool.execute(
      `SELECT block_name, SUM(nyay_count) AS nyay_count FROM goswara_nyay_panchayat WHERE admin_id IN (${ph}) GROUP BY block_name`,
      adminIds
    );
    const nyayMap = {};
    nyayRows.forEach(r => { nyayMap[r.block_name] = parseInt(r.nyay_count || 0); });

    const data = rows.map(r => ({
      block_name: r.block_name || '',
      zonal_count: parseInt(r.zonal_count || 0),
      sector_count: parseInt(r.sector_count || 0),
      nyay_panchayat_count: nyayMap[r.block_name] || 0,
      gram_panchayat_count: parseInt(r.gram_panchayat_count || 0),
    }));

    return res.json({ success: true, electionDate, phase, data });
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
       VALUES (?,?,?) ON DUPLICATE KEY UPDATE nyay_count = VALUES(nyay_count)`,
      [req.user.id, blockName, nyayCount]
    );
    return ok(res, null, 'saved');
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ELECTION CONFIG ROUTES — NEW (all missing from Node.js)
// ══════════════════════════════════════════════════════════════════════════════

// GET /election-config/active
router.get('/election-config/active', adminRequired, async (req, res) => {
  try {
    const district = (req.user.district || '').trim();
    if (!district) return err(res, 'Admin has no district set', 400);

    const pool = await require('../config/db').getPool();
    const [rows] = await pool.execute(`
      SELECT id, district, state, election_type, election_name,
             phase, election_year, election_date,
             pratah_samay, saya_samay, instructions,
             is_active, is_archived, created_at, updated_at
      FROM election_configs
      WHERE district=? AND is_active=1 AND is_archived=0
      ORDER BY updated_at DESC, id DESC LIMIT 1
    `, [district]);

    if (!rows.length) return err(res, 'No active election config found for this district', 404);
    const r = rows[0];
    return ok(res, {
      id: r.id, district: r.district || '', state: r.state || '',
      electionType: r.election_type || '', electionName: r.election_name || '',
      phase: r.phase || '', electionYear: r.election_year || '',
      electionDate: r.election_date ? String(r.election_date) : '',
      pratahSamay: r.pratah_samay || '', sayaSamay: r.saya_samay || '',
      instructions: r.instructions || '',
      isActive: !!r.is_active, isArchived: !!r.is_archived,
    });
  } catch (e) { return err(res, e.message, 500); }
});

// POST /election-config
router.post('/election-config', adminRequired, async (req, res) => {
  try {
    const body = req.body || {};
    let district = (body.district || req.user.district || '').trim();
    const state = (body.state || '').trim();
    const electionType = (body.electionType || '').trim();
    const electionName = (body.electionName || '').trim();
    const phase = (body.phase || '').trim();
    const electionYear = (body.electionYear || '').trim();
    let electionDate = body.electionDate || null;
    const pratahSamay = (body.pratahSamay || '07:00').trim();
    const sayaSamay = (body.sayaSamay || '06:00').trim();
    const instructions = (body.instructions || '').trim();

    if (!district || !electionName) return err(res, 'district and electionName required');

    // Normalise DD.MM.YYYY → YYYY-MM-DD
    if (electionDate && String(electionDate).includes('.')) {
      const parts = String(electionDate).split('.');
      if (parts.length === 3) electionDate = `${parts[2]}-${parts[1]}-${parts[0]}`;
    }

    const pool = await require('../config/db').getPool();
    await withTransaction(async conn => {
      // Archive existing active config for this district
      await conn.execute(`
        UPDATE election_configs SET is_active=0, is_archived=1, archived_at=NOW()
        WHERE district=? AND is_active=1 AND is_archived=0
      `, [district]);

      await conn.execute(`
        INSERT INTO election_configs
          (district, state, election_type, election_name, phase,
           election_year, election_date, pratah_samay, saya_samay,
           instructions, is_active, is_archived, created_by)
        VALUES (?,?,?,?,?,?,?,?,?,?,1,0,?)
      `, [district, state, electionType, electionName, phase,
          electionYear, electionDate || null, pratahSamay, sayaSamay,
          instructions, req.user.id]);
    });

    await writeLog('INFO', `Election config saved for ${district} by admin ${getAdminId(req)}`, 'ElectionConfig');
    return ok(res, {}, 'Election config saved', 201);
  } catch (e) { return err(res, `Save failed: ${e.message}`, 500); }
});

// GET /election-config/list
router.get('/election-config/list', adminRequired, async (req, res) => {
  try {
    const district = (req.user.district || '').trim();
    const pool = await require('../config/db').getPool();
    let rows;
    if (district) {
      [rows] = await pool.execute(`
        SELECT id, district, state, election_name, phase,
               election_year, election_date, pratah_samay, saya_samay,
               is_active, is_archived, created_at, updated_at
        FROM election_configs WHERE district=? ORDER BY id DESC
      `, [district]);
    } else {
      [rows] = await pool.execute(`
        SELECT id, district, state, election_name, phase,
               election_year, election_date, pratah_samay, saya_samay,
               is_active, is_archived, created_at, updated_at
        FROM election_configs ORDER BY id DESC LIMIT 100
      `);
    }
    return ok(res, rows.map(r => ({
      id: r.id, district: r.district || '', state: r.state || '',
      electionName: r.election_name || '', phase: r.phase || '',
      electionYear: r.election_year || '',
      electionDate: r.election_date ? String(r.election_date) : '',
      pratahSamay: r.pratah_samay || '', sayaSamay: r.saya_samay || '',
      isActive: !!r.is_active, isArchived: !!r.is_archived,
      createdAt: String(r.created_at), updatedAt: String(r.updated_at),
    })));
  } catch (e) { return err(res, e.message, 500); }
});

// ══════════════════════════════════════════════════════════════════════════════
//  FORM-DATA (public, backward compat)
// ══════════════════════════════════════════════════════════════════════════════

router.get('/form-data', async (req, res) => {
  try {
    const rows = await query(`
      SELECT u.id AS adminId, u.name AS adminName, u.district,
             COUNT(DISTINCT sz.id) AS superZones, COUNT(DISTINCT z.id) AS zones,
             COUNT(DISTINCT s.id) AS sectors,     COUNT(DISTINCT gp.id) AS gramPanchayats,
             COUNT(DISTINCT ms.id) AS centers,    MAX(ms.created_at) AS lastUpdated
      FROM users u
      LEFT JOIN super_zones     sz ON sz.admin_id          = u.id
      LEFT JOIN zones            z ON z.super_zone_id      = sz.id
      LEFT JOIN sectors          s ON s.zone_id            = z.id
      LEFT JOIN gram_panchayats gp ON gp.sector_id         = s.id
      LEFT JOIN matdan_sthal    ms ON ms.gram_panchayat_id = gp.id
      WHERE u.role='admin' GROUP BY u.id ORDER BY u.id DESC
    `);
    return res.json({ success: true, data: rows });
  } catch (e) { return res.status(500).json({ success: false, message: e.message }); }
});

module.exports = router;