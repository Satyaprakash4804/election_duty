from datetime import date
from flask import Blueprint, request, abort
from db import get_db
from app.routes import ok, err, write_log, admin_required
from app.election_guard import (
    get_active_election,
    finalize_district_auto,
    sweep_auto_finalize_all_districts,
)

election_finalize_bp = Blueprint(
    "election_finalize", __name__, url_prefix="/api/admin/election"
)


# ═════════════════════════════════════════════════════════════════════════════
#  INTERNAL HELPERS
# ═════════════════════════════════════════════════════════════════════════════

def _admin_id():
    return request.user["id"]


def _district_admin_ids(district: str) -> list:
    """All admin/super_admin user IDs in the same district."""
    if not district:
        return [_admin_id()]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM users "
                "WHERE role IN ('admin','super_admin') AND district = %s",
                (district,),
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


def _page_params():
    page  = max(1, int(request.args.get("page", 1)))
    limit = min(200, max(1, int(request.args.get("limit", 50))))
    return page, limit, (page - 1) * limit


def _paginated(data, total, page, limit):
    return ok({
        "data":       data,
        "total":      total,
        "page":       page,
        "limit":      limit,
        "totalPages": -(-total // limit) if limit else 0,
    })


def _verify_election_district(election_id: int, district: str):
    """Abort 404 if election_id does not belong to this district."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM election_configs WHERE id = %s AND district = %s",
                (election_id, district),
            )
            if not cur.fetchone():
                abort(404)
    finally:
        conn.close()


# ═════════════════════════════════════════════════════════════════════════════
#  STATUS
# ═════════════════════════════════════════════════════════════════════════════

@election_finalize_bp.route("/finalize/status", methods=["GET"])
@admin_required
def finalize_status():
    """
    Returns the active election config for the admin's district,
    whether it is eligible for finalization, and live assignment counts.
    """
    district = (request.user.get("district") or "").strip()
    if not district:
        return err("Admin has no district configured", 400)

    cfg = get_active_election(district)
    if not cfg:
        return ok({
            "hasActiveConfig": False,
            "config":          None,
            "canFinalize":     False,
            "dateInPast":      False,
            "readyToFinalize": False,
            "alreadyFinalized": False,
            "counts":          {},
        })

    d_ids      = _district_admin_ids(district)
    ph, params = _ph(d_ids)

    election_date = cfg.get("election_date")
    today         = date.today()
    date_in_past  = bool(election_date and election_date < today)
    already_final = bool(cfg.get("is_finalized"))
    ready         = date_in_past and not already_final

    conn = get_db()
    try:
        with conn.cursor() as cur:

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
        "hasActiveConfig":  True,
        "readyToFinalize":  ready,
        "canFinalize":      True,
        "dateInPast":       date_in_past,
        "alreadyFinalized": already_final,
        "config": {
            "id":           cfg["id"],
            "electionName": cfg.get("election_name")  or "",
            "electionType": cfg.get("election_type")  or "",
            "electionDate": str(election_date) if election_date else "",
            "phase":        cfg.get("phase")          or "",
            "electionYear": cfg.get("election_year")  or "",
            "state":        cfg.get("state")          or "",
            "pratahSamay":  cfg.get("pratah_samay")   or "",
            "sayaSamay":    cfg.get("saya_samay")      or "",
            "isFinalized":  already_final,
        },
        "counts": {
            "boothAssignments":    booth_count,
            "districtAssignments": district_count,
            "kshetraOfficers":     kshetra_count,
            "zonalOfficers":       zonal_count,
            "sectorOfficers":      sector_count,
        },
    })


# ═════════════════════════════════════════════════════════════════════════════
#  MANUAL FINALIZE
# ═════════════════════════════════════════════════════════════════════════════

@election_finalize_bp.route("/finalize", methods=["POST"])
@admin_required
def finalize_now():
    """
    Manually finalize the active election for the admin's district.
    All live duty data is archived to history tables, super zones are
    unlocked, and the election config is marked finalized.

    Body (optional):
      { "force": true }  →  bypass date guard (for testing / admin override)
    """
    body     = request.get_json() or {}
    force    = bool(body.get("force", False))
    district = (request.user.get("district") or "").strip()

    if not district:
        return err("Admin has no district configured", 400)

    cfg = get_active_election(district)
    if not cfg:
        return err(
            "कोई सक्रिय चुनाव कॉन्फ़िगरेशन नहीं है। "
            "(No active election config to finalize.)",
            404,
        )

    if cfg.get("is_finalized"):
        return err(
            f"Election '{cfg.get('election_name')}' is already finalized. "
            "Ask the master to create a new election config.",
            409,
        )

    # Date guard
    if not force:
        election_date = cfg.get("election_date")
        if election_date is None:
            return err(
                "Election date is not set. Ask the master to set it first.",
                400,
            )
        if election_date > date.today():
            return err(
                f"Election date is {election_date} — finalization is only allowed "
                "on or after the election date. Pass force=true to override.",
                400,
            )

    try:
        finalize_district_auto(district, cfg["id"])

        # Stamp as manual finalize
        conn = get_db()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE election_configs SET auto_finalized=0, finalized_by=%s WHERE id=%s",
                    (_admin_id(), cfg["id"]),
                )
            conn.commit()
        finally:
            conn.close()

    except Exception as e:
        write_log("ERROR", f"manual finalize failed: {e}", "ElectionFinalize")
        return err(f"Finalize failed: {e}", 500)

    write_log(
        "INFO",
        f"Manual finalize: election={cfg['id']} district={district} "
        f"by user {_admin_id()}",
        "ElectionFinalize",
    )

    return ok(
        {
            "electionId":  cfg["id"],
            "district":    district,
            "electionName": cfg.get("election_name", ""),
        },
        "चुनाव सफलतापूर्वक समाप्त किया गया (Election finalized successfully)",
    )


# ═════════════════════════════════════════════════════════════════════════════
#  AUTO-CHECK — cron / scheduler
# ═════════════════════════════════════════════════════════════════════════════

@election_finalize_bp.route("/finalize/auto-check", methods=["GET", "POST"])
def finalize_auto_check():
    """
    Sweep every district whose election_date has passed and finalize
    automatically. Safe to hit via cron / GET.
    Add reverse-proxy auth if you want to restrict access.
    """
    try:
        result = sweep_auto_finalize_all_districts()
        write_log(
            "INFO",
            f"Auto-finalize sweep: {len(result.get('finalized', []))} finalized, "
            f"{len(result.get('errors', []))} errors",
            "ElectionFinalize",
        )
        return ok(result, "Auto-finalize sweep complete")
    except Exception as e:
        write_log("ERROR", f"auto-check sweep failed: {e}", "ElectionFinalize")
        return err(f"Sweep failed: {e}", 500)


# ═════════════════════════════════════════════════════════════════════════════
#  HISTORY — LIST
# ═════════════════════════════════════════════════════════════════════════════

@election_finalize_bp.route("/history", methods=["GET"])
@admin_required
def list_history():
    """
    List past (finalized / archived) elections.
    - admin / super_admin : own district only
    - master              : all districts (filter via ?district= and ?name=)
    """
    role     = request.user.get("role")
    district = request.user.get("district") or ""
    name_q   = (request.args.get("name")     or "").strip()
    dist_q   = (request.args.get("district") or "").strip()

    where  = ["is_finalized = 1"]
    params = []

    if role == "master":
        if dist_q:
            where.append("district = %s")
            params.append(dist_q)
    else:
        where.append("district = %s")
        params.append(district)

    if name_q:
        where.append("election_name LIKE %s")
        params.append(f"%{name_q}%")

    where_sql = " AND ".join(where)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT id, district, state, election_type, election_name,
                       phase, election_year, election_date,
                       pratah_samay, saya_samay, instructions,
                       auto_finalized, is_finalized,
                       finalized_at, finalized_by,
                       archived_at, created_at
                FROM election_configs
                WHERE {where_sql}
                ORDER BY COALESCE(finalized_at, archived_at, created_at) DESC
            """, params)
            configs = cur.fetchall()

            if not configs:
                return ok([])

            cfg_ids = [c["id"] for c in configs]
            c_ph    = ",".join(["%s"] * len(cfg_ids))

            def _counts(table, election_col="election_id"):
                cur.execute(f"""
                    SELECT {election_col} AS eid, COUNT(*) AS cnt
                    FROM {table}
                    WHERE {election_col} IN ({c_ph})
                    GROUP BY {election_col}
                """, cfg_ids)
                return {r["eid"]: int(r["cnt"] or 0) for r in cur.fetchall()}

            booth_map    = _counts("duty_assignments_history")
            district_map = _counts("district_duty_history")
            kshetra_map  = _counts("kshetra_officers_history")
            zonal_map    = _counts("zonal_officers_history")
            sector_map   = _counts("sector_officers_history")

    finally:
        conn.close()

    return ok([{
        "id":                          c["id"],
        "district":                    c["district"]       or "",
        "state":                       c["state"]          or "",
        "electionName":                c["election_name"]  or "",
        "electionType":                c["election_type"]  or "",
        "electionDate":                str(c["election_date"]) if c["election_date"] else "",
        "phase":                       c["phase"]          or "",
        "electionYear":                c["election_year"]  or "",
        "isFinalized":                 bool(c["is_finalized"]),
        "autoFinalized":               bool(c.get("auto_finalized")),
        "finalizedAt":                 str(c["finalized_at"]) if c["finalized_at"] else "",
        "archivedAt":                  str(c["archived_at"])  if c["archived_at"]  else "",
        "createdAt":                   str(c["created_at"]),
        "boothAssignmentsArchived":    booth_map.get(c["id"],    0),
        "districtAssignmentsArchived": district_map.get(c["id"], 0),
        "kshetraOfficersArchived":     kshetra_map.get(c["id"],  0),
        "zonalOfficersArchived":       zonal_map.get(c["id"],    0),
        "sectorOfficersArchived":      sector_map.get(c["id"],   0),
        "totalArchived": (
            booth_map.get(c["id"], 0) +
            district_map.get(c["id"], 0) +
            kshetra_map.get(c["id"], 0) +
            zonal_map.get(c["id"], 0) +
            sector_map.get(c["id"], 0)
        ),
    } for c in configs])


# ═════════════════════════════════════════════════════════════════════════════
#  HISTORY — DETAIL
# ═════════════════════════════════════════════════════════════════════════════

@election_finalize_bp.route("/history/<int:eid>", methods=["GET"])
@admin_required
def history_detail(eid):
    """Full election config + summary counts for one archived election."""
    role     = request.user.get("role")
    district = request.user.get("district") or ""

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM election_configs WHERE id = %s", (eid,))
            cfg = cur.fetchone()
            if not cfg:
                return err("Election not found", 404)
            if role != "master" and cfg["district"] != district:
                return err("Access denied", 403)

            d_ids      = _district_admin_ids(cfg["district"])
            ph, params = _ph(d_ids)

            # Booth assignments grouped by center_type
            cur.execute(f"""
                SELECT center_type,
                       COUNT(*)                  AS total_staff,
                       COUNT(DISTINCT sthal_id)  AS centers_covered,
                       SUM(attended)             AS total_attended
                FROM duty_assignments_history
                WHERE election_id = %s AND admin_id IN ({ph})
                GROUP BY center_type
            """, [eid] + params)
            booth_by_type = cur.fetchall()

            # District duties grouped by duty_type
            cur.execute(f"""
                SELECT duty_type, duty_label_hi,
                       MAX(batch_no)             AS batch_count,
                       COUNT(DISTINCT staff_id)  AS total_staff
                FROM district_duty_history
                WHERE election_id = %s AND admin_id IN ({ph})
                GROUP BY duty_type, duty_label_hi
                ORDER BY duty_type
            """, [eid] + params)
            district_summary = cur.fetchall()

            # Officer counts
            def _officer_count(table):
                cur.execute(
                    f"SELECT COUNT(*) AS cnt FROM {table} "
                    f"WHERE election_id = %s AND admin_id IN ({ph})",
                    [eid] + params,
                )
                return int(cur.fetchone()["cnt"] or 0)

            kshetra_count = _officer_count("kshetra_officers_history")
            zonal_count   = _officer_count("zonal_officers_history")
            sector_count  = _officer_count("sector_officers_history")

            # Overall assignment counts (for compatibility)
            cur.execute(
                "SELECT COUNT(*) AS c FROM duty_assignments_history WHERE election_id=%s",
                (eid,),
            )
            booth_total = int(cur.fetchone()["c"] or 0)

            cur.execute(
                "SELECT COUNT(*) AS c FROM district_duty_history WHERE election_id=%s",
                (eid,),
            )
            district_total = int(cur.fetchone()["c"] or 0)

    finally:
        conn.close()

    return ok({
        "config": {
            "id":           cfg["id"],
            "district":     cfg["district"]       or "",
            "state":        cfg.get("state")      or "",
            "electionName": cfg["election_name"]  or "",
            "electionType": cfg.get("election_type") or "",
            "electionDate": str(cfg["election_date"]) if cfg["election_date"] else "",
            "phase":        cfg.get("phase")      or "",
            "electionYear": cfg.get("election_year") or "",
            "pratahSamay":  cfg.get("pratah_samay")  or "",
            "sayaSamay":    cfg.get("saya_samay")     or "",
            "instructions": cfg.get("instructions")  or "",
            "isFinalized":  bool(cfg.get("is_finalized")),
            "finalizedAt":  str(cfg["finalized_at"])  if cfg.get("finalized_at") else "",
            "archivedAt":   str(cfg["archived_at"])   if cfg.get("archived_at")  else "",
        },
        "boothSummary": [{
            "centerType":     r["center_type"]    or "",
            "totalStaff":     int(r["total_staff"]     or 0),
            "centersCovered": int(r["centers_covered"] or 0),
            "totalAttended":  int(r["total_attended"]  or 0),
        } for r in booth_by_type],
        "districtDutySummary": [{
            "dutyType":    r["duty_type"]     or "",
            "dutyLabelHi": r["duty_label_hi"] or "",
            "batchCount":  int(r["batch_count"] or 0),
            "totalStaff":  int(r["total_staff"] or 0),
        } for r in district_summary],
        "officerSummary": {
            "kshetraOfficers": kshetra_count,
            "zonalOfficers":   zonal_count,
            "sectorOfficers":  sector_count,
        },
        # Flat counts (backward-compatible)
        "boothAssigned":    booth_total,
        "districtAssigned": district_total,
        "kshetraOfficers":  kshetra_count,
        "zonalOfficers":    zonal_count,
        "sectorOfficers":   sector_count,
        "totalAssigned":    booth_total + district_total + kshetra_count + zonal_count + sector_count,
    })


# ═════════════════════════════════════════════════════════════════════════════
#  HISTORY — BOOTH ASSIGNMENTS (paginated)
# ═════════════════════════════════════════════════════════════════════════════

@election_finalize_bp.route("/history/<int:eid>/booth-assignments", methods=["GET"])
@admin_required
def history_booth_assignments(eid):
    """Paginated booth assignment records for one archived election."""
    district    = (request.user.get("district") or "").strip()
    d_ids       = _district_admin_ids(district)
    ph, params  = _ph(d_ids)
    search      = request.args.get("q",          "").strip()
    center_type = request.args.get("centerType", "").strip()
    page, limit, offset = _page_params()

    _verify_election_district(eid, district)

    where   = ["dah.election_id = %s", f"dah.admin_id IN ({ph})"]
    wparams = [eid] + params

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
            cur.execute(
                f"SELECT COUNT(*) AS cnt FROM duty_assignments_history dah WHERE {where_sql}",
                wparams,
            )
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

    return _paginated([{
        "id":             r["id"],
        "originalId":     r["original_id"],
        "staffId":        r["staff_id"],
        "sthalId":        r["sthal_id"],
        "staffName":      r["staff_name"]     or "",
        "staffPno":       r["staff_pno"]      or "",
        "staffMobile":    r["staff_mobile"]   or "",
        "staffRank":      r["staff_rank"]      or "",
        "staffDistrict":  r["staff_district"] or "",
        "staffThana":     r["staff_thana"]    or "",
        "isArmed":        bool(r["is_armed"]),
        "centerName":     r["center_name"]    or "",
        "centerType":     r["center_type"]    or "",
        "busNo":          r["bus_no"]         or "",
        "electionDate":   str(r["election_date"]) if r["election_date"] else "",
        "attended":       bool(r["attended"]),
        "cardDownloaded": bool(r["card_downloaded"]),
        "archivedAt":     str(r["archived_at"]),
    } for r in rows], total, page, limit)


# ═════════════════════════════════════════════════════════════════════════════
#  HISTORY — DISTRICT DUTIES (paginated)
# ═════════════════════════════════════════════════════════════════════════════

@election_finalize_bp.route("/history/<int:eid>/district-duties", methods=["GET"])
@admin_required
def history_district_duties(eid):
    """Paginated district duty records for one archived election."""
    district    = (request.user.get("district") or "").strip()
    d_ids       = _district_admin_ids(district)
    ph, params  = _ph(d_ids)
    search      = request.args.get("q",        "").strip()
    duty_type   = request.args.get("dutyType", "").strip()
    batch_no    = request.args.get("batchNo",  None)
    page, limit, offset = _page_params()

    _verify_election_district(eid, district)

    where   = ["ddh.election_id = %s", f"ddh.admin_id IN ({ph})"]
    wparams = [eid] + params

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
            cur.execute(
                f"SELECT COUNT(*) AS cnt FROM district_duty_history ddh WHERE {where_sql}",
                wparams,
            )
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

    return _paginated([{
        "id":            r["id"],
        "originalId":    r["original_id"],
        "dutyType":      r["duty_type"]     or "",
        "dutyLabelHi":   r["duty_label_hi"] or "",
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
    } for r in rows], total, page, limit)


# ═════════════════════════════════════════════════════════════════════════════
#  HISTORY — OFFICERS (kshetra + zonal + sector combined)
# ═════════════════════════════════════════════════════════════════════════════

@election_finalize_bp.route("/history/<int:eid>/officers", methods=["GET"])
@admin_required
def history_officers(eid):
    """All officer snapshots (kshetra + zonal + sector) for one archived election."""
    district    = (request.user.get("district") or "").strip()
    d_ids       = _district_admin_ids(district)
    ph, params  = _ph(d_ids)
    search      = request.args.get("q", "").strip()
    like        = f"%{search}%"

    _verify_election_district(eid, district)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # ── Kshetra officers ─────────────────────────────────────────────
            q  = [f"election_id = %s", f"admin_id IN ({ph})"]
            qp = [eid] + params
            if search:
                q.append(
                    "(name LIKE %s OR pno LIKE %s OR user_rank LIKE %s "
                    "OR super_zone_name LIKE %s)"
                )
                qp += [like, like, like, like]
            cur.execute(f"""
                SELECT id, original_id, super_zone_id, super_zone_name,
                       super_zone_block, user_id, name, pno, mobile,
                       user_rank, archived_at
                FROM kshetra_officers_history
                WHERE {" AND ".join(q)}
                ORDER BY super_zone_name, name
            """, qp)
            kshetra = cur.fetchall()

            # ── Zonal officers ───────────────────────────────────────────────
            q2  = [f"election_id = %s", f"admin_id IN ({ph})"]
            qp2 = [eid] + params
            if search:
                q2.append(
                    "(name LIKE %s OR pno LIKE %s OR user_rank LIKE %s "
                    "OR zone_name LIKE %s OR super_zone_name LIKE %s)"
                )
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

            # ── Sector officers ──────────────────────────────────────────────
            q3  = [f"election_id = %s", f"admin_id IN ({ph})"]
            qp3 = [eid] + params
            if search:
                q3.append(
                    "(name LIKE %s OR pno LIKE %s OR user_rank LIKE %s "
                    "OR sector_name LIKE %s OR zone_name LIKE %s "
                    "OR super_zone_name LIKE %s)"
                )
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

    return ok({
        "kshetraOfficers": [{
            "id":             r["id"],
            "originalId":     r["original_id"],
            "superZoneId":    r["super_zone_id"],
            "superZoneName":  r["super_zone_name"]  or "",
            "superZoneBlock": r["super_zone_block"]  or "",
            "userId":         r["user_id"],
            "name":           r["name"]             or "",
            "pno":            r["pno"]              or "",
            "mobile":         r["mobile"]           or "",
            "rank":           r["user_rank"]         or "",
            "archivedAt":     str(r["archived_at"]),
        } for r in kshetra],
        "zonalOfficers": [{
            "id":            r["id"],
            "originalId":    r["original_id"],
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
        } for r in zonal],
        "sectorOfficers": [{
            "id":            r["id"],
            "originalId":    r["original_id"],
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
        } for r in sector],
    })


# ═════════════════════════════════════════════════════════════════════════════
#  HISTORY — RULES SNAPSHOT
# ═════════════════════════════════════════════════════════════════════════════

@election_finalize_bp.route("/history/<int:eid>/rules", methods=["GET"])
@admin_required
def history_rules(eid):
    """Booth rules + district rules snapshots for one archived election."""
    district    = (request.user.get("district") or "").strip()
    d_ids       = _district_admin_ids(district)
    ph, params  = _ph(d_ids)

    _verify_election_district(eid, district)

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
                ORDER BY FIELD(sensitivity,'A++','A','B','C'), booth_count
            """, [eid] + params)
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
            """, [eid] + params)
            district_rules = cur.fetchall()

    finally:
        conn.close()

    return ok({
        "boothRules": [{
            "sensitivity":       r["sensitivity"],
            "boothCount":        r["booth_count"],
            "siArmedCount":      r["si_armed_count"],
            "siUnarmedCount":    r["si_unarmed_count"],
            "hcArmedCount":      r["hc_armed_count"],
            "hcUnarmedCount":    r["hc_unarmed_count"],
            "constArmedCount":   r["const_armed_count"],
            "constUnarmedCount": r["const_unarmed_count"],
            "auxArmedCount":     r["aux_armed_count"],
            "auxUnarmedCount":   r["aux_unarmed_count"],
            "pacCount":          float(r["pac_count"] or 0),
        } for r in booth_rules],
        "districtRules": [{
            "dutyType":          r["duty_type"]       or "",
            "dutyLabelHi":       r["duty_label_hi"]   or "",
            "sankhya":           r["sankhya"]          or 0,
            "siArmedCount":      r["si_armed_count"],
            "siUnarmedCount":    r["si_unarmed_count"],
            "hcArmedCount":      r["hc_armed_count"],
            "hcUnarmedCount":    r["hc_unarmed_count"],
            "constArmedCount":   r["const_armed_count"],
            "constUnarmedCount": r["const_unarmed_count"],
            "auxArmedCount":     r["aux_armed_count"],
            "auxUnarmedCount":   r["aux_unarmed_count"],
            "pacCount":          float(r["pac_count"] or 0),
            "sortOrder":         r["sort_order"]       or 0,
        } for r in district_rules],
    })