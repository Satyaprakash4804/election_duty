import json
import sys
import io
import csv
from concurrent.futures import ThreadPoolExecutor, as_completed
from flask import Blueprint, request, Response, stream_with_context
from werkzeug.security import generate_password_hash
from db import get_db
from app.routes import ok, err, write_log, admin_required
import hashlib
admin_bp = Blueprint("admin", __name__, url_prefix="/api/admin")
from flask_jwt_extended import jwt_required

# ── Constants ─────────────────────────────────────────────────────────────────
DEFAULT_PAGE_SIZE = 50
MAX_PAGE_SIZE     = 200
HASH_WORKERS      = 8
MAX_BATCH_ROWS    = 10_000
INSERT_CHUNK_SIZE = 200
SALT = "election_2026_secure_key"

RANK_HIERARCHY = [
    'SP', 'ASP', 'DSP', 'Inspector', 'SI', 'ASI', 'Head Constable', 'Constable'
]

def _fast_hash(pno: str) -> str:
    return hashlib.sha256((pno + SALT).encode()).hexdigest()


def _sse(data: dict) -> bytes:
    return f"data: {json.dumps(data, ensure_ascii=False)}\n\n".encode("utf-8")


def _admin_id():
    return request.user["id"]


# ══════════════════════════════════════════════════════════════════════════════
#  DISTRICT SHARING — core helper
#
#  Returns a list of ALL admin user IDs that belong to the same district as
#  the currently logged-in admin.  Every route that previously filtered by
#  `admin_id = _admin_id()` now uses `admin_id IN (_district_admin_ids())`
#  so that all admins in the same district share full read/write access to
#  the same data.  Admins from other districts cannot see or modify anything.
#
#  Rules:
#   - If current user is a super_admin → include all admins in same district
#   - If current user is an admin       → include all admins in same district
#     (this gives district-wide sharing regardless of who created the data)
#   - If the admin has no district set  → fallback to only themselves (safe)
# ══════════════════════════════════════════════════════════════════════════════

def _district_admin_ids() -> list:
    """
    Returns list of admin IDs in the same district as the current user.
    Always includes at least [_admin_id()] as a fallback.
    """
    district = (request.user.get("district") or "").strip()
    if not district:
        return [_admin_id()]

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM users WHERE role IN ('admin','super_admin') AND district = %s",
                (district,)
            )
            rows = cur.fetchall()
            ids = [r["id"] for r in rows]
            # Always guarantee current user is in the list
            if _admin_id() not in ids:
                ids.append(_admin_id())
            return ids if ids else [_admin_id()]
    finally:
        conn.close()


def _district_placeholder(ids: list) -> tuple:
    """
    Returns (placeholder_string, ids) for use in SQL IN clauses.
    Example: _district_placeholder([1,2,3]) → ("%s,%s,%s", [1,2,3])
    """
    ph = ",".join(["%s"] * len(ids))
    return ph, ids


def _super_admin_id():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT role, super_admin_id FROM users WHERE id=%s",
                (_admin_id(),)
            )
            u = cur.fetchone()

            if not u:
                return None

            # if admin → return its super admin
            if u["role"] == "admin":
                return u["super_admin_id"]

            # if super admin → return own id
            return _admin_id()

    finally:
        conn.close()

def _o(r):
    return {
        "id":     r["id"],
        "userId": r["user_id"],
        "name":   r["name"]      or "",
        "pno":    r["pno"]       or "",
        "mobile": r["mobile"]    or "",
        "rank":   r["user_rank"] or "",
    }


def _page_params():
    page  = max(1, request.args.get("page", 1, type=int))
    limit = min(MAX_PAGE_SIZE, max(1, request.args.get("limit", DEFAULT_PAGE_SIZE, type=int)))
    return page, limit, (page - 1) * limit


def _paginated(data, total, page, limit):
    return ok({
        "data":       data,
        "total":      total,
        "page":       page,
        "limit":      limit,
        "totalPages": -(-total // limit),
    })


def _staff_list(cur, district=None):
    if district:
        cur.execute(
            "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users "
            "WHERE role='staff' AND district=%s AND is_active=1 ORDER BY name",
            (district,)
        )
    else:
        cur.execute(
            "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users "
            "WHERE role='staff' AND is_active=1 ORDER BY name"
        )
    return [{"id": r["id"], "name": r["name"] or "", "pno": r["pno"] or "",
             "mobile": r["mobile"] or "", "rank": r["user_rank"] or "", "isArmed": bool(r["is_armed"]) }
            for r in cur.fetchall()]

def _get_lower_rank(rank: str) -> str | None:
    """Returns the next lower rank in hierarchy, or None if already lowest."""
    try:
        idx = RANK_HIERARCHY.index(rank)
        if idx < len(RANK_HIERARCHY) - 1:
            return RANK_HIERARCHY[idx + 1]
    except ValueError:
        pass
    return None

# ══════════════════════════════════════════════════════════════════════════════
#  SUPER ZONES
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/super-zones", methods=["GET"])
@admin_required
def get_super_zones():
    search = request.args.get("q", "").strip()
    page, limit, offset = _page_params()

    # DISTRICT SHARING: query all admins in same district
    d_ids = _district_admin_ids()
    ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            count_params = list(d_params)
            where_extra = ""
            if search:
                where_extra = "AND sz.name LIKE %s"
                count_params.append(f"%{search}%")

            cur.execute(f"""
                SELECT COUNT(*) AS cnt FROM super_zones sz
                WHERE sz.admin_id IN ({ph}) {where_extra}
            """, count_params)
            total = cur.fetchone()["cnt"]

            data_params = list(d_params)
            if search:
                data_params.append(f"%{search}%")

            cur.execute(f"""
                SELECT sz.id, sz.name, sz.district, sz.block,
                       COUNT(DISTINCT z.id) AS zone_count
                FROM super_zones sz
                LEFT JOIN zones z ON z.super_zone_id = sz.id
                WHERE sz.admin_id IN ({ph}) {where_extra}
                GROUP BY sz.id ORDER BY sz.id
                LIMIT %s OFFSET %s
            """, data_params + [limit, offset])
            zones = cur.fetchall()

            if not zones:
                return _paginated([], total, page, limit)

            sz_ids = [sz["id"] for sz in zones]
            sz_ph = ",".join(["%s"] * len(sz_ids))
            cur.execute(
                f"SELECT * FROM kshetra_officers WHERE super_zone_id IN ({sz_ph}) ORDER BY super_zone_id, id",
                sz_ids
            )
            officers_by_sz = {}
            for row in cur.fetchall():
                officers_by_sz.setdefault(row["super_zone_id"], []).append(_o(row))

            result = [{
                "id":        sz["id"],
                "name":      sz["name"]      or "",
                "district":  sz["district"]  or "",
                "block":     sz["block"]     or "",
                "zoneCount": sz["zone_count"],
                "officers":  officers_by_sz.get(sz["id"], []),
            } for sz in zones]

    finally:
        conn.close()

    return _paginated(result, total, page, limit)


@admin_bp.route("/super-zones", methods=["POST"])
@admin_required
def add_super_zone():
    body = request.get_json() or {}
    name = body.get("name", "").strip()
    if not name:
        return err("name required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            # New zones are always created under the current admin_id
            cur.execute("INSERT INTO super_zones (name,district,block,admin_id) VALUES (%s,%s,%s,%s)",
                        (name, body.get("district", request.user.get("district") or ""),
                         body.get("block", ""), _admin_id()))
            sz_id = cur.lastrowid
            for o in body.get("officers", []):
                _insert_officer(cur, "kshetra_officers", "super_zone_id", sz_id, o)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": sz_id, "name": name}, "Super Zone added", 201)


@admin_bp.route("/super-zones/<int:sz_id>", methods=["PUT"])
@admin_required
def update_super_zone(sz_id):
    body = request.get_json() or {}

    # DISTRICT SHARING: allow update if super_zone belongs to any district admin
    d_ids = _district_admin_ids()
    ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Verify the zone belongs to this district before updating
            cur.execute(f"SELECT id FROM super_zones WHERE id=%s AND admin_id IN ({ph})", [sz_id] + d_params)
            if not cur.fetchone():
                return err("Not found or access denied", 403)

            cur.execute(
                "UPDATE super_zones SET name=%s,district=%s,block=%s WHERE id=%s",
                (body.get("name",""), body.get("district",""), body.get("block",""), sz_id)
            )
            cur.execute("DELETE FROM kshetra_officers WHERE super_zone_id=%s", (sz_id,))
            for o in body.get("officers", []):
                _insert_officer(cur, "kshetra_officers", "super_zone_id", sz_id, o)
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Updated")


@admin_bp.route("/super-zones/<int:sz_id>", methods=["DELETE"])
@admin_required
def delete_super_zone(sz_id):
    d_ids = _district_admin_ids()
    ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM super_zones WHERE id=%s AND admin_id IN ({ph})", [sz_id] + d_params)
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


@admin_bp.route("/super-zones/<int:sz_id>/officers", methods=["GET"])
@admin_required
def get_kshetra_officers(sz_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM kshetra_officers WHERE super_zone_id=%s ORDER BY id", (sz_id,))
            rows = cur.fetchall()
            staff = _staff_list(cur, request.user.get("district"))
    finally:
        conn.close()
    return ok({"officers": [_o(r) for r in rows], "availableStaff": staff})


@admin_bp.route("/super-zones/<int:sz_id>/officers", methods=["POST"])
@admin_required
def add_kshetra_officer(sz_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(cur, "kshetra_officers", "super_zone_id", sz_id, body)
            cur.execute("SELECT user_id FROM kshetra_officers WHERE id=%s", (new_id,))
            row = cur.fetchone()
            user_id = row["user_id"] if row else None
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "userId": user_id}, "Officer added", 201)


@admin_bp.route("/kshetra-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_kshetra_officer(o_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT user_id FROM kshetra_officers WHERE id=%s", (o_id,))
            existing = cur.fetchone()

            uid    = body.get("userId") or (existing["user_id"] if existing else None)
            name   = body.get("name",   "")
            pno    = body.get("pno",    "")
            mobile = body.get("mobile", "")
            rank   = body.get("rank",   "")

            if not uid and pno:
                cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
                u = cur.fetchone()
                if u:
                    uid = u["id"]
                else:
                    cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
                    username = pno if not cur.fetchone() else f"{pno}_off"
                    cur.execute("""
                        INSERT INTO users
                            (name, pno, username, password, mobile,
                             user_rank, role, is_active, created_by)
                        VALUES (%s,%s,%s,%s,%s,%s,'staff',1,%s)
                    """, (name, pno, username, _fast_hash(pno),
                          mobile, rank, request.user["id"]))
                    uid = cur.lastrowid

            if uid:
                cur.execute("""
                    UPDATE users SET name=%s, mobile=%s, user_rank=%s
                    WHERE id=%s AND role='staff'
                """, (name, mobile, rank, uid))

            cur.execute("""
                UPDATE kshetra_officers
                SET name=%s, pno=%s, mobile=%s, user_rank=%s, user_id=%s
                WHERE id=%s
            """, (name, pno, mobile, rank, uid, o_id))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Updated")


@admin_bp.route("/kshetra-officers/<int:o_id>", methods=["DELETE"])
@admin_required
def delete_kshetra_officer(o_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM kshetra_officers WHERE id=%s", (o_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  ZONES
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/super-zones/<int:sz_id>/zones", methods=["GET"])
@admin_required
def get_zones(sz_id):
    search = request.args.get("q", "").strip()
    page, limit, offset = _page_params()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # DISTRICT SHARING: verify sz_id belongs to any admin in this district
            d_ids = _district_admin_ids()
            ph, d_params = _district_placeholder(d_ids)
            cur.execute(f"SELECT id FROM super_zones WHERE id=%s AND admin_id IN ({ph})", [sz_id] + d_params)
            if not cur.fetchone():
                return err("Not found or access denied", 403)

            params = [sz_id]
            where_extra = ""
            if search:
                where_extra = "AND z.name LIKE %s"
                params.append(f"%{search}%")

            cur.execute(f"SELECT COUNT(*) AS cnt FROM zones z WHERE z.super_zone_id=%s {where_extra}", params)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT z.id, z.name, z.hq_address, COUNT(DISTINCT s.id) AS sector_count
                FROM zones z LEFT JOIN sectors s ON s.zone_id=z.id
                WHERE z.super_zone_id=%s {where_extra}
                GROUP BY z.id ORDER BY z.id
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            zones = cur.fetchall()

            if not zones:
                return _paginated([], total, page, limit)

            z_ids = [z["id"] for z in zones]
            z_ph = ",".join(["%s"] * len(z_ids))
            cur.execute(f"SELECT * FROM zonal_officers WHERE zone_id IN ({z_ph}) ORDER BY zone_id, id", z_ids)
            officers_by_zone = {}
            for row in cur.fetchall():
                officers_by_zone.setdefault(row["zone_id"], []).append(_o(row))

            result = [{
                "id":          z["id"],
                "name":        z["name"]       or "",
                "hqAddress":   z["hq_address"] or "",
                "sectorCount": z["sector_count"],
                "officers":    officers_by_zone.get(z["id"], []),
            } for z in zones]

    finally:
        conn.close()

    return _paginated(result, total, page, limit)


@admin_bp.route("/super-zones/<int:sz_id>/zones", methods=["POST"])
@admin_required
def add_zone(sz_id):
    body = request.get_json() or {}
    name = body.get("name", "").strip()
    if not name:
        return err("name required")

    # DISTRICT SHARING: verify sz_id is accessible to this district
    d_ids = _district_admin_ids()
    ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT id FROM super_zones WHERE id=%s AND admin_id IN ({ph})", [sz_id] + d_params)
            if not cur.fetchone():
                return err("Not found or access denied", 403)

            cur.execute("INSERT INTO zones (name,hq_address,super_zone_id) VALUES (%s,%s,%s)",
                        (name, body.get("hqAddress", ""), sz_id))
            z_id = cur.lastrowid
            for o in body.get("officers", []):
                _insert_officer(cur, "zonal_officers", "zone_id", z_id, o)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": z_id, "name": name}, "Zone added", 201)


@admin_bp.route("/zones/<int:z_id>", methods=["PUT"])
@admin_required
def update_zone(z_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE zones SET name=%s,hq_address=%s WHERE id=%s",
                (body.get("name",""), body.get("hqAddress",""), z_id)
            )
            cur.execute("DELETE FROM zonal_officers WHERE zone_id=%s", (z_id,))
            for o in body.get("officers", []):
                _insert_officer(cur, "zonal_officers", "zone_id", z_id, o)
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Updated")


@admin_bp.route("/zones/<int:z_id>", methods=["DELETE"])
@admin_required
def delete_zone(z_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM zones WHERE id=%s", (z_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


@admin_bp.route("/zones/<int:z_id>/officers", methods=["GET"])
@admin_required
def get_zonal_officers(z_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM zonal_officers WHERE zone_id=%s ORDER BY id", (z_id,))
            rows = cur.fetchall()
            staff = _staff_list(cur, request.user.get("district"))
    finally:
        conn.close()
    return ok({"officers": [_o(r) for r in rows], "availableStaff": staff})


@admin_bp.route("/zones/<int:z_id>/officers", methods=["POST"])
@admin_required
def add_zonal_officer(z_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(cur, "zonal_officers", "zone_id", z_id, body)
            cur.execute("SELECT user_id FROM zonal_officers WHERE id=%s", (new_id,))
            row = cur.fetchone()
            user_id = row["user_id"] if row else None
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "userId": user_id}, "Officer added", 201)


@admin_bp.route("/zonal-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_zonal_officer(o_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT user_id FROM zonal_officers WHERE id=%s", (o_id,))
            existing = cur.fetchone()

            uid    = body.get("userId") or (existing["user_id"] if existing else None)
            name   = body.get("name",   "")
            pno    = body.get("pno",    "")
            mobile = body.get("mobile", "")
            rank   = body.get("rank",   "")

            if not uid and pno:
                cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
                u = cur.fetchone()
                if u:
                    uid = u["id"]
                else:
                    cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
                    username = pno if not cur.fetchone() else f"{pno}_off"
                    cur.execute("""
                        INSERT INTO users
                            (name, pno, username, password, mobile,
                             user_rank, role, is_active, created_by)
                        VALUES (%s,%s,%s,%s,%s,%s,'staff',1,%s)
                    """, (name, pno, username, _fast_hash(pno),
                          mobile, rank, request.user["id"]))
                    uid = cur.lastrowid

            if uid:
                cur.execute("""
                    UPDATE users SET name=%s, mobile=%s, user_rank=%s
                    WHERE id=%s AND role='staff'
                """, (name, mobile, rank, uid))

            cur.execute("""
                UPDATE zonal_officers
                SET name=%s, pno=%s, mobile=%s, user_rank=%s, user_id=%s
                WHERE id=%s
            """, (name, pno, mobile, rank, uid, o_id))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Updated")


@admin_bp.route("/zonal-officers/<int:o_id>", methods=["DELETE"])
@admin_required
def delete_zonal_officer(o_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM zonal_officers WHERE id=%s", (o_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  SECTORS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/zones/<int:z_id>/sectors", methods=["GET"])
@admin_required
def get_sectors(z_id):
    search = request.args.get("q", "").strip()
    page, limit, offset = _page_params()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = [z_id]
            where_extra = ""
            if search:
                where_extra = "AND s.name LIKE %s"
                params.append(f"%{search}%")

            cur.execute(f"SELECT COUNT(*) AS cnt FROM sectors s WHERE s.zone_id=%s {where_extra}", params)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT s.id, s.name, s.hq_address, COUNT(DISTINCT gp.id) AS gp_count
                FROM sectors s LEFT JOIN gram_panchayats gp ON gp.sector_id=s.id
                WHERE s.zone_id=%s {where_extra}
                GROUP BY s.id ORDER BY s.id
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            sectors = cur.fetchall()

            if not sectors:
                return _paginated([], total, page, limit)

            s_ids = [s["id"] for s in sectors]
            s_ph = ",".join(["%s"] * len(s_ids))
            cur.execute(f"SELECT * FROM sector_officers WHERE sector_id IN ({s_ph}) ORDER BY sector_id, id", s_ids)
            officers_by_sector = {}
            for row in cur.fetchall():
                officers_by_sector.setdefault(row["sector_id"], []).append(_o(row))

            result = [{
                "id":       s["id"],
                "name":     s["name"] or "",
                "hqAddress": s.get("hq_address", "") or "",
                "gpCount":  s["gp_count"],
                "officers": officers_by_sector.get(s["id"], []),
            } for s in sectors]

    finally:
        conn.close()

    return _paginated(result, total, page, limit)


@admin_bp.route("/zones/<int:z_id>/sectors", methods=["POST"])
@admin_required
def add_sector(z_id):
    body = request.get_json() or {}
    name = body.get("name", "").strip()
    if not name:
        return err("name required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO sectors (name, hq_address, zone_id) VALUES (%s,%s,%s)",
                (name, body.get("hqAddress", ""), z_id)
            )
            s_id = cur.lastrowid
            for o in body.get("officers", []):
                _insert_officer(cur, "sector_officers", "sector_id", s_id, o)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": s_id, "name": name}, "Sector added", 201)


@admin_bp.route("/sectors/<int:s_id>", methods=["PUT"])
@admin_required
def update_sector(s_id):
    body = request.get_json() or {}

    name = (body.get("name") or "").strip()
    hq   = (body.get("hqAddress") or "").strip()
    officers = body.get("officers", [])

    if not name:
        return err("name required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE sectors SET name=%s, hq_address=%s WHERE id=%s", (name, hq, s_id))
            cur.execute("DELETE FROM sector_officers WHERE sector_id=%s", (s_id,))
            for o in officers:
                _insert_officer(cur, "sector_officers", "sector_id", s_id, o)
        conn.commit()
    finally:
        conn.close()

    return ok(None, "Sector + Officers Updated")


@admin_bp.route("/sectors/<int:s_id>", methods=["DELETE"])
@admin_required
def delete_sector(s_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM sectors WHERE id=%s", (s_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


@admin_bp.route("/sectors/<int:s_id>/officers", methods=["GET"])
@admin_required
def get_sector_officers(s_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sector_officers WHERE sector_id=%s ORDER BY id", (s_id,))
            rows = cur.fetchall()
            staff = _staff_list(cur, request.user.get("district"))
    finally:
        conn.close()
    return ok({"officers": [_o(r) for r in rows], "availableStaff": staff})


@admin_bp.route("/sectors/<int:s_id>/officers", methods=["POST"])
@admin_required
def add_sector_officer(s_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(cur, "sector_officers", "sector_id", s_id, body)
            cur.execute("SELECT user_id FROM sector_officers WHERE id=%s", (new_id,))
            row = cur.fetchone()
            user_id = row["user_id"] if row else None
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "userId": user_id}, "Officer added", 201)


@admin_bp.route("/sector-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_sector_officer(o_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT user_id FROM sector_officers WHERE id=%s", (o_id,))
            existing = cur.fetchone()

            uid    = body.get("userId") or (existing["user_id"] if existing else None)
            name   = body.get("name",   "")
            pno    = body.get("pno",    "")
            mobile = body.get("mobile", "")
            rank   = body.get("rank",   "")

            if not uid and pno:
                cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
                u = cur.fetchone()
                if u:
                    uid = u["id"]
                else:
                    cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
                    username = pno if not cur.fetchone() else f"{pno}_off"
                    cur.execute("""
                        INSERT INTO users
                            (name, pno, username, password, mobile,
                             user_rank, role, is_active, created_by)
                        VALUES (%s,%s,%s,%s,%s,%s,'staff',1,%s)
                    """, (name, pno, username, _fast_hash(pno),
                          mobile, rank, request.user["id"]))
                    uid = cur.lastrowid

            if uid:
                cur.execute("""
                    UPDATE users SET name=%s, mobile=%s, user_rank=%s
                    WHERE id=%s AND role='staff'
                """, (name, mobile, rank, uid))

            cur.execute("""
                UPDATE sector_officers
                SET name=%s, pno=%s, mobile=%s, user_rank=%s, user_id=%s
                WHERE id=%s
            """, (name, pno, mobile, rank, uid, o_id))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Updated")


@admin_bp.route("/sector-officers/<int:o_id>", methods=["DELETE"])
@admin_required
def delete_sector_officer(o_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM sector_officers WHERE id=%s", (o_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


def _insert_officer(cur, table, fk_col, fk_val, o):
    uid    = o.get("userId") or o.get("user_id") or None
    name   = (o.get("name")   or "").strip()
    pno    = (o.get("pno")    or "").strip()
    mobile = (o.get("mobile") or "").strip()
    rank   = (o.get("rank")   or "").strip()

    if uid:
        cur.execute(
            "SELECT name, pno, mobile, user_rank, is_armed FROM users WHERE id=%s",
            (uid,)
        )
        u = cur.fetchone()
        if u:
            if not name:   name   = u["name"] or ""
            if not pno:    pno    = u["pno"] or ""
            if not mobile: mobile = u["mobile"] or ""
            if not rank:   rank   = u["user_rank"] or ""

    elif pno:
        cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
        existing = cur.fetchone()

        if existing:
            uid = existing["id"]
        else:
            cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
            username = pno if not cur.fetchone() else f"{pno}_off"

            cur.execute("""
                INSERT INTO users
                    (name, pno, username, password, mobile, user_rank,
                     is_armed, role, is_active, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
            """, (
                name, pno, username, _fast_hash(pno),
                mobile, rank, 0, request.user["id"]
            ))
            uid = cur.lastrowid

    cur.execute(
        f"""
        INSERT INTO {table}
            ({fk_col}, user_id, name, pno, mobile, user_rank)
        VALUES (%s,%s,%s,%s,%s,%s)
        """,
        (fk_val, uid or None, name, pno, mobile, rank)
    )

    return cur.lastrowid


# ══════════════════════════════════════════════════════════════════════════════
#  GRAM PANCHAYATS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/sectors/<int:s_id>/gram-panchayats", methods=["GET"])
@admin_required
def get_gram_panchayats(s_id):
    search = request.args.get("q", "").strip()
    page, limit, offset = _page_params()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = [s_id]
            where_extra = ""
            if search:
                where_extra = "AND gp.name LIKE %s"
                params.append(f"%{search}%")

            cur.execute(f"SELECT COUNT(*) AS cnt FROM gram_panchayats gp WHERE gp.sector_id=%s {where_extra}", params)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT gp.*, COUNT(ms.id) AS center_count
                FROM gram_panchayats gp
                LEFT JOIN matdan_sthal ms ON ms.gram_panchayat_id=gp.id
                WHERE gp.sector_id=%s {where_extra}
                GROUP BY gp.id ORDER BY gp.id
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            rows = cur.fetchall()
    finally:
        conn.close()

    data = [{
        "id":          r["id"],
        "name":        r["name"]    or "",
        "address":     r["address"] or "",
        "centerCount": r["center_count"],
    } for r in rows]

    return _paginated(data, total, page, limit)


@admin_bp.route("/sectors/<int:s_id>/gram-panchayats", methods=["POST"])
@admin_required
def add_gram_panchayat(s_id):
    body = request.get_json() or {}
    name = body.get("name", "").strip()
    if not name:
        return err("name required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO gram_panchayats (name,address,sector_id) VALUES (%s,%s,%s)",
                        (name, body.get("address", ""), s_id))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "name": name}, "GP added", 201)


@admin_bp.route("/gram-panchayats/<int:gp_id>", methods=["PUT"])
@admin_required
def update_gram_panchayat(gp_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE gram_panchayats SET name=%s,address=%s WHERE id=%s",
                        (body.get("name", ""), body.get("address", ""), gp_id))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Updated")


@admin_bp.route("/gram-panchayats/<int:gp_id>", methods=["DELETE"])
@admin_required
def delete_gram_panchayat(gp_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM gram_panchayats WHERE id=%s", (gp_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  ELECTION CENTERS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/gram-panchayats/<int:gp_id>/centers", methods=["GET"])
@admin_required
def get_centers(gp_id):
    page, limit, offset = _page_params()
    search = request.args.get("q", "").strip()
    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = [gp_id]
            where_extra = ""
            if search:
                where_extra = "AND ms.name LIKE %s"
                params.append(f"%{search}%")
            cur.execute(f"SELECT COUNT(*) AS cnt FROM matdan_sthal ms WHERE ms.gram_panchayat_id=%s {where_extra}", params)
            total = cur.fetchone()["cnt"]
            cur.execute(f"""
                SELECT ms.*,
                    (SELECT COUNT(*) FROM duty_assignments da WHERE da.sthal_id=ms.id) AS duty_count,
                    (SELECT COUNT(*) FROM matdan_kendra mk WHERE mk.matdan_sthal_id=ms.id) AS room_count
                FROM matdan_sthal ms
                WHERE ms.gram_panchayat_id=%s {where_extra}
                ORDER BY ms.name LIMIT %s OFFSET %s
            """, params + [limit, offset])
            centers = cur.fetchall()
            if not centers:
                return _paginated([], total, page, limit)
            center_ids = [c["id"] for c in centers]
            c_ph = ",".join(["%s"] * len(center_ids))
            cur.execute(f"""
                SELECT da.sthal_id, u.id, u.name, u.pno, u.mobile, u.user_rank
                FROM duty_assignments da JOIN users u ON u.id=da.staff_id
                WHERE da.sthal_id IN ({c_ph}) ORDER BY da.sthal_id, u.name
            """, center_ids)
            staff_by_center = {}
            for row in cur.fetchall():
                staff_by_center.setdefault(row["sthal_id"], []).append({
                    "id": row["id"], "name": row["name"] or "", "pno": row["pno"] or "", "rank": row["user_rank"] or ""})

            # DISTRICT SHARING: load rules for all admins in same district
            d_ids = _district_admin_ids()
            d_ph, d_params = _district_placeholder(d_ids)
            cur.execute(f"SELECT sensitivity, user_rank, required_count FROM booth_staff_rules WHERE admin_id IN ({d_ph})", d_params)
            rules_raw = cur.fetchall()
            rules = {}
            for r in rules_raw:
                rules.setdefault(r["sensitivity"], {})[r["user_rank"]] = r["required_count"]
    finally:
        conn.close()
    data = []
    for c in centers:
        center_type  = c["center_type"] or "C"
        assigned     = staff_by_center.get(c["id"], [])
        center_rules = rules.get(center_type, {})
        assigned_rank_count = {}
        for s in assigned:
            assigned_rank_count[s["rank"]] = assigned_rank_count.get(s["rank"], 0) + 1
        missing = []
        for rank, required in center_rules.items():
            have = assigned_rank_count.get(rank, 0)
            if have < required:
                lower = _get_lower_rank(rank)
                missing.append({"rank": rank, "required": required, "available": have,
                                 "lowerRankSuggestion": lower})
        data.append({
            "id": c["id"], "name": c["name"] or "", "address": c["address"] or "",
            "thana": c["thana"] or "", "centerType": center_type, "busNo": c["bus_no"] or "",
            "latitude": float(c["latitude"]) if c["latitude"] else None,
            "longitude": float(c["longitude"]) if c["longitude"] else None,
            "dutyCount": c["duty_count"], "roomCount": c["room_count"],
            "assignedStaff": assigned, "missingRanks": missing,
        })
    return _paginated(data, total, page, limit)


@admin_bp.route("/gram-panchayats/<int:gp_id>/centers", methods=["POST"])
@admin_required
def add_center(gp_id):
    body = request.get_json() or {}
    name = (body.get("name") or "").strip()
    if not name:
        return err("name required")
    center_type = (body.get("centerType", "C") or "").strip().upper()
    if center_type not in ["A++", "A", "B", "C"]:
        center_type = "C"
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO matdan_sthal
                (name, address, gram_panchayat_id, thana, center_type, bus_no, latitude, longitude)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
            """, (
                name,
                (body.get("address") or "").strip(),
                gp_id,
                (body.get("thana") or "").strip(),
                center_type,
                (body.get("busNo") or "").strip(),
                body.get("latitude"),
                body.get("longitude")
            ))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "name": name, "centerType": center_type}, "Center added", 201)


@admin_bp.route("/centers/<int:c_id>", methods=["PUT"])
@admin_required
def update_center(c_id):
    body = request.get_json() or {}
    center_type = (body.get("centerType", "C") or "").strip().upper()
    if center_type not in ["A++", "A", "B", "C"]:
        center_type = "C"
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE matdan_sthal
                SET name=%s, address=%s, thana=%s, center_type=%s, bus_no=%s, latitude=%s, longitude=%s
                WHERE id=%s
            """, (
                (body.get("name") or "").strip(),
                (body.get("address") or "").strip(),
                (body.get("thana") or "").strip(),
                center_type,
                (body.get("busNo") or "").strip(),
                body.get("latitude"),
                body.get("longitude"),
                c_id
            ))
        conn.commit()
    finally:
        conn.close()
    return ok({"centerType": center_type}, "Updated")


@admin_bp.route("/centers/<int:c_id>", methods=["DELETE"])
@admin_required
def delete_center(c_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM matdan_sthal WHERE id=%s", (c_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


@admin_bp.route("/centers/<int:c_id>/clear-assignments", methods=["POST"])
@admin_required
def clear_center_assignments(c_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM duty_assignments WHERE sthal_id=%s", (c_id,))
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Cleared {removed} assignments from center {c_id}", "AutoAssign")
    return ok({"removed": removed}, "Assignments cleared")


# ══════════════════════════════════════════════════════════════════════════════
#  ROOMS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/centers/<int:c_id>/rooms", methods=["GET"])
@admin_required
def get_rooms(c_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id, room_number FROM matdan_kendra WHERE matdan_sthal_id=%s ORDER BY id", (c_id,))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{"id": r["id"], "roomNumber": r["room_number"] or ""} for r in rows])


@admin_bp.route("/centers/<int:c_id>/rooms", methods=["POST"])
@admin_required
def add_room(c_id):
    body = request.get_json() or {}
    rn = body.get("roomNumber", "").strip()
    if not rn:
        return err("roomNumber required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO matdan_kendra (room_number,matdan_sthal_id) VALUES (%s,%s)", (rn, c_id))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "roomNumber": rn}, "Room added", 201)


@admin_bp.route("/rooms/<int:r_id>", methods=["DELETE"])
@admin_required
def delete_room(r_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM matdan_kendra WHERE id=%s", (r_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  STAFF — paginated + search
#  DISTRICT SHARING: staff is scoped by district (users.district column)
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/staff", methods=["GET"])
@admin_required
def get_staff():
    search      = request.args.get("q", "").strip()
    assigned    = request.args.get("assigned", "").strip().lower()
    rank_filter = request.args.get("rank", "").strip()
    armed       = request.args.get("armed", "").strip().lower()
    page, limit, offset = _page_params()

    # ALL staff is visible to ALL admins across all districts
    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = []
            where_parts = ["u.role='staff'"]

            if search:
                where_parts.append(
                    "(u.name LIKE %s OR u.pno LIKE %s OR u.mobile LIKE %s "
                    "OR u.thana LIKE %s OR u.district LIKE %s)"
                )
                like = f"%{search}%"
                params.extend([like, like, like, like, like])

            if rank_filter:
                where_parts.append("u.user_rank = %s")
                params.append(rank_filter)

            OFFICER_EXISTS = """(
                EXISTS (SELECT 1 FROM duty_assignments da WHERE da.staff_id=u.id)
                OR EXISTS (SELECT 1 FROM kshetra_officers ko WHERE ko.user_id=u.id)
                OR EXISTS (SELECT 1 FROM zonal_officers zo WHERE zo.user_id=u.id)
                OR EXISTS (SELECT 1 FROM sector_officers so WHERE so.user_id=u.id)
            )"""

            if assigned == "yes":
                where_parts.append(OFFICER_EXISTS)
            elif assigned == "no":
                where_parts.append(f"NOT {OFFICER_EXISTS}")

            if armed == "yes":
                where_parts.append("u.is_armed = 1")
            elif armed == "no":
                where_parts.append("u.is_armed = 0")

            where_sql = " AND ".join(where_parts)

            cur.execute(f"""
                SELECT COUNT(*) AS cnt FROM users u WHERE {where_sql}
            """, params)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT
                    u.id, u.name, u.pno, u.mobile, u.thana,
                    u.district, u.user_rank, u.is_armed,
                    (SELECT ms.name FROM duty_assignments da
                     JOIN matdan_sthal ms ON ms.id=da.sthal_id
                     WHERE da.staff_id=u.id LIMIT 1) AS center_name,
                    (SELECT sz.name FROM kshetra_officers ko
                     JOIN super_zones sz ON sz.id=ko.super_zone_id
                     WHERE ko.user_id=u.id LIMIT 1) AS sz_name,
                    (SELECT z.name FROM zonal_officers zo
                     JOIN zones z ON z.id=zo.zone_id
                     WHERE zo.user_id=u.id LIMIT 1) AS zone_name,
                    (SELECT s.name FROM sector_officers so
                     JOIN sectors s ON s.id=so.sector_id
                     WHERE so.user_id=u.id LIMIT 1) AS sector_name
                FROM users u
                WHERE {where_sql}
                ORDER BY u.name
                LIMIT %s OFFSET %s
            """, params + [limit, offset])

            rows = cur.fetchall()

    finally:
        conn.close()

    data = []
    for r in rows:
        if r["center_name"]:
            assign_type  = "booth"
            assign_label = r["center_name"]
        elif r["sz_name"]:
            assign_type  = "kshetra"
            assign_label = r["sz_name"]
        elif r["zone_name"]:
            assign_type  = "zone"
            assign_label = r["zone_name"]
        elif r["sector_name"]:
            assign_type  = "sector"
            assign_label = r["sector_name"]
        else:
            assign_type  = ""
            assign_label = ""

        data.append({
            "id": r["id"],
            "name": r["name"] or "",
            "pno": r["pno"] or "",
            "mobile": r["mobile"] or "",
            "thana": r["thana"] or "",
            "district": r["district"] or "",
            "rank": r["user_rank"] or "",
            "isArmed": bool(r["is_armed"]),
            "isAssigned": bool(assign_type),
            "assignType": assign_type,
            "assignLabel": assign_label,
        })

    return _paginated(data, total, page, limit)


@admin_bp.route("/staff/search", methods=["GET"])
@admin_required
def search_staff():
    q    = request.args.get("q",     "").strip()
    armed = request.args.get("armed", "").strip().lower()
    if not q:
        return ok([])
    like = f"%{q}%"

    # ALL staff is visible to ALL admins across all districts
    armed_clause = ""
    if armed == "yes":
        armed_clause = " AND is_armed = 1"
    elif armed == "no":
        armed_clause = " AND is_armed = 0"

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, pno, mobile, thana, user_rank, district, is_armed "
                "FROM users "
                f"WHERE role='staff' {armed_clause} "
                "AND (name LIKE %s OR pno LIKE %s OR mobile LIKE %s OR district LIKE %s) "
                "ORDER BY name LIMIT 20",
                [like, like, like, like]
            )
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id":       r["id"],
        "name":     r["name"]      or "",
        "pno":      r["pno"]       or "",
        "mobile":   r["mobile"]    or "",
        "thana":    r["thana"]     or "",
        "district": r["district"]  or "",
        "rank":     r["user_rank"] or "",
        "isArmed":  bool(r["is_armed"]),
    } for r in rows])


@admin_bp.route("/staff", methods=["POST"])
@admin_required
def add_staff():
    body = request.get_json() or {}

    name = (body.get("name") or "").strip()
    pno  = (body.get("pno")  or "").strip()

    if not name or not pno:
        return err("name and pno required")

    is_armed = 1 if (
        body.get("isArmed") in [True, 1, "1", "true"] or
        body.get("is_armed") in [True, 1, "1", "true"] or
        str(body.get("weapon", "")).lower() in ["sastra", "armed", "yes"]
    ) else 0

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
            if cur.fetchone():
                return err(f"PNO {pno} already registered", 409)

            cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
            username = pno if not cur.fetchone() else f"{pno}_{_admin_id()}"

            # DISTRICT SHARING: staff inherits the current admin's district
            district = request.user.get("district") or ""

            cur.execute("""
                INSERT INTO users
                    (name, pno, username, password, mobile, thana,
                     district, user_rank, is_armed, role, is_active, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
            """, (
                name, pno, username, _fast_hash(pno),
                (body.get("mobile") or "").strip(),
                (body.get("thana")  or "").strip(),
                district,
                (body.get("rank")   or "").strip(),
                is_armed,
                _admin_id(),
            ))

            new_id = cur.lastrowid

        conn.commit()

    except Exception as e:
        try:
            conn.rollback()
        except:
            pass
        write_log("ERROR", f"add_staff error: {e}", "Staff")
        return err("Failed to add staff", 500)

    finally:
        conn.close()

    write_log(
        "INFO",
        f"Staff '{name}' PNO:{pno} added (is_armed={is_armed}) by admin {_admin_id()}",
        "Staff"
    )

    return ok({
        "id": new_id,
        "name": name,
        "pno": pno,
        "isArmed": bool(is_armed)
    }, "Staff added", 201)


# ══════════════════════════════════════════════════════════════════════════════
#  BULK UPLOAD — SSE streaming
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/staff/bulk", methods=["POST"])
@admin_required
def add_staff_bulk():
    body  = request.get_json(force=True, silent=True) or {}
    items = body.get("staff", [])

    if not items:
        return err("staff list empty")
    if len(items) > MAX_BATCH_ROWS:
        return err(f"Too many rows. Max {MAX_BATCH_ROWS} per upload.")

    # DISTRICT SHARING: staff is stored with current admin's district
    district    = (request.user.get("district") or "").strip()
    admin_id    = request.user["id"]
    total_input = len(items)

    def generate():
        yield _sse({"phase": "parse", "pct": 2, "msg": "Validating rows..."})

        clean, skipped = [], []
        seen_pnos = set()

        for i, s in enumerate(items):
            pno  = str(s.get("pno",  "") or "").strip()
            name = str(s.get("name", "") or "").strip()

            if not pno or not name:
                skipped.append(pno or f"row_{i+1}")
                continue

            if pno in seen_pnos:
                skipped.append(pno)
                continue

            seen_pnos.add(pno)

            is_armed_val = str(
                s.get("sastra", s.get("armed", s.get("is_armed", ""))) or ""
            ).strip().lower()

            is_armed = 1 if is_armed_val in (
                "1", "yes", "हाँ", "han", "sastra", "सशस्त्र", "armed", "true"
            ) else 0

            clean.append({
                "pno":    pno,
                "name":   name,
                "rank":   str(s.get("rank",     "") or "").strip(),
                "mobile": str(s.get("mobile",   "") or "").strip(),
                "thana":  str(s.get("thana",    "") or "").strip(),
                # DISTRICT SHARING: district from CSV or fallback to admin's district
                "dist":   (str(s.get("district","") or "").strip()) or district,
                "is_armed": is_armed,
            })

        yield _sse({"phase": "parse", "pct": 10, "msg": f"{len(clean)} valid, {len(skipped)} skipped"})

        if not clean:
            yield _sse({"phase": "done", "added": 0, "skipped": skipped, "total": total_input, "pct": 100, "msg": "0 जोड़े गए"})
            return

        yield _sse({"phase": "parse", "pct": 15, "msg": "Duplicates जांच रहे हैं..."})

        read_conn = get_db()
        try:
            with read_conn.cursor() as cur:
                all_pnos = [r["pno"] for r in clean]
                ph = ",".join(["%s"] * len(all_pnos))
                cur.execute(f"SELECT pno FROM users WHERE pno IN ({ph})", all_pnos)
                existing_pnos = {r["pno"] for r in cur.fetchall()}
                cur.execute(f"SELECT username FROM users WHERE username IN ({ph})", all_pnos)
                existing_usernames = {r["username"] for r in cur.fetchall()}
        finally:
            read_conn.close()

        yield _sse({"phase": "parse", "pct": 22, "msg": f"{len(existing_pnos)} duplicates मिले"})

        pre_insert = []
        for r in clean:
            if r["pno"] in existing_pnos:
                skipped.append(r["pno"])
                continue
            uname = r["pno"] if r["pno"] not in existing_usernames else f"{r['pno']}_{admin_id}"
            pre_insert.append({**r, "username": uname})

        yield _sse({"phase": "parse", "pct": 25, "msg": f"{len(pre_insert)} rows insert होंगे"})

        if not pre_insert:
            yield _sse({"phase": "done", "added": 0, "skipped": skipped, "total": total_input, "pct": 100, "msg": "0 जोड़े गए (सभी duplicate थे)"})
            return

        total_to_hash = len(pre_insert)
        hashed        = [None] * total_to_hash
        hashed_count  = 0
        workers       = min(HASH_WORKERS, max(1, total_to_hash // 5))
        report_every  = max(1, total_to_hash // 50)

        yield _sse({"phase": "hash", "pct": 25, "msg": f"0/{total_to_hash} passwords hash हो रहे हैं..."})

        with ThreadPoolExecutor(max_workers=workers) as pool:
            future_to_idx = {pool.submit(_fast_hash, r["pno"]): i for i, r in enumerate(pre_insert)}
            for future in as_completed(future_to_idx):
                idx = future_to_idx[future]
                hashed[idx] = future.result()
                hashed_count += 1
                if hashed_count % report_every == 0 or hashed_count == total_to_hash:
                    pct = 25 + int((hashed_count / total_to_hash) * 30)
                    yield _sse({"phase": "hash", "pct": pct, "msg": f"Hashing {hashed_count}/{total_to_hash}..."})

        yield _sse({"phase": "hash", "pct": 55, "msg": "Hash पूर्ण। DB में insert हो रहा है..."})

        insert_conn = get_db()
        added       = 0
        total_ins   = len(pre_insert)

        try:
            with insert_conn.cursor() as cur:
                cur.execute("SET autocommit=1")

            with insert_conn.cursor() as cur:
                for chunk_start in range(0, total_ins, INSERT_CHUNK_SIZE):
                    chunk_rows   = pre_insert[chunk_start: chunk_start + INSERT_CHUNK_SIZE]
                    chunk_hashes = hashed[chunk_start: chunk_start + INSERT_CHUNK_SIZE]

                    params_list = [
                        (
                            r["name"], r["pno"], r["username"],
                            chunk_hashes[i],
                            r["mobile"], r["thana"], r["dist"],
                            r["rank"], r.get("is_armed", 0), admin_id
                        )
                        for i, r in enumerate(chunk_rows)
                    ]

                    cur.executemany("""
                        INSERT IGNORE INTO users
                            (name, pno, username, password, mobile, thana,
                            district, user_rank, is_armed, role, is_active, created_by)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
                    """, params_list)

                    added += cur.rowcount
                    pct = 55 + int(((chunk_start + len(chunk_rows)) / total_ins) * 43)
                    yield _sse({"phase": "insert", "pct": min(pct, 98), "added": added, "total": total_ins, "msg": f"Insert: {added}/{total_ins}"})

        except Exception as e:
            yield _sse({"phase": "error", "message": f"Insert error (after {added} rows saved): {str(e)}"})
            return
        finally:
            try:
                insert_conn.close()
            except:
                pass

        write_log("INFO", f"Bulk: {added} added, {len(skipped)} skipped (admin {admin_id})", "Import")

        yield _sse({
            "phase": "done", "added": added, "skipped": skipped,
            "total": total_input, "pct": 100,
            "msg": f"{added} जोड़े गए, {len(skipped)} छोड़े गए",
        })

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={
            "Cache-Control":          "no-cache, no-store",
            "X-Accel-Buffering":      "no",
            "X-Content-Type-Options": "nosniff",
            "Connection":             "keep-alive",
        },
        direct_passthrough=True,
    )


@admin_bp.route("/staff/bulk-csv", methods=["POST"])
@admin_required
def add_staff_bulk_csv():
    file = request.files.get("file")
    if not file:
        return err("CSV file required (field: 'file')")

    try:
        content = file.read().decode("utf-8-sig")
    except UnicodeDecodeError:
        try:
            content = file.read().decode("latin-1")
        except Exception as e:
            return err(f"File encoding error: {e}")

    reader = csv.DictReader(io.StringIO(content))
    fieldnames = [h.strip().lower() for h in (reader.fieldnames or [])]

    items = []
    ARMED_VALS = {'1', 'yes', 'हाँ', 'han', 'sastra', 'सशस्त्र', 'armed', 'true'}

    for row in reader:
        norm = {k.strip().lower(): v for k, v in row.items()}
        pno  = norm.get('pno') or norm.get('p.no') or ''
        name = norm.get('name') or norm.get('नाम') or ''
        if not pno and not name:
            continue
        armed_raw = (
            norm.get('sastra') or norm.get('armed') or
            norm.get('weapon') or norm.get('शस्त्र') or ''
        ).strip().lower()

        items.append({
            "pno":      pno.strip(),
            "name":     name.strip(),
            "mobile":   (norm.get('mobile') or norm.get('mob') or norm.get('phone') or '').strip(),
            "thana":    (norm.get('thana') or norm.get('थाना') or norm.get('ps') or '').strip(),
            "district": (norm.get('district') or norm.get('dist') or norm.get('जिला') or '').strip(),
            "rank":     (norm.get('rank') or norm.get('post') or norm.get('पद') or '').strip(),
            "is_armed": 1 if armed_raw in ARMED_VALS else 0,
        })

    if not items:
        return err("No valid rows found in CSV")

    request._cached_json = ({"staff": items}, True)
    return add_staff_bulk()


@admin_bp.route("/staff/<int:staff_id>", methods=["PUT"])
@admin_required
def update_staff(staff_id):
    body     = request.get_json() or {}
    is_armed = 1 if body.get("isArmed") else 0

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE users
                SET name=%s, pno=%s, mobile=%s, thana=%s, user_rank=%s, is_armed=%s
                WHERE id=%s AND role='staff'
            """, (
                body.get("name",   ""),
                body.get("pno",    ""),
                body.get("mobile", ""),
                body.get("thana",  ""),
                body.get("rank",   ""),
                is_armed,
                staff_id,
            ))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Staff updated")


@admin_bp.route("/staff/<int:staff_id>", methods=["DELETE"])
@admin_required
def delete_staff(staff_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM users WHERE id=%s AND role='staff'",
                [staff_id]
            )
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Staff deleted")


@admin_bp.route("/staff/bulk-delete", methods=["POST"])
@admin_required
def bulk_delete_staff():
    body = request.get_json() or {}
    ids  = body.get("staffIds", [])
    if not ids:
        return err("staffIds required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            ph = ",".join(["%s"] * len(ids))
            cur.execute(
                f"DELETE FROM users WHERE id IN ({ph}) AND role='staff'",
                ids
            )
            deleted = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Bulk delete: {deleted} staff by admin {_admin_id()}", "Staff")
    return ok({"deleted": deleted}, f"{deleted} staff deleted")


@admin_bp.route("/staff/bulk-assign", methods=["POST"])
@admin_required
def bulk_assign_duty():
    body      = request.get_json() or {}
    ids       = body.get("staffIds", [])
    center_id = body.get("centerId")
    bus_no    = body.get("busNo", "")
    if not ids or not center_id:
        return err("staffIds and centerId required")
    conn = get_db()
    assigned = 0
    try:
        with conn.cursor() as cur:
            for sid in ids:
                cur.execute("""INSERT INTO duty_assignments (staff_id, sthal_id, bus_no, assigned_by)
                    VALUES (%s,%s,%s,%s)
                    ON DUPLICATE KEY UPDATE sthal_id=VALUES(sthal_id), bus_no=VALUES(bus_no), assigned_by=VALUES(assigned_by)""",
                    (sid, center_id, bus_no, _admin_id()))
                assigned += 1
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Bulk assign: {assigned} staff → center {center_id} by admin {_admin_id()}", "Duty")
    return ok({"assigned": assigned}, f"{assigned} staff assigned")


@admin_bp.route("/staff/bulk-unassign", methods=["POST"])
@admin_required
def bulk_unassign_duty():
    body = request.get_json() or {}
    ids  = body.get("staffIds", [])
    if not ids:
        return err("staffIds required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            ph = ",".join(["%s"] * len(ids))
            cur.execute(f"DELETE FROM duty_assignments WHERE staff_id IN ({ph})", ids)
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    return ok({"removed": removed}, f"{removed} duties removed")


@admin_bp.route("/staff/<int:staff_id>/duty", methods=["DELETE"])
@admin_required
def remove_duty_by_staff(staff_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM duty_assignments WHERE staff_id=%s", (staff_id,))
            affected = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    if affected == 0:
        return err("No duty found for this staff", 404)
    return ok(None, "Duty removed")


# ══════════════════════════════════════════════════════════════════════════════
#  DUTY ASSIGNMENTS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/duties", methods=["GET"])
@admin_required
def get_duties():
    center_id_filter = request.args.get("center_id", type=int)
    search           = request.args.get("q", "").strip()
    page, limit, offset = _page_params()

    # DISTRICT SHARING: show duties for all admins in same district
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            where_parts = [f"sz.admin_id IN ({d_ph})"]
            params      = list(d_params)
            if center_id_filter:
                where_parts.append("ms.id = %s")
                params.append(center_id_filter)
            if search:
                where_parts.append("(u.name LIKE %s OR u.pno LIKE %s OR ms.name LIKE %s)")
                like = f"%{search}%"
                params.extend([like, like, like])
            where_sql = " AND ".join(where_parts)

            cur.execute(f"""SELECT COUNT(*) AS cnt
                FROM duty_assignments da JOIN users u ON u.id=da.staff_id
                JOIN matdan_sthal ms ON ms.id=da.sthal_id
                JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
                JOIN sectors s ON s.id=gp.sector_id JOIN zones z ON z.id=s.zone_id
                JOIN super_zones sz ON sz.id=z.super_zone_id WHERE {where_sql}""", params)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""SELECT da.id, da.bus_no, da.card_downloaded,
                       u.id AS staff_id, u.name, u.pno, u.mobile, u.thana, u.user_rank, u.district,
                       ms.id AS center_id, ms.name AS center_name, ms.center_type,
                       gp.name AS gp_name,
                       s.id AS sector_id, s.name AS sector_name,
                       z.id AS zone_id, z.name AS zone_name,
                       sz.id AS super_zone_id, sz.name AS super_zone_name, sz.block AS block_name
                FROM duty_assignments da
                JOIN users u ON u.id=da.staff_id JOIN matdan_sthal ms ON ms.id=da.sthal_id
                JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
                JOIN sectors s ON s.id=gp.sector_id JOIN zones z ON z.id=s.zone_id
                JOIN super_zones sz ON sz.id=z.super_zone_id
                WHERE {where_sql} ORDER BY ms.name, u.name LIMIT %s OFFSET %s""",
                params + [limit, offset])
            rows = cur.fetchall()

            if not rows:
                return _paginated([], total, page, limit)

            sz_ids     = list({r["super_zone_id"] for r in rows})
            z_ids      = list({r["zone_id"]       for r in rows})
            s_ids      = list({r["sector_id"]     for r in rows})
            center_ids = list({r["center_id"]     for r in rows})

            def _fetch_map(sql, id_list):
                if not id_list: return {}
                ph = ",".join(["%s"] * len(id_list))
                cur.execute(sql.format(ph=ph), id_list)
                result = {}
                for row in cur.fetchall():
                    key = list(row.values())[0]
                    result.setdefault(key, []).append(dict(row))
                return result

            super_off_map  = _fetch_map("SELECT super_zone_id AS _fk, name, pno, mobile, user_rank FROM kshetra_officers WHERE super_zone_id IN ({ph})", sz_ids)
            zonal_off_map  = _fetch_map("SELECT zone_id AS _fk, name, pno, mobile, user_rank FROM zonal_officers WHERE zone_id IN ({ph})", z_ids)
            sector_off_map = _fetch_map("SELECT sector_id AS _fk, name, pno, mobile, user_rank FROM sector_officers WHERE sector_id IN ({ph})", s_ids)
            sahyogi_map    = _fetch_map("SELECT da2.sthal_id AS _fk, u2.name, u2.pno, u2.mobile, u2.thana, u2.user_rank, u2.district FROM duty_assignments da2 JOIN users u2 ON u2.id=da2.staff_id WHERE da2.sthal_id IN ({ph})", center_ids)

            def _strip(lst):
                return [{k: v for k, v in d.items() if k != "_fk"} for d in lst]

            result = [{
                "id": r["id"], "centerId": r["center_id"],
                "name": r["name"] or "", "pno": r["pno"] or "", "mobile": r["mobile"] or "",
                "staffThana": r["thana"] or "", "rank": r["user_rank"] or "", "district": r["district"] or "",
                "centerName": r["center_name"] or "", "gpName": r["gp_name"] or "",
                "sectorName": r["sector_name"] or "", "zoneName": r["zone_name"] or "",
                "superZoneName": r["super_zone_name"] or "", "blockName": r["block_name"] or "",
                "busNo": r["bus_no"] or "",
                "cardDownloaded": bool(r.get("card_downloaded", False)),
                "superOfficers":  _strip(super_off_map.get(r["super_zone_id"], [])),
                "zonalOfficers":  _strip(zonal_off_map.get(r["zone_id"],       [])),
                "sectorOfficers": _strip(sector_off_map.get(r["sector_id"],    [])),
                "sahyogi":        _strip(sahyogi_map.get(r["center_id"],        [])),
            } for r in rows]
    finally:
        conn.close()
    return _paginated(result, total, page, limit)


@admin_bp.route("/duties", methods=["POST"])
@admin_required
def assign_duty():
    body     = request.get_json() or {}
    staff_id = body.get("staffId")
    sthal_id = body.get("centerId")

    if not staff_id or not sthal_id:
        return err("staffId and centerId required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT value FROM app_config WHERE `key`='electionDate' LIMIT 1")
            cfg = cur.fetchone()
            electiondate = cfg["value"] if cfg else None

            cur.execute("SELECT bus_no FROM matdan_sthal WHERE id = %s LIMIT 1", (sthal_id,))
            center = cur.fetchone()
            if not center:
                return err("Center not found")

            bus_no = center.get("bus_no") or ""

            cur.execute("""
                INSERT INTO duty_assignments
                    (staff_id, sthal_id, bus_no, assigned_by, election_date)
                VALUES (%s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    sthal_id=VALUES(sthal_id),
                    bus_no=VALUES(bus_no),
                    assigned_by=VALUES(assigned_by),
                    election_date=VALUES(election_date)
            """, (staff_id, sthal_id, bus_no, _admin_id(), electiondate))

        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Duty: staff {staff_id} → center {sthal_id} (Bus: {bus_no})", "Duty")
    return ok({"busNo": bus_no}, "Duty assigned", 201)


@admin_bp.route("/duties/<int:duty_id>", methods=["DELETE"])
@admin_required
def remove_duty(duty_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM duty_assignments WHERE id=%s", (duty_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Duty removed")


# ══════════════════════════════════════════════════════════════════════════════
#  ALL CENTERS (map view)
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/centers/all", methods=["GET"])
@admin_required
def all_centers():
    search = request.args.get("q", "").strip()
    page, limit, offset = _page_params()

    # DISTRICT SHARING: show centers for all admins in same district
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            count_params = list(d_params)
            where_extra = ""
            if search:
                where_extra = "AND (ms.name LIKE %s OR ms.thana LIKE %s OR gp.name LIKE %s)"
                like = f"%{search}%"
                count_params.extend([like, like, like])

            cur.execute(f"""SELECT COUNT(DISTINCT ms.id) AS cnt
                FROM matdan_sthal ms JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
                JOIN sectors s ON s.id=gp.sector_id JOIN zones z ON z.id=s.zone_id
                JOIN super_zones sz ON sz.id=z.super_zone_id
                WHERE sz.admin_id IN ({d_ph}) {where_extra}""", count_params)
            total = cur.fetchone()["cnt"]

            data_params = list(d_params)
            if search:
                data_params.extend([like, like, like])

            cur.execute(f"""SELECT ms.id, ms.name, ms.address, ms.thana, ms.center_type, ms.bus_no,
                       ms.latitude, ms.longitude,
                       gp.name AS gp_name, s.name AS sector_name, z.name AS zone_name,
                       sz.name AS super_zone_name, sz.block AS block_name,
                       COUNT(da.id) AS duty_count
                FROM matdan_sthal ms JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
                JOIN sectors s ON s.id=gp.sector_id JOIN zones z ON z.id=s.zone_id
                JOIN super_zones sz ON sz.id=z.super_zone_id
                LEFT JOIN duty_assignments da ON da.sthal_id=ms.id
                WHERE sz.admin_id IN ({d_ph}) {where_extra}
                GROUP BY ms.id ORDER BY ms.name LIMIT %s OFFSET %s""",
                data_params + [limit, offset])
            rows = cur.fetchall()
    finally:
        conn.close()
    data = [{"id": r["id"], "name": r["name"] or "", "address": r["address"] or "",
             "thana": r["thana"] or "", "centerType": r["center_type"] or "C",
             "busNo": r["bus_no"] or "",
             "latitude": float(r["latitude"]) if r["latitude"] else None,
             "longitude": float(r["longitude"]) if r["longitude"] else None,
             "gpName": r["gp_name"] or "", "sectorName": r["sector_name"] or "",
             "zoneName": r["zone_name"] or "", "superZoneName": r["super_zone_name"] or "",
             "blockName": r["block_name"] or "", "dutyCount": r["duty_count"]} for r in rows]
    return _paginated(data, total, page, limit)


# ══════════════════════════════════════════════════════════════════════════════
#  OVERVIEW — district-wide aggregation
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/overview", methods=["GET"])
@admin_required
def admin_overview():
    # DISTRICT SHARING: aggregate stats for all admins in same district
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    district = (request.user.get("district") or "").strip()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) AS cnt FROM super_zones WHERE admin_id IN ({d_ph})", d_params)
            sz = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT COUNT(DISTINCT ms.id) AS cnt
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s ON s.id = gp.sector_id
                JOIN zones z ON z.id = s.zone_id
                JOIN super_zones sz ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({d_ph})
            """, d_params)
            booths = cur.fetchone()["cnt"]

            # Staff count: ALL staff across all districts
            cur.execute("SELECT COUNT(*) AS cnt FROM users WHERE role='staff' AND is_active=1")
            staff = cur.fetchone()["cnt"]

            # Duty count: duties at centers belonging to this district's admins
            cur.execute(f"""
                SELECT COUNT(*) AS cnt
                FROM duty_assignments da
                JOIN matdan_sthal ms ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s ON s.id = gp.sector_id
                JOIN zones z ON z.id = s.zone_id
                JOIN super_zones sz ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({d_ph})
            """, d_params)
            assigned = cur.fetchone()["cnt"]

    except Exception as e:
        write_log("ERROR", f"overview error: {e}", "Overview")
        return {"success": True, "data": {"superZones": 0, "totalBooths": 0, "totalStaff": 0, "assignedDuties": 0}}
    finally:
        conn.close()

    return {
        "success": True,
        "data": {
            "superZones":    int(sz or 0),
            "totalBooths":   int(booths or 0),
            "totalStaff":    int(staff or 0),
            "assignedDuties": int(assigned or 0),
        }
    }


@admin_bp.route("/staff/debug", methods=["GET"])
@admin_required
def debug_staff():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS cnt FROM users WHERE role='staff'")
            total = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT LOWER(TRIM(district)) AS district_norm, COUNT(*) AS cnt
                FROM users WHERE role='staff'
                GROUP BY district_norm ORDER BY cnt DESC LIMIT 20
            """)
            by_district = [{"district": r["district_norm"] or "(empty)", "count": r["cnt"]}
                          for r in cur.fetchall()]

            admin_district = (request.user.get("district") or "").strip().lower()

            if admin_district:
                cur.execute(
                    "SELECT COUNT(*) AS cnt FROM users WHERE role='staff' AND LOWER(TRIM(district))=%s",
                    (admin_district,)
                )
                matching = cur.fetchone()["cnt"]
            else:
                matching = total

    finally:
        conn.close()

    return ok({
        "adminDistrict":    admin_district or "(not set)",
        "totalStaffInDB":   total,
        "matchingDistrict": matching,
        "byDistrict":       by_district,
        "message": "If matchingDistrict=0 but totalStaffInDB>0, district mismatch is still the bug"
    })


# ══════════════════════════════════════════════════════════════════════════════
#  RULES — DISTRICT SHARING
#  Rules are saved per admin_id but read from ALL district admins combined.
#  This means if Admin 1 sets rules for "A", Admin 2 in same district sees them.
#  When saving, always save under current admin's own ID (no conflict).
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/rules", methods=["POST"])
@admin_required
def save_rules():
    body        = request.get_json() or {}
    sensitivity = (body.get("sensitivity") or "").strip()
    rules       = body.get("rules", [])

    if not sensitivity:
        return err("sensitivity required")
    if sensitivity not in ("A++", "A", "B", "C"):
        return err("sensitivity must be one of: A++, A, B, C")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS booth_staff_rules (
                    id             INT AUTO_INCREMENT PRIMARY KEY,
                    admin_id       INT  NOT NULL,
                    sensitivity    ENUM('A++','A','B','C') NOT NULL,
                    user_rank      VARCHAR(100) NOT NULL,
                    is_armed       TINYINT(1)   NOT NULL DEFAULT 0,
                    required_count INT          NOT NULL DEFAULT 1,
                    created_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_admin       (admin_id),
                    INDEX idx_sensitivity (sensitivity),
                    FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)
            cur.execute("""
                SELECT COUNT(*) AS cnt FROM information_schema.columns
                WHERE table_schema = DATABASE()
                  AND table_name   = 'booth_staff_rules'
                  AND column_name  = 'is_armed'
            """)
            if cur.fetchone()["cnt"] == 0:
                cur.execute("ALTER TABLE booth_staff_rules ADD COLUMN is_armed TINYINT(1) NOT NULL DEFAULT 0 AFTER user_rank")

            # DISTRICT SHARING: when saving rules, delete for ALL district admins
            # and save fresh under current admin_id only.
            # This prevents duplicates when district admins each save rules.
            d_ids = _district_admin_ids()
            d_ph, d_params = _district_placeholder(d_ids)
            cur.execute(
                f"DELETE FROM booth_staff_rules WHERE admin_id IN ({d_ph}) AND sensitivity=%s",
                d_params + [sensitivity]
            )

            # Save new rules under current admin_id
            for r in rules:
                rank = str(r.get("rank", "")).strip()
                if not rank:
                    continue
                count = int(r.get("count") or r.get("required_count") or 1)
                is_armed = 1 if (
                    r.get("isArmed") in [True, 1, "1", "true"] or
                    r.get("is_armed") in [True, 1, "1", "true"]
                ) else 0
                cur.execute("""
                    INSERT INTO booth_staff_rules
                        (admin_id, sensitivity, user_rank, is_armed, required_count)
                    VALUES (%s, %s, %s, %s, %s)
                """, (_admin_id(), sensitivity, rank, is_armed, count))

        conn.commit()

    except Exception as e:
        try: conn.rollback()
        except: pass
        write_log("ERROR", f"save_rules error: {e}", "Rules")
        return err(f"Save failed: {str(e)}", 500)
    finally:
        conn.close()

    write_log("INFO", f"Rules saved: sensitivity={sensitivity}, {len(rules)} rules by admin {_admin_id()}", "Rules")
    return ok(None, f"{sensitivity} rules saved")


@admin_bp.route("/rules", methods=["GET"])
@admin_required
def get_rules():
    sensitivity = (request.args.get("sensitivity") or "").strip()

    # DISTRICT SHARING: read rules from ALL admins in same district
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            if sensitivity:
                cur.execute(f"""
                    SELECT sensitivity,
                           user_rank AS `rank`,
                           is_armed,
                           required_count AS count
                    FROM booth_staff_rules
                    WHERE admin_id IN ({d_ph}) AND sensitivity = %s
                    ORDER BY id
                """, d_params + [sensitivity])
            else:
                cur.execute(f"""
                    SELECT sensitivity,
                           user_rank AS `rank`,
                           is_armed,
                           required_count AS count
                    FROM booth_staff_rules
                    WHERE admin_id IN ({d_ph})
                    ORDER BY FIELD(sensitivity,'A++','A','B','C'), id
                """, d_params)

            rows = cur.fetchall()

    except Exception as e:
        print("GET RULES ERROR:", e)
        return ok([])
    finally:
        conn.close()

    result = []
    for r in rows:
        result.append({
            "rank":        str(r["rank"]),
            "count":       int(r["count"]),
            "isArmed":     bool(r["is_armed"]),
            "sensitivity": r["sensitivity"]
        })

    return ok(result)


# ══════════════════════════════════════════════════════════════════════════════
#  AUTO-ASSIGN — uses district-wide rules
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/auto-assign/<int:center_id>", methods=["POST"])
@admin_required
def auto_assign(center_id):
    body             = request.get_json(silent=True) or {}
    custom_rules_raw = body.get("customRules", [])

    # DISTRICT SHARING: load rules from all admins in same district
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT center_type,bus_no FROM matdan_sthal WHERE id=%s", (center_id,))
            center = cur.fetchone()
            if not center:
                return err("Center not found", 404)

            sensitivity = (center["center_type"] or "").strip().upper()

            if custom_rules_raw:
                rules = [{
                    "user_rank":      r["rank"],
                    "required_count": int(r.get("count", 1)),
                    "is_armed":       int(r.get("isArmed") or r.get("is_armed") or 0),
                } for r in custom_rules_raw if r.get("rank")]
            else:
                cur.execute(f"""
                    SELECT user_rank, required_count, is_armed
                    FROM booth_staff_rules
                    WHERE admin_id IN ({d_ph}) AND sensitivity = %s
                """, d_params + [sensitivity])
                rules = cur.fetchall()

            if not rules:
                return ok({
                    "assigned": [], "missing": [], "lowerRankUsed": [], "total": 0,
                    "message": f"No rules set for {sensitivity}. Set rules on Dashboard.",
                })

            assigned_list   = []
            missing_list    = []
            lower_rank_used = []

            # Auto-assign draws from ALL staff across all districts
            for rule in rules:
                rank     = rule["user_rank"]
                count    = rule["required_count"]
                is_armed = int(rule.get("is_armed", 0))

                cur.execute("""
                    SELECT id, name, pno, mobile, user_rank, is_armed
                    FROM users
                    WHERE role      = 'staff'
                      AND user_rank = %s
                      AND is_armed  = %s
                      AND is_active = 1
                      AND NOT EXISTS (
                          SELECT 1 FROM duty_assignments da WHERE da.staff_id = id
                      )
                    ORDER BY RAND()
                    LIMIT %s
                """, [rank, is_armed, count])

                available         = cur.fetchall()
                assigned_for_rank = list(available)
                needed            = count - len(available)

                if needed > 0:
                    lower_rank    = _get_lower_rank(rank)
                    lower_assigned = []

                    while lower_rank and needed > 0:
                        cur.execute("""
                            SELECT id, name, pno, mobile, user_rank, is_armed
                            FROM users
                            WHERE role      = 'staff'
                              AND user_rank = %s
                              AND is_armed  = %s
                              AND is_active = 1
                              AND NOT EXISTS (
                                  SELECT 1 FROM duty_assignments da WHERE da.staff_id = id
                              )
                            ORDER BY RAND()
                            LIMIT %s
                        """, [lower_rank, is_armed, needed])

                        la = cur.fetchall()
                        if la:
                            lower_assigned.extend(la)
                            needed -= len(la)
                            lower_rank_used.append({
                                "requiredRank": rank,
                                "assignedRank": lower_rank,
                                "count":        len(la),
                                "isArmed":      bool(is_armed),
                            })
                        lower_rank = _get_lower_rank(lower_rank) if lower_rank else None

                    still_missing = count - len(assigned_for_rank) - len(lower_assigned)
                    if still_missing > 0:
                        missing_list.append({
                            "rank":      rank,
                            "required":  count,
                            "available": count - still_missing,
                            "shortage":  still_missing,
                            "isArmed":   bool(is_armed),
                        })

                    for s in lower_assigned:
                        cur.execute("""
                            INSERT IGNORE INTO duty_assignments
                                (staff_id, sthal_id, assigned_by, bus_no)
                            VALUES (%s, %s, %s, %s)
                        """, (s["id"], center_id, _admin_id(), center["bus_no"]))
                        assigned_list.append({
                            "id":           s["id"],
                            "name":         s["name"]      or "",
                            "pno":          s["pno"]       or "",
                            "rank":         s["user_rank"] or "",
                            "originalRank": rank,
                            "isLowerRank":  True,
                            "isArmed":      bool(s["is_armed"]),
                            "bus_no":       center["bus_no"]
                        })

                for s in assigned_for_rank:
                    cur.execute("""
                        INSERT IGNORE INTO duty_assignments
                            (staff_id, sthal_id, assigned_by, bus_no)
                        VALUES (%s, %s, %s, %s)
                    """, (s["id"], center_id, _admin_id(), center["bus_no"]))
                    assigned_list.append({
                        "id":          s["id"],
                        "name":        s["name"]      or "",
                        "pno":         s["pno"]       or "",
                        "rank":        s["user_rank"] or "",
                        "isLowerRank": False,
                        "isArmed":     bool(s["is_armed"]),
                        "bus_no":      center["bus_no"]
                    })

                if not assigned_for_rank and needed == count:
                    if not any(m["rank"] == rank for m in missing_list):
                        missing_list.append({
                            "rank":                rank,
                            "required":            count,
                            "available":           0,
                            "shortage":            count,
                            "isArmed":             bool(is_armed),
                            "lowerRankSuggestion": _get_lower_rank(rank),
                        })

        conn.commit()

    finally:
        conn.close()

    write_log("INFO",
              f"Auto-assign: {len(assigned_list)} to center {center_id} "
              f"(missing: {len(missing_list)}, lower: {len(lower_rank_used)})",
              "AutoAssign")

    return ok({
        "assigned":      assigned_list,
        "missing":       missing_list,
        "lowerRankUsed": lower_rank_used,
        "total":         len(assigned_list),
    })


@admin_bp.route("/officers/save-to-users", methods=["POST"])
@admin_required
def save_officer_to_users():
    body   = request.get_json() or {}
    name   = (body.get("name") or "").strip()
    pno    = (body.get("pno") or "").strip()
    mobile = (body.get("mobile") or "").strip()
    rank   = (body.get("rank") or "").strip()

    if not name or not pno:
        return err("name and pno required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
            existing = cur.fetchone()
            if existing:
                return ok({"id": existing["id"], "existed": True}, "Already in users")

            cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
            username = pno if not cur.fetchone() else f"{pno}_{_admin_id()}"

            district = request.user.get("district") or ""

            cur.execute("""
                INSERT INTO users
                    (name, pno, username, password, mobile,
                     district, user_rank, is_armed, role, is_active, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
            """, (name, pno, username, generate_password_hash(pno),
                  mobile, district, rank, 0, _admin_id()))

            new_id = cur.lastrowid

        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Officer '{name}' PNO:{pno} saved to users by admin {_admin_id()}", "Officer")
    return ok({"id": new_id, "existed": False}, "Officer saved to users", 201)


@admin_bp.route("/super/admins", methods=["GET"])
@admin_required
def get_all_admins():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    u.id, u.name, u.username, u.district, u.is_active, u.created_at,
                    (SELECT COUNT(*) FROM matdan_sthal ms
                     JOIN super_zones sz ON sz.id = (
                        SELECT z.super_zone_id FROM zones z
                        JOIN sectors s ON s.zone_id = z.id
                        JOIN gram_panchayats gp ON gp.sector_id = s.id
                        WHERE gp.id = ms.gram_panchayat_id LIMIT 1
                     )
                     WHERE sz.admin_id = u.id
                    ) AS totalBooths,
                    (SELECT COUNT(*) FROM duty_assignments da
                     JOIN users us ON us.id = da.staff_id
                     WHERE us.created_by = u.id
                    ) AS assignedStaff
                FROM users u
                WHERE u.role = 'admin'
                ORDER BY u.id DESC
            """)
            rows = cur.fetchall()
    finally:
        conn.close()

    data = [{
        "id": r["id"], "name": r["name"], "username": r["username"],
        "district": r["district"], "isActive": bool(r["is_active"]),
        "totalBooths": r["totalBooths"] or 0,
        "assignedStaff": r["assignedStaff"] or 0,
        "createdAt": r["created_at"]
    } for r in rows]

    return ok(data)


@admin_bp.route("/super/form-data", methods=["GET"])
@admin_required
def get_form_data():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    u.id AS adminId, u.name AS adminName, u.district,
                    COUNT(DISTINCT sz.id) AS superZones,
                    COUNT(DISTINCT z.id) AS zones,
                    COUNT(DISTINCT s.id) AS sectors,
                    COUNT(DISTINCT gp.id) AS gramPanchayats,
                    COUNT(DISTINCT ms.id) AS centers,
                    MAX(ms.created_at) AS lastUpdated
                FROM users u
                LEFT JOIN super_zones sz ON sz.admin_id = u.id
                LEFT JOIN zones z ON z.super_zone_id = sz.id
                LEFT JOIN sectors s ON s.zone_id = z.id
                LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
                LEFT JOIN matdan_sthal ms ON ms.gram_panchayat_id = gp.id
                WHERE u.role = 'admin'
                GROUP BY u.id
                ORDER BY u.id DESC
            """)
            rows = cur.fetchall()
    finally:
        conn.close()

    data = [{
        "adminId": r["adminId"], "adminName": r["adminName"], "district": r["district"],
        "superZones": r["superZones"], "zones": r["zones"], "sectors": r["sectors"],
        "gramPanchayats": r["gramPanchayats"], "centers": r["centers"], "lastUpdated": r["lastUpdated"]
    } for r in rows]

    return ok(data)


@admin_bp.route("/duties/<int:duty_id>/attended", methods=["PATCH"])
@admin_required
def mark_attendance(duty_id):
    body     = request.get_json() or {}
    attended = 1 if body.get("attended") else 0
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE duty_assignments SET attended=%s WHERE id=%s", (attended, duty_id))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Attendance updated")


@admin_bp.route("/goswara", methods=["GET"])
@admin_required
def get_goswara():
    current_id   = _admin_id()
    current_role = request.user.get("role", "admin")
    district     = (request.user.get("district") or "").strip()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT `key`, value FROM app_config WHERE `key` IN ('electionDate', 'phase')")
            cfg = {r["key"]: r["value"] for r in cur.fetchall()}

            # DISTRICT SHARING: always aggregate by district
            if district:
                cur.execute("SELECT id FROM users WHERE role='admin' AND district=%s", (district,))
                rows_ids = cur.fetchall()
                admin_ids = [r["id"] for r in rows_ids] if rows_ids else [current_id]
            else:
                admin_ids = [current_id]

            if not admin_ids:
                from flask import jsonify
                return jsonify({"success": True, "electionDate": cfg.get("electionDate", ""), "phase": cfg.get("phase", ""), "data": []})

            ph = ",".join(["%s"] * len(admin_ids))

            cur.execute(f"""
                SELECT sz.block AS block_name,
                       COUNT(DISTINCT zo.id)     AS zonal_count,
                       COUNT(DISTINCT so_off.id) AS sector_count,
                       COUNT(DISTINCT gp.id)     AS gram_panchayat_count
                FROM super_zones sz
                LEFT JOIN zones z ON z.super_zone_id = sz.id
                LEFT JOIN zonal_officers zo ON zo.zone_id = z.id
                LEFT JOIN sectors s ON s.zone_id = z.id
                LEFT JOIN sector_officers so_off ON so_off.sector_id = s.id
                LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
                WHERE sz.admin_id IN ({ph})
                  AND sz.block IS NOT NULL AND TRIM(sz.block) != ''
                GROUP BY sz.block ORDER BY sz.block
            """, admin_ids)
            rows = cur.fetchall()

            cur.execute(f"""
                SELECT block_name, SUM(nyay_count) AS nyay_count
                FROM goswara_nyay_panchayat
                WHERE admin_id IN ({ph})
                GROUP BY block_name
            """, admin_ids)
            nyay_map = {r["block_name"]: int(r["nyay_count"] or 0) for r in cur.fetchall()}

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

    finally:
        conn.close()

    from flask import jsonify
    return jsonify({
        "success":      True,
        "electionDate": cfg.get("electionDate", ""),
        "phase":        cfg.get("phase", ""),
        "data":         data,
    })


@admin_bp.route("/goswara/nyay-panchayat", methods=["POST"])
@admin_required
def save_nyay_panchayat():
    body       = request.get_json() or {}
    block_name = (body.get("blockName") or "").strip()
    nyay_count = int(body.get("nyayCount") or 0)

    if not block_name:
        return err("blockName required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO goswara_nyay_panchayat (admin_id, block_name, nyay_count)
                VALUES (%s, %s, %s)
                ON DUPLICATE KEY UPDATE nyay_count = VALUES(nyay_count)
            """, (_admin_id(), block_name, nyay_count))
        conn.commit()
    finally:
        conn.close()

    return ok(None, "saved")