"""
election_history_report.py
──────────────────────────
All history report endpoints consumed by ElectionHistoryListPage
and ElectionHistoryReportPage in Flutter.

Register in app.py:
    from election_history_report import history_report_bp
    app.register_blueprint(history_report_bp)

ENDPOINTS  (all under /api/admin/election/history)
────────────────────────────────────────────────────────────────────────────
  GET  /all-elections                                   ← master only
  GET  /districts-list                                  ← master only

  GET  /<election_id>/booth-manak
  GET  /<election_id>/district-rules-full
  GET  /<election_id>/district-duty-summary
  GET  /<election_id>/district-duty/<duty_type>/batches
  GET  /<election_id>/hierarchy-overview
  GET  /<election_id>/booth-assignments-summary
  GET  /<election_id>/booth-assignments          (paginated + search)
  GET  /<election_id>/all-district-duties        (paginated + search)
────────────────────────────────────────────────────────────────────────────
"""

from flask import Blueprint, request, abort
from db import get_db
from app.routes import admin_required, ok, err, write_log

history_report_bp = Blueprint(
    "history_report", __name__,
    url_prefix="/api/admin/election/history"
)


# ═════════════════════════════════════════════════════════════════════════════
#  INTERNAL HELPERS
# ═════════════════════════════════════════════════════════════════════════════

def _admin_id():
    return request.user["id"]

def _role():
    return request.user.get("role", "admin")

def _district():
    return (request.user.get("district") or "").strip()

def _district_admin_ids(district: str) -> list:
    """All admin/super_admin IDs in the same district."""
    if not district:
        return [_admin_id()]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM users "
                "WHERE role IN ('admin','super_admin','master') AND district = %s",
                (district,)
            )
            ids = [r["id"] for r in cur.fetchall()]
            if _admin_id() not in ids:
                ids.append(_admin_id())
            return ids or [_admin_id()]
    finally:
        conn.close()

def _ph(ids: list):
    """SQL IN placeholder + list."""
    return ",".join(["%s"] * len(ids)), list(ids)

def _verify_election_access(election_id: int) -> dict:
    """
    Returns the election_configs row if current user may access it.
    Masters: any election.  Admin/super_admin: only their district.
    Aborts 404 if not found / not permitted.
    """
    role     = _role()
    district = _district()
    conn = get_db()
    try:
        with conn.cursor() as cur:
            if role == "master":
                cur.execute(
                    "SELECT id, district, election_name, election_type, "
                    "election_date, phase, election_year, state, "
                    "is_finalized, finalized_at, archived_at "
                    "FROM election_configs WHERE id = %s",
                    (election_id,)
                )
            else:
                cur.execute(
                    "SELECT id, district, election_name, election_type, "
                    "election_date, phase, election_year, state, "
                    "is_finalized, finalized_at, archived_at "
                    "FROM election_configs "
                    "WHERE id = %s AND district = %s",
                    (election_id, district)
                )
            cfg = cur.fetchone()
            if not cfg:
                abort(404)
            return cfg
    finally:
        conn.close()

def _page_params():
    page  = max(1, int(request.args.get("page",  1)))
    limit = min(200, max(1, int(request.args.get("limit", 50))))
    return page, limit, (page - 1) * limit


# ═════════════════════════════════════════════════════════════════════════════
#  MASTER-ONLY: list all finalized elections across all districts
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/all-elections", methods=["GET"])
@admin_required
def all_elections():
    """Master can see finalized elections for every district, with optional filter."""
    if _role() != "master":
        return err("Master access required", 403)

    district_filter = request.args.get("district", "").strip()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            if district_filter:
                cur.execute("""
                    SELECT id, district, election_name, election_type,
                           election_date, phase, election_year, state,
                           is_finalized, finalized_at, archived_at, created_at
                    FROM election_configs
                    WHERE (is_archived = 1 OR is_finalized = 1)
                      AND district = %s
                    ORDER BY district, id DESC
                """, (district_filter,))
            else:
                cur.execute("""
                    SELECT id, district, election_name, election_type,
                           election_date, phase, election_year, state,
                           is_finalized, finalized_at, archived_at, created_at
                    FROM election_configs
                    WHERE (is_archived = 1 OR is_finalized = 1)
                    ORDER BY district, id DESC
                """)
            configs = cur.fetchall()

            if not configs:
                return ok([])

            cfg_ids = [c["id"] for c in configs]
            c_ph    = ",".join(["%s"] * len(cfg_ids))

            def _cnt(table):
                cur.execute(f"""
                    SELECT election_id AS eid, COUNT(*) AS cnt
                    FROM {table}
                    WHERE election_id IN ({c_ph})
                    GROUP BY election_id
                """, cfg_ids)
                return {r["eid"]: r["cnt"] for r in cur.fetchall()}

            booth_map    = _cnt("duty_assignments_history")
            district_map = _cnt("district_duty_history")
            kshetra_map  = _cnt("kshetra_officers_history")
            zonal_map    = _cnt("zonal_officers_history")
            sector_map   = _cnt("sector_officers_history")

    finally:
        conn.close()

    return ok([{
        "id":                          c["id"],
        "district":                    c["district"]      or "",
        "electionName":                c["election_name"] or "",
        "electionType":                c["election_type"] or "",
        "electionDate":                str(c["election_date"]) if c["election_date"] else "",
        "phase":                       c["phase"]         or "",
        "electionYear":                c["election_year"] or "",
        "state":                       c["state"]         or "",
        "isFinalized":                 bool(c["is_finalized"]),
        "finalizedAt":                 str(c["finalized_at"]) if c["finalized_at"] else "",
        "archivedAt":                  str(c["archived_at"])  if c["archived_at"]  else "",
        "boothAssigned":               booth_map.get(c["id"],    0),
        "districtAssigned":            district_map.get(c["id"], 0),
        "boothAssignmentsArchived":    booth_map.get(c["id"],    0),
        "districtAssignmentsArchived": district_map.get(c["id"], 0),
        "kshetraOfficersArchived":     kshetra_map.get(c["id"],  0),
        "zonalOfficersArchived":       zonal_map.get(c["id"],    0),
        "sectorOfficersArchived":      sector_map.get(c["id"],   0),
    } for c in configs])


# ─────────────────────────────────────────────────────────────────────────────
#  MASTER-ONLY: distinct district names that have finalized elections
# ─────────────────────────────────────────────────────────────────────────────

@history_report_bp.route("/districts-list", methods=["GET"])
@admin_required
def districts_list():
    if _role() != "master":
        return err("Master access required", 403)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT DISTINCT district
                FROM election_configs
                WHERE (is_archived = 1 OR is_finalized = 1)
                  AND district IS NOT NULL AND district != ''
                ORDER BY district
            """)
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([r["district"] for r in rows])


# ═════════════════════════════════════════════════════════════════════════════
#  TAB 1 — BOOTH MANAK  (booth_rules_history)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/<int:election_id>/booth-manak", methods=["GET"])
@admin_required
def history_booth_manak(election_id):
    """Returns archived booth rules grouped by sensitivity (A++/A/B/C)."""
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT sensitivity, booth_count,
                       si_armed_count,    si_unarmed_count,
                       hc_armed_count,    hc_unarmed_count,
                       const_armed_count, const_unarmed_count,
                       aux_armed_count,   aux_unarmed_count,
                       pac_count
                FROM booth_rules_history
                WHERE election_id = %s AND admin_id IN ({ph})
                ORDER BY FIELD(sensitivity,'A++','A','B','C'), booth_count
            """, [election_id] + params)
            rows = cur.fetchall()
    finally:
        conn.close()

    grouped = {"A++": [], "A": [], "B": [], "C": []}
    for r in rows:
        s = r["sensitivity"]
        if s in grouped:
            grouped[s].append({
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
            })
    return ok(grouped)


# ═════════════════════════════════════════════════════════════════════════════
#  TAB 2 — DISTRICT RULES FULL  (district_rules_history)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/<int:election_id>/district-rules-full", methods=["GET"])
@admin_required
def history_district_rules_full(election_id):
    """Returns full archived district rules (manak) list."""
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT duty_type, duty_label_hi, sankhya,
                       si_armed_count,    si_unarmed_count,
                       hc_armed_count,    hc_unarmed_count,
                       const_armed_count, const_unarmed_count,
                       aux_armed_count,   aux_unarmed_count,
                       pac_count, sort_order
                FROM district_rules_history
                WHERE election_id = %s AND admin_id IN ({ph})
                ORDER BY sort_order, duty_type
            """, [election_id] + params)
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "dutyType":          r["duty_type"]       or "",
        "dutyLabelHi":       r["duty_label_hi"]   or "",
        "sankhya":           int(r["sankhya"]      or 0),
        "siArmedCount":      int(r["si_armed_count"]),
        "siUnarmedCount":    int(r["si_unarmed_count"]),
        "hcArmedCount":      int(r["hc_armed_count"]),
        "hcUnarmedCount":    int(r["hc_unarmed_count"]),
        "constArmedCount":   int(r["const_armed_count"]),
        "constUnarmedCount": int(r["const_unarmed_count"]),
        "auxArmedCount":     int(r["aux_armed_count"]),
        "auxUnarmedCount":   int(r["aux_unarmed_count"]),
        "pacCount":          float(r["pac_count"] or 0),
        "sortOrder":         int(r["sort_order"]  or 0),
    } for r in rows])


# ═════════════════════════════════════════════════════════════════════════════
#  TAB 3 — DISTRICT DUTY SUMMARY  (per duty_type totals)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/<int:election_id>/district-duty-summary", methods=["GET"])
@admin_required
def history_district_duty_summary(election_id):
    """Returns district_duty_history grouped by duty_type with staff/batch counts."""
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT
                    ddh.duty_type,
                    ddh.duty_label_hi,
                    COUNT(DISTINCT ddh.staff_id)  AS total_staff,
                    COUNT(DISTINCT ddh.batch_no)  AS batch_count,
                    MAX(ddh.batch_no)             AS max_batch,
                    SUM(CASE WHEN ddh.is_armed=1 THEN 1 ELSE 0 END) AS armed_count,
                    SUM(CASE WHEN ddh.is_armed=0 THEN 1 ELSE 0 END) AS unarmed_count,
                    -- pull sankhya from archived rules snapshot
                    COALESCE(drh.sankhya, 0) AS sankhya
                FROM district_duty_history ddh
                LEFT JOIN district_rules_history drh
                    ON drh.election_id = ddh.election_id
                   AND drh.admin_id   = ddh.admin_id
                   AND drh.duty_type  = ddh.duty_type
                WHERE ddh.election_id = %s AND ddh.admin_id IN ({ph})
                GROUP BY ddh.duty_type, ddh.duty_label_hi, drh.sankhya
                ORDER BY ddh.duty_type
            """, [election_id] + params)
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "dutyType":     r["duty_type"]      or "",
        "dutyLabelHi":  r["duty_label_hi"]  or "",
        "totalStaff":   int(r["total_staff"]   or 0),
        "batchCount":   int(r["batch_count"]   or 0),
        "maxBatch":     int(r["max_batch"]     or 0),
        "armedCount":   int(r["armed_count"]   or 0),
        "unarmedCount": int(r["unarmed_count"] or 0),
        "sankhya":      int(r["sankhya"]       or 0),
    } for r in rows])


# ═════════════════════════════════════════════════════════════════════════════
#  TAB 3 — DUTY BATCH DETAIL  (per duty_type, all batches + staff)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route(
    "/<int:election_id>/district-duty/<duty_type>/batches",
    methods=["GET"]
)
@admin_required
def history_duty_batches(election_id, duty_type):
    """
    Returns batch-grouped staff list for one duty_type.
    Response: [ { batchNo, staffCount, busNo, note, staff: [...] } ]
    """
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Batch summary
            cur.execute(f"""
                SELECT batch_no,
                       COUNT(*)   AS staff_count,
                       MAX(bus_no) AS bus_no,
                       MAX(note)   AS note
                FROM district_duty_history
                WHERE election_id = %s AND admin_id IN ({ph}) AND duty_type = %s
                GROUP BY batch_no
                ORDER BY batch_no
            """, [election_id] + params + [duty_type])
            batch_summary = cur.fetchall()

            if not batch_summary:
                return ok([])

            batch_numbers = [b["batch_no"] for b in batch_summary]
            b_ph = ",".join(["%s"] * len(batch_numbers))

            # All staff for these batches
            cur.execute(f"""
                SELECT
                    ddh.id,
                    ddh.batch_no,
                    ddh.bus_no,
                    ddh.note,
                    ddh.staff_id,
                    ddh.staff_name,
                    ddh.staff_pno,
                    ddh.staff_mobile,
                    ddh.staff_rank,
                    ddh.staff_thana,
                    ddh.staff_district,
                    ddh.is_armed,
                    ddh.archived_at
                FROM district_duty_history ddh
                WHERE ddh.election_id = %s
                  AND ddh.admin_id IN ({ph})
                  AND ddh.duty_type = %s
                  AND ddh.batch_no  IN ({b_ph})
                ORDER BY ddh.batch_no, ddh.staff_name
            """, [election_id] + params + [duty_type] + batch_numbers)
            rows = cur.fetchall()

    finally:
        conn.close()

    # Group by batch
    staff_by_batch = {}
    for r in rows:
        bn = r["batch_no"]
        staff_by_batch.setdefault(bn, []).append({
            "id":       r["id"],
            "staffId":  r["staff_id"],
            "name":     r["staff_name"]     or "",
            "pno":      r["staff_pno"]      or "",
            "mobile":   r["staff_mobile"]   or "",
            "rank":     r["staff_rank"]     or "",
            "thana":    r["staff_thana"]    or "",
            "district": r["staff_district"] or "",
            "isArmed":  bool(r["is_armed"]),
            "busNo":    r["bus_no"]         or "",
            "note":     r["note"]           or "",
        })

    return ok([{
        "batchNo":    b["batch_no"],
        "staffCount": int(b["staff_count"]),
        "busNo":      b["bus_no"] or "",
        "note":       b["note"]  or "",
        "staff":      staff_by_batch.get(b["batch_no"], []),
    } for b in batch_summary])


# ═════════════════════════════════════════════════════════════════════════════
#  TAB 4 — HIERARCHY OVERVIEW  (officers per super-zone → zone → sector)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/<int:election_id>/hierarchy-overview", methods=["GET"])
@admin_required
def history_hierarchy_overview(election_id):
    """
    Returns a nested structure:
      superZones[ { superZoneName, superZoneBlock, kshetraOfficers[],
                    zones[ { zoneName, zonalOfficers[],
                              sectors[ { sectorName, sectorOfficers[] } ] } ] } ]
    plus a summary counts object.
    """
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # Kshetra officers
            cur.execute(f"""
                SELECT super_zone_id, super_zone_name, super_zone_block,
                       user_id, name, pno, mobile, user_rank
                FROM kshetra_officers_history
                WHERE election_id = %s AND admin_id IN ({ph})
                ORDER BY super_zone_name, name
            """, [election_id] + params)
            kshetra_rows = cur.fetchall()

            # Zonal officers
            cur.execute(f"""
                SELECT zone_id, zone_name, super_zone_id, super_zone_name,
                       user_id, name, pno, mobile, user_rank
                FROM zonal_officers_history
                WHERE election_id = %s AND admin_id IN ({ph})
                ORDER BY super_zone_name, zone_name, name
            """, [election_id] + params)
            zonal_rows = cur.fetchall()

            # Sector officers
            cur.execute(f"""
                SELECT sector_id, sector_name, zone_id, zone_name,
                       super_zone_id, super_zone_name,
                       user_id, name, pno, mobile, user_rank
                FROM sector_officers_history
                WHERE election_id = %s AND admin_id IN ({ph})
                ORDER BY super_zone_name, zone_name, sector_name, name
            """, [election_id] + params)
            sector_rows = cur.fetchall()

            # Summary counts
            cur.execute(f"""
                SELECT COUNT(DISTINCT super_zone_id) AS sz_count
                FROM kshetra_officers_history
                WHERE election_id = %s AND admin_id IN ({ph})
            """, [election_id] + params)
            sz_count = (cur.fetchone() or {}).get("sz_count", 0) or 0

            cur.execute(f"""
                SELECT COUNT(DISTINCT zone_id) AS z_count
                FROM zonal_officers_history
                WHERE election_id = %s AND admin_id IN ({ph})
            """, [election_id] + params)
            z_count = (cur.fetchone() or {}).get("z_count", 0) or 0

            cur.execute(f"""
                SELECT COUNT(DISTINCT sector_id) AS s_count
                FROM sector_officers_history
                WHERE election_id = %s AND admin_id IN ({ph})
            """, [election_id] + params)
            s_count = (cur.fetchone() or {}).get("s_count", 0) or 0

    finally:
        conn.close()

    # ── Build nested super-zone map ───────────────────────────────────────────
    sz_map = {}   # szid → { ..., zones: { zid → { ..., sectors: { sid → ... } } } }

    def _ensure_sz(szid, szname, szblock=""):
        if szid not in sz_map:
            sz_map[szid] = {
                "superZoneId":     szid,
                "superZoneName":   szname  or "",
                "superZoneBlock":  szblock or "",
                "kshetraOfficers": [],
                "zones":           {},
            }

    def _ensure_zone(szid, zid, zname):
        if zid not in sz_map[szid]["zones"]:
            sz_map[szid]["zones"][zid] = {
                "zoneId":        zid,
                "zoneName":      zname or "",
                "zonalOfficers": [],
                "sectors":       {},
            }

    def _officer(r):
        return {
            "userId": r["user_id"],
            "name":   r["name"]      or "",
            "pno":    r["pno"]       or "",
            "mobile": r["mobile"]    or "",
            "rank":   r["user_rank"] or "",
        }

    for r in kshetra_rows:
        _ensure_sz(r["super_zone_id"], r["super_zone_name"], r["super_zone_block"])
        sz_map[r["super_zone_id"]]["kshetraOfficers"].append(_officer(r))

    for r in zonal_rows:
        _ensure_sz(r["super_zone_id"], r["super_zone_name"])
        _ensure_zone(r["super_zone_id"], r["zone_id"], r["zone_name"])
        sz_map[r["super_zone_id"]]["zones"][r["zone_id"]]["zonalOfficers"].append(_officer(r))

    for r in sector_rows:
        _ensure_sz(r["super_zone_id"], r["super_zone_name"])
        _ensure_zone(r["super_zone_id"], r["zone_id"], r["zone_name"])
        zones = sz_map[r["super_zone_id"]]["zones"]
        sid   = r["sector_id"]
        if sid not in zones[r["zone_id"]]["sectors"]:
            zones[r["zone_id"]]["sectors"][sid] = {
                "sectorId":       sid,
                "sectorName":     r["sector_name"] or "",
                "sectorOfficers": [],
            }
        zones[r["zone_id"]]["sectors"][sid]["sectorOfficers"].append(_officer(r))

    # ── Flatten to lists ──────────────────────────────────────────────────────
    result = []
    for sz in sorted(sz_map.values(), key=lambda x: x["superZoneName"]):
        zones_out = []
        for z in sorted(sz["zones"].values(), key=lambda x: x["zoneName"]):
            sectors_out = sorted(z["sectors"].values(), key=lambda x: x["sectorName"])
            zones_out.append({
                "zoneId":        z["zoneId"],
                "zoneName":      z["zoneName"],
                "zonalOfficers": z["zonalOfficers"],
                "sectors":       sectors_out,
            })
        result.append({
            "superZoneId":    sz["superZoneId"],
            "superZoneName":  sz["superZoneName"],
            "superZoneBlock": sz["superZoneBlock"],
            "kshetraOfficers": sz["kshetraOfficers"],
            "zones":          zones_out,
        })

    return ok({
        "summary": {
            "superZoneCount":  int(sz_count),
            "zoneCount":       int(z_count),
            "sectorCount":     int(s_count),
            "kshetraOfficers": len(kshetra_rows),
            "zonalOfficers":   len(zonal_rows),
            "sectorOfficers":  len(sector_rows),
        },
        "superZones": result,
    })


# ═════════════════════════════════════════════════════════════════════════════
#  TAB 5 — BOOTH ASSIGNMENTS SUMMARY  (aggregate stats for booth staff)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route(
    "/<int:election_id>/booth-assignments-summary",
    methods=["GET"]
)
@admin_required
def history_booth_assignments_summary(election_id):
    """
    Returns aggregate booth assignment stats:
      totals { total, attended, centers, armed }
      byType [ { centerType, totalStaff, centersCovered, attended, armed, unarmed } ]
      byRank [ { rank, total, armed, unarmed, attended } ]
    """
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # Overall totals
            cur.execute(f"""
                SELECT
                    COUNT(*)                                          AS total,
                    SUM(attended)                                     AS attended,
                    COUNT(DISTINCT sthal_id)                          AS centers,
                    SUM(CASE WHEN is_armed=1 THEN 1 ELSE 0 END)      AS armed,
                    SUM(CASE WHEN is_armed=0 THEN 1 ELSE 0 END)      AS unarmed,
                    SUM(card_downloaded)                              AS card_downloaded
                FROM duty_assignments_history
                WHERE election_id = %s AND admin_id IN ({ph})
            """, [election_id] + params)
            totals = cur.fetchone() or {}

            # By center_type
            cur.execute(f"""
                SELECT
                    center_type,
                    COUNT(*)                                        AS total_staff,
                    COUNT(DISTINCT sthal_id)                        AS centers_covered,
                    SUM(attended)                                   AS attended,
                    SUM(CASE WHEN is_armed=1 THEN 1 ELSE 0 END)    AS armed,
                    SUM(CASE WHEN is_armed=0 THEN 1 ELSE 0 END)    AS unarmed
                FROM duty_assignments_history
                WHERE election_id = %s AND admin_id IN ({ph})
                GROUP BY center_type
                ORDER BY FIELD(center_type,'A++','A','B','C')
            """, [election_id] + params)
            by_type = cur.fetchall()

            # By rank
            cur.execute(f"""
                SELECT
                    staff_rank,
                    COUNT(*)                                        AS total,
                    SUM(CASE WHEN is_armed=1 THEN 1 ELSE 0 END)    AS armed,
                    SUM(CASE WHEN is_armed=0 THEN 1 ELSE 0 END)    AS unarmed,
                    SUM(attended)                                   AS attended
                FROM duty_assignments_history
                WHERE election_id = %s AND admin_id IN ({ph})
                GROUP BY staff_rank
                ORDER BY FIELD(staff_rank,'SP','ASP','DSP','Inspector',
                               'SI','ASI','Head Constable','Constable')
            """, [election_id] + params)
            by_rank = cur.fetchall()

    finally:
        conn.close()

    return ok({
        "totals": {
            "total":          int(totals.get("total",          0) or 0),
            "attended":       int(totals.get("attended",       0) or 0),
            "centers":        int(totals.get("centers",        0) or 0),
            "armed":          int(totals.get("armed",          0) or 0),
            "unarmed":        int(totals.get("unarmed",        0) or 0),
            "cardDownloaded": int(totals.get("card_downloaded",0) or 0),
        },
        "byType": [{
            "centerType":     r["center_type"]      or "",
            "totalStaff":     int(r["total_staff"]   or 0),
            "centersCovered": int(r["centers_covered"] or 0),
            "attended":       int(r["attended"]      or 0),
            "armed":          int(r["armed"]         or 0),
            "unarmed":        int(r["unarmed"]       or 0),
        } for r in by_type],
        "byRank": [{
            "rank":     r["staff_rank"] or "",
            "total":    int(r["total"]    or 0),
            "armed":    int(r["armed"]    or 0),
            "unarmed":  int(r["unarmed"]  or 0),
            "attended": int(r["attended"] or 0),
        } for r in by_rank],
    })


# ═════════════════════════════════════════════════════════════════════════════
#  TAB 5 — BOOTH ASSIGNMENTS  (paginated + search list)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route(
    "/<int:election_id>/booth-assignments",
    methods=["GET"]
)
@admin_required
def history_booth_assignments(election_id):
    """
    Paginated list of archived booth assignments.
    Query params: q (search), centerType, page, limit
    """
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    search      = request.args.get("q",          "").strip()
    center_type = request.args.get("centerType", "").strip()
    page, limit, offset = _page_params()

    where   = ["dah.election_id = %s", f"dah.admin_id IN ({ph})"]
    wparams = [election_id] + params

    if search:
        where.append(
            "(dah.staff_name LIKE %s OR dah.staff_pno LIKE %s "
            "OR dah.center_name LIKE %s OR dah.staff_rank LIKE %s "
            "OR dah.staff_thana LIKE %s)"
        )
        like = f"%{search}%"
        wparams += [like, like, like, like, like]

    if center_type:
        where.append("dah.center_type = %s")
        wparams.append(center_type)

    where_sql = " AND ".join(where)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT COUNT(*) AS cnt "
                f"FROM duty_assignments_history dah "
                f"WHERE {where_sql}",
                wparams
            )
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT
                    dah.id,
                    dah.original_id,
                    dah.staff_id,
                    dah.sthal_id,
                    dah.staff_name,
                    dah.staff_pno,
                    dah.staff_mobile,
                    dah.staff_rank,
                    dah.staff_district,
                    dah.staff_thana,
                    dah.is_armed,
                    dah.center_name,
                    dah.center_type,
                    dah.bus_no,
                    dah.election_date,
                    dah.attended,
                    dah.card_downloaded,
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
            "staffRank":     r["staff_rank"]     or "",
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


# ═════════════════════════════════════════════════════════════════════════════
#  EXTRA — ALL DISTRICT DUTIES (paginated full list, all types)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route(
    "/<int:election_id>/all-district-duties",
    methods=["GET"]
)
@admin_required
def history_all_district_duties(election_id):
    """Paginated full list of all district duty history records."""
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    duty_type = request.args.get("dutyType", "").strip()
    search    = request.args.get("q",        "").strip()
    page, limit, offset = _page_params()

    where   = ["ddh.election_id = %s", f"ddh.admin_id IN ({ph})"]
    wparams = [election_id] + params

    if duty_type:
        where.append("ddh.duty_type = %s")
        wparams.append(duty_type)

    if search:
        where.append(
            "(ddh.staff_name LIKE %s OR ddh.staff_pno LIKE %s "
            "OR ddh.duty_label_hi LIKE %s OR ddh.staff_rank LIKE %s)"
        )
        like = f"%{search}%"
        wparams += [like, like, like, like]

    where_sql = " AND ".join(where)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT COUNT(*) AS cnt FROM district_duty_history ddh "
                f"WHERE {where_sql}", wparams
            )
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT ddh.id, ddh.duty_type, ddh.duty_label_hi, ddh.batch_no,
                       ddh.staff_id, ddh.staff_name, ddh.staff_pno,
                       ddh.staff_mobile, ddh.staff_rank, ddh.staff_thana,
                       ddh.staff_district, ddh.is_armed, ddh.bus_no, ddh.note
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
            "id":          r["id"],
            "dutyType":    r["duty_type"]      or "",
            "dutyLabelHi": r["duty_label_hi"]  or "",
            "batchNo":     r["batch_no"],
            "staffId":     r["staff_id"],
            "name":        r["staff_name"]     or "",
            "pno":         r["staff_pno"]      or "",
            "mobile":      r["staff_mobile"]   or "",
            "rank":        r["staff_rank"]     or "",
            "thana":       r["staff_thana"]    or "",
            "district":    r["staff_district"] or "",
            "isArmed":     bool(r["is_armed"]),
            "busNo":       r["bus_no"]         or "",
            "note":        r["note"]           or "",
        } for r in rows],
        "total":      total,
        "page":       page,
        "limit":      limit,
        "totalPages": -(-total // limit),
    })