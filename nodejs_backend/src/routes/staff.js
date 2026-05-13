const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const { query } = require('../config/db');
const { ok, err, loginRequired } = require('../middleware/auth');
const { passwordSalt } = require('../config');

const SALT = passwordSalt || "election_2026_secure_key";

function hashPassword(plain) {
  return crypto.createHash('sha256').update(plain + SALT).digest('hex');
}

// ─────────────────────────────────────────────────────────────────────────────
//  _getElectionDate  — matches Flask: queries election_configs by district
// ─────────────────────────────────────────────────────────────────────────────
async function _getElectionDate(district = null) {
  try {
    let rows;
    if (district) {
      rows = await query(`
        SELECT election_date FROM election_configs
        WHERE district = ? AND is_active = 1 AND is_archived = 0
        ORDER BY id DESC LIMIT 1
      `, [district]);
    } else {
      rows = await query(`
        SELECT election_date FROM election_configs
        WHERE is_active = 1 AND is_archived = 0
        ORDER BY id DESC LIMIT 1
      `);
    }
    return rows.length ? rows[0].election_date : null;
  } catch (e) {
    console.error("❌ election_date fetch error:", e);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _getBoothRulesForSuperZone — matches Flask _get_booth_rules_for_super_zone
//  Fetches all booth_rules for the admin of this super_zone and expands
//  columnar counts into per-rank rows.
// ─────────────────────────────────────────────────────────────────────────────
async function _getBoothRulesForSuperZone(superZoneId) {
  const szRows = await query(
    `SELECT admin_id FROM super_zones WHERE id = ? LIMIT 1`,
    [superZoneId]
  );
  if (!szRows.length || !szRows[0].admin_id) return [];
  const adminId = szRows[0].admin_id;

  const ruleRows = await query(`
    SELECT sensitivity,
           si_armed_count,    si_unarmed_count,
           hc_armed_count,    hc_unarmed_count,
           const_armed_count, const_unarmed_count,
           aux_armed_count,   aux_unarmed_count
    FROM booth_rules
    WHERE admin_id = ?
    GROUP BY sensitivity,
             si_armed_count,    si_unarmed_count,
             hc_armed_count,    hc_unarmed_count,
             const_armed_count, const_unarmed_count,
             aux_armed_count,   aux_unarmed_count
    ORDER BY FIELD(sensitivity, 'A++', 'A', 'B', 'C')
  `, [adminId]);

  const rankCols = [
    ["SI",             "si_armed_count",    "si_unarmed_count"],
    ["Head Constable", "hc_armed_count",    "hc_unarmed_count"],
    ["Constable",      "const_armed_count", "const_unarmed_count"],
    ["Home Guard",     "aux_armed_count",   "aux_unarmed_count"],
  ];

  const results = [];
  for (const r of ruleRows) {
    for (const [rank, ac, uc] of rankCols) {
      if ((r[ac] || 0) > 0)
        results.push({ sensitivity: r.sensitivity, rank, is_armed: 1, count: r[ac] });
      if ((r[uc] || 0) > 0)
        results.push({ sensitivity: r.sensitivity, rank, is_armed: 0, count: r[uc] });
    }
  }
  return results;
}

// ─────────────────────────────────────────────────────────────────────────────
//  _getBoothRules — matches Flask _get_booth_rules
//  Finds the closest-matching booth_rules row for this center's booth_count
//  and sensitivity, then expands to per-rank rows.
// ─────────────────────────────────────────────────────────────────────────────
async function _getBoothRules(superZoneId, sensitivity, centerId) {
  const msRows = await query(
    `SELECT booth_count FROM matdan_sthal WHERE id = ?`,
    [centerId]
  );
  const boothCount = msRows.length ? (msRows[0].booth_count || 1) : 1;

  const szRows = await query(
    `SELECT admin_id FROM super_zones WHERE id = ? LIMIT 1`,
    [superZoneId]
  );
  if (!szRows.length || !szRows[0].admin_id) return [];
  const adminId = szRows[0].admin_id;

  const ruleRows = await query(`
    SELECT * FROM booth_rules
    WHERE admin_id = ? AND sensitivity = ?
    ORDER BY ABS(booth_count - ?), booth_count
    LIMIT 1
  `, [adminId, sensitivity, boothCount]);

  if (!ruleRows.length) return [];
  const rule = ruleRows[0];

  const rankCols = [
    ["SI",             "si_armed_count",    "si_unarmed_count"],
    ["Head Constable", "hc_armed_count",    "hc_unarmed_count"],
    ["Constable",      "const_armed_count", "const_unarmed_count"],
    ["Home Guard",     "aux_armed_count",   "aux_unarmed_count"],
  ];

  const rows = [];
  for (const [rank, ac, uc] of rankCols) {
    const armedCnt   = rule[ac] || 0;
    const unarmedCnt = rule[uc] || 0;
    if (armedCnt > 0)
      rows.push({ sensitivity, rank, is_armed: 1, count: armedCnt });
    if (unarmedCnt > 0)
      rows.push({ sensitivity, rank, is_armed: 0, count: unarmedCnt });
  }
  return rows;
}

// ─────────────────────────────────────────────────────────────────────────────
//  _detectRole  → returns [roleType, entityId]
// ─────────────────────────────────────────────────────────────────────────────
async function _detectRole(staffId) {
  let rows = await query(
    `SELECT id, sector_id FROM sector_officers WHERE user_id = ? LIMIT 1`,
    [staffId]
  );
  if (rows.length) return ["sector", rows[0].sector_id];

  rows = await query(
    `SELECT id, zone_id FROM zonal_officers WHERE user_id = ? LIMIT 1`,
    [staffId]
  );
  if (rows.length) return ["zone", rows[0].zone_id];

  rows = await query(
    `SELECT id, super_zone_id FROM kshetra_officers WHERE user_id = ? LIMIT 1`,
    [staffId]
  );
  if (rows.length) return ["kshetra", rows[0].super_zone_id];

  rows = await query(
    `SELECT id FROM duty_assignments WHERE staff_id = ? LIMIT 1`,
    [staffId]
  );
  if (rows.length) return ["booth", null];

  return ["none", null];
}

// ══════════════════════════════════════════════════════════════════════════════
//  PROFILE
// ══════════════════════════════════════════════════════════════════════════════
router.get('/profile', loginRequired, async (req, res) => {
  try {
    const rows = await query(`
      SELECT id, name, pno, mobile, thana, district,
             user_rank, is_active, is_armed
      FROM users WHERE id = ?
    `, [req.user.id]);

    if (!rows.length) return err(res, "User not found", 404);

    const row = rows[0];
    return ok(res, {
      id:       row.id,
      name:     row.name      || "",
      pno:      row.pno       || "",
      mobile:   row.mobile    || "",
      thana:    row.thana     || "",
      district: row.district  || "",
      rank:     row.user_rank || "",
      isArmed:  Boolean(row.is_armed),
      isActive: Boolean(row.is_active),
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  MARK CARD DOWNLOADED
// ══════════════════════════════════════════════════════════════════════════════
router.post('/mark-card-downloaded', loginRequired, async (req, res) => {
  try {
    await query(`
      UPDATE duty_assignments SET card_downloaded = 1 WHERE staff_id = ?
    `, [req.user.id]);

    return ok(res, null, "Card marked as downloaded");
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  MY DUTY — unified endpoint
// ══════════════════════════════════════════════════════════════════════════════
router.get('/my-duty', loginRequired, async (req, res) => {
  try {
    const [roleType, entityId] = await _detectRole(req.user.id);

    if (roleType === "booth")   return ok(res, await _boothDuty(req.user.id));
    if (roleType === "sector")  return ok(res, await _sectorDuty(req.user.id, entityId));
    if (roleType === "zone")    return ok(res, await _zoneDuty(req.user.id, entityId));
    if (roleType === "kshetra") return ok(res, await _kshetraDuty(req.user.id, entityId));

    return ok(res, null, "No duty assigned yet");
  } catch (e) {
    console.error("❌ /my-duty error:", e);
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
//  BOOTH DUTY — uses _getBoothRules (matches Flask)
// ─────────────────────────────────────────────────────────────────────────────
async function _boothDuty(uid) {
  const rows = await query(`
    SELECT
      da.id AS duty_id, da.bus_no,
      ms.id AS center_id, ms.name AS center_name,
      ms.address AS center_address, ms.thana,
      ms.center_type, ms.latitude, ms.longitude,
      gp.id AS gp_id, gp.name AS gp_name, gp.address AS gp_address,
      s.id AS sector_id, s.name AS sector_name,
      z.id AS zone_id, z.name AS zone_name, z.hq_address AS zone_hq,
      sz.id AS super_zone_id, sz.name AS super_zone_name,
      u2.name AS assigned_by_name
    FROM duty_assignments da
    JOIN matdan_sthal ms    ON ms.id = da.sthal_id
    JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
    JOIN sectors s          ON s.id  = gp.sector_id
    JOIN zones z            ON z.id  = s.zone_id
    JOIN super_zones sz     ON sz.id = z.super_zone_id
    LEFT JOIN users u2      ON u2.id = da.assigned_by
    WHERE da.staff_id = ?
    LIMIT 1
  `, [uid]);

  const row = rows[0];
  if (!row) return null;

  const [allStaff, sectorOfficers, zonalOfficers, superOfficers] = await Promise.all([
    query(`
      SELECT u.name, u.pno, u.mobile, u.thana, u.district, u.user_rank, u.is_armed
      FROM duty_assignments da2
      JOIN users u ON u.id = da2.staff_id
      WHERE da2.sthal_id = ?
      ORDER BY u.name
    `, [row.center_id]),

    query(`
      SELECT COALESCE(u.name, so.name) AS name,
             COALESCE(u.pno, so.pno)   AS pno,
             COALESCE(u.mobile, so.mobile) AS mobile,
             COALESCE(u.user_rank, so.user_rank) AS user_rank
      FROM sector_officers so
      LEFT JOIN users u ON u.id = so.user_id
      WHERE so.sector_id = ?
    `, [row.sector_id]),

    query(`
      SELECT COALESCE(u.name, zo.name) AS name,
             COALESCE(u.pno, zo.pno)   AS pno,
             COALESCE(u.mobile, zo.mobile) AS mobile,
             COALESCE(u.user_rank, zo.user_rank) AS user_rank
      FROM zonal_officers zo
      LEFT JOIN users u ON u.id = zo.user_id
      WHERE zo.zone_id = ?
    `, [row.zone_id]),

    query(`
      SELECT COALESCE(u.name, ko.name) AS name,
             COALESCE(u.pno, ko.pno)   AS pno,
             COALESCE(u.mobile, ko.mobile) AS mobile,
             COALESCE(u.user_rank, ko.user_rank) AS user_rank
      FROM kshetra_officers ko
      LEFT JOIN users u ON u.id = ko.user_id
      WHERE ko.super_zone_id = ?
    `, [row.super_zone_id]),
  ]);

  // Use the proper booth_rules lookup matching Flask
  const rules = await _getBoothRules(row.super_zone_id, row.center_type, row.center_id);

  return {
    roleType:      "booth",
    dutyId:        row.duty_id,
    busNo:         row.bus_no          || "",
    centerId:      row.center_id,
    centerName:    row.center_name     || "",
    centerAddress: row.center_address  || "",
    thana:         row.thana           || "",
    centerType:    row.center_type     || "",
    latitude:      row.latitude  != null ? parseFloat(row.latitude)  : null,
    longitude:     row.longitude != null ? parseFloat(row.longitude) : null,
    gpName:        row.gp_name         || "",
    gpAddress:     row.gp_address      || "",
    sectorName:    row.sector_name     || "",
    zoneName:      row.zone_name       || "",
    zoneHq:        row.zone_hq         || "",
    superZoneName: row.super_zone_name || "",
    assignedBy:    row.assigned_by_name || "",
    allStaff,
    sectorOfficers,
    zonalOfficers,
    superOfficers,
    boothRules: rules,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
//  SECTOR DUTY — uses _getBoothRulesForSuperZone (matches Flask)
// ─────────────────────────────────────────────────────────────────────────────
async function _sectorDuty(uid, sectorId) {
  const secRows = await query(`
    SELECT s.id, s.name, s.hq_address,
           z.id AS zone_id, z.name AS zone_name,
           sz.id AS super_zone_id, sz.name AS super_zone_name
    FROM sectors s
    JOIN zones z        ON z.id  = s.zone_id
    JOIN super_zones sz ON sz.id = z.super_zone_id
    WHERE s.id = ?
  `, [sectorId]);

  if (!secRows.length) return { roleType: "sector", error: "Sector not found" };
  const sec = secRows[0];

  const [coOfficers, zonalOfficers, gps, rules] = await Promise.all([
    query(`
      SELECT COALESCE(u.name, so.name) AS name,
             COALESCE(u.pno, so.pno)   AS pno,
             COALESCE(u.mobile, so.mobile) AS mobile,
             COALESCE(u.user_rank, so.user_rank) AS user_rank
      FROM sector_officers so
      LEFT JOIN users u ON u.id = so.user_id
      WHERE so.sector_id = ?
    `, [sectorId]),

    query(`
      SELECT COALESCE(u.name, zo.name) AS name,
             COALESCE(u.pno, zo.pno)   AS pno,
             COALESCE(u.mobile, zo.mobile) AS mobile,
             COALESCE(u.user_rank, zo.user_rank) AS user_rank
      FROM zonal_officers zo
      LEFT JOIN users u ON u.id = zo.user_id
      WHERE zo.zone_id = ?
    `, [sec.zone_id]),

    query(`
      SELECT gp.id, gp.name, gp.address
      FROM gram_panchayats gp
      WHERE gp.sector_id = ?
      ORDER BY gp.name
    `, [sectorId]),

    _getBoothRulesForSuperZone(sec.super_zone_id),
  ]);

  const gpIds = gps.map(g => g.id);
  let centersList = [];
  let totalBooths = 0;
  let totalAssigned = 0;

  if (gpIds.length) {
    const ph = gpIds.map(() => '?').join(',');

    const centers = await query(`
      SELECT ms.id, ms.name, ms.thana, ms.center_type,
             ms.latitude, ms.longitude, ms.bus_no,
             ms.gram_panchayat_id,
             gp.name AS gp_name,
             (SELECT COUNT(*) FROM duty_assignments da WHERE da.sthal_id = ms.id) AS staff_count
      FROM matdan_sthal ms
      JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
      WHERE ms.gram_panchayat_id IN (${ph})
      ORDER BY gp.name, ms.name
    `, gpIds);

    totalBooths = centers.length;
    const centerIds = centers.map(c => c.id);

    let staffByCenter = {};
    if (centerIds.length) {
      const ph2 = centerIds.map(() => '?').join(',');
      const staffRows = await query(`
        SELECT da.sthal_id, da.id AS duty_id,
               u.id AS staff_id, u.name, u.pno, u.mobile,
               u.user_rank, u.is_armed, u.thana, u.district,
               da.attended
        FROM duty_assignments da
        JOIN users u ON u.id = da.staff_id
        WHERE da.sthal_id IN (${ph2})
        ORDER BY u.name
      `, centerIds);

      for (const r of staffRows) {
        if (!staffByCenter[r.sthal_id]) staffByCenter[r.sthal_id] = [];
        staffByCenter[r.sthal_id].push(r);
        totalAssigned++;
      }
    }

    centersList = centers.map(c => ({ ...c, staff: staffByCenter[c.id] || [] }));
  }

  return {
    roleType:       "sector",
    sectorId:       sec.id,
    sectorName:     sec.name       || "",
    hqAddress:      sec.hq_address || "",
    zoneId:         sec.zone_id,
    zoneName:       sec.zone_name  || "",
    superZoneId:    sec.super_zone_id,
    superZoneName:  sec.super_zone_name || "",
    coOfficers,
    zonalOfficers,
    gramPanchayats: gps,
    centers:        centersList,
    totalBooths,
    totalAssigned,
    boothRules:     rules,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
//  ZONE DUTY — uses _getBoothRulesForSuperZone (matches Flask)
// ─────────────────────────────────────────────────────────────────────────────
async function _zoneDuty(uid, zoneId) {
  const zoneRows = await query(`
    SELECT z.id, z.name, z.hq_address,
           sz.id AS super_zone_id, sz.name AS super_zone_name
    FROM zones z
    JOIN super_zones sz ON sz.id = z.super_zone_id
    WHERE z.id = ?
  `, [zoneId]);

  if (!zoneRows.length) return { roleType: "zone", error: "Zone not found" };
  const zone = zoneRows[0];

  const [coOfficers, superOfficers, sectors, rules] = await Promise.all([
    query(`
      SELECT COALESCE(u.name, zo.name) AS name,
             COALESCE(u.pno, zo.pno)   AS pno,
             COALESCE(u.mobile, zo.mobile) AS mobile,
             COALESCE(u.user_rank, zo.user_rank) AS user_rank
      FROM zonal_officers zo
      LEFT JOIN users u ON u.id = zo.user_id
      WHERE zo.zone_id = ?
    `, [zoneId]),

    query(`
      SELECT COALESCE(u.name, ko.name) AS name,
             COALESCE(u.pno, ko.pno)   AS pno,
             COALESCE(u.mobile, ko.mobile) AS mobile,
             COALESCE(u.user_rank, ko.user_rank) AS user_rank
      FROM kshetra_officers ko
      LEFT JOIN users u ON u.id = ko.user_id
      WHERE ko.super_zone_id = ?
    `, [zone.super_zone_id]),

    query(`
      SELECT s.id, s.name, s.hq_address,
             COUNT(DISTINCT gp.id) AS gp_count,
             COUNT(DISTINCT ms.id) AS center_count,
             (SELECT COUNT(*) FROM duty_assignments da
              JOIN matdan_sthal ms2    ON ms2.id  = da.sthal_id
              JOIN gram_panchayats gp2 ON gp2.id  = ms2.gram_panchayat_id
              WHERE gp2.sector_id = s.id) AS staff_assigned
      FROM sectors s
      LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
      LEFT JOIN matdan_sthal ms    ON ms.gram_panchayat_id = gp.id
      WHERE s.zone_id = ?
      GROUP BY s.id
      ORDER BY s.name
    `, [zoneId]),

    _getBoothRulesForSuperZone(zone.super_zone_id),
  ]);

  const sectorIds = sectors.map(s => s.id);
  let officersBySector = {};
  if (sectorIds.length) {
    const ph = sectorIds.map(() => '?').join(',');
    const officerRows = await query(`
      SELECT so.sector_id,
             COALESCE(u.name, so.name) AS name,
             COALESCE(u.pno, so.pno)   AS pno,
             COALESCE(u.mobile, so.mobile) AS mobile,
             COALESCE(u.user_rank, so.user_rank) AS user_rank
      FROM sector_officers so
      LEFT JOIN users u ON u.id = so.user_id
      WHERE so.sector_id IN (${ph})
    `, sectorIds);

    for (const r of officerRows) {
      if (!officersBySector[r.sector_id]) officersBySector[r.sector_id] = [];
      officersBySector[r.sector_id].push(r);
    }
  }

  let totalBooths = 0, totalAssigned = 0;
  const sectorsData = sectors.map(s => {
    totalBooths   += s.center_count   || 0;
    totalAssigned += s.staff_assigned || 0;
    return { ...s, officers: officersBySector[s.id] || [] };
  });

  return {
    roleType:      "zone",
    zoneId:        zone.id,
    zoneName:      zone.name       || "",
    hqAddress:     zone.hq_address || "",
    superZoneId:   zone.super_zone_id,
    superZoneName: zone.super_zone_name || "",
    coOfficers,
    superOfficers,
    sectors:       sectorsData,
    totalSectors:  sectorsData.length,
    totalBooths,
    totalAssigned,
    boothRules:    rules,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
//  KSHETRA DUTY — uses _getBoothRulesForSuperZone (matches Flask)
// ─────────────────────────────────────────────────────────────────────────────
async function _kshetraDuty(uid, superZoneId) {
  const szRows = await query(`
    SELECT id, name, district, block FROM super_zones WHERE id = ?
  `, [superZoneId]);

  if (!szRows.length) return { roleType: "kshetra", error: "Super zone not found" };
  const sz = szRows[0];

  const [coOfficers, zones, rules] = await Promise.all([
    query(`
      SELECT COALESCE(u.name, ko.name) AS name,
             COALESCE(u.pno, ko.pno)   AS pno,
             COALESCE(u.mobile, ko.mobile) AS mobile,
             COALESCE(u.user_rank, ko.user_rank) AS user_rank
      FROM kshetra_officers ko
      LEFT JOIN users u ON u.id = ko.user_id
      WHERE ko.super_zone_id = ?
    `, [superZoneId]),

    query(`
      SELECT z.id, z.name, z.hq_address,
             COUNT(DISTINCT s.id)  AS sector_count,
             COUNT(DISTINCT gp.id) AS gp_count,
             COUNT(DISTINCT ms.id) AS center_count,
             (SELECT COUNT(*) FROM duty_assignments da
              JOIN matdan_sthal ms2    ON ms2.id  = da.sthal_id
              JOIN gram_panchayats gp2 ON gp2.id  = ms2.gram_panchayat_id
              JOIN sectors s2          ON s2.id   = gp2.sector_id
              WHERE s2.zone_id = z.id) AS staff_assigned
      FROM zones z
      LEFT JOIN sectors s          ON s.zone_id           = z.id
      LEFT JOIN gram_panchayats gp ON gp.sector_id        = s.id
      LEFT JOIN matdan_sthal ms    ON ms.gram_panchayat_id = gp.id
      WHERE z.super_zone_id = ?
      GROUP BY z.id
      ORDER BY z.name
    `, [superZoneId]),

    _getBoothRulesForSuperZone(superZoneId),
  ]);

  const zoneIds = zones.map(z => z.id);
  let officersByZone = {};
  if (zoneIds.length) {
    const ph = zoneIds.map(() => '?').join(',');
    const officerRows = await query(`
      SELECT zo.zone_id,
             COALESCE(u.name, zo.name) AS name,
             COALESCE(u.pno, zo.pno)   AS pno,
             COALESCE(u.mobile, zo.mobile) AS mobile,
             COALESCE(u.user_rank, zo.user_rank) AS user_rank
      FROM zonal_officers zo
      LEFT JOIN users u ON u.id = zo.user_id
      WHERE zo.zone_id IN (${ph})
    `, zoneIds);

    for (const r of officerRows) {
      if (!officersByZone[r.zone_id]) officersByZone[r.zone_id] = [];
      officersByZone[r.zone_id].push(r);
    }
  }

  let totalZones = 0, totalSectors = 0, totalBooths = 0, totalAssigned = 0;
  const zonesData = zones.map(z => {
    totalZones    += 1;
    totalSectors  += z.sector_count   || 0;
    totalBooths   += z.center_count   || 0;
    totalAssigned += z.staff_assigned || 0;
    return { ...z, officers: officersByZone[z.id] || [] };
  });

  return {
    roleType:      "kshetra",
    superZoneId:   sz.id,
    superZoneName: sz.name     || "",
    district:      sz.district || "",
    block:         sz.block    || "",
    coOfficers,
    zones:         zonesData,
    totalZones,
    totalSectors,
    totalBooths,
    totalAssigned,
    boothRules:    rules,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
//  ELECTION CONFIG  ← NEW: was missing in Node.js
// ══════════════════════════════════════════════════════════════════════════════
router.get('/election-config', loginRequired, async (req, res) => {
  try {
    const userRows = await query(
      `SELECT district FROM users WHERE id = ?`,
      [req.user.id]
    );
    const district = userRows.length ? userRows[0].district : null;

    let row = null;

    if (district) {
      const rows = await query(`
        SELECT id, election_name, election_type, phase,
               election_date, pratah_samay, saya_samay,
               district, is_active
        FROM election_configs
        WHERE district = ? AND is_active = 1 AND is_archived = 0
        ORDER BY id DESC LIMIT 1
      `, [district]);
      row = rows[0] || null;
    }

    if (!row) {
      const rows = await query(`
        SELECT id, election_name, election_type, phase,
               election_date, pratah_samay, saya_samay,
               district, is_active
        FROM election_configs
        WHERE is_active = 1 AND is_archived = 0
        ORDER BY id DESC LIMIT 1
      `);
      row = rows[0] || null;
    }

    if (!row) return ok(res, null);

    return ok(res, {
      id:            row.id,
      election_name: row.election_name || "",
      election_type: row.election_type || "",
      phase:         row.phase         != null ? String(row.phase)         : "",
      election_date: row.election_date != null ? String(row.election_date) : null,
      pratah_samay:  row.pratah_samay  != null ? String(row.pratah_samay)  : "",
      saya_samay:    row.saya_samay    != null ? String(row.saya_samay)    : "",
      district:      row.district      || "",
    });
  } catch (e) {
    console.error("❌ /election-config error:", e);
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY  ← NEW: was missing in Node.js
// ══════════════════════════════════════════════════════════════════════════════
router.get('/district-duty', loginRequired, async (req, res) => {
  try {
    const userRows = await query(
      `SELECT district FROM users WHERE id = ?`,
      [req.user.id]
    );
    const userDistrict = userRows.length ? (userRows[0].district || "") : "";

    const rows = await query(`
      SELECT
        dda.id         AS assignment_id,
        dda.duty_type  AS duty_type,
        dda.batch_no   AS batch_no,
        dda.bus_no     AS bus_no,
        dda.note       AS note,
        dda.admin_id   AS admin_id,
        dda.created_at AS assigned_at
      FROM district_duty_assignments dda
      WHERE dda.staff_id = ?
      ORDER BY dda.id DESC
      LIMIT 1
    `, [req.user.id]);

    if (!rows.length) return ok(res, null);

    const row = rows[0];
    const { batch_no, admin_id, duty_type } = row;

    const batchStaff = await query(`
      SELECT u.id, u.name, u.pno, u.mobile,
             u.user_rank, u.thana, u.district, u.is_armed
      FROM district_duty_assignments dda
      JOIN users u ON u.id = dda.staff_id
      WHERE dda.admin_id  = ?
        AND dda.duty_type = ?
        AND dda.batch_no  = ?
      ORDER BY u.name
    `, [admin_id, duty_type, batch_no]);

    return ok(res, {
      dutyType:   row.duty_type  || "",
      batchNo:    row.batch_no,
      busNo:      row.bus_no     || "",
      note:       row.note       || "",
      district:   userDistrict,
      assignedAt: row.assigned_at ? String(row.assigned_at) : "",
      batchStaff,
    });
  } catch (e) {
    console.error("❌ /district-duty error:", e);
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ATTENDANCE — single
// ══════════════════════════════════════════════════════════════════════════════
router.post('/attendance', loginRequired, async (req, res) => {
  const uid = req.user.id;
  const { dutyId, attended = true } = req.body || {};

  if (!dutyId) return err(res, "dutyId required");

  try {
    const [roleType, sectorId] = await _detectRole(uid);
    if (roleType !== "sector")
      return err(res, "Only sector officers can mark attendance", 403);

    const valid = await query(`
      SELECT da.id FROM duty_assignments da
      JOIN matdan_sthal ms    ON ms.id  = da.sthal_id
      JOIN gram_panchayats gp ON gp.id  = ms.gram_panchayat_id
      WHERE da.id = ? AND gp.sector_id = ?
    `, [dutyId, sectorId]);

    if (!valid.length)
      return err(res, "This duty is not under your sector", 403);

    await query(
      `UPDATE duty_assignments SET attended = ? WHERE id = ?`,
      [attended ? 1 : 0, dutyId]
    );

    return ok(res, { dutyId, attended }, "Attendance marked");
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ATTENDANCE — bulk
// ══════════════════════════════════════════════════════════════════════════════
router.post('/attendance/bulk', loginRequired, async (req, res) => {
  const uid = req.user.id;
  const { updates = [] } = req.body || {};

  if (!updates.length) return err(res, "updates list required");

  try {
    const [roleType, sectorId] = await _detectRole(uid);
    if (roleType !== "sector")
      return err(res, "Only sector officers can mark attendance", 403);

    const dutyIds = updates.map(u => u.dutyId).filter(Boolean);
    if (!dutyIds.length) return err(res, "No valid dutyIds");

    const ph = dutyIds.map(() => '?').join(',');
    const validRows = await query(`
      SELECT da.id FROM duty_assignments da
      JOIN matdan_sthal ms    ON ms.id  = da.sthal_id
      JOIN gram_panchayats gp ON gp.id  = ms.gram_panchayat_id
      WHERE da.id IN (${ph}) AND gp.sector_id = ?
    `, [...dutyIds, sectorId]);

    const validIds = new Set(validRows.map(r => r.id));

    let updated = 0;
    for (const u of updates) {
      if (!validIds.has(u.dutyId)) continue;
      await query(
        `UPDATE duty_assignments SET attended = ? WHERE id = ?`,
        [u.attended ? 1 : 0, u.dutyId]
      );
      updated++;
    }

    return ok(res, { updated }, `${updated} attendance records updated`);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  CHANGE PASSWORD
// ══════════════════════════════════════════════════════════════════════════════
router.post('/change-password', loginRequired, async (req, res) => {
  try {
    const { currentPassword = "", newPassword = "" } = req.body || {};

    if (newPassword.length < 6)
      return err(res, "पासवर्ड कम से कम 6 अक्षर का होना चाहिए");

    const rows = await query(
      `SELECT password FROM users WHERE id = ?`,
      [req.user.id]
    );
    if (!rows.length) return err(res, "User not found", 404);

    if (hashPassword(currentPassword) !== rows[0].password)
      return err(res, "वर्तमान पासवर्ड गलत है", 401);

    await query(
      `UPDATE users SET password = ? WHERE id = ?`,
      [hashPassword(newPassword), req.user.id]
    );

    return ok(res, null, "पासवर्ड बदल दिया गया");
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  CURRENT DUTY
// ══════════════════════════════════════════════════════════════════════════════
router.get('/current-duty', loginRequired, async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        da.id           AS duty_id,
        da.attended,
        da.bus_no,
        ms.name         AS booth,
        ms.address,
        ms.thana,
        ms.center_type  AS center_type,
        gp.name         AS gram_panchayat,
        s.name          AS sector,
        z.name          AS zone,
        z.hq_address    AS zone_hq,
        sz.name         AS super_zone,
        sz.district     AS district,
        sz.block        AS block
      FROM duty_assignments da
      JOIN matdan_sthal ms    ON ms.id  = da.sthal_id
      JOIN gram_panchayats gp ON gp.id  = ms.gram_panchayat_id
      JOIN sectors s          ON s.id   = gp.sector_id
      JOIN zones z            ON z.id   = s.zone_id
      JOIN super_zones sz     ON sz.id  = z.super_zone_id
      WHERE da.staff_id = ?
      ORDER BY da.id DESC
      LIMIT 1
    `, [req.user.id]);

    if (!rows.length) return ok(res, null);

    const row = rows[0];
    const electionDate = await _getElectionDate();

    return ok(res, {
      dutyId:        row.duty_id,
      present:       Boolean(row.attended),
      date:          electionDate,
      busNo:         row.bus_no         || "",
      booth:         row.booth          || "",
      address:       row.address        || "",
      thana:         row.thana          || "",
      centerType:    row.center_type    || "",
      gramPanchayat: row.gram_panchayat || "",
      sector:        row.sector         || "",
      zone:          row.zone           || "",
      zoneHq:        row.zone_hq        || "",
      superZone:     row.super_zone     || "",
      district:      row.district       || "",
      block:         row.block          || "",
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY HISTORY — matches Flask: handles both booth AND district duties
// ══════════════════════════════════════════════════════════════════════════════
router.get('/history', loginRequired, async (req, res) => {
  try {
    // ── Booth duties ────────────────────────────────────────────────────────
    const boothRows = await query(`
      SELECT
        da.id           AS duty_id,
        da.attended,
        da.bus_no,
        da.sthal_id,
        ms.name         AS booth,
        ms.address,
        ms.thana,
        ms.center_type,
        gp.name         AS gram_panchayat,
        s.name          AS sector,
        z.name          AS zone,
        z.hq_address    AS zone_hq,
        sz.name         AS super_zone,
        sz.district,
        sz.block
      FROM duty_assignments da
      JOIN matdan_sthal ms    ON ms.id  = da.sthal_id
      JOIN gram_panchayats gp ON gp.id  = ms.gram_panchayat_id
      JOIN sectors s          ON s.id   = gp.sector_id
      JOIN zones z            ON z.id   = s.zone_id
      JOIN super_zones sz     ON sz.id  = z.super_zone_id
      WHERE da.staff_id = ?
      ORDER BY da.id DESC
    `, [req.user.id]);

    // Batch fetch staff per booth
    let boothStaff = {};
    if (boothRows.length) {
      const sthalIds = [...new Set(boothRows.map(r => r.sthal_id))];
      const ph = sthalIds.map(() => '?').join(',');
      const staffRows = await query(`
        SELECT da2.sthal_id,
               u.id, u.name, u.pno, u.user_rank
        FROM duty_assignments da2
        JOIN users u ON u.id = da2.staff_id
        WHERE da2.sthal_id IN (${ph})
        ORDER BY da2.sthal_id, u.name
      `, sthalIds);

      for (const sr of staffRows) {
        if (!boothStaff[sr.sthal_id]) boothStaff[sr.sthal_id] = [];
        boothStaff[sr.sthal_id].push({
          id:   sr.id,
          name: sr.name      || "",
          pno:  sr.pno       || "",
          rank: sr.user_rank || "",
        });
      }
    }

    // ── District duties — JOIN users to get district (matches Flask fix) ───
    const districtRows = await query(`
      SELECT
        dda.id         AS assignment_id,
        dda.duty_type  AS duty_type,
        dda.batch_no   AS batch_no,
        dda.bus_no     AS bus_no,
        dda.note       AS note,
        dda.admin_id   AS admin_id,
        dda.created_at AS assigned_at,
        u_s.district   AS district
      FROM district_duty_assignments dda
      JOIN users u_s ON u_s.id = dda.staff_id
      WHERE dda.staff_id = ?
      ORDER BY dda.id DESC
    `, [req.user.id]);

    // Batch fetch staff per district duty batch
    let districtStaff = {};
    if (districtRows.length) {
      const batchKeys = [...new Map(
        districtRows
          .filter(r => r.batch_no && r.admin_id)
          .map(r => [`${r.admin_id}::${r.duty_type}::${r.batch_no}`, r])
      ).values()];

      for (const r of batchKeys) {
        const key = `${r.admin_id}::${r.duty_type}::${r.batch_no}`;
        const staff = await query(`
          SELECT u.id, u.name, u.pno, u.user_rank AS rank
          FROM district_duty_assignments dda
          JOIN users u ON u.id = dda.staff_id
          WHERE dda.admin_id  = ?
            AND dda.duty_type = ?
            AND dda.batch_no  = ?
          ORDER BY u.name
        `, [r.admin_id, r.duty_type, r.batch_no]);
        districtStaff[key] = staff;
      }
    }

    const electionDate = await _getElectionDate();
    const results = [];

    for (const r of boothRows) {
      results.push({
        dutyKind:      "booth",
        dutyId:        r.duty_id,
        present:       Boolean(r.attended),
        date:          electionDate,
        busNo:         r.bus_no         || "",
        booth:         r.booth          || "",
        address:       r.address        || "",
        thana:         r.thana          || "",
        centerType:    r.center_type    || "",
        gramPanchayat: r.gram_panchayat || "",
        sector:        r.sector         || "",
        zone:          r.zone           || "",
        zoneHq:        r.zone_hq        || "",
        superZone:     r.super_zone     || "",
        district:      r.district       || "",
        block:         r.block          || "",
        assignedStaff: boothStaff[r.sthal_id] || [],
      });
    }

    for (const r of districtRows) {
      const key = `${r.admin_id}::${r.duty_type}::${r.batch_no}`;
      results.push({
        dutyKind:      "district",
        dutyId:        r.assignment_id,
        present:       null,
        date:          electionDate,
        dutyType:      r.duty_type  || "",
        batchNo:       r.batch_no,
        busNo:         r.bus_no     || "",
        note:          r.note       || "",
        district:      r.district   || "",
        assignedAt:    r.assigned_at ? String(r.assigned_at) : "",
        batchStaff:    districtStaff[key] || [],
        // Empty fields for shape consistency with booth entries
        booth: "", address: "", thana: "", centerType: "",
        gramPanchayat: "", sector: "", zone: "",
        zoneHq: "", superZone: "", block: "",
        assignedStaff: [],
      });
    }

    return ok(res, results);
  } catch (e) {
    console.error("❌ /history error:", e);
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ELECTION DATE (legacy)
// ══════════════════════════════════════════════════════════════════════════════
router.get('/election-date', loginRequired, async (req, res) => {
  try {
    const district = req.query.district || null;
    const date = await _getElectionDate(district);
    return ok(res, date);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

module.exports = router;