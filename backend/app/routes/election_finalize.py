"""
election_finalize.py
────────────────────
Blueprint: finalize_bp   →  prefix  /api/admin/election

Register in app.py:
    from election_finalize import finalize_bp
    app.register_blueprint(finalize_bp)

ENDPOINTS
─────────
GET  /api/admin/election/finalize/status
POST /api/admin/election/finalize
GET  /api/admin/election/history
GET  /api/admin/election/history/<election_id>
GET  /api/admin/election/history/<election_id>/booth-assignments
GET  /api/admin/election/history/<election_id>/district-duties
GET  /api/admin/election/history/<election_id>/officers
GET  /api/admin/election/history/<election_id>/rules

WHAT FINALIZE DOES (in one transaction)
────────────────────────────────────────
1.  duty_assignments          → duty_assignments_history        (with denormalized staff+center info)
2.  district_duty_assignments → district_duty_history           (with denormalized staff info + duty label)
3.  district_rules            → district_rules_history
4.  booth_rules               → booth_rules_history
5.  kshetra_officers          → kshetra_officers_history        (with super_zone name/block)
6.  zonal_officers            → zonal_officers_history          (with zone + super_zone names)
7.  sector_officers           → sector_officers_history         (with sector + zone + super_zone names)
8.  DELETE live duty_assignments
9.  DELETE live district_duty_assignments
10. Unlock all super zones for this district
11. Mark election_config  is_finalized=1, is_archived=1
"""

from datetime import date
from flask import Blueprint, request
from db import get_db
from app.routes import admin_required, ok, err, write_log   # adjust if your import path differs

finalize_bp = Blueprint("finalize", __name__, url_prefix="/api/admin/election")


# ─────────────────────────────────────────────────────────────────────────────
#  Internal helpers
# ─────────────────────────────────────────────────────────────────────────────

def _admin_id():
    return request.user["id"]


def _district_admin_ids(district: str) -> list:
    """All admin/super_admin user IDs in the same district as the current user."""
    if not district:
        return [_admin_id()]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM users "
                "WHERE role IN ('admin','super_admin') AND district = %s",
                (district,)
            )
            ids = [r["id"] for r in cur.fetchall()]
            if _admin_id() not in ids:
                ids.append(_admin_id())
            return ids or [_admin_id()]
    finally:
        conn.close()


def _ph(ids: list):
    """Return (placeholder_str, ids_list) for SQL IN clauses."""
    return ",".join(["%s"] * len(ids)), list(ids)


# ─────────────────────────────────────────────────────────────────────────────
#  GET /api/admin/election/finalize/status
# ─────────────────────────────────────────────────────────────────────────────

@finalize_bp.route("/finalize/status", methods=["GET"])
@admin_required
def finalize_status():
    """
    Returns the active election config for the admin's district,
    whether it is eligible for finalization, and live assignment counts.
    """
    district = (request.user.get("district") or "").strip()
    if not district:
        return err("Admin has no district configured", 400)

    d_ids = _district_admin_ids(district)
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # Active election config
            cur.execute("""
                SELECT id, election_name, election_type, election_date,
                       is_finalized, is_archived, phase, election_year,
                       pratah_samay, saya_samay, state
                FROM election_configs
                WHERE district    = %s
                  AND is_active   = 1
                  AND is_archived = 0
                ORDER BY updated_at DESC, id DESC
                LIMIT 1
            """, (district,))
            cfg = cur.fetchone()

            if not cfg:
                return ok({
                    "hasActiveConfig":  False,
                    "readyToFinalize":  False,
                    "config":           None,
                    "counts":           {},
                })

            today         = date.today()
            election_date = cfg["election_date"]
            ready = (
                election_date is not None
                and election_date <= today
                and not cfg["is_finalized"]
            )

            # Live assignment counts
            cur.execute(f"""
                SELECT COUNT(*) AS cnt
                FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
            """, params)
            booth_count = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT COUNT(*) AS cnt
                FROM district_duty_assignments
                WHERE admin_id IN ({ph})
            """, params)
            district_count = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT COUNT(*) AS cnt
                FROM kshetra_officers ko
                JOIN super_zones sz ON sz.id = ko.super_zone_id
                WHERE sz.admin_id IN ({ph})
            """, params)
            kshetra_count = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT COUNT(*) AS cnt
                FROM zonal_officers zo
                JOIN zones z        ON z.id  = zo.zone_id
                JOIN super_zones sz  ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
            """, params)
            zonal_count = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT COUNT(*) AS cnt
                FROM sector_officers so
                JOIN sectors s      ON s.id  = so.sector_id
                JOIN zones z        ON z.id  = s.zone_id
                JOIN super_zones sz  ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
            """, params)
            sector_count = cur.fetchone()["cnt"]

    finally:
        conn.close()

    return ok({
        "hasActiveConfig":   True,
        "readyToFinalize":   bool(ready),
        "alreadyFinalized":  bool(cfg["is_finalized"]),
        "config": {
            "id":           cfg["id"],
            "electionName": cfg["election_name"]  or "",
            "electionType": cfg["election_type"]  or "",
            "electionDate": str(election_date)    if election_date else "",
            "phase":        cfg["phase"]          or "",
            "electionYear": cfg["election_year"]  or "",
            "state":        cfg["state"]          or "",
            "pratahSamay":  cfg["pratah_samay"]   or "",
            "sayaSamay":    cfg["saya_samay"]      or "",
            "isFinalized":  bool(cfg["is_finalized"]),
        },
        "counts": {
            "boothAssignments":    booth_count,
            "districtAssignments": district_count,
            "kshetraOfficers":     kshetra_count,
            "zonalOfficers":       zonal_count,
            "sectorOfficers":      sector_count,
        },
    })


# ─────────────────────────────────────────────────────────────────────────────
#  POST /api/admin/election/finalize
# ─────────────────────────────────────────────────────────────────────────────

@finalize_bp.route("/finalize", methods=["POST"])
@admin_required
def finalize_election():
    """
    Archives all live assignments + officer lists to history tables,
    clears live data, unlocks super zones, marks the election config finalized.

    Body (optional):
      { "force": true }  →  bypass the date guard (for admin override / testing)
    """
    body     = request.get_json() or {}
    force    = bool(body.get("force", False))
    district = (request.user.get("district") or "").strip()

    if not district:
        return err("Admin has no district configured", 400)

    # ── Fetch active election config ──────────────────────────────────────────
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, election_name, election_date, is_finalized
                FROM election_configs
                WHERE district    = %s
                  AND is_active   = 1
                  AND is_archived = 0
                ORDER BY updated_at DESC, id DESC
                LIMIT 1
            """, (district,))
            cfg = cur.fetchone()
    finally:
        conn.close()

    if not cfg:
        return err("No active election config found for your district", 404)

    if cfg["is_finalized"]:
        return err(
            f"Election '{cfg['election_name']}' is already finalized. "
            "Ask the master to create a new election config.",
            409
        )

    # ── Date guard ────────────────────────────────────────────────────────────
    if not force:
        today         = date.today()
        election_date = cfg["election_date"]
        if election_date is None:
            return err("Election date is not set. Ask the master to set it first.", 400)
        if election_date > today:
            return err(
                f"Election date is {election_date} — finalization is only allowed "
                "on or after the election date. Pass force=true to override.",
                400
            )

    election_id = cfg["id"]
    d_ids       = _district_admin_ids(district)
    ph, params  = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # ── Step 1: Archive duty_assignments (with denormalized data) ─────
            cur.execute(f"""
                INSERT INTO duty_assignments_history
                    (election_id, original_id, admin_id,
                     staff_id, sthal_id,
                     staff_name, staff_pno, staff_mobile, staff_rank,
                     staff_district, staff_thana, is_armed,
                     center_name, center_type,
                     bus_no, election_date, attended, card_downloaded,
                     assigned_by, original_created_at)
                SELECT
                    %s,
                    da.id,
                    sz.admin_id,
                    da.staff_id,
                    da.sthal_id,
                    u.name,
                    u.pno,
                    u.mobile,
                    u.user_rank,
                    u.district,
                    u.thana,
                    u.is_armed,
                    ms.name,
                    ms.center_type,
                    da.bus_no,
                    da.election_date,
                    da.attended,
                    da.card_downloaded,
                    da.assigned_by,
                    da.created_at
                FROM duty_assignments da
                JOIN users u            ON u.id  = da.staff_id
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
            """, [election_id] + params)
            booth_archived = cur.rowcount

            # ── Step 2: Archive district_duty_assignments (with denorm data) ──
            cur.execute(f"""
                INSERT INTO district_duty_history
                    (election_id, original_id, admin_id,
                     duty_type, duty_label_hi, batch_no,
                     staff_id, staff_name, staff_pno, staff_mobile,
                     staff_rank, staff_district, staff_thana, is_armed,
                     assigned_by, bus_no, note, original_created_at)
                SELECT
                    %s,
                    dda.id,
                    dda.admin_id,
                    dda.duty_type,
                    COALESCE(dr.duty_label_hi, ''),
                    dda.batch_no,
                    dda.staff_id,
                    u.name,
                    u.pno,
                    u.mobile,
                    u.user_rank,
                    u.district,
                    u.thana,
                    u.is_armed,
                    dda.assigned_by,
                    dda.bus_no,
                    dda.note,
                    dda.created_at
                FROM district_duty_assignments dda
                JOIN users u ON u.id = dda.staff_id
                LEFT JOIN district_rules dr
                    ON dr.admin_id = dda.admin_id
                   AND dr.duty_type = dda.duty_type
                WHERE dda.admin_id IN ({ph})
            """, [election_id] + params)
            district_archived = cur.rowcount

            # ── Step 3: Archive district_rules ────────────────────────────────
            cur.execute(f"""
                INSERT INTO district_rules_history
                    (election_id, original_id, admin_id,
                     duty_type, duty_label_hi, sankhya,
                     si_armed_count, si_unarmed_count,
                     hc_armed_count, hc_unarmed_count,
                     const_armed_count, const_unarmed_count,
                     aux_armed_count, aux_unarmed_count,
                     pac_count, sort_order, original_created_at)
                SELECT
                    %s, id, admin_id,
                    duty_type, duty_label_hi, sankhya,
                    si_armed_count, si_unarmed_count,
                    hc_armed_count, hc_unarmed_count,
                    const_armed_count, const_unarmed_count,
                    aux_armed_count, aux_unarmed_count,
                    pac_count, sort_order, created_at
                FROM district_rules
                WHERE admin_id IN ({ph})
            """, [election_id] + params)
            rules_archived = cur.rowcount

            # ── Step 4: Archive booth_rules ───────────────────────────────────
            cur.execute(f"""
                INSERT INTO booth_rules_history
                    (election_id, original_id, admin_id,
                     sensitivity, booth_count,
                     si_armed_count, si_unarmed_count,
                     hc_armed_count, hc_unarmed_count,
                     const_armed_count, const_unarmed_count,
                     aux_armed_count, aux_unarmed_count,
                     pac_count, original_created_at)
                SELECT
                    %s, id, admin_id,
                    sensitivity, booth_count,
                    si_armed_count, si_unarmed_count,
                    hc_armed_count, hc_unarmed_count,
                    const_armed_count, const_unarmed_count,
                    aux_armed_count, aux_unarmed_count,
                    pac_count, created_at
                FROM booth_rules
                WHERE admin_id IN ({ph})
            """, [election_id] + params)
            booth_rules_archived = cur.rowcount

            # ── Step 5: Archive kshetra_officers ──────────────────────────────
            cur.execute(f"""
                INSERT INTO kshetra_officers_history
                    (election_id, original_id, admin_id,
                     super_zone_id, super_zone_name, super_zone_block,
                     user_id, name, pno, mobile, user_rank,
                     original_created_at)
                SELECT
                    %s,
                    ko.id,
                    sz.admin_id,
                    ko.super_zone_id,
                    sz.name,
                    sz.block,
                    ko.user_id,
                    ko.name,
                    ko.pno,
                    ko.mobile,
                    ko.user_rank,
                    ko.created_at
                FROM kshetra_officers ko
                JOIN super_zones sz ON sz.id = ko.super_zone_id
                WHERE sz.admin_id IN ({ph})
            """, [election_id] + params)
            kshetra_archived = cur.rowcount

            # ── Step 6: Archive zonal_officers ────────────────────────────────
            cur.execute(f"""
                INSERT INTO zonal_officers_history
                    (election_id, original_id, admin_id,
                     zone_id, zone_name,
                     super_zone_id, super_zone_name,
                     user_id, name, pno, mobile, user_rank,
                     original_created_at)
                SELECT
                    %s,
                    zo.id,
                    sz.admin_id,
                    zo.zone_id,
                    z.name,
                    sz.id,
                    sz.name,
                    zo.user_id,
                    zo.name,
                    zo.pno,
                    zo.mobile,
                    zo.user_rank,
                    zo.created_at
                FROM zonal_officers zo
                JOIN zones z        ON z.id  = zo.zone_id
                JOIN super_zones sz  ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
            """, [election_id] + params)
            zonal_archived = cur.rowcount

            # ── Step 7: Archive sector_officers ───────────────────────────────
            cur.execute(f"""
                INSERT INTO sector_officers_history
                    (election_id, original_id, admin_id,
                     sector_id, sector_name,
                     zone_id, zone_name,
                     super_zone_id, super_zone_name,
                     user_id, name, pno, mobile, user_rank,
                     original_created_at)
                SELECT
                    %s,
                    so.id,
                    sz.admin_id,
                    so.sector_id,
                    s.name,
                    z.id,
                    z.name,
                    sz.id,
                    sz.name,
                    so.user_id,
                    so.name,
                    so.pno,
                    so.mobile,
                    so.user_rank,
                    so.created_at
                FROM sector_officers so
                JOIN sectors s      ON s.id  = so.sector_id
                JOIN zones z        ON z.id  = s.zone_id
                JOIN super_zones sz  ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
            """, [election_id] + params)
            sector_archived = cur.rowcount

            # ── Step 8: Delete live duty_assignments ──────────────────────────
            cur.execute(f"""
                DELETE da FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
            """, params)

            # ── Step 9: Delete live district_duty_assignments ─────────────────
            cur.execute(f"""
                DELETE FROM district_duty_assignments
                WHERE admin_id IN ({ph})
            """, params)

            # ── Step 10: Unlock all super zones for this district ─────────────
            cur.execute(f"""
                UPDATE sz_duty_locks
                SET is_locked     = 0,
                    status        = 'unlocked',
                    unlock_reason = 'Auto-unlocked on election finalization'
                WHERE super_zone_id IN (
                    SELECT id FROM super_zones WHERE admin_id IN ({ph})
                )
            """, params)

            # ── Step 11: Mark election config finalized + archived ────────────
            cur.execute("""
                UPDATE election_configs
                SET is_finalized = 1,
                    finalized_at = NOW(),
                    finalized_by = %s,
                    is_active    = 0,
                    is_archived  = 1,
                    archived_at  = NOW()
                WHERE id = %s
            """, (_admin_id(), election_id))

        conn.commit()

    except Exception as e:
        try:
            conn.rollback()
        except Exception:
            pass
        write_log("ERROR", f"finalize_election: {e}", "ElectionFinalize")
        return err(f"Finalization failed: {e}", 500)

    finally:
        conn.close()

    write_log(
        "INFO",
        (
            f"Election finalized: config_id={election_id} district={district} | "
            f"booth={booth_archived} district={district_archived} "
            f"kshetra={kshetra_archived} zonal={zonal_archived} sector={sector_archived} "
            f"by admin {_admin_id()}"
        ),
        "ElectionFinalize"
    )

    return ok({
        "electionId":   election_id,
        "electionName": cfg["election_name"],
        "archived": {
            "boothAssignments":    booth_archived,
            "districtAssignments": district_archived,
            "districtRules":       rules_archived,
            "boothRules":          booth_rules_archived,
            "kshetraOfficers":     kshetra_archived,
            "zonalOfficers":       zonal_archived,
            "sectorOfficers":      sector_archived,
        },
        "message": (
            "All assignments and officer lists have been archived. "
            "Super zones are unlocked. "
            "Admins can now assign duties for the next election."
        ),
    }, "Election finalized successfully")


# ─────────────────────────────────────────────────────────────────────────────
#  GET /api/admin/election/history
#  List of all archived elections for this district with summary counts
# ─────────────────────────────────────────────────────────────────────────────

@finalize_bp.route("/history", methods=["GET"])
@admin_required
def election_history_list():
    district = (request.user.get("district") or "").strip()
    d_ids    = _district_admin_ids(district)
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # All archived/finalized configs for this district
            cur.execute("""
                SELECT id, election_name, election_type, election_date,
                       phase, election_year, state, is_finalized,
                       finalized_at, finalized_by, archived_at, created_at
                FROM election_configs
                WHERE district = %s
                  AND (is_archived = 1 OR is_finalized = 1)
                ORDER BY id DESC
            """, (district,))
            configs = cur.fetchall()

            if not configs:
                return ok([])

            cfg_ids = [c["id"] for c in configs]
            c_ph    = ",".join(["%s"] * len(cfg_ids))

            # Summary counts per election from every history table
            def _counts(table, election_col="election_id"):
                cur.execute(f"""
                    SELECT {election_col} AS eid, COUNT(*) AS cnt
                    FROM {table}
                    WHERE {election_col} IN ({c_ph})
                    GROUP BY {election_col}
                """, cfg_ids)
                return {r["eid"]: r["cnt"] for r in cur.fetchall()}

            booth_map    = _counts("duty_assignments_history")
            district_map = _counts("district_duty_history")
            kshetra_map  = _counts("kshetra_officers_history")
            zonal_map    = _counts("zonal_officers_history")
            sector_map   = _counts("sector_officers_history")

    finally:
        conn.close()

    return ok([{
        "id":                       c["id"],
        "electionName":             c["election_name"]  or "",
        "electionType":             c["election_type"]  or "",
        "electionDate":             str(c["election_date"]) if c["election_date"] else "",
        "phase":                    c["phase"]          or "",
        "electionYear":             c["election_year"]  or "",
        "state":                    c["state"]          or "",
        "isFinalized":              bool(c["is_finalized"]),
        "finalizedAt":              str(c["finalized_at"]) if c["finalized_at"] else "",
        "archivedAt":               str(c["archived_at"])  if c["archived_at"]  else "",
        "boothAssignmentsArchived":    booth_map.get(c["id"],    0),
        "districtAssignmentsArchived": district_map.get(c["id"], 0),
        "kshetraOfficersArchived":     kshetra_map.get(c["id"],  0),
        "zonalOfficersArchived":       zonal_map.get(c["id"],    0),
        "sectorOfficersArchived":      sector_map.get(c["id"],   0),
    } for c in configs])


# ─────────────────────────────────────────────────────────────────────────────
#  GET /api/admin/election/history/<election_id>
#  Full detail summary for one archived election
# ─────────────────────────────────────────────────────────────────────────────

@finalize_bp.route("/history/<int:election_id>", methods=["GET"])
@admin_required
def election_history_detail(election_id):
    district = (request.user.get("district") or "").strip()
    d_ids    = _district_admin_ids(district)
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # Verify config belongs to this district
            cur.execute("""
                SELECT id, election_name, election_type, election_date,
                       phase, election_year, state, is_finalized,
                       finalized_at, archived_at
                FROM election_configs
                WHERE id = %s AND district = %s
            """, (election_id, district))
            cfg = cur.fetchone()
            if not cfg:
                return err("Election not found or access denied", 404)

            # Booth assignments — grouped by center_type
            cur.execute("""
                SELECT center_type,
                       COUNT(*)              AS total_staff,
                       COUNT(DISTINCT sthal_id) AS centers_covered,
                       SUM(attended)         AS total_attended
                FROM duty_assignments_history
                WHERE election_id = %s
                  AND admin_id IN (""" + ph + """)
                GROUP BY center_type
            """, [election_id] + params)
            booth_by_type = cur.fetchall()

            # District duties — grouped by duty_type
            cur.execute("""
                SELECT duty_type, duty_label_hi,
                       MAX(batch_no)              AS batch_count,
                       COUNT(DISTINCT staff_id)   AS total_staff
                FROM district_duty_history
                WHERE election_id = %s
                  AND admin_id IN (""" + ph + """)
                GROUP BY duty_type, duty_label_hi
                ORDER BY duty_type
            """, [election_id] + params)
            district_summary = cur.fetchall()

            # Officer summary counts
            cur.execute("""
                SELECT COUNT(*) AS cnt
                FROM kshetra_officers_history
                WHERE election_id = %s AND admin_id IN (""" + ph + """)
            """, [election_id] + params)
            kshetra_count = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT COUNT(*) AS cnt
                FROM zonal_officers_history
                WHERE election_id = %s AND admin_id IN (""" + ph + """)
            """, [election_id] + params)
            zonal_count = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT COUNT(*) AS cnt
                FROM sector_officers_history
                WHERE election_id = %s AND admin_id IN (""" + ph + """)
            """, [election_id] + params)
            sector_count = cur.fetchone()["cnt"]

    finally:
        conn.close()

    return ok({
        "config": {
            "id":           cfg["id"],
            "electionName": cfg["election_name"]  or "",
            "electionType": cfg["election_type"]  or "",
            "electionDate": str(cfg["election_date"]) if cfg["election_date"] else "",
            "phase":        cfg["phase"]          or "",
            "electionYear": cfg["election_year"]  or "",
            "state":        cfg["state"]          or "",
            "isFinalized":  bool(cfg["is_finalized"]),
            "finalizedAt":  str(cfg["finalized_at"]) if cfg["finalized_at"] else "",
            "archivedAt":   str(cfg["archived_at"])  if cfg["archived_at"]  else "",
        },
        "boothSummary": [{
            "centerType":      r["center_type"]     or "",
            "totalStaff":      int(r["total_staff"]      or 0),
            "centersCovered":  int(r["centers_covered"]  or 0),
            "totalAttended":   int(r["total_attended"]   or 0),
        } for r in booth_by_type],
        "districtDutySummary": [{
            "dutyType":      r["duty_type"]      or "",
            "dutyLabelHi":   r["duty_label_hi"]  or "",
            "batchCount":    int(r["batch_count"] or 0),
            "totalStaff":    int(r["total_staff"] or 0),
        } for r in district_summary],
        "officerSummary": {
            "kshetraOfficers": int(kshetra_count or 0),
            "zonalOfficers":   int(zonal_count   or 0),
            "sectorOfficers":  int(sector_count  or 0),
        },
    })


# ─────────────────────────────────────────────────────────────────────────────
#  GET /api/admin/election/history/<election_id>/booth-assignments
#  Paginated booth assignment records for one archived election
# ─────────────────────────────────────────────────────────────────────────────

@finalize_bp.route("/history/<int:election_id>/booth-assignments", methods=["GET"])
@admin_required
def history_booth_assignments(election_id):
    district     = (request.user.get("district") or "").strip()
    d_ids        = _district_admin_ids(district)
    ph, params   = _ph(d_ids)
    search       = request.args.get("q",           "").strip()
    center_type  = request.args.get("centerType",  "").strip()
    page         = max(1, int(request.args.get("page",  1)))
    limit        = min(200, max(1, int(request.args.get("limit", 50))))
    offset       = (page - 1) * limit

    _verify_election_district(election_id, district)

    where  = ["dah.election_id = %s", f"dah.admin_id IN ({ph})"]
    wparams = [election_id] + params

    if search:
        where.append(
            "(dah.staff_name LIKE %s OR dah.staff_pno LIKE %s "
            "OR dah.center_name LIKE %s OR dah.staff_rank LIKE %s)"
        )
        like = f"%{search}%"
        wparams += [like, like, like, like]

    if center_type:
        where.append("dah.center_type = %s")
        wparams.append(center_type)

    where_sql = " AND ".join(where)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) AS cnt FROM duty_assignments_history dah WHERE {where_sql}", wparams)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT
                    dah.id, dah.original_id,
                    dah.staff_id, dah.sthal_id,
                    dah.staff_name, dah.staff_pno, dah.staff_mobile,
                    dah.staff_rank, dah.staff_district, dah.staff_thana,
                    dah.is_armed,
                    dah.center_name, dah.center_type,
                    dah.bus_no, dah.election_date,
                    dah.attended, dah.card_downloaded,
                    dah.archived_at
                FROM duty_assignments_history dah
                WHERE {where_sql}
                ORDER BY dah.center_name, dah.staff_name
                LIMIT %s OFFSET %s
            """, wparams + [limit, offset])
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok({
        "data": [{
            "id":            r["id"],
            "staffId":       r["staff_id"],
            "sthalId":       r["sthal_id"],
            "staffName":     r["staff_name"]     or "",
            "staffPno":      r["staff_pno"]      or "",
            "staffMobile":   r["staff_mobile"]   or "",
            "staffRank":     r["staff_rank"]      or "",
            "staffDistrict": r["staff_district"] or "",
            "staffThana":    r["staff_thana"]    or "",
            "isArmed":       bool(r["is_armed"]),
            "centerName":    r["center_name"]    or "",
            "centerType":    r["center_type"]    or "",
            "busNo":         r["bus_no"]         or "",
            "electionDate":  str(r["election_date"]) if r["election_date"] else "",
            "attended":      bool(r["attended"]),
            "cardDownloaded":bool(r["card_downloaded"]),
            "archivedAt":    str(r["archived_at"]),
        } for r in rows],
        "total":      total,
        "page":       page,
        "limit":      limit,
        "totalPages": -(-total // limit),
    })


# ─────────────────────────────────────────────────────────────────────────────
#  GET /api/admin/election/history/<election_id>/district-duties
#  Paginated district duty records for one archived election
# ─────────────────────────────────────────────────────────────────────────────

@finalize_bp.route("/history/<int:election_id>/district-duties", methods=["GET"])
@admin_required
def history_district_duties(election_id):
    district    = (request.user.get("district") or "").strip()
    d_ids       = _district_admin_ids(district)
    ph, params  = _ph(d_ids)
    search      = request.args.get("q",         "").strip()
    duty_type   = request.args.get("dutyType",  "").strip()
    batch_no    = request.args.get("batchNo",   None)
    page        = max(1, int(request.args.get("page",  1)))
    limit       = min(200, max(1, int(request.args.get("limit", 50))))
    offset      = (page - 1) * limit

    _verify_election_district(election_id, district)

    where  = ["ddh.election_id = %s", f"ddh.admin_id IN ({ph})"]
    wparams = [election_id] + params

    if search:
        where.append(
            "(ddh.staff_name LIKE %s OR ddh.staff_pno LIKE %s "
            "OR ddh.duty_label_hi LIKE %s OR ddh.staff_rank LIKE %s)"
        )
        like = f"%{search}%"
        wparams += [like, like, like, like]

    if duty_type:
        where.append("ddh.duty_type = %s")
        wparams.append(duty_type)

    if batch_no is not None:
        where.append("ddh.batch_no = %s")
        wparams.append(int(batch_no))

    where_sql = " AND ".join(where)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) AS cnt FROM district_duty_history ddh WHERE {where_sql}", wparams)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT
                    ddh.id, ddh.original_id,
                    ddh.duty_type, ddh.duty_label_hi, ddh.batch_no,
                    ddh.staff_id,
                    ddh.staff_name, ddh.staff_pno, ddh.staff_mobile,
                    ddh.staff_rank, ddh.staff_district, ddh.staff_thana,
                    ddh.is_armed, ddh.bus_no, ddh.note,
                    ddh.archived_at
                FROM district_duty_history ddh
                WHERE {where_sql}
                ORDER BY ddh.duty_type, ddh.batch_no, ddh.staff_name
                LIMIT %s OFFSET %s
            """, wparams + [limit, offset])
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok({
        "data": [{
            "id":            r["id"],
            "dutyType":      r["duty_type"]      or "",
            "dutyLabelHi":   r["duty_label_hi"]  or "",
            "batchNo":       r["batch_no"],
            "staffId":       r["staff_id"],
            "staffName":     r["staff_name"]     or "",
            "staffPno":      r["staff_pno"]      or "",
            "staffMobile":   r["staff_mobile"]   or "",
            "staffRank":     r["staff_rank"]      or "",
            "staffDistrict": r["staff_district"] or "",
            "staffThana":    r["staff_thana"]    or "",
            "isArmed":       bool(r["is_armed"]),
            "busNo":         r["bus_no"]         or "",
            "note":          r["note"]           or "",
            "archivedAt":    str(r["archived_at"]),
        } for r in rows],
        "total":      total,
        "page":       page,
        "limit":      limit,
        "totalPages": -(-total // limit),
    })


# ─────────────────────────────────────────────────────────────────────────────
#  GET /api/admin/election/history/<election_id>/officers
#  All officer snapshots (kshetra + zonal + sector) for one archived election
# ─────────────────────────────────────────────────────────────────────────────

@finalize_bp.route("/history/<int:election_id>/officers", methods=["GET"])
@admin_required
def history_officers(election_id):
    district    = (request.user.get("district") or "").strip()
    d_ids       = _district_admin_ids(district)
    ph, params  = _ph(d_ids)
    search      = request.args.get("q", "").strip()

    _verify_election_district(election_id, district)

    like = f"%{search}%"

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # Kshetra officers
            q = [f"election_id = %s", f"admin_id IN ({ph})"]
            qp = [election_id] + params
            if search:
                q.append("(name LIKE %s OR pno LIKE %s OR user_rank LIKE %s OR super_zone_name LIKE %s)")
                qp += [like, like, like, like]
            where_sql = " AND ".join(q)

            cur.execute(f"""
                SELECT id, original_id, super_zone_id, super_zone_name,
                       super_zone_block, user_id, name, pno, mobile,
                       user_rank, archived_at
                FROM kshetra_officers_history
                WHERE {where_sql}
                ORDER BY super_zone_name, name
            """, qp)
            kshetra = cur.fetchall()

            # Zonal officers
            q2  = [f"election_id = %s", f"admin_id IN ({ph})"]
            qp2 = [election_id] + params
            if search:
                q2.append("(name LIKE %s OR pno LIKE %s OR user_rank LIKE %s "
                           "OR zone_name LIKE %s OR super_zone_name LIKE %s)")
                qp2 += [like, like, like, like, like]
            cur.execute(f"""
                SELECT id, original_id, zone_id, zone_name,
                       super_zone_id, super_zone_name,
                       user_id, name, pno, mobile, user_rank, archived_at
                FROM zonal_officers_history
                WHERE {" AND ".join(q2)}
                ORDER BY super_zone_name, zone_name, name
            """, qp2)
            zonal = cur.fetchall()

            # Sector officers
            q3  = [f"election_id = %s", f"admin_id IN ({ph})"]
            qp3 = [election_id] + params
            if search:
                q3.append("(name LIKE %s OR pno LIKE %s OR user_rank LIKE %s "
                           "OR sector_name LIKE %s OR zone_name LIKE %s OR super_zone_name LIKE %s)")
                qp3 += [like, like, like, like, like, like]
            cur.execute(f"""
                SELECT id, original_id, sector_id, sector_name,
                       zone_id, zone_name,
                       super_zone_id, super_zone_name,
                       user_id, name, pno, mobile, user_rank, archived_at
                FROM sector_officers_history
                WHERE {" AND ".join(q3)}
                ORDER BY super_zone_name, zone_name, sector_name, name
            """, qp3)
            sector = cur.fetchall()

    finally:
        conn.close()

    def _fmt_kshetra(r):
        return {
            "id":             r["id"],
            "superZoneId":    r["super_zone_id"],
            "superZoneName":  r["super_zone_name"]  or "",
            "superZoneBlock": r["super_zone_block"]  or "",
            "userId":         r["user_id"],
            "name":           r["name"]             or "",
            "pno":            r["pno"]              or "",
            "mobile":         r["mobile"]           or "",
            "rank":           r["user_rank"]         or "",
            "archivedAt":     str(r["archived_at"]),
        }

    def _fmt_zonal(r):
        return {
            "id":            r["id"],
            "zoneId":        r["zone_id"],
            "zoneName":      r["zone_name"]         or "",
            "superZoneId":   r["super_zone_id"],
            "superZoneName": r["super_zone_name"]   or "",
            "userId":        r["user_id"],
            "name":          r["name"]              or "",
            "pno":           r["pno"]               or "",
            "mobile":        r["mobile"]            or "",
            "rank":          r["user_rank"]          or "",
            "archivedAt":    str(r["archived_at"]),
        }

    def _fmt_sector(r):
        return {
            "id":            r["id"],
            "sectorId":      r["sector_id"],
            "sectorName":    r["sector_name"]       or "",
            "zoneId":        r["zone_id"],
            "zoneName":      r["zone_name"]         or "",
            "superZoneId":   r["super_zone_id"],
            "superZoneName": r["super_zone_name"]   or "",
            "userId":        r["user_id"],
            "name":          r["name"]              or "",
            "pno":           r["pno"]               or "",
            "mobile":        r["mobile"]            or "",
            "rank":          r["user_rank"]          or "",
            "archivedAt":    str(r["archived_at"]),
        }

    return ok({
        "kshetraOfficers": [_fmt_kshetra(r) for r in kshetra],
        "zonalOfficers":   [_fmt_zonal(r)   for r in zonal],
        "sectorOfficers":  [_fmt_sector(r)  for r in sector],
    })


# ─────────────────────────────────────────────────────────────────────────────
#  GET /api/admin/election/history/<election_id>/rules
#  Booth rules + district rules snapshots for one archived election
# ─────────────────────────────────────────────────────────────────────────────

@finalize_bp.route("/history/<int:election_id>/rules", methods=["GET"])
@admin_required
def history_rules(election_id):
    district    = (request.user.get("district") or "").strip()
    d_ids       = _district_admin_ids(district)
    ph, params  = _ph(d_ids)

    _verify_election_district(election_id, district)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute(f"""
                SELECT sensitivity, booth_count,
                       si_armed_count, si_unarmed_count,
                       hc_armed_count, hc_unarmed_count,
                       const_armed_count, const_unarmed_count,
                       aux_armed_count, aux_unarmed_count,
                       pac_count
                FROM booth_rules_history
                WHERE election_id = %s AND admin_id IN ({ph})
                ORDER BY sensitivity, booth_count
            """, [election_id] + params)
            booth_rules = cur.fetchall()

            cur.execute(f"""
                SELECT duty_type, duty_label_hi, sankhya,
                       si_armed_count, si_unarmed_count,
                       hc_armed_count, hc_unarmed_count,
                       const_armed_count, const_unarmed_count,
                       aux_armed_count, aux_unarmed_count,
                       pac_count, sort_order
                FROM district_rules_history
                WHERE election_id = %s AND admin_id IN ({ph})
                ORDER BY sort_order
            """, [election_id] + params)
            district_rules = cur.fetchall()

    finally:
        conn.close()

    return ok({
        "boothRules": [{
            "sensitivity":      r["sensitivity"],
            "boothCount":       r["booth_count"],
            "siArmedCount":     r["si_armed_count"],
            "siUnarmedCount":   r["si_unarmed_count"],
            "hcArmedCount":     r["hc_armed_count"],
            "hcUnarmedCount":   r["hc_unarmed_count"],
            "constArmedCount":  r["const_armed_count"],
            "constUnarmedCount":r["const_unarmed_count"],
            "auxArmedCount":    r["aux_armed_count"],
            "auxUnarmedCount":  r["aux_unarmed_count"],
            "pacCount":         float(r["pac_count"] or 0),
        } for r in booth_rules],
        "districtRules": [{
            "dutyType":         r["duty_type"]       or "",
            "dutyLabelHi":      r["duty_label_hi"]   or "",
            "sankhya":          r["sankhya"]          or 0,
            "siArmedCount":     r["si_armed_count"],
            "siUnarmedCount":   r["si_unarmed_count"],
            "hcArmedCount":     r["hc_armed_count"],
            "hcUnarmedCount":   r["hc_unarmed_count"],
            "constArmedCount":  r["const_armed_count"],
            "constUnarmedCount":r["const_unarmed_count"],
            "auxArmedCount":    r["aux_armed_count"],
            "auxUnarmedCount":  r["aux_unarmed_count"],
            "pacCount":         float(r["pac_count"] or 0),
            "sortOrder":        r["sort_order"]       or 0,
        } for r in district_rules],
    })


# ─────────────────────────────────────────────────────────────────────────────
#  Internal: verify the election_id belongs to the admin's district
# ─────────────────────────────────────────────────────────────────────────────

def _verify_election_district(election_id: int, district: str):
    """Raises a 404-style error if election_id doesn't belong to district."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM election_configs WHERE id = %s AND district = %s",
                (election_id, district)
            )
            if not cur.fetchone():
                from flask import abort
                abort(404)
    finally:
        conn.close()