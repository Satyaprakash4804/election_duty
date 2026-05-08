from flask import Blueprint, request
from db import get_db
from app.routes import ok, err, login_required
import hashlib

staff_bp = Blueprint("staff", __name__, url_prefix="/api/staff")

SALT = "election_2026_secure_key"


def _get_election_date(district=None):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            if district:
                cur.execute("""
                    SELECT election_date
                    FROM election_configs
                    WHERE district = %s
                      AND is_active = 1
                      AND is_archived = 0
                    ORDER BY id DESC LIMIT 1
                """, (district,))
            else:
                cur.execute("""
                    SELECT election_date
                    FROM election_configs
                    WHERE is_active = 1
                      AND is_archived = 0
                    ORDER BY id DESC LIMIT 1
                """)
            row = cur.fetchone()
            return row["election_date"] if row else None
    except Exception as e:
        print("❌ election_date fetch error:", e)
        return None
    finally:
        conn.close()


def _get_booth_rules_for_super_zone(cur, super_zone_id: int) -> list:
    """
    Fetch all booth_rules for the admin of this super_zone and expand
    columnar counts into per-rank rows for the Flutter _RulesSection widget.
    """
    cur.execute(
        "SELECT admin_id FROM super_zones WHERE id = %s LIMIT 1",
        (super_zone_id,))
    sz = cur.fetchone()
    if not sz or not sz["admin_id"]:
        return []

    admin_id = sz["admin_id"]

    cur.execute("""
        SELECT sensitivity,
               si_armed_count,    si_unarmed_count,
               hc_armed_count,    hc_unarmed_count,
               const_armed_count, const_unarmed_count,
               aux_armed_count,   aux_unarmed_count
        FROM booth_rules
        WHERE admin_id = %s
        GROUP BY sensitivity,
                 si_armed_count,    si_unarmed_count,
                 hc_armed_count,    hc_unarmed_count,
                 const_armed_count, const_unarmed_count,
                 aux_armed_count,   aux_unarmed_count
        ORDER BY FIELD(sensitivity,'A++','A','B','C')
    """, (admin_id,))
    rule_rows = cur.fetchall()

    results = []
    rank_cols = [
        ("SI",             "si_armed_count",    "si_unarmed_count"),
        ("Head Constable", "hc_armed_count",    "hc_unarmed_count"),
        ("Constable",      "const_armed_count", "const_unarmed_count"),
        ("Home Guard",     "aux_armed_count",   "aux_unarmed_count"),
    ]
    for r in rule_rows:
        sens = r["sensitivity"]
        for rank, ac, uc in rank_cols:
            if (r.get(ac) or 0) > 0:
                results.append({"sensitivity": sens, "rank": rank,
                                 "is_armed": 1, "count": r[ac]})
            if (r.get(uc) or 0) > 0:
                results.append({"sensitivity": sens, "rank": rank,
                                 "is_armed": 0, "count": r[uc]})
    return results


def _get_booth_rules(cur, super_zone_id: int,
                     sensitivity: str, center_id: int) -> list:
    """
    For booth duty: find the closest-matching booth_rules row for this
    center's booth_count and sensitivity, then expand to per-rank rows.
    """
    cur.execute(
        "SELECT booth_count FROM matdan_sthal WHERE id = %s", (center_id,))
    ms = cur.fetchone()
    booth_count = ms["booth_count"] if ms else 1

    cur.execute(
        "SELECT admin_id FROM super_zones WHERE id = %s LIMIT 1",
        (super_zone_id,))
    sz = cur.fetchone()
    if not sz or not sz["admin_id"]:
        return []

    admin_id = sz["admin_id"]

    cur.execute("""
        SELECT * FROM booth_rules
        WHERE admin_id = %s AND sensitivity = %s
        ORDER BY ABS(booth_count - %s), booth_count
        LIMIT 1
    """, (admin_id, sensitivity, booth_count))
    rule = cur.fetchone()
    if not rule:
        return []

    rows = []
    rank_cols = [
        ("SI",             "si_armed_count",    "si_unarmed_count"),
        ("Head Constable", "hc_armed_count",    "hc_unarmed_count"),
        ("Constable",      "const_armed_count", "const_unarmed_count"),
        ("Home Guard",     "aux_armed_count",   "aux_unarmed_count"),
    ]
    for rank, ac, uc in rank_cols:
        armed_cnt   = rule.get(ac, 0) or 0
        unarmed_cnt = rule.get(uc, 0) or 0
        if armed_cnt > 0:
            rows.append({"sensitivity": sensitivity, "rank": rank,
                          "is_armed": 1, "count": armed_cnt})
        if unarmed_cnt > 0:
            rows.append({"sensitivity": sensitivity, "rank": rank,
                          "is_armed": 0, "count": unarmed_cnt})
    return rows


# ══════════════════════════════════════════════════════════════════════════════
#  PROFILE
# ══════════════════════════════════════════════════════════════════════════════
@staff_bp.route("/profile", methods=["GET"])
@login_required
def my_profile():
    uid = request.user["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, name, pno, mobile, thana, district,
                       user_rank, is_active, is_armed
                FROM users WHERE id = %s
            """, (uid,))
            row = cur.fetchone()
    finally:
        conn.close()
    if not row:
        return err("User not found", 404)
    return ok({
        "id":       row["id"],
        "name":     row["name"]      or "",
        "pno":      row["pno"]       or "",
        "mobile":   row["mobile"]    or "",
        "thana":    row["thana"]     or "",
        "district": row["district"]  or "",
        "rank":     row["user_rank"] or "",
        "isArmed":  bool(row["is_armed"]),
        "isActive": bool(row["is_active"]),
    })


@staff_bp.route("/mark-card-downloaded", methods=["POST"])
@login_required
def mark_card_downloaded():
    uid = request.user["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE duty_assignments
                SET card_downloaded = 1
                WHERE staff_id = %s
            """, (uid,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Card marked as downloaded")


# ══════════════════════════════════════════════════════════════════════════════
#  DETECT ROLE
# ══════════════════════════════════════════════════════════════════════════════
def _detect_role(cur, uid: int) -> tuple[str, int | None]:
    cur.execute(
        "SELECT id, sector_id FROM sector_officers WHERE user_id=%s LIMIT 1",
        (uid,))
    r = cur.fetchone()
    if r:
        return "sector", r["sector_id"]

    cur.execute(
        "SELECT id, zone_id FROM zonal_officers WHERE user_id=%s LIMIT 1",
        (uid,))
    r = cur.fetchone()
    if r:
        return "zone", r["zone_id"]

    cur.execute(
        "SELECT id, super_zone_id FROM kshetra_officers WHERE user_id=%s LIMIT 1",
        (uid,))
    r = cur.fetchone()
    if r:
        return "kshetra", r["super_zone_id"]

    cur.execute(
        "SELECT id FROM duty_assignments WHERE staff_id=%s LIMIT 1",
        (uid,))
    r = cur.fetchone()
    if r:
        return "booth", None

    return "none", None


# ══════════════════════════════════════════════════════════════════════════════
#  MY DUTY
# ══════════════════════════════════════════════════════════════════════════════
@staff_bp.route("/my-duty", methods=["GET"])
@login_required
def my_duty():
    uid  = request.user["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            role_type, entity_id = _detect_role(cur, uid)
            if role_type == "booth":
                data = _booth_duty(cur, uid)
            elif role_type == "sector":
                data = _sector_duty(cur, uid, entity_id)
            elif role_type == "zone":
                data = _zone_duty(cur, uid, entity_id)
            elif role_type == "kshetra":
                data = _kshetra_duty(cur, uid, entity_id)
            else:
                return ok(None, "No duty assigned yet")
    except Exception as e:
        import traceback
        print("❌ /my-duty error:", traceback.format_exc())
        return err(f"Server error: {e}", 500)
    finally:
        conn.close()
    return ok(data)


# ══════════════════════════════════════════════════════════════════════════════
#  BOOTH DUTY
# ══════════════════════════════════════════════════════════════════════════════
def _booth_duty(cur, uid: int) -> dict:
    cur.execute("""
        SELECT
            da.id            AS duty_id,
            da.bus_no,
            ms.id            AS center_id,
            ms.name          AS center_name,
            ms.address       AS center_address,
            ms.thana,
            ms.center_type,
            ms.latitude,
            ms.longitude,
            gp.id            AS gp_id,
            gp.name          AS gp_name,
            gp.address       AS gp_address,
            s.id             AS sector_id,
            s.name           AS sector_name,
            z.id             AS zone_id,
            z.name           AS zone_name,
            z.hq_address     AS zone_hq,
            sz.id            AS super_zone_id,
            sz.name          AS super_zone_name,
            u2.name          AS assigned_by_name
        FROM duty_assignments da
        JOIN matdan_sthal ms    ON ms.id = da.sthal_id
        JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
        JOIN sectors s          ON s.id  = gp.sector_id
        JOIN zones z            ON z.id  = s.zone_id
        JOIN super_zones sz     ON sz.id = z.super_zone_id
        LEFT JOIN users u2      ON u2.id = da.assigned_by
        WHERE da.staff_id = %s
        LIMIT 1
    """, (uid,))
    row = cur.fetchone()
    if not row:
        return None

    cur.execute("""
        SELECT u.name, u.pno, u.mobile, u.thana, u.district,
               u.user_rank, u.is_armed
        FROM duty_assignments da2
        JOIN users u ON u.id = da2.staff_id
        WHERE da2.sthal_id = %s
        ORDER BY u.name
    """, (row["center_id"],))
    all_staff = cur.fetchall()

    cur.execute("""
        SELECT COALESCE(u.name, so.name)           AS name,
               COALESCE(u.pno, so.pno)             AS pno,
               COALESCE(u.mobile, so.mobile)       AS mobile,
               COALESCE(u.user_rank, so.user_rank) AS user_rank
        FROM sector_officers so
        LEFT JOIN users u ON u.id = so.user_id
        WHERE so.sector_id = %s
    """, (row["sector_id"],))
    sector_officers = cur.fetchall()

    cur.execute("""
        SELECT COALESCE(u.name, zo.name)           AS name,
               COALESCE(u.pno, zo.pno)             AS pno,
               COALESCE(u.mobile, zo.mobile)       AS mobile,
               COALESCE(u.user_rank, zo.user_rank) AS user_rank
        FROM zonal_officers zo
        LEFT JOIN users u ON u.id = zo.user_id
        WHERE zo.zone_id = %s
    """, (row["zone_id"],))
    zonal_officers = cur.fetchall()

    cur.execute("""
        SELECT COALESCE(u.name, ko.name)           AS name,
               COALESCE(u.pno, ko.pno)             AS pno,
               COALESCE(u.mobile, ko.mobile)       AS mobile,
               COALESCE(u.user_rank, ko.user_rank) AS user_rank
        FROM kshetra_officers ko
        LEFT JOIN users u ON u.id = ko.user_id
        WHERE ko.super_zone_id = %s
    """, (row["super_zone_id"],))
    super_officers = cur.fetchall()

    rules = _get_booth_rules(
        cur, row["super_zone_id"], row["center_type"], row["center_id"])

    return {
        "roleType":       "booth",
        "dutyId":         row["duty_id"],
        "busNo":          row["bus_no"] or "",
        "centerId":       row["center_id"],
        "centerName":     row["center_name"] or "",
        "centerAddress":  row["center_address"] or "",
        "thana":          row["thana"] or "",
        "centerType":     row["center_type"] or "",
        "latitude":       float(row["latitude"])  if row["latitude"]  else None,
        "longitude":      float(row["longitude"]) if row["longitude"] else None,
        "gpName":         row["gp_name"] or "",
        "gpAddress":      row["gp_address"] or "",
        "sectorName":     row["sector_name"] or "",
        "zoneName":       row["zone_name"] or "",
        "zoneHq":         row["zone_hq"] or "",
        "superZoneName":  row["super_zone_name"] or "",
        "assignedBy":     row["assigned_by_name"] or "",
        "allStaff":       [dict(s) for s in all_staff],
        "sectorOfficers": [dict(s) for s in sector_officers],
        "zonalOfficers":  [dict(s) for s in zonal_officers],
        "superOfficers":  [dict(s) for s in super_officers],
        "boothRules":     rules,
    }


# ══════════════════════════════════════════════════════════════════════════════
#  SECTOR DUTY
# ══════════════════════════════════════════════════════════════════════════════
def _sector_duty(cur, uid: int, sector_id: int) -> dict:
    cur.execute("""
        SELECT s.id, s.name, s.hq_address,
               z.id   AS zone_id,       z.name AS zone_name,
               sz.id  AS super_zone_id, sz.name AS super_zone_name
        FROM sectors s
        JOIN zones z        ON z.id  = s.zone_id
        JOIN super_zones sz ON sz.id = z.super_zone_id
        WHERE s.id = %s
    """, (sector_id,))
    sec = cur.fetchone()
    if not sec:
        return {"roleType": "sector", "error": "Sector not found"}

    cur.execute("""
        SELECT COALESCE(u.name, so.name)           AS name,
               COALESCE(u.pno, so.pno)             AS pno,
               COALESCE(u.mobile, so.mobile)       AS mobile,
               COALESCE(u.user_rank, so.user_rank) AS user_rank
        FROM sector_officers so
        LEFT JOIN users u ON u.id = so.user_id
        WHERE so.sector_id = %s
    """, (sector_id,))
    co_officers = cur.fetchall()

    cur.execute("""
        SELECT COALESCE(u.name, zo.name)           AS name,
               COALESCE(u.pno, zo.pno)             AS pno,
               COALESCE(u.mobile, zo.mobile)       AS mobile,
               COALESCE(u.user_rank, zo.user_rank) AS user_rank
        FROM zonal_officers zo
        LEFT JOIN users u ON u.id = zo.user_id
        WHERE zo.zone_id = %s
    """, (sec["zone_id"],))
    zonal_officers = cur.fetchall()

    cur.execute("""
        SELECT gp.id, gp.name, gp.address
        FROM gram_panchayats gp
        WHERE gp.sector_id = %s
        ORDER BY gp.name
    """, (sector_id,))
    gps = cur.fetchall()

    gp_ids         = [g["id"] for g in gps]
    centers_list   = []
    total_booths   = 0
    total_assigned = 0

    if gp_ids:
        ph = ",".join(["%s"] * len(gp_ids))
        cur.execute(f"""
            SELECT ms.id, ms.name, ms.thana, ms.center_type,
                   ms.latitude, ms.longitude, ms.bus_no,
                   ms.gram_panchayat_id,
                   gp.name AS gp_name,
                   (SELECT COUNT(*) FROM duty_assignments da
                    WHERE da.sthal_id = ms.id) AS staff_count
            FROM matdan_sthal ms
            JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
            WHERE ms.gram_panchayat_id IN ({ph})
            ORDER BY gp.name, ms.name
        """, gp_ids)
        centers    = cur.fetchall()
        total_booths = len(centers)
        center_ids   = [c["id"] for c in centers]

        staff_by_center = {}
        if center_ids:
            ph2 = ",".join(["%s"] * len(center_ids))
            cur.execute(f"""
                SELECT da.sthal_id, da.id AS duty_id,
                       u.id AS staff_id, u.name, u.pno, u.mobile,
                       u.user_rank, u.is_armed, u.thana, u.district,
                       da.attended
                FROM duty_assignments da
                JOIN users u ON u.id = da.staff_id
                WHERE da.sthal_id IN ({ph2})
                ORDER BY u.name
            """, center_ids)
            for row in cur.fetchall():
                staff_by_center.setdefault(row["sthal_id"], []).append(dict(row))
                total_assigned += 1

        for c in centers:
            centers_list.append({
                **dict(c),
                "staff": staff_by_center.get(c["id"], []),
            })

    rules = _get_booth_rules_for_super_zone(cur, sec["super_zone_id"])

    return {
        "roleType":       "sector",
        "sectorId":       sec["id"],
        "sectorName":     sec["name"] or "",
        "hqAddress":      sec["hq_address"] or "",
        "zoneId":         sec["zone_id"],
        "zoneName":       sec["zone_name"] or "",
        "superZoneId":    sec["super_zone_id"],
        "superZoneName":  sec["super_zone_name"] or "",
        "coOfficers":     [dict(o) for o in co_officers],
        "zonalOfficers":  [dict(o) for o in zonal_officers],
        "gramPanchayats": [dict(g) for g in gps],
        "centers":        centers_list,
        "totalBooths":    total_booths,
        "totalAssigned":  total_assigned,
        "boothRules":     rules,
    }


# ══════════════════════════════════════════════════════════════════════════════
#  ZONE DUTY
# ══════════════════════════════════════════════════════════════════════════════
def _zone_duty(cur, uid: int, zone_id: int) -> dict:
    cur.execute("""
        SELECT z.id, z.name, z.hq_address,
               sz.id AS super_zone_id, sz.name AS super_zone_name
        FROM zones z
        JOIN super_zones sz ON sz.id = z.super_zone_id
        WHERE z.id = %s
    """, (zone_id,))
    zone = cur.fetchone()
    if not zone:
        return {"roleType": "zone", "error": "Zone not found"}

    cur.execute("""
        SELECT COALESCE(u.name, zo.name)           AS name,
               COALESCE(u.pno, zo.pno)             AS pno,
               COALESCE(u.mobile, zo.mobile)       AS mobile,
               COALESCE(u.user_rank, zo.user_rank) AS user_rank
        FROM zonal_officers zo
        LEFT JOIN users u ON u.id = zo.user_id
        WHERE zo.zone_id = %s
    """, (zone_id,))
    co_officers = cur.fetchall()

    cur.execute("""
        SELECT COALESCE(u.name, ko.name)           AS name,
               COALESCE(u.pno, ko.pno)             AS pno,
               COALESCE(u.mobile, ko.mobile)       AS mobile,
               COALESCE(u.user_rank, ko.user_rank) AS user_rank
        FROM kshetra_officers ko
        LEFT JOIN users u ON u.id = ko.user_id
        WHERE ko.super_zone_id = %s
    """, (zone["super_zone_id"],))
    super_officers = cur.fetchall()

    cur.execute("""
        SELECT s.id, s.name, s.hq_address,
               COUNT(DISTINCT gp.id) AS gp_count,
               COUNT(DISTINCT ms.id) AS center_count,
               (SELECT COUNT(*) FROM duty_assignments da
                JOIN matdan_sthal ms2 ON ms2.id = da.sthal_id
                JOIN gram_panchayats gp2 ON gp2.id = ms2.gram_panchayat_id
                WHERE gp2.sector_id = s.id) AS staff_assigned
        FROM sectors s
        LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
        LEFT JOIN matdan_sthal ms ON ms.gram_panchayat_id = gp.id
        WHERE s.zone_id = %s
        GROUP BY s.id
        ORDER BY s.name
    """, (zone_id,))
    sectors = cur.fetchall()

    sector_ids = [s["id"] for s in sectors]
    officers_by_sector = {}
    if sector_ids:
        ph = ",".join(["%s"] * len(sector_ids))
        cur.execute(f"""
            SELECT so.sector_id,
                   COALESCE(u.name, so.name)           AS name,
                   COALESCE(u.pno, so.pno)             AS pno,
                   COALESCE(u.mobile, so.mobile)       AS mobile,
                   COALESCE(u.user_rank, so.user_rank) AS user_rank
            FROM sector_officers so
            LEFT JOIN users u ON u.id = so.user_id
            WHERE so.sector_id IN ({ph})
        """, sector_ids)
        for row in cur.fetchall():
            officers_by_sector.setdefault(row["sector_id"], []).append(dict(row))

    sectors_data   = []
    total_booths   = 0
    total_assigned = 0
    for s in sectors:
        total_booths   += s["center_count"]   or 0
        total_assigned += s["staff_assigned"] or 0
        sectors_data.append({
            **dict(s),
            "officers": officers_by_sector.get(s["id"], []),
        })

    rules = _get_booth_rules_for_super_zone(cur, zone["super_zone_id"])

    return {
        "roleType":      "zone",
        "zoneId":        zone["id"],
        "zoneName":      zone["name"] or "",
        "hqAddress":     zone["hq_address"] or "",
        "superZoneId":   zone["super_zone_id"],
        "superZoneName": zone["super_zone_name"] or "",
        "coOfficers":    [dict(o) for o in co_officers],
        "superOfficers": [dict(o) for o in super_officers],
        "sectors":       sectors_data,
        "totalSectors":  len(sectors_data),
        "totalBooths":   total_booths,
        "totalAssigned": total_assigned,
        "boothRules":    rules,
    }


# ══════════════════════════════════════════════════════════════════════════════
#  KSHETRA DUTY
# ══════════════════════════════════════════════════════════════════════════════
def _kshetra_duty(cur, uid: int, super_zone_id: int) -> dict:
    cur.execute("""
        SELECT id, name, district, block
        FROM super_zones WHERE id = %s
    """, (super_zone_id,))
    sz = cur.fetchone()
    if not sz:
        return {"roleType": "kshetra", "error": "Super zone not found"}

    cur.execute("""
        SELECT COALESCE(u.name, ko.name)           AS name,
               COALESCE(u.pno, ko.pno)             AS pno,
               COALESCE(u.mobile, ko.mobile)       AS mobile,
               COALESCE(u.user_rank, ko.user_rank) AS user_rank
        FROM kshetra_officers ko
        LEFT JOIN users u ON u.id = ko.user_id
        WHERE ko.super_zone_id = %s
    """, (super_zone_id,))
    co_officers = cur.fetchall()

    cur.execute("""
        SELECT z.id, z.name, z.hq_address,
               COUNT(DISTINCT s.id)  AS sector_count,
               COUNT(DISTINCT gp.id) AS gp_count,
               COUNT(DISTINCT ms.id) AS center_count,
               (SELECT COUNT(*) FROM duty_assignments da
                JOIN matdan_sthal ms2 ON ms2.id = da.sthal_id
                JOIN gram_panchayats gp2 ON gp2.id = ms2.gram_panchayat_id
                JOIN sectors s2 ON s2.id = gp2.sector_id
                WHERE s2.zone_id = z.id) AS staff_assigned
        FROM zones z
        LEFT JOIN sectors s ON s.zone_id = z.id
        LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
        LEFT JOIN matdan_sthal ms ON ms.gram_panchayat_id = gp.id
        WHERE z.super_zone_id = %s
        GROUP BY z.id
        ORDER BY z.name
    """, (super_zone_id,))
    zones = cur.fetchall()

    zone_ids = [z["id"] for z in zones]
    officers_by_zone = {}
    if zone_ids:
        ph = ",".join(["%s"] * len(zone_ids))
        cur.execute(f"""
            SELECT zo.zone_id,
                   COALESCE(u.name, zo.name)           AS name,
                   COALESCE(u.pno, zo.pno)             AS pno,
                   COALESCE(u.mobile, zo.mobile)       AS mobile,
                   COALESCE(u.user_rank, zo.user_rank) AS user_rank
            FROM zonal_officers zo
            LEFT JOIN users u ON u.id = zo.user_id
            WHERE zo.zone_id IN ({ph})
        """, zone_ids)
        for row in cur.fetchall():
            officers_by_zone.setdefault(row["zone_id"], []).append(dict(row))

    zones_data     = []
    total_zones    = 0
    total_sectors  = 0
    total_booths   = 0
    total_assigned = 0
    for z in zones:
        total_zones    += 1
        total_sectors  += z["sector_count"]   or 0
        total_booths   += z["center_count"]   or 0
        total_assigned += z["staff_assigned"] or 0
        zones_data.append({
            **dict(z),
            "officers": officers_by_zone.get(z["id"], []),
        })

    rules = _get_booth_rules_for_super_zone(cur, super_zone_id)

    return {
        "roleType":      "kshetra",
        "superZoneId":   sz["id"],
        "superZoneName": sz["name"] or "",
        "district":      sz["district"] or "",
        "block":         sz["block"] or "",
        "coOfficers":    [dict(o) for o in co_officers],
        "zones":         zones_data,
        "totalZones":    total_zones,
        "totalSectors":  total_sectors,
        "totalBooths":   total_booths,
        "totalAssigned": total_assigned,
        "boothRules":    rules,
    }


# ══════════════════════════════════════════════════════════════════════════════
#  ELECTION CONFIG
# ══════════════════════════════════════════════════════════════════════════════
@staff_bp.route("/election-config", methods=["GET"])
@login_required
def get_election_config():
    uid = request.user["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT district FROM users WHERE id = %s", (uid,))
            user_row = cur.fetchone()
            district = user_row["district"] if user_row else None

            row = None
            if district:
                cur.execute("""
                    SELECT id, election_name, election_type, phase,
                           election_date, pratah_samay, saya_samay,
                           district, is_active
                    FROM election_configs
                    WHERE district = %s
                      AND is_active = 1
                      AND is_archived = 0
                    ORDER BY id DESC LIMIT 1
                """, (district,))
                row = cur.fetchone()

            if not row:
                cur.execute("""
                    SELECT id, election_name, election_type, phase,
                           election_date, pratah_samay, saya_samay,
                           district, is_active
                    FROM election_configs
                    WHERE is_active = 1
                      AND is_archived = 0
                    ORDER BY id DESC LIMIT 1
                """)
                row = cur.fetchone()
    except Exception as e:
        import traceback
        print("❌ /election-config error:", traceback.format_exc())
        return err(f"Server error: {e}", 500)
    finally:
        conn.close()

    if not row:
        return ok(None)

    return ok({
        "id":            row["id"],
        "election_name": row["election_name"] or "",
        "election_type": row["election_type"] or "",
        "phase":         str(row["phase"])         if row["phase"]         else "",
        "election_date": str(row["election_date"]) if row["election_date"] else None,
        "pratah_samay":  str(row["pratah_samay"])  if row["pratah_samay"]  else "",
        "saya_samay":    str(row["saya_samay"])    if row["saya_samay"]    else "",
        "district":      row["district"] or "",
    })


# ══════════════════════════════════════════════════════════════════════════════
#  DISTRICT DUTY
# ══════════════════════════════════════════════════════════════════════════════
@staff_bp.route("/district-duty", methods=["GET"])
@login_required
def get_district_duty():
    uid = request.user["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT district FROM users WHERE id = %s", (uid,))
            user_row = cur.fetchone()
            user_district = user_row["district"] if user_row else ""

            cur.execute("""
                SELECT
                    dda.id         AS assignment_id,
                    dda.duty_type  AS duty_type,
                    dda.batch_no   AS batch_no,
                    dda.bus_no     AS bus_no,
                    dda.note       AS note,
                    dda.admin_id   AS admin_id,
                    dda.created_at AS assigned_at
                FROM district_duty_assignments dda
                WHERE dda.staff_id = %s
                ORDER BY dda.id DESC
                LIMIT 1
            """, (uid,))
            row = cur.fetchone()

            if not row:
                return ok(None)

            batch_no  = row["batch_no"]
            admin_id  = row["admin_id"]
            duty_type = row["duty_type"]

            cur.execute("""
                SELECT u.id, u.name, u.pno, u.mobile,
                       u.user_rank, u.thana, u.district, u.is_armed
                FROM district_duty_assignments dda
                JOIN users u ON u.id = dda.staff_id
                WHERE dda.admin_id  = %s
                  AND dda.duty_type = %s
                  AND dda.batch_no  = %s
                ORDER BY u.name
            """, (admin_id, duty_type, batch_no))
            batch_staff = cur.fetchall()

    except Exception as e:
        import traceback
        print("❌ /district-duty error:", traceback.format_exc())
        return err(f"Server error: {e}", 500)
    finally:
        conn.close()

    return ok({
        "dutyType":   row["duty_type"]  or "",
        "batchNo":    row["batch_no"],
        "busNo":      row["bus_no"]     or "",
        "note":       row["note"]       or "",
        "district":   user_district,
        "assignedAt": str(row["assigned_at"]) if row["assigned_at"] else "",
        "batchStaff": [dict(s) for s in batch_staff],
    })


# ══════════════════════════════════════════════════════════════════════════════
#  ATTENDANCE
# ══════════════════════════════════════════════════════════════════════════════
@staff_bp.route("/attendance", methods=["POST"])
@login_required
def mark_attendance():
    uid  = request.user["id"]
    body = request.get_json() or {}
    duty_id  = body.get("dutyId")
    attended = body.get("attended", True)

    if not duty_id:
        return err("dutyId required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            role_type, sector_id = _detect_role(cur, uid)
            if role_type != "sector":
                return err("Only sector officers can mark attendance", 403)

            cur.execute("""
                SELECT da.id FROM duty_assignments da
                JOIN matdan_sthal ms ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                WHERE da.id = %s AND gp.sector_id = %s
            """, (duty_id, sector_id))
            if not cur.fetchone():
                return err("This duty is not under your sector", 403)

            cur.execute(
                "UPDATE duty_assignments SET attended = %s WHERE id = %s",
                (1 if attended else 0, duty_id))
        conn.commit()
    finally:
        conn.close()

    return ok({"dutyId": duty_id, "attended": attended}, "Attendance marked")


@staff_bp.route("/attendance/bulk", methods=["POST"])
@login_required
def mark_attendance_bulk():
    uid  = request.user["id"]
    body = request.get_json() or {}
    updates = body.get("updates", [])

    if not updates:
        return err("updates list required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            role_type, sector_id = _detect_role(cur, uid)
            if role_type != "sector":
                return err("Only sector officers can mark attendance", 403)

            duty_ids = [u["dutyId"] for u in updates if u.get("dutyId")]
            if not duty_ids:
                return err("No valid dutyIds")

            ph = ",".join(["%s"] * len(duty_ids))
            cur.execute(f"""
                SELECT da.id FROM duty_assignments da
                JOIN matdan_sthal ms ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                WHERE da.id IN ({ph}) AND gp.sector_id = %s
            """, duty_ids + [sector_id])
            valid_ids = {r["id"] for r in cur.fetchall()}

            updated = 0
            for u in updates:
                d_id = u.get("dutyId")
                if d_id not in valid_ids:
                    continue
                cur.execute(
                    "UPDATE duty_assignments SET attended = %s WHERE id = %s",
                    (1 if u.get("attended") else 0, d_id))
                updated += 1

        conn.commit()
    finally:
        conn.close()

    return ok({"updated": updated}, f"{updated} attendance records updated")


# ══════════════════════════════════════════════════════════════════════════════
#  CHANGE PASSWORD
# ══════════════════════════════════════════════════════════════════════════════
@staff_bp.route("/change-password", methods=["POST"])
@login_required
def change_password():
    body     = request.get_json() or {}
    current  = body.get("currentPassword", "")
    new_pass = body.get("newPassword", "")

    if len(new_pass) < 6:
        return err("पासवर्ड कम से कम 6 अक्षर का होना चाहिए")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT password FROM users WHERE id = %s",
                (request.user["id"],))
            row = cur.fetchone()
            if not row:
                return err("User not found", 404)

            cur_hash = hashlib.sha256((current + SALT).encode()).hexdigest()
            if cur_hash != row["password"]:
                return err("वर्तमान पासवर्ड गलत है", 401)

            new_hash = hashlib.sha256((new_pass + SALT).encode()).hexdigest()
            cur.execute(
                "UPDATE users SET password = %s WHERE id = %s",
                (new_hash, request.user["id"]))
        conn.commit()
    finally:
        conn.close()

    return ok(None, "पासवर्ड बदल दिया गया")


# ══════════════════════════════════════════════════════════════════════════════
#  HISTORY  — fixed: get district from users JOIN, not dda.district
# ══════════════════════════════════════════════════════════════════════════════
@staff_bp.route("/history", methods=["GET"])
@login_required
def duty_history():
    uid  = request.user["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:

            # ── Booth duties ───────────────────────────────────────────────
            cur.execute("""
                SELECT
                    da.id          AS duty_id,
                    da.attended,
                    da.bus_no,
                    da.sthal_id,
                    ms.name        AS booth,
                    ms.address,
                    ms.thana,
                    ms.center_type,
                    gp.name        AS gram_panchayat,
                    s.name         AS sector,
                    z.name         AS zone,
                    z.hq_address   AS zone_hq,
                    sz.name        AS super_zone,
                    sz.district,
                    sz.block
                FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id  = da.sthal_id
                JOIN gram_panchayats gp ON gp.id  = ms.gram_panchayat_id
                JOIN sectors s          ON s.id   = gp.sector_id
                JOIN zones z            ON z.id   = s.zone_id
                JOIN super_zones sz     ON sz.id  = z.super_zone_id
                WHERE da.staff_id = %s
                ORDER BY da.id DESC
            """, (uid,))
            booth_rows = cur.fetchall()

            booth_staff = {}
            if booth_rows:
                sthal_ids = list({r["sthal_id"] for r in booth_rows})
                ph = ",".join(["%s"] * len(sthal_ids))
                cur.execute(f"""
                    SELECT da2.sthal_id,
                           u.id, u.name, u.pno, u.user_rank
                    FROM duty_assignments da2
                    JOIN users u ON u.id = da2.staff_id
                    WHERE da2.sthal_id IN ({ph})
                    ORDER BY da2.sthal_id, u.name
                """, sthal_ids)
                for sr in cur.fetchall():
                    booth_staff.setdefault(sr["sthal_id"], []).append({
                        "id":   sr["id"],
                        "name": sr["name"]      or "",
                        "pno":  sr["pno"]       or "",
                        "rank": sr["user_rank"] or "",
                    })

            # ── District duties — JOIN users to get district ───────────────
            cur.execute("""
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
                WHERE dda.staff_id = %s
                ORDER BY dda.id DESC
            """, (uid,))
            district_rows = cur.fetchall()

            district_staff = {}
            if district_rows:
                # Key: (admin_id, duty_type, batch_no) — no district column
                batch_keys = list({
                    (r["admin_id"], r["duty_type"], r["batch_no"])
                    for r in district_rows
                    if r["batch_no"] and r["admin_id"]
                })
                for admin_id, duty_type, batch_no in batch_keys:
                    cur.execute("""
                        SELECT u.id, u.name, u.pno, u.user_rank AS rank
                        FROM district_duty_assignments dda
                        JOIN users u ON u.id = dda.staff_id
                        WHERE dda.admin_id  = %s
                          AND dda.duty_type = %s
                          AND dda.batch_no  = %s
                        ORDER BY u.name
                    """, (admin_id, duty_type, batch_no))
                    district_staff[(admin_id, duty_type, batch_no)] = [
                        dict(r) for r in cur.fetchall()
                    ]

    except Exception as e:
        import traceback
        print("❌ /history error:", traceback.format_exc())
        return err(f"Server error: {e}", 500)
    finally:
        conn.close()

    election_date = _get_election_date()
    results = []

    for r in booth_rows:
        results.append({
            "dutyKind":      "booth",
            "dutyId":        r["duty_id"],
            "present":       bool(r["attended"]),
            "date":          election_date,
            "busNo":         r["bus_no"]        or "",
            "booth":         r["booth"]         or "",
            "address":       r["address"]       or "",
            "thana":         r["thana"]         or "",
            "centerType":    r["center_type"]   or "",
            "gramPanchayat": r["gram_panchayat"] or "",
            "sector":        r["sector"]        or "",
            "zone":          r["zone"]          or "",
            "zoneHq":        r["zone_hq"]       or "",
            "superZone":     r["super_zone"]    or "",
            "district":      r["district"]      or "",
            "block":         r["block"]         or "",
            "assignedStaff": booth_staff.get(r["sthal_id"], []),
        })

    for r in district_rows:
        key = (r["admin_id"], r["duty_type"], r["batch_no"])
        results.append({
            "dutyKind":      "district",
            "dutyId":        r["assignment_id"],
            "present":       None,
            "date":          election_date,
            "dutyType":      r["duty_type"]  or "",
            "batchNo":       r["batch_no"],
            "busNo":         r["bus_no"]     or "",
            "note":          r["note"]       or "",
            "district":      r["district"]   or "",
            "assignedAt":    str(r["assigned_at"]) if r["assigned_at"] else "",
            "batchStaff":    district_staff.get(key, []),
            "booth": "", "address": "", "thana": "", "centerType": "",
            "gramPanchayat": "", "sector": "", "zone": "",
            "zoneHq": "", "superZone": "", "block": "",
            "assignedStaff": [],
        })

    return ok(results)


# ══════════════════════════════════════════════════════════════════════════════
#  ELECTION DATE (legacy)
# ══════════════════════════════════════════════════════════════════════════════
@staff_bp.route("/election-date", methods=["GET"])
@login_required
def get_election_date():
    district = request.args.get("district")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            if district:
                cur.execute("""
                    SELECT election_date FROM election_configs
                    WHERE district = %s AND is_active = 1 AND is_archived = 0
                    ORDER BY id DESC LIMIT 1
                """, (district,))
            else:
                cur.execute("""
                    SELECT election_date FROM election_configs
                    WHERE is_active = 1 AND is_archived = 0
                    ORDER BY id DESC LIMIT 1
                """)
            row = cur.fetchone()
    finally:
        conn.close()
    return ok(row["election_date"] if row else None)


# ══════════════════════════════════════════════════════════════════════════════
#  CURRENT DUTY (legacy widget)
# ══════════════════════════════════════════════════════════════════════════════
@staff_bp.route("/current-duty", methods=["GET"])
@login_required
def get_current_duty():
    uid  = request.user["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    da.id          AS duty_id,
                    da.attended,
                    da.bus_no,
                    ms.name        AS booth,
                    ms.address,
                    ms.thana,
                    ms.center_type AS center_type,
                    gp.name        AS gram_panchayat,
                    s.name         AS sector,
                    z.name         AS zone,
                    z.hq_address   AS zone_hq,
                    sz.name        AS super_zone,
                    sz.district,
                    sz.block
                FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE da.staff_id = %s
                ORDER BY da.id DESC LIMIT 1
            """, (uid,))
            row = cur.fetchone()
    finally:
        conn.close()

    if not row:
        return ok(None)

    election_date = _get_election_date()
    return ok({
        "dutyId":        row["duty_id"],
        "present":       bool(row["attended"]),
        "date":          election_date,
        "busNo":         row["bus_no"]         or "",
        "booth":         row["booth"]          or "",
        "address":       row["address"]        or "",
        "thana":         row["thana"]          or "",
        "centerType":    row["center_type"]    or "",
        "gramPanchayat": row["gram_panchayat"] or "",
        "sector":        row["sector"]         or "",
        "zone":          row["zone"]           or "",
        "zoneHq":        row["zone_hq"]        or "",
        "superZone":     row["super_zone"]     or "",
        "district":      row["district"]       or "",
        "block":         row["block"]          or "",
    })