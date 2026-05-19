from urllib.parse import unquote
from flask import Blueprint, request, jsonify
from db import get_db
from app.routes import admin_required, ok, err
from app.election_guard import (
    get_active_election,
    require_active_election,
    run_auto_finalize_if_due,
)
import hashlib

# ── Blueprints ─────────────────────────────────────────────────────────────
hierarchy    = Blueprint("hierarchy",    __name__, url_prefix="/api/admin/hierarchy")
elections_bp = Blueprint("elections_bp", __name__, url_prefix="/api/admin")

SALT = "election_2026_secure_key"

# Roles that are allowed to READ the hierarchy (including super-level roles)
_READ_ROLES  = {"admin", "super_admin", "multi_super_admin", "master"}
# Roles that are allowed to WRITE / mutate officer/duty records
_WRITE_ROLES = {"admin", "super_admin", "multi_super_admin", "master"}


# ══════════════════════════════════════════════════════════════════════════════
#  AUTH HELPERS
#  We keep using @admin_required for pure-admin-only endpoints (super-zone /
#  sector structural edits) but add two new decorators for hierarchy reads
#  and officer writes that must also work for super-level roles.
# ══════════════════════════════════════════════════════════════════════════════

def _role_required(allowed_roles: set):
    """
    Factory that returns a decorator accepting any role in `allowed_roles`.
    Reuses the same JWT / cookie extraction logic as admin_required so token
    handling stays consistent across the app.
    """
    from functools import wraps
    import jwt
    from config import Config

    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            token = None
            auth_header = request.headers.get("Authorization", "")
            if auth_header.startswith("Bearer "):
                token = auth_header.split(" ", 1)[1]
            else:
                token = request.cookies.get("token")

            if not token:
                return err("Missing or malformed token", 401)

            try:
                payload = jwt.decode(
                    token, Config.JWT_SECRET, algorithms=["HS256"]
                )
            except jwt.ExpiredSignatureError:
                return err("Token expired", 401)
            except jwt.InvalidTokenError:
                return err("Invalid token", 401)

            role = (payload.get("role") or "").lower()
            if role not in allowed_roles:
                return err(
                    f"Access denied — requires one of: {sorted(allowed_roles)}",
                    403,
                )

            # Best-effort token-revocation check (mirrors the global pattern)
            try:
                iat = payload.get("iat")
                if iat and role != "master":
                    conn = get_db()
                    try:
                        with conn.cursor() as cur:
                            cur.execute(
                                "SELECT revoke_before FROM token_revocations "
                                "WHERE role=%s LIMIT 1",
                                (role,),
                            )
                            row = cur.fetchone()
                            if row and int(iat) < int(row["revoke_before"]):
                                return err(
                                    "Session expired — please log in again", 401
                                )
                    finally:
                        conn.close()
            except Exception:
                pass  # Fail open on revocation-table errors

            request.user = payload
            return f(*args, **kwargs)

        return wrapper
    return decorator


# Concrete decorators used in this file
hierarchy_read_required  = _role_required(_READ_ROLES)
hierarchy_write_required = _role_required(_WRITE_ROLES)


# ══════════════════════════════════════════════════════════════════════════════
#  DISTRICT RESOLVER
#  Works for ALL roles:
#    admin / super_admin   → JWT district (no header needed)
#    multi_super_admin     → X-Active-District header  (REQUIRED, URI-decoded)
#                          → ?district= query param   (fallback)
#    master                → ?district= or header      (optional; all if absent)
#
#  Returns (district_string_or_None, error_response_or_None).
# ══════════════════════════════════════════════════════════════════════════════

def _resolve_district():
    """
    Resolves the effective district for the current request.
    Returns (district: str | None, error_response | None).
    """
    user = getattr(request, "user", {})
    role = (user.get("role") or "").lower()

    # ── Step 1: X-Active-District header (URI-decoded) ────────────────────
    district = None
    raw_header = (request.headers.get("X-Active-District") or "").strip()
    if raw_header:
        district = unquote(raw_header)

    # ── Step 2: ?district= query param ────────────────────────────────────
    if not district:
        raw_param = (request.args.get("district") or "").strip()
        if raw_param:
            district = unquote(raw_param)

    # ── Step 3: JWT district (for admin / super_admin) ─────────────────────
    if not district:
        district = (user.get("district") or "").strip()

    district = (district or "").strip()

    # ── Role-specific enforcement ─────────────────────────────────────────
    if role == "multi_super_admin":
        if not district:
            return None, err(
                "District context required — send X-Active-District header "
                "or ?district= query param.",
                400,
            )
        # Verify the district is actually assigned to this user
        uid = user.get("id")
        if uid:
            try:
                conn = get_db()
                try:
                    with conn.cursor() as cur:
                        cur.execute(
                            "SELECT 1 FROM user_districts "
                            "WHERE user_id = %s "
                            "  AND TRIM(LOWER(district)) = TRIM(LOWER(%s))",
                            (uid, district),
                        )
                        if not cur.fetchone():
                            return None, err(
                                f"District '{district}' is not assigned to "
                                "this user.",
                                403,
                            )
                finally:
                    conn.close()
            except Exception as e:
                return None, err(
                    f"Could not verify district assignment: {e}", 500
                )

    elif role == "master":
        # master may omit district → None means "all districts" (caller handles)
        pass

    elif role in ("admin", "super_admin"):
        if not district:
            return None, err("District not found in token", 400)

    return district, None


# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def _hash(pno: str) -> str:
    return hashlib.sha256((pno + SALT).encode()).hexdigest()


def _admin_id():
    return request.user["id"]


def _officer_row(r: dict) -> dict:
    return {
        "id":          r["id"],
        "user_id":     r.get("user_id"),
        "name":        r.get("name")      or "",
        "pno":         r.get("pno")       or "",
        "mobile":      r.get("mobile")    or "",
        "user_rank":   r.get("user_rank") or "",
        "election_id": r.get("election_id"),
    }


def _fetch_officers(cur, table: str, fk_col: str, fk_val: int,
                    election_id=None) -> list:
    """
    Fetch officers for a hierarchy node.
    election_id=None  → live mode: all rows for this node.
    election_id=X     → history mode: only rows stamped with that election.
    """
    if election_id is not None:
        cur.execute(
            f"SELECT * FROM {table} "
            f"WHERE {fk_col} = %s AND election_id = %s ORDER BY id",
            (fk_val, election_id)
        )
    else:
        cur.execute(
            f"SELECT * FROM {table} WHERE {fk_col} = %s ORDER BY id",
            (fk_val,)
        )
    return [_officer_row(r) for r in cur.fetchall()]


def _fetch_kendras(cur, sthal_id: int) -> list:
    cur.execute(
        "SELECT id, room_number FROM matdan_kendra "
        "WHERE matdan_sthal_id = %s ORDER BY id",
        (sthal_id,)
    )
    return [
        {"id": r["id"], "room_number": r["room_number"] or ""}
        for r in cur.fetchall()
    ]


def _fetch_duty_officers(cur, sthal_id: int, election_id=None) -> list:
    """
    Fetch duty officers for a polling station.
    election_id=None  → live mode (all duties for this sthal).
    election_id=X     → history mode (duties for that election only).
    """
    if election_id is not None:
        cur.execute("""
            SELECT u.id, u.name, u.pno, u.mobile, u.user_rank, u.thana,
                   da.id AS duty_id, da.bus_no, da.election_id
            FROM duty_assignments da
            JOIN users u ON u.id = da.staff_id
            WHERE da.sthal_id = %s AND da.election_id = %s
            ORDER BY u.name
        """, (sthal_id, election_id))
    else:
        cur.execute("""
            SELECT u.id, u.name, u.pno, u.mobile, u.user_rank, u.thana,
                   da.id AS duty_id, da.bus_no, da.election_id
            FROM duty_assignments da
            JOIN users u ON u.id = da.staff_id
            WHERE da.sthal_id = %s
            ORDER BY u.name
        """, (sthal_id,))

    return [
        {
            "id":          r["duty_id"],
            "user_id":     r["id"],
            "name":        r["name"]      or "",
            "pno":         r["pno"]       or "",
            "mobile":      r["mobile"]    or "",
            "user_rank":   r["user_rank"] or "",
            "thana":       r["thana"]     or "",
            "bus_no":      r["bus_no"]    or "",
            "election_id": r["election_id"],
        }
        for r in cur.fetchall()
    ]


def _ensure_user(cur, name: str, pno: str, mobile: str, rank: str,
                 created_by: int):
    if not pno:
        return None
    cur.execute("SELECT id FROM users WHERE pno = %s", (pno,))
    row = cur.fetchone()
    if row:
        return row["id"]
    cur.execute("SELECT id FROM users WHERE username = %s", (pno,))
    username = pno if not cur.fetchone() else f"{pno}_{created_by}"
    cur.execute("""
        INSERT INTO users (name, pno, username, password, mobile, user_rank,
                           role, is_active, created_by)
        VALUES (%s,%s,%s,%s,%s,%s,'staff',1,%s)
    """, (name, pno, username, _hash(pno), mobile, rank, created_by))
    return cur.lastrowid


def _insert_officer(cur, table: str, fk_col: str, fk_val: int,
                    o: dict, election_id):
    """Always stamps election_id + assigned_by."""
    name   = (o.get("name")      or "").strip()
    pno    = (o.get("pno")       or "").strip()
    mobile = (o.get("mobile")    or "").strip()
    rank   = (o.get("user_rank") or o.get("rank") or "").strip()
    uid    = o.get("user_id") or o.get("userId") or None

    if not uid:
        uid = _ensure_user(cur, name, pno, mobile, rank, _admin_id())

    cur.execute(
        f"INSERT INTO {table} "
        f"({fk_col}, user_id, name, pno, mobile, user_rank, election_id, assigned_by) "
        f"VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
        (fk_val, uid, name, pno, mobile, rank, election_id, _admin_id())
    )
    return cur.lastrowid


def _update_officer(o_id: int, table: str, body: dict, election_id):
    """Stamps election_id on update too."""
    name   = (body.get("name")      or "").strip()
    pno    = (body.get("pno")       or "").strip()
    mobile = (body.get("mobile")    or "").strip()
    rank   = (body.get("user_rank") or body.get("rank") or "").strip()
    uid    = body.get("user_id") or body.get("userId") or None

    conn = get_db()
    try:
        with conn.cursor() as cur:
            if not uid:
                uid = _ensure_user(cur, name, pno, mobile, rank, _admin_id())
            if uid:
                cur.execute(
                    "UPDATE users SET name=%s, mobile=%s, user_rank=%s "
                    "WHERE id=%s AND role='staff'",
                    (name, mobile, rank, uid)
                )
            cur.execute(
                f"UPDATE {table} "
                f"SET name=%s, pno=%s, mobile=%s, user_rank=%s, user_id=%s, "
                f"election_id=%s, assigned_by=%s "
                f"WHERE id=%s",
                (name, pno, mobile, rank, uid,
                 election_id, _admin_id(), o_id)
            )
        conn.commit()
    finally:
        conn.close()


def _delete_officer(o_id: int, table: str):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM {table} WHERE id=%s", (o_id,))
        conn.commit()
    finally:
        conn.close()


def _replace_officers(table: str, fk_col: str, fk_val: int,
                      officers: list, election_id):
    """
    Delete only rows for this node+election, then re-insert.
    Past election snapshots (different election_id) are untouched.
    """
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"DELETE FROM {table} "
                f"WHERE {fk_col} = %s AND election_id = %s",
                (fk_val, election_id)
            )
            for o in officers:
                if (o.get("name") or "").strip():
                    _insert_officer(cur, table, fk_col, fk_val, o, election_id)
        conn.commit()
    finally:
        conn.close()


# ── Shared election-row serialiser ──────────────────────────────────────────
def _election_row(r: dict) -> dict:
    return {
        "id":         r["id"],
        "name":       r["name"]       or "",
        "district":   r["district"]   or "",
        "start_date": str(r["start_date"]) if r.get("start_date") else "",
        "end_date":   str(r["end_date"])   if r.get("end_date")   else "",
        "is_active":  bool(r["is_active"]),
        "status":     "active" if r["is_active"] else "completed",
    }


# ══════════════════════════════════════════════════════════════════════════════
#  ELECTIONS LIST
#  GET /api/admin/elections
#
#  admin / super_admin        → district locked from JWT token
#  multi_super_admin          → district from X-Active-District header
#  master                     → ?district= query param (required)
#
#  Returns active election first, then historical ones (newest first).
# ══════════════════════════════════════════════════════════════════════════════

@elections_bp.route("/elections", methods=["GET"])
@hierarchy_read_required
def list_elections():
    district, resp = _resolve_district()
    if resp:
        return resp

    role = (request.user.get("role") or "").lower()

    # master with no district → require explicit param
    if role == "master" and not district:
        district = (request.args.get("district") or "").strip()
        if not district:
            return err("district param required for master role", 400)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            if district:
                cur.execute("""
                    SELECT id, name, district, start_date, end_date, is_active
                    FROM elections
                    WHERE TRIM(LOWER(district)) = TRIM(LOWER(%s))
                    ORDER BY is_active DESC, id DESC
                """, (district,))
            else:
                cur.execute("""
                    SELECT id, name, district, start_date, end_date, is_active
                    FROM elections
                    ORDER BY is_active DESC, id DESC
                """)
            rows = cur.fetchall()
    finally:
        conn.close()

    elections = [_election_row(dict(r)) for r in rows]
    return ok({"data": elections, "total": len(elections)})


# ══════════════════════════════════════════════════════════════════════════════
#  FULL HIERARCHY TREE
#  GET /api/admin/hierarchy/full
#
#  Allowed roles  : admin, super_admin, multi_super_admin, master
#  Optional params: ?electionId=X   → history mode (read-only snapshot)
#                   ?district=X     → master / multi_super_admin override
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/full", methods=["GET", "OPTIONS"])
@hierarchy_read_required
def get_full_hierarchy():
    # Resolve district first — needed for auto-finalize too
    district, dist_err = _resolve_district()
    if dist_err:
        return dist_err

    role = (request.user.get("role") or "").lower()

    # Opportunistic auto-finalize (live mode only, harmless in history mode)
    run_auto_finalize_if_due(district or "")

    req_election_id = request.args.get("electionId", type=int)  # None = live
    is_history      = req_election_id is not None

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # ── District scoping ──────────────────────────────────────────
            # master with no district → return all
            # all other roles         → scoped to resolved district
            if role == "master" and not district:
                cur.execute("SELECT * FROM super_zones ORDER BY id")
            else:
                cur.execute("""
                    SELECT * FROM super_zones
                    WHERE TRIM(LOWER(district)) = TRIM(LOWER(%s))
                    ORDER BY id
                """, (district,))

            super_zones = cur.fetchall()
            result      = []

            for sz in super_zones:
                sz_id = sz["id"]
                cur.execute(
                    "SELECT * FROM zones WHERE super_zone_id = %s ORDER BY id",
                    (sz_id,))
                zone_list = []

                for z in cur.fetchall():
                    z_id = z["id"]
                    cur.execute(
                        "SELECT * FROM sectors WHERE zone_id = %s ORDER BY id",
                        (z_id,))
                    sector_list = []

                    for s in cur.fetchall():
                        s_id = s["id"]
                        cur.execute(
                            "SELECT * FROM gram_panchayats "
                            "WHERE sector_id = %s ORDER BY id",
                            (s_id,))
                        gp_list = []

                        for gp in cur.fetchall():
                            gp_id = gp["id"]
                            cur.execute("""
                                SELECT id, name, address, thana, center_type,
                                       bus_no, latitude, longitude
                                FROM matdan_sthal
                                WHERE gram_panchayat_id = %s ORDER BY id
                            """, (gp_id,))
                            center_list = []

                            for ms in cur.fetchall():
                                ms_id = ms["id"]
                                center_list.append({
                                    "id":          ms["id"],
                                    "name":        ms["name"]        or "",
                                    "address":     ms["address"]     or "",
                                    "thana":       ms["thana"]       or "",
                                    "center_type": ms["center_type"] or "C",
                                    "bus_no":      ms["bus_no"]      or "",
                                    "latitude":  (
                                        float(ms["latitude"])
                                        if ms["latitude"] else None
                                    ),
                                    "longitude": (
                                        float(ms["longitude"])
                                        if ms["longitude"] else None
                                    ),
                                    "kendras": _fetch_kendras(cur, ms_id),
                                    "duty_officers": _fetch_duty_officers(
                                        cur, ms_id,
                                        election_id=req_election_id
                                    ),
                                })

                            gp_list.append({
                                "id":      gp["id"],
                                "name":    gp["name"]    or "",
                                "address": gp["address"] or "",
                                "thana":   gp.get("thana", ""),
                                "centers": center_list,
                            })

                        sector_list.append({
                            "id":   s["id"],
                            "name": s["name"] or "",
                            "hq":   s.get("hq_address") or "",
                            "officers": _fetch_officers(
                                cur, "sector_officers", "sector_id", s_id,
                                election_id=req_election_id
                            ),
                            "panchayats": gp_list,
                        })

                    zone_list.append({
                        "id":         z["id"],
                        "name":       z["name"]       or "",
                        "hq_address": z["hq_address"] or "",
                        "officers": _fetch_officers(
                            cur, "zonal_officers", "zone_id", z_id,
                            election_id=req_election_id
                        ),
                        "sectors": sector_list,
                    })

                result.append({
                    "id":       sz["id"],
                    "name":     sz["name"]     or "",
                    "district": sz["district"] or "",
                    "block":    sz["block"]    or "",
                    "officers": _fetch_officers(
                        cur, "kshetra_officers", "super_zone_id", sz_id,
                        election_id=req_election_id
                    ),
                    "zones": zone_list,
                })

        # ── Election config for response ──────────────────────────────────
        if is_history:
            conn2 = get_db()
            try:
                with conn2.cursor() as cur2:
                    cur2.execute(
                        "SELECT id, name, district, start_date, end_date, "
                        "is_active FROM elections WHERE id = %s",
                        (req_election_id,)
                    )
                    ec_row = cur2.fetchone()
            finally:
                conn2.close()
            election_config = _election_row(dict(ec_row)) if ec_row else None
        else:
            election_config = get_active_election(district)

        return jsonify({
            "data":                result,
            "electionConfig":      election_config,
            "hasActiveConfig":     bool(election_config),
            "isHistory":           is_history,
            "requestedElectionId": req_election_id,
        })

    except Exception as e:
        print("❌ ERROR in get_full_hierarchy:", str(e))
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()


# ══════════════════════════════════════════════════════════════════════════════
#  DISTRICTS LIST
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/districts", methods=["GET"])
@hierarchy_read_required
def list_districts():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT DISTINCT TRIM(district) AS district
                FROM super_zones
                WHERE district IS NOT NULL AND TRIM(district) <> ''
                ORDER BY district
            """)
            rows      = cur.fetchall()
            districts = [r["district"] for r in rows if r.get("district")]
    finally:
        conn.close()
    return jsonify({"data": districts})


# ══════════════════════════════════════════════════════════════════════════════
#  SUPER ZONES  (structural edits — admin / super-level only)
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/super-zone/<int:sz_id>", methods=["PUT"])
@hierarchy_write_required
def update_super_zone(sz_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE super_zones SET name=%s, district=%s, block=%s "
                "WHERE id=%s AND admin_id=%s",
                (body.get("name",     ""),
                 body.get("district", ""),
                 body.get("block",    ""),
                 sz_id, _admin_id())
            )
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Super Zone updated")


@hierarchy.route("/super-zone/<int:sz_id>", methods=["DELETE"])
@hierarchy_write_required
def delete_super_zone(sz_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM super_zones WHERE id=%s AND admin_id=%s",
                (sz_id, _admin_id())
            )
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Super Zone deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  SECTOR / STHAL  (non-officer CRUD)
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/sector/<int:s_id>", methods=["PUT"])
@hierarchy_write_required
def update_sector(s_id):
    body = request.get_json() or {}
    name = (body.get("name") or "").strip()
    if not name:
        return err("name required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE sectors SET name=%s WHERE id=%s", (name, s_id))
        conn.commit()
    finally:
        conn.close()
    return ok({"id": s_id, "name": name}, "Sector updated")


@hierarchy.route("/sector/<int:s_id>", methods=["DELETE"])
@hierarchy_write_required
def delete_sector(s_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM sectors WHERE id=%s", (s_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Sector deleted")


@hierarchy.route("/sthal/<int:ms_id>", methods=["PUT"])
@hierarchy_write_required
def update_sthal(ms_id):
    body        = request.get_json() or {}
    center_type = (
        body.get("centerType") or body.get("center_type") or "C"
    ).strip().upper()
    if center_type not in ("A++", "A", "B", "C"):
        center_type = "C"
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE matdan_sthal
                SET name=%s, address=%s, thana=%s, center_type=%s, bus_no=%s
                WHERE id = %s
            """, (
                (body.get("name")    or "").strip(),
                (body.get("address") or "").strip(),
                (body.get("thana")   or "").strip(),
                center_type,
                (body.get("busNo") or body.get("bus_no") or "").strip(),
                ms_id,
            ))
        conn.commit()
    finally:
        conn.close()
    return ok({"center_type": center_type}, "Sthal updated")


@hierarchy.route("/sthal/<int:ms_id>", methods=["DELETE"])
@hierarchy_write_required
def delete_sthal(ms_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM matdan_sthal WHERE id=%s", (ms_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Sthal deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  REQUIRE-ACTIVE-ELECTION WRAPPER
#  For write endpoints, multi_super_admin and super_admin need the district
#  resolved from the header, not just the JWT claim.
# ══════════════════════════════════════════════════════════════════════════════

def _require_election():
    """
    Returns (election_cfg, error_response).
    Resolves district properly for all roles before calling
    require_active_election().
    """
    district, dist_err = _resolve_district()
    if dist_err:
        return None, dist_err
    cfg, gerr = require_active_election(district)
    return cfg, gerr


# ══════════════════════════════════════════════════════════════════════════════
#  KSHETRA OFFICERS  (super-zone level)
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/super-zones/<int:sz_id>/officers", methods=["GET"])
@hierarchy_read_required
def get_kshetra_officers(sz_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            officers = _fetch_officers(
                cur, "kshetra_officers", "super_zone_id", sz_id)
    finally:
        conn.close()
    return ok({"officers": officers})


@hierarchy.route("/super-zones/<int:sz_id>/officers", methods=["POST"])
@hierarchy_write_required
def add_kshetra_officer(sz_id):
    cfg, gerr = _require_election()
    if gerr:
        return gerr
    election_id = cfg["id"]
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(
                cur, "kshetra_officers", "super_zone_id",
                sz_id, body, election_id)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "electionId": election_id}, "Officer added", 201)


@hierarchy.route("/kshetra-officers/<int:o_id>", methods=["PUT"])
@hierarchy_write_required
def update_kshetra_officer(o_id):
    cfg, gerr = _require_election()
    if gerr:
        return gerr
    body = request.get_json() or {}
    _update_officer(o_id, "kshetra_officers", body, cfg["id"])
    return ok({"electionId": cfg["id"]}, "Updated")


@hierarchy.route("/kshetra-officers/<int:o_id>", methods=["DELETE"])
@hierarchy_write_required
def delete_kshetra_officer(o_id):
    _delete_officer(o_id, "kshetra_officers")
    return ok(None, "Deleted")


@hierarchy.route("/super-zone/<int:sz_id>/officers/replace", methods=["POST"])
@hierarchy_write_required
def replace_kshetra_officers(sz_id):
    cfg, gerr = _require_election()
    if gerr:
        return gerr
    body = request.get_json() or {}
    _replace_officers("kshetra_officers", "super_zone_id", sz_id,
                      body.get("officers", []), cfg["id"])
    return ok({"electionId": cfg["id"]}, "Officers replaced")


# ══════════════════════════════════════════════════════════════════════════════
#  ZONAL OFFICERS
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/zones/<int:z_id>/officers", methods=["GET"])
@hierarchy_read_required
def get_zonal_officers(z_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            officers = _fetch_officers(
                cur, "zonal_officers", "zone_id", z_id)
    finally:
        conn.close()
    return ok({"officers": officers})


@hierarchy.route("/zones/<int:z_id>/officers", methods=["POST"])
@hierarchy_write_required
def add_zonal_officer(z_id):
    cfg, gerr = _require_election()
    if gerr:
        return gerr
    election_id = cfg["id"]
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(
                cur, "zonal_officers", "zone_id",
                z_id, body, election_id)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "electionId": election_id}, "Officer added", 201)


@hierarchy.route("/zonal-officers/<int:o_id>", methods=["PUT"])
@hierarchy_write_required
def update_zonal_officer(o_id):
    cfg, gerr = _require_election()
    if gerr:
        return gerr
    body = request.get_json() or {}
    _update_officer(o_id, "zonal_officers", body, cfg["id"])
    return ok({"electionId": cfg["id"]}, "Updated")


@hierarchy.route("/zonal-officers/<int:o_id>", methods=["DELETE"])
@hierarchy_write_required
def delete_zonal_officer(o_id):
    _delete_officer(o_id, "zonal_officers")
    return ok(None, "Deleted")


@hierarchy.route("/zones/<int:z_id>/officers/replace", methods=["POST"])
@hierarchy_write_required
def replace_zonal_officers(z_id):
    cfg, gerr = _require_election()
    if gerr:
        return gerr
    body = request.get_json() or {}
    _replace_officers("zonal_officers", "zone_id", z_id,
                      body.get("officers", []), cfg["id"])
    return ok({"electionId": cfg["id"]}, "Officers replaced")


# ══════════════════════════════════════════════════════════════════════════════
#  SECTOR OFFICERS
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/sectors/<int:s_id>/officers", methods=["GET"])
@hierarchy_read_required
def get_sector_officers(s_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            officers = _fetch_officers(
                cur, "sector_officers", "sector_id", s_id)
    finally:
        conn.close()
    return ok({"officers": officers})


@hierarchy.route("/sectors/<int:s_id>/officers", methods=["POST"])
@hierarchy_write_required
def add_sector_officer(s_id):
    cfg, gerr = _require_election()
    if gerr:
        return gerr
    election_id = cfg["id"]
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(
                cur, "sector_officers", "sector_id",
                s_id, body, election_id)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "electionId": election_id}, "Officer added", 201)


@hierarchy.route("/sector-officers/<int:o_id>", methods=["PUT"])
@hierarchy_write_required
def update_sector_officer(o_id):
    cfg, gerr = _require_election()
    if gerr:
        return gerr
    body = request.get_json() or {}
    _update_officer(o_id, "sector_officers", body, cfg["id"])
    return ok({"electionId": cfg["id"]}, "Updated")


@hierarchy.route("/sector-officers/<int:o_id>", methods=["DELETE"])
@hierarchy_write_required
def delete_sector_officer(o_id):
    _delete_officer(o_id, "sector_officers")
    return ok(None, "Deleted")


@hierarchy.route("/sectors/<int:s_id>/officers/replace", methods=["POST"])
@hierarchy_write_required
def replace_sector_officers(s_id):
    cfg, gerr = _require_election()
    if gerr:
        return gerr
    body = request.get_json() or {}
    _replace_officers("sector_officers", "sector_id", s_id,
                      body.get("officers", []), cfg["id"])
    return ok({"electionId": cfg["id"]}, "Officers replaced")


# ══════════════════════════════════════════════════════════════════════════════
#  DUTY ASSIGNMENTS
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/duties", methods=["POST"])
@hierarchy_write_required
def assign_duty():
    cfg, gerr = _require_election()
    if gerr:
        return gerr
    election_id = cfg["id"]

    body     = request.get_json() or {}
    staff_id = body.get("staffId")
    sthal_id = body.get("centerId") or body.get("sthalId")
    bus_no   = body.get("busNo", "")
    if not staff_id or not sthal_id:
        return err("staffId and centerId required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO duty_assignments
                    (staff_id, sthal_id, election_id, bus_no, assigned_by)
                VALUES (%s,%s,%s,%s,%s)
                ON DUPLICATE KEY UPDATE
                    sthal_id    = VALUES(sthal_id),
                    election_id = VALUES(election_id),
                    bus_no      = VALUES(bus_no),
                    assigned_by = VALUES(assigned_by)
            """, (staff_id, sthal_id, election_id, bus_no, _admin_id()))
            duty_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": duty_id, "electionId": election_id}, "Duty assigned", 201)


@hierarchy.route("/duties/<int:duty_id>", methods=["DELETE"])
@hierarchy_write_required
def remove_duty(duty_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM duty_assignments WHERE id=%s", (duty_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Duty removed")


# ══════════════════════════════════════════════════════════════════════════════
#  AVAILABLE STAFF
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/staff/available", methods=["GET"])
@hierarchy_read_required
def get_available_staff():
    q      = (request.args.get("q", "") or "").strip()
    page   = max(1, request.args.get("page",  1,  type=int))
    limit  = min(200, max(1, request.args.get("limit", 30, type=int)))
    offset = (page - 1) * limit

    NOT_ASSIGNED = """
        NOT (
            EXISTS (SELECT 1 FROM duty_assignments  da  WHERE da.staff_id  = u.id)
         OR EXISTS (SELECT 1 FROM kshetra_officers  ko  WHERE ko.user_id   = u.id)
         OR EXISTS (SELECT 1 FROM zonal_officers    zo  WHERE zo.user_id   = u.id)
         OR EXISTS (SELECT 1 FROM sector_officers   so  WHERE so.user_id   = u.id)
         OR EXISTS (SELECT 1 FROM district_duty_assignments dda
                    WHERE dda.staff_id = u.id)
        )
    """

    # Resolve district using the shared helper so multi_super_admin works
    district, dist_err = _resolve_district()
    if dist_err:
        return dist_err

    role = (request.user.get("role") or "").lower()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            params          = []
            district_clause = ""
            if district:
                district_clause = (
                    "AND TRIM(LOWER(u.district)) = TRIM(LOWER(%s))"
                )
                params.append(district)

            search_clause = ""
            if q:
                search_clause = (
                    "AND (u.name LIKE %s OR u.pno LIKE %s OR u.thana LIKE %s)"
                )
                like = f"%{q}%"
                params.extend([like, like, like])

            cur.execute(
                f"SELECT COUNT(*) AS cnt FROM users u "
                f"WHERE u.role='staff' AND u.is_active=1 {district_clause} "
                f"AND {NOT_ASSIGNED} {search_clause}",
                params
            )
            total = cur.fetchone()["cnt"]

            cur.execute(
                f"""SELECT u.id, u.name, u.pno, u.mobile, u.thana, u.user_rank
                    FROM users u
                    WHERE u.role='staff' AND u.is_active=1 {district_clause}
                      AND {NOT_ASSIGNED} {search_clause}
                    ORDER BY u.name
                    LIMIT %s OFFSET %s""",
                params + [limit, offset]
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    data = [{
        "id":        r["id"],
        "name":      r["name"]      or "",
        "pno":       r["pno"]       or "",
        "mobile":    r["mobile"]    or "",
        "thana":     r["thana"]     or "",
        "user_rank": r["user_rank"] or "",
    } for r in rows]

    return ok({
        "data":       data,
        "total":      total,
        "page":       page,
        "limit":      limit,
        "totalPages": -(-total // limit) if total else 1,
    })