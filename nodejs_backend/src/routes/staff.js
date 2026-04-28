
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
//  _getElectionDate
// ─────────────────────────────────────────────────────────────────────────────
async function _getElectionDate() {
  try {
    const rows = await query(`
      SELECT value FROM app_config WHERE \`key\` = 'electiondate' LIMIT 1
    `);
    return rows.length ? rows[0].value : null;
  } catch (e) {
    console.error("❌ electiondate fetch error:", e);
    return null;
  }
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
      name:     row.name     || "",
      pno:      row.pno      || "",
      mobile:   row.mobile   || "",
      thana:    row.thana    || "",
      district: row.district || "",
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

    if (roleType === "booth")    return ok(res, await _boothDuty(req.user.id));
    if (roleType === "sector")   return ok(res, await _sectorDuty(req.user.id, entityId));
    if (roleType === "zone")     return ok(res, await _zoneDuty(req.user.id, entityId));
    if (roleType === "kshetra")  return ok(res, await _kshetraDuty(req.user.id, entityId));

    return ok(res, null, "No duty assigned yet");
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
//  BOOTH DUTY
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
  `, [uid]);

  const row = rows[0];
  if (!row) return null;

  const [allStaff, sectorOfficers, zonalOfficers, superOfficers, rules] = await Promise.all([
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

    query(`
      SELECT user_rank AS \`rank\`, is_armed, required_count AS count
      FROM booth_staff_rules bsr
      JOIN super_zones sz ON sz.id = ?
      WHERE bsr.admin_id = sz.admin_id AND bsr.sensitivity = ?
      LIMIT 20
    `, [row.super_zone_id, row.center_type]),
  ]);

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
    boothRules:    rules,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
//  SECTOR DUTY
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

    query(`
      SELECT sensitivity, user_rank AS \`rank\`, is_armed, required_count AS count
      FROM booth_staff_rules
      WHERE admin_id = (
        SELECT admin_id FROM super_zones WHERE id = ? LIMIT 1
      )
      ORDER BY FIELD(sensitivity, 'A++', 'A', 'B', 'C'), id
    `, [sec.super_zone_id]),
  ]);

  const gp_ids = gps.map(g => g.id);
  let centersList = [];
  let totalBooths = 0;
  let totalAssigned = 0;

  if (gp_ids.length) {
    const ph = gp_ids.map(() => '?').join(',');

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
    `, gp_ids);

    totalBooths = centers.length;
    const center_ids = centers.map(c => c.id);

    let staffByCenter = {};
    if (center_ids.length) {
      const ph2 = center_ids.map(() => '?').join(',');
      const staffRows = await query(`
        SELECT da.sthal_id, da.id AS duty_id,
               u.id AS staff_id, u.name, u.pno, u.mobile,
               u.user_rank, u.is_armed, u.thana, u.district,
               da.attended
        FROM duty_assignments da
        JOIN users u ON u.id = da.staff_id
        WHERE da.sthal_id IN (${ph2})
        ORDER BY u.name
      `, center_ids);

      for (const r of staffRows) {
        if (!staffByCenter[r.sthal_id]) staffByCenter[r.sthal_id] = [];
        staffByCenter[r.sthal_id].push(r);
        totalAssigned++;
      }
    }

    centersList = centers.map(c => ({
      ...c,
      staff: staffByCenter[c.id] || [],
    }));
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
//  ZONE DUTY
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
              JOIN matdan_sthal ms2  ON ms2.id  = da.sthal_id
              JOIN gram_panchayats gp2 ON gp2.id = ms2.gram_panchayat_id
              WHERE gp2.sector_id = s.id) AS staff_assigned
      FROM sectors s
      LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
      LEFT JOIN matdan_sthal ms    ON ms.gram_panchayat_id = gp.id
      WHERE s.zone_id = ?
      GROUP BY s.id
      ORDER BY s.name
    `, [zoneId]),

    query(`
      SELECT sensitivity, user_rank AS \`rank\`, is_armed, required_count AS count
      FROM booth_staff_rules
      WHERE admin_id = (SELECT admin_id FROM super_zones WHERE id = ? LIMIT 1)
      ORDER BY FIELD(sensitivity, 'A++', 'A', 'B', 'C'), id
    `, [zone.super_zone_id]),
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

  let totalBooths = 0;
  let totalAssigned = 0;
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
//  KSHETRA (SUPER ZONE) DUTY
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
      LEFT JOIN sectors s          ON s.zone_id         = z.id
      LEFT JOIN gram_panchayats gp ON gp.sector_id       = s.id
      LEFT JOIN matdan_sthal ms    ON ms.gram_panchayat_id = gp.id
      WHERE z.super_zone_id = ?
      GROUP BY z.id
      ORDER BY z.name
    `, [superZoneId]),

    query(`
      SELECT sensitivity, user_rank AS \`rank\`, is_armed, required_count AS count
      FROM booth_staff_rules
      WHERE admin_id = (SELECT admin_id FROM super_zones WHERE id = ? LIMIT 1)
      ORDER BY FIELD(sensitivity, 'A++', 'A', 'B', 'C'), id
    `, [superZoneId]),
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
        da.election_date,
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
      busNo:         row.bus_no        || "",
      booth:         row.booth         || "",
      address:       row.address       || "",
      thana:         row.thana         || "",
      centerType:    row.center_type   || "",
      gramPanchayat: row.gram_panchayat || "",
      sector:        row.sector        || "",
      zone:          row.zone          || "",
      zoneHq:        row.zone_hq       || "",
      superZone:     row.super_zone    || "",
      district:      row.district      || "",
      block:         row.block         || "",
    });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY HISTORY
// ══════════════════════════════════════════════════════════════════════════════
router.get('/history', loginRequired, async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        da.id           AS duty_id,
        da.attended,
        da.election_date,
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
      ORDER BY da.election_date DESC, da.id DESC
    `, [req.user.id]);

    if (!rows.length) return ok(res, []);

    // Batch fetch all staff per booth
    const sthalIds = [...new Set(rows.map(r => r.sthal_id))];
    const ph = sthalIds.map(() => '?').join(',');
    const staffRows = await query(`
      SELECT da2.sthal_id,
             u.id, u.name, u.pno, u.user_rank
      FROM duty_assignments da2
      JOIN users u ON u.id = da2.staff_id
      WHERE da2.sthal_id IN (${ph})
      ORDER BY da2.sthal_id, u.name
    `, sthalIds);

    const boothStaff = {};
    for (const sr of staffRows) {
      if (!boothStaff[sr.sthal_id]) boothStaff[sr.sthal_id] = [];
      boothStaff[sr.sthal_id].push({
        id:   sr.id,
        name: sr.name      || "",
        pno:  sr.pno       || "",
        rank: sr.user_rank || "",
      });
    }

    const electionDate = await _getElectionDate();

    return ok(res, rows.map(r => ({
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
    })));
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
//  ELECTION DATE
// ══════════════════════════════════════════════════════════════════════════════
router.get('/election-date', loginRequired, async (req, res) => {
  try {
    const date = await _getElectionDate();
    return ok(res, date);
  } catch (e) {
    return err(res, e.message, 500);
  }
});

module.exports = router;