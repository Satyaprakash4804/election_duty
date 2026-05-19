"""
app/routes/history_report.py
════════════════════════════
Election history report endpoints.

KEY CHANGES vs previous version:
─────────────────────────────────
1.  _role() / _district() now support multi_super_admin and master in addition
    to admin/super_admin. Previously the guard and district resolver only worked
    for admin-role tokens, causing a 403 for multi_super_admin.

2.  @admin_required replaced with @history_required (defined in this file)
    which accepts admin, super_admin, multi_super_admin, and master.
    This avoids touching app/routes/__init__.py.

3.  _district() URI-decodes the X-Active-District header (same fix as
    super_admin.py) so Hindi district names like "बागपत" are correctly
    matched after Flutter percent-encodes them.

4.  _verify_election_access() updated: master + multi_super_admin can access
    any election in their assigned district; admin/super_admin still restricted
    to their own district.
"""

from functools import wraps
from urllib.parse import unquote          # ← NEW: decode URI-encoded header

from flask import Blueprint, request, abort
import jwt

from db import get_db
from config import Config
from app.routes import ok, err            # reuse existing helpers

history_report_bp = Blueprint(
    "history_report", __name__,
    url_prefix="/api/admin/election/history"
)


# ═════════════════════════════════════════════════════════════════════════════
#  INLINE AUTH GUARD
#  Accepts: admin, super_admin, multi_super_admin, master
#  (admin_required only accepts admin/super_admin, causing 403 for multi_super)
# ═════════════════════════════════════════════════════════════════════════════

_ALLOWED_ROLES = {"admin", "super_admin", "multi_super_admin", "master"}


def history_required(f):
    """
    Decorator: JWT required, role must be in _ALLOWED_ROLES.
    Sets request.user = jwt payload on success.
    Falls back to request.user if already set by an outer decorator.
    """
    @wraps(f)
    def wrapper(*args, **kwargs):
        # If an outer decorator (e.g. super_or_multi_required) already ran,
        # trust it — don't re-decode.
        if hasattr(request, "user") and request.user:
            role = (request.user.get("role") or "").lower()
            if role in _ALLOWED_ROLES:
                return f(*args, **kwargs)

        # ── Extract token ────────────────────────────────────────────────────
        token = None
        auth  = request.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            token = auth.split(" ", 1)[1]
        else:
            token = request.cookies.get("token")

        if not token:
            return err("Missing or malformed token", 401)

        # ── Decode ───────────────────────────────────────────────────────────
        try:
            payload = jwt.decode(token, Config.JWT_SECRET, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            return err("Token expired", 401)
        except jwt.InvalidTokenError:
            return err("Invalid token", 401)

        role = (payload.get("role") or "").lower()
        if role not in _ALLOWED_ROLES:
            return err(
                "Access denied — requires admin, super_admin, "
                "multi_super_admin, or master role",
                403,
            )

        request.user = payload
        return f(*args, **kwargs)

    return wrapper


# ═════════════════════════════════════════════════════════════════════════════
#  INTERNAL HELPERS
# ═════════════════════════════════════════════════════════════════════════════

def _admin_id():
    return request.user["id"]


def _role():
    return (request.user.get("role") or "admin").lower()


def _district():
    """
    Resolve the active district for this request.

    Priority:
      1. X-Active-District header (URI-decoded)  — used by multi_super_admin
      2. ?district= query param                  — fallback for same
      3. JWT 'district' claim                    — for plain admin/super_admin

    For multi_super_admin the header / query param is REQUIRED.
    For master it is optional (master can see all).
    """
    role = _role()

    # ── Step 1: X-Active-District header ─────────────────────────────────────
    raw_header = (request.headers.get("X-Active-District") or "").strip()
    if raw_header:
        return unquote(raw_header)

    # ── Step 2: ?district= query param ───────────────────────────────────────
    raw_param = (request.args.get("district") or "").strip()
    if raw_param:
        return unquote(raw_param)

    # ── Step 3: JWT district (valid for admin/super_admin/master) ────────────
    return (request.user.get("district") or "").strip()


def _ph(ids: list):
    """SQL IN placeholder string + list copy."""
    return ",".join(["%s"] * len(ids)), list(ids)


def _page_params(default=50, mx=200):
    page  = max(1, int(request.args.get("page",  1)))
    limit = min(mx, max(1, int(request.args.get("limit", default))))
    return page, limit, (page - 1) * limit


def _paginated(data, total, page, limit):
    return ok({
        "data":       data,
        "total":      total,
        "page":       page,
        "limit":      limit,
        "totalPages": -(-total // limit) if limit else 0,
    })


def _district_admin_ids(district: str) -> list:
    """
    All admin/super_admin/master user IDs in the given district.
    Always includes the caller's own ID as a fallback.
    """
    caller_id = _admin_id()
    if not district:
        return [caller_id]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM users "
                "WHERE role IN ('admin','super_admin','master') AND district = %s",
                (district,)
            )
            ids = [r["id"] for r in cur.fetchall()]
            if caller_id not in ids:
                ids.append(caller_id)
            return ids or [caller_id]
    finally:
        conn.close()


def _verify_election_access(election_id: int) -> dict:
    """
    Returns the election_configs row if the current user may access it.

    Access rules:
      master            → any election (no district check)
      multi_super_admin → any election in their resolved active district
      admin/super_admin → only elections in their own JWT district

    Aborts 404 if not found or access denied.
    """
    role     = _role()
    district = _district()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            if role in ("master", "multi_super_admin"):
                if district:
                    # Scoped to the active district for multi_super_admin
                    cur.execute(
                        "SELECT id, district, election_name, election_type, "
                        "election_date, phase, election_year, state, "
                        "is_finalized, finalized_at, archived_at "
                        "FROM election_configs "
                        "WHERE id = %s AND TRIM(LOWER(district)) = TRIM(LOWER(%s))",
                        (election_id, district),
                    )
                else:
                    # master with no district filter = global access
                    cur.execute(
                        "SELECT id, district, election_name, election_type, "
                        "election_date, phase, election_year, state, "
                        "is_finalized, finalized_at, archived_at "
                        "FROM election_configs WHERE id = %s",
                        (election_id,),
                    )
            else:
                # admin / super_admin — must match JWT district
                cur.execute(
                    "SELECT id, district, election_name, election_type, "
                    "election_date, phase, election_year, state, "
                    "is_finalized, finalized_at, archived_at "
                    "FROM election_configs "
                    "WHERE id = %s AND district = %s",
                    (election_id, district),
                )
            cfg = cur.fetchone()
            if not cfg:
                abort(404)
            return cfg
    finally:
        conn.close()


# ═════════════════════════════════════════════════════════════════════════════
#  LIST FINALIZED ELECTIONS  (role-scoped, paginated)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/list", methods=["GET"])
@history_required
def list_elections():
    """
    Paginated list of finalized elections.
    admin/super_admin       : own district only.
    multi_super_admin       : active district from X-Active-District header.
    master                  : all districts, optionally filtered by ?district=
    """
    role     = _role()
    district = _district()
    name_q   = (request.args.get("name")     or "").strip()
    dist_q   = (request.args.get("district") or "").strip()

    where, params = ["is_finalized = 1"], []

    if role == "master":
        # Master can optionally filter by district
        if dist_q:
            where.append("district = %s")
            params.append(dist_q)
        elif district:
            # If master also sends a header district (rare), respect it
            pass
    else:
        # admin / super_admin / multi_super_admin — restrict to their district
        if not district:
            return err("District context required", 400)
        where.append("TRIM(LOWER(district)) = TRIM(LOWER(%s))")
        params.append(district)

    if name_q:
        where.append("election_name LIKE %s")
        params.append(f"%{name_q}%")

    page, limit, offset = _page_params()
    where_sql = " AND ".join(where)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT COUNT(*) AS c FROM election_configs WHERE {where_sql}",
                params
            )
            total = cur.fetchone()["c"]

            cur.execute(f"""
                SELECT id, district, state, election_type, election_name,
                       phase, election_year, election_date, auto_finalized,
                       is_finalized, finalized_at, archived_at, created_at
                FROM election_configs
                WHERE {where_sql}
                ORDER BY COALESCE(finalized_at, archived_at, created_at) DESC
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            configs = cur.fetchall()

            if not configs:
                return _paginated([], total, page, limit)

            cfg_ids = [c["id"] for c in configs]
            c_ph    = ",".join(["%s"] * len(cfg_ids))

            def _cnt(table):
                cur.execute(f"""
                    SELECT election_id AS eid, COUNT(*) AS cnt
                    FROM {table}
                    WHERE election_id IN ({c_ph})
                    GROUP BY election_id
                """, cfg_ids)
                return {r["eid"]: int(r["cnt"] or 0) for r in cur.fetchall()}

            booth_map    = _cnt("duty_assignments_history")
            district_map = _cnt("district_duty_history")
            kshetra_map  = _cnt("kshetra_officers_history")
            zonal_map    = _cnt("zonal_officers_history")
            sector_map   = _cnt("sector_officers_history")

    finally:
        conn.close()

    return _paginated([{
        "id":                          c["id"],
        "district":                    c["district"]      or "",
        "state":                       c["state"]         or "",
        "electionName":                c["election_name"] or "",
        "electionType":                c["election_type"] or "",
        "electionDate":                str(c["election_date"]) if c["election_date"] else "",
        "phase":                       c["phase"]         or "",
        "electionYear":                c["election_year"] or "",
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
    } for c in configs], total, page, limit)


# ═════════════════════════════════════════════════════════════════════════════
#  ALL ELECTIONS  (master only — full cross-district view)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/all-elections", methods=["GET"])
@history_required
def all_elections():
    """Master-only: all finalized/archived elections across every district."""
    if _role() != "master":
        return err("Master access required", 403)

    district_filter = (request.args.get("district") or "").strip()
    name_filter     = (request.args.get("name")     or "").strip()

    where, params = ["(is_archived = 1 OR is_finalized = 1)"], []
    if district_filter:
        where.append("district = %s")
        params.append(district_filter)
    if name_filter:
        where.append("election_name LIKE %s")
        params.append(f"%{name_filter}%")
    where_sql = " AND ".join(where)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT id, district, election_name, election_type,
                       election_date, phase, election_year, state,
                       is_finalized, auto_finalized,
                       finalized_at, archived_at, created_at
                FROM election_configs
                WHERE {where_sql}
                ORDER BY district, id DESC
            """, params)
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
                return {r["eid"]: int(r["cnt"] or 0) for r in cur.fetchall()}

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
        "autoFinalized":               bool(c.get("auto_finalized")),
        "finalizedAt":                 str(c["finalized_at"]) if c["finalized_at"] else "",
        "archivedAt":                  str(c["archived_at"])  if c["archived_at"]  else "",
        "boothAssigned":               booth_map.get(c["id"],    0),
        "districtAssigned":            district_map.get(c["id"], 0),
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
#  DISTRICTS LIST  (master only — dropdown population)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/districts-list", methods=["GET"])
@history_required
def districts_list():
    """Master-only: distinct district names that have finalized elections."""
    role     = _role()
    district = _district()

    if role != "master":
        # Non-master gets only their own district for consistency
        return ok([district] if district else [])

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
@history_required
def history_booth_manak(election_id):
    """Archived booth rules grouped by sensitivity (A++/A/B/C)."""
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
                "boothCount":        int(r["booth_count"]),
                "siArmedCount":      int(r["si_armed_count"]),
                "siUnarmedCount":    int(r["si_unarmed_count"]),
                "hcArmedCount":      int(r["hc_armed_count"]),
                "hcUnarmedCount":    int(r["hc_unarmed_count"]),
                "constArmedCount":   int(r["const_armed_count"]),
                "constUnarmedCount": int(r["const_unarmed_count"]),
                "auxArmedCount":     int(r["aux_armed_count"]),
                "auxUnarmedCount":   int(r["aux_unarmed_count"]),
                "pacCount":          float(r["pac_count"] or 0),
            })
    return ok(grouped)


# ═════════════════════════════════════════════════════════════════════════════
#  TAB 2 — DISTRICT RULES FULL  (district_rules_history)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/<int:election_id>/district-rules-full", methods=["GET"])
@history_required
def history_district_rules_full(election_id):
    """Full archived district rules (manak) list."""
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
@history_required
def history_district_duty_summary(election_id):
    """district_duty_history grouped by duty_type with staff/batch counts."""
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
                    COUNT(DISTINCT ddh.staff_id)                        AS total_staff,
                    COUNT(DISTINCT ddh.batch_no)                        AS batch_count,
                    MAX(ddh.batch_no)                                   AS max_batch,
                    SUM(CASE WHEN ddh.is_armed = 1 THEN 1 ELSE 0 END)  AS armed_count,
                    SUM(CASE WHEN ddh.is_armed = 0 THEN 1 ELSE 0 END)  AS unarmed_count,
                    COALESCE(drh.sankhya, 0)                            AS sankhya
                FROM district_duty_history ddh
                LEFT JOIN district_rules_history drh
                    ON  drh.election_id = ddh.election_id
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
#  TAB 3 — DUTY BATCH DETAIL
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route(
    "/<int:election_id>/district-duty/<duty_type>/batches",
    methods=["GET"]
)
@history_required
def history_duty_batches(election_id, duty_type):
    """Batch-grouped staff list for one duty_type."""
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT batch_no,
                       COUNT(*)    AS staff_count,
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

    staff_by_batch: dict = {}
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
        "batchNo":    int(b["batch_no"]),
        "staffCount": int(b["staff_count"]),
        "busNo":      b["bus_no"] or "",
        "note":       b["note"]  or "",
        "staff":      staff_by_batch.get(b["batch_no"], []),
    } for b in batch_summary])


# ═════════════════════════════════════════════════════════════════════════════
#  TAB 4 — HIERARCHY OVERVIEW
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/<int:election_id>/hierarchy-overview", methods=["GET"])
@history_required
def history_hierarchy_overview(election_id):
    """Nested SZ → Zone → Sector officer structure for a finalized election."""
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute(f"""
                SELECT super_zone_id, super_zone_name, super_zone_block,
                       user_id, name, pno, mobile, user_rank
                FROM kshetra_officers_history
                WHERE election_id = %s AND admin_id IN ({ph})
                ORDER BY super_zone_name, name
            """, [election_id] + params)
            kshetra_rows = cur.fetchall()

            cur.execute(f"""
                SELECT zone_id, zone_name, super_zone_id, super_zone_name,
                       user_id, name, pno, mobile, user_rank
                FROM zonal_officers_history
                WHERE election_id = %s AND admin_id IN ({ph})
                ORDER BY super_zone_name, zone_name, name
            """, [election_id] + params)
            zonal_rows = cur.fetchall()

            cur.execute(f"""
                SELECT sector_id, sector_name, zone_id, zone_name,
                       super_zone_id, super_zone_name,
                       user_id, name, pno, mobile, user_rank
                FROM sector_officers_history
                WHERE election_id = %s AND admin_id IN ({ph})
                ORDER BY super_zone_name, zone_name, sector_name, name
            """, [election_id] + params)
            sector_rows = cur.fetchall()

            def _distinct(table, col):
                cur.execute(
                    f"SELECT COUNT(DISTINCT {col}) AS c FROM {table} "
                    f"WHERE election_id = %s AND admin_id IN ({ph})",
                    [election_id] + params
                )
                return int((cur.fetchone() or {}).get("c", 0) or 0)

            sz_count = _distinct("kshetra_officers_history", "super_zone_id")
            z_count  = _distinct("zonal_officers_history",   "zone_id")
            s_count  = _distinct("sector_officers_history",  "sector_id")

    finally:
        conn.close()

    sz_map: dict = {}

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
            "superZoneId":     sz["superZoneId"],
            "superZoneName":   sz["superZoneName"],
            "superZoneBlock":  sz["superZoneBlock"],
            "kshetraOfficers": sz["kshetraOfficers"],
            "zones":           zones_out,
        })

    return ok({
        "summary": {
            "superZoneCount":  sz_count,
            "zoneCount":       z_count,
            "sectorCount":     s_count,
            "kshetraOfficers": len(kshetra_rows),
            "zonalOfficers":   len(zonal_rows),
            "sectorOfficers":  len(sector_rows),
        },
        "superZones": result,
    })


# ═════════════════════════════════════════════════════════════════════════════
#  TAB 5 — BOOTH ASSIGNMENTS SUMMARY
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route(
    "/<int:election_id>/booth-assignments-summary",
    methods=["GET"]
)
@history_required
def history_booth_assignments_summary(election_id):
    """Aggregate booth assignment stats: totals, byType, byRank."""
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT
                    COUNT(*)                                         AS total,
                    SUM(attended)                                    AS attended,
                    COUNT(DISTINCT sthal_id)                         AS centers,
                    SUM(CASE WHEN is_armed = 1 THEN 1 ELSE 0 END)   AS armed,
                    SUM(CASE WHEN is_armed = 0 THEN 1 ELSE 0 END)   AS unarmed,
                    SUM(card_downloaded)                             AS card_downloaded
                FROM duty_assignments_history
                WHERE election_id = %s AND admin_id IN ({ph})
            """, [election_id] + params)
            totals = cur.fetchone() or {}

            cur.execute(f"""
                SELECT
                    center_type,
                    COUNT(*)                                        AS total_staff,
                    COUNT(DISTINCT sthal_id)                        AS centers_covered,
                    SUM(attended)                                   AS attended,
                    SUM(CASE WHEN is_armed = 1 THEN 1 ELSE 0 END)  AS armed,
                    SUM(CASE WHEN is_armed = 0 THEN 1 ELSE 0 END)  AS unarmed
                FROM duty_assignments_history
                WHERE election_id = %s AND admin_id IN ({ph})
                GROUP BY center_type
                ORDER BY FIELD(center_type,'A++','A','B','C')
            """, [election_id] + params)
            by_type = cur.fetchall()

            cur.execute(f"""
                SELECT
                    staff_rank,
                    COUNT(*)                                        AS total,
                    SUM(CASE WHEN is_armed = 1 THEN 1 ELSE 0 END)  AS armed,
                    SUM(CASE WHEN is_armed = 0 THEN 1 ELSE 0 END)  AS unarmed,
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
            "centerType":     r["center_type"]        or "",
            "totalStaff":     int(r["total_staff"]     or 0),
            "centersCovered": int(r["centers_covered"] or 0),
            "attended":       int(r["attended"]        or 0),
            "armed":          int(r["armed"]           or 0),
            "unarmed":        int(r["unarmed"]         or 0),
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
@history_required
def history_booth_assignments(election_id):
    """Paginated list of archived booth assignments."""
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    search      = (request.args.get("q",          "") or "").strip()
    center_type = (request.args.get("centerType", "") or "").strip()
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
                f"FROM duty_assignments_history dah WHERE {where_sql}",
                wparams
            )
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT
                    dah.id, dah.original_id, dah.staff_id, dah.sthal_id,
                    dah.staff_name, dah.staff_pno, dah.staff_mobile,
                    dah.staff_rank, dah.staff_district, dah.staff_thana,
                    dah.is_armed, dah.center_name, dah.center_type,
                    dah.bus_no, dah.election_date, dah.attended,
                    dah.card_downloaded, dah.archived_at
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
        "staffRank":      r["staff_rank"]     or "",
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
#  ALL DISTRICT DUTIES  (paginated full list, all types)
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route(
    "/<int:election_id>/all-district-duties",
    methods=["GET"]
)
@history_required
def history_all_district_duties(election_id):
    """Paginated full list of all district duty history records."""
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    duty_type = (request.args.get("dutyType", "") or "").strip()
    search    = (request.args.get("q",        "") or "").strip()
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
                SELECT
                    ddh.id, ddh.duty_type, ddh.duty_label_hi,
                    ddh.batch_no, ddh.staff_id, ddh.staff_name,
                    ddh.staff_pno, ddh.staff_mobile, ddh.staff_rank,
                    ddh.staff_thana, ddh.staff_district,
                    ddh.is_armed, ddh.bus_no, ddh.note
                FROM district_duty_history ddh
                WHERE {where_sql}
                ORDER BY ddh.duty_type, ddh.batch_no, ddh.staff_name
                LIMIT %s OFFSET %s
            """, wparams + [limit, offset])
            rows = cur.fetchall()
    finally:
        conn.close()

    return _paginated([{
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
    } for r in rows], total, page, limit)


# ═════════════════════════════════════════════════════════════════════════════
#  HIERARCHY-FULL  — nested live tree with archived officers/duties
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/<int:election_id>/hierarchy-full", methods=["GET"])
@history_required
def history_hierarchy_full(election_id):
    """
    Builds nested SZ→Zone→Sector→GP→Center tree using the live hierarchy
    tables, overlaid with officers and duty assignments from history tables.
    """
    cfg      = _verify_election_access(election_id)
    district = cfg["district"]

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT * FROM super_zones
                WHERE TRIM(LOWER(district)) = TRIM(LOWER(%s))
                ORDER BY id
            """, (district,))
            super_zones = cur.fetchall()
            if not super_zones:
                return ok([])

            sz_ids = [r["id"] for r in super_zones]
            sz_ph  = ",".join(["%s"] * len(sz_ids))

            cur.execute(
                f"SELECT * FROM zones WHERE super_zone_id IN ({sz_ph}) ORDER BY id",
                sz_ids
            )
            zones = cur.fetchall()
            z_ids = [r["id"] for r in zones] or [-1]
            z_ph  = ",".join(["%s"] * len(z_ids))

            cur.execute(
                f"SELECT * FROM sectors WHERE zone_id IN ({z_ph}) ORDER BY id",
                z_ids
            )
            sectors = cur.fetchall()
            s_ids = [r["id"] for r in sectors] or [-1]
            s_ph  = ",".join(["%s"] * len(s_ids))

            cur.execute(
                f"SELECT * FROM gram_panchayats WHERE sector_id IN ({s_ph}) ORDER BY id",
                s_ids
            )
            gps    = cur.fetchall()
            gp_ids = [r["id"] for r in gps] or [-1]
            gp_ph  = ",".join(["%s"] * len(gp_ids))

            cur.execute(f"""
                SELECT id, name, address, thana, center_type, bus_no,
                       gram_panchayat_id
                FROM matdan_sthal WHERE gram_panchayat_id IN ({gp_ph})
                ORDER BY id
            """, gp_ids)
            centers = cur.fetchall()

            # Officers from history
            cur.execute(f"""
                SELECT super_zone_id, name, pno, mobile, user_rank
                FROM kshetra_officers_history
                WHERE election_id=%s AND super_zone_id IN ({sz_ph})
                ORDER BY id
            """, [election_id] + sz_ids)
            ksh_by_sz = {}
            for r in cur.fetchall():
                ksh_by_sz.setdefault(r["super_zone_id"], []).append({
                    "name": r["name"] or "", "pno": r["pno"] or "",
                    "mobile": r["mobile"] or "", "user_rank": r["user_rank"] or "",
                })

            cur.execute(f"""
                SELECT zone_id, name, pno, mobile, user_rank
                FROM zonal_officers_history
                WHERE election_id=%s AND zone_id IN ({z_ph})
                ORDER BY id
            """, [election_id] + z_ids)
            zon_by_z = {}
            for r in cur.fetchall():
                zon_by_z.setdefault(r["zone_id"], []).append({
                    "name": r["name"] or "", "pno": r["pno"] or "",
                    "mobile": r["mobile"] or "", "user_rank": r["user_rank"] or "",
                })

            cur.execute(f"""
                SELECT sector_id, name, pno, mobile, user_rank
                FROM sector_officers_history
                WHERE election_id=%s AND sector_id IN ({s_ph})
                ORDER BY id
            """, [election_id] + s_ids)
            sec_by_s = {}
            for r in cur.fetchall():
                sec_by_s.setdefault(r["sector_id"], []).append({
                    "name": r["name"] or "", "pno": r["pno"] or "",
                    "mobile": r["mobile"] or "", "user_rank": r["user_rank"] or "",
                })

            center_ids = [c["id"] for c in centers] or [-1]
            c_ph = ",".join(["%s"] * len(center_ids))
            cur.execute(f"""
                SELECT sthal_id, staff_name, staff_pno, staff_mobile,
                       staff_rank, staff_thana, bus_no
                FROM duty_assignments_history
                WHERE election_id=%s AND sthal_id IN ({c_ph})
                ORDER BY id
            """, [election_id] + center_ids)
            duty_by_center = {}
            for r in cur.fetchall():
                duty_by_center.setdefault(r["sthal_id"], []).append({
                    "name":      r["staff_name"]   or "",
                    "pno":       r["staff_pno"]    or "",
                    "mobile":    r["staff_mobile"] or "",
                    "user_rank": r["staff_rank"]   or "",
                    "thana":     r["staff_thana"]  or "",
                    "bus_no":    r["bus_no"]       or "",
                })

    finally:
        conn.close()

    centers_by_gp = {}
    for c in centers:
        centers_by_gp.setdefault(c["gram_panchayat_id"], []).append({
            "id":            c["id"],
            "name":          c["name"]        or "",
            "address":       c["address"]     or "",
            "thana":         c["thana"]       or "",
            "center_type":   c["center_type"] or "C",
            "bus_no":        c["bus_no"]      or "",
            "duty_officers": duty_by_center.get(c["id"], []),
            "kendras":       [],
        })

    gps_by_sector = {}
    for gp in gps:
        gps_by_sector.setdefault(gp["sector_id"], []).append({
            "id":      gp["id"],
            "name":    gp["name"]   or "",
            "address": gp.get("address", "") or "",
            "thana":   gp.get("thana", "")   or "",
            "centers": centers_by_gp.get(gp["id"], []),
        })

    sectors_by_zone = {}
    for s in sectors:
        sectors_by_zone.setdefault(s["zone_id"], []).append({
            "id":         s["id"],
            "name":       s["name"] or "",
            "hq":         s.get("hq_address") or "",
            "officers":   sec_by_s.get(s["id"], []),
            "panchayats": gps_by_sector.get(s["id"], []),
        })

    zones_by_sz = {}
    for z in zones:
        zones_by_sz.setdefault(z["super_zone_id"], []).append({
            "id":         z["id"],
            "name":       z["name"]       or "",
            "hq_address": z["hq_address"] or "",
            "officers":   zon_by_z.get(z["id"], []),
            "sectors":    sectors_by_zone.get(z["id"], []),
        })

    result = []
    for sz in super_zones:
        result.append({
            "id":       sz["id"],
            "name":     sz["name"]     or "",
            "district": sz["district"] or "",
            "block":    sz["block"]    or "",
            "officers": ksh_by_sz.get(sz["id"], []),
            "zones":    zones_by_sz.get(sz["id"], []),
        })

    return ok(result)


# ═════════════════════════════════════════════════════════════════════════════
#  BOOTH CENTER COUNTS
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/<int:election_id>/booth-center-counts", methods=["GET"])
@history_required
def history_booth_center_counts(election_id):
    cfg      = _verify_election_access(election_id)
    district = cfg["district"]

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT ms.center_type,
                       LEAST(ms.booth_count, 15) AS bucket,
                       COUNT(*)                  AS cnt
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE TRIM(LOWER(sz.district)) = TRIM(LOWER(%s))
                  AND ms.center_type IN ('A++','A','B','C')
                  AND ms.booth_count >= 1
                GROUP BY ms.center_type, bucket
            """, (district,))
            rows = cur.fetchall()
    finally:
        conn.close()

    result = {sens: {str(bc): 0 for bc in range(1, 16)}
              for sens in ("A++", "A", "B", "C")}
    for r in rows:
        ct     = r["center_type"]
        bucket = int(r["bucket"] or 1)
        if ct in result and 1 <= bucket <= 15:
            result[ct][str(bucket)] += int(r["cnt"] or 0)
    return ok(result)


# ═════════════════════════════════════════════════════════════════════════════
#  GOSWARA — block-wise summary for an archived election
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route("/<int:election_id>/goswara", methods=["GET"])
@history_required
def history_goswara(election_id):
    cfg      = _verify_election_access(election_id)
    district = cfg["district"]
    d_ids    = _district_admin_ids(district)
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT sz.block AS block_name,
                       COUNT(DISTINCT z.id)        AS zonal_count,
                       COUNT(DISTINCT s.id)        AS sector_count,
                       COUNT(DISTINCT gp.id)       AS gram_panchayat_count
                FROM super_zones sz
                LEFT JOIN zones z            ON z.super_zone_id = sz.id
                LEFT JOIN sectors s          ON s.zone_id        = z.id
                LEFT JOIN gram_panchayats gp ON gp.sector_id     = s.id
                WHERE sz.admin_id IN ({ph})
                  AND sz.block IS NOT NULL AND TRIM(sz.block) <> ''
                GROUP BY sz.block
                ORDER BY sz.block
            """, params)
            rows = cur.fetchall()

            cur.execute(
                f"SELECT block_name, SUM(nyay_count) AS nyay_count "
                f"FROM goswara_nyay_panchayat WHERE admin_id IN ({ph}) "
                f"GROUP BY block_name",
                params
            )
            nyay_map = {r["block_name"]: int(r["nyay_count"] or 0)
                        for r in cur.fetchall()}
    finally:
        conn.close()

    data = []
    for r in rows:
        block = r["block_name"] or ""
        data.append({
            "block_name":           block,
            "zonal_count":          int(r["zonal_count"]          or 0),
            "sector_count":         int(r["sector_count"]         or 0),
            "nyay_panchayat_count": nyay_map.get(block, 0),
            "gram_panchayat_count": int(r["gram_panchayat_count"] or 0),
        })

    return ok({
        "electionDate": str(cfg["election_date"]) if cfg.get("election_date") else "",
        "phase":        cfg.get("phase") or "",
        "electionName": cfg.get("election_name") or "",
        "district":     district,
        "data":         data,
    })


# ═════════════════════════════════════════════════════════════════════════════
#  BOOTH ASSIGNMENTS GROUPED BY CENTER
# ═════════════════════════════════════════════════════════════════════════════

@history_report_bp.route(
    "/<int:election_id>/booth-assignments-grouped", methods=["GET"]
)
@history_required
def history_booth_assignments_grouped(election_id):
    """Booth assignments grouped by center for hierarchy-style printing."""
    cfg   = _verify_election_access(election_id)
    d_ids = _district_admin_ids(cfg["district"])
    ph, params = _ph(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT dah.id, dah.sthal_id, dah.staff_name, dah.staff_pno,
                       dah.staff_mobile, dah.staff_rank, dah.staff_thana,
                       dah.is_armed, dah.center_name, dah.center_type,
                       dah.bus_no, dah.election_date
                FROM duty_assignments_history dah
                WHERE dah.election_id = %s AND dah.admin_id IN ({ph})
                ORDER BY dah.center_name, dah.staff_name
            """, [election_id] + params)
            rows = cur.fetchall()
    finally:
        conn.close()

    by_center = {}
    for r in rows:
        cid = r["sthal_id"]
        if cid not in by_center:
            by_center[cid] = {
                "centerId":     cid,
                "centerName":   r["center_name"] or "",
                "centerType":   r["center_type"] or "C",
                "busNo":        r["bus_no"]      or "",
                "electionDate": str(r["election_date"]) if r["election_date"] else "",
                "staff":        [],
            }
        by_center[cid]["staff"].append({
            "id":      r["id"],
            "name":    r["staff_name"]   or "",
            "pno":     r["staff_pno"]    or "",
            "mobile":  r["staff_mobile"] or "",
            "rank":    r["staff_rank"]   or "",
            "thana":   r["staff_thana"]  or "",
            "isArmed": bool(r["is_armed"]),
        })

    return ok(list(by_center.values()))