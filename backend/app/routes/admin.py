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
import threading
import time

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

def normalize_rule(r):
    return {
        "booth_count": r.get("boothCount"),

        "si_armed_count": r.get("siArmedCount", 0),
        "si_unarmed_count": r.get("siUnarmedCount", 0),

        "hc_armed_count": r.get("hcArmedCount", 0),
        "hc_unarmed_count": r.get("hcUnarmedCount", 0),

        "const_armed_count": r.get("constArmedCount", 0),
        "const_unarmed_count": r.get("constUnarmedCount", 0),

        # ✅ NEW
        "aux_armed_count": r.get("auxArmedCount", 0),
        "aux_unarmed_count": r.get("auxUnarmedCount", 0),

        "pac_count": r.get("pacCount", 0),
    }

import threading

def run_auto_assign_job(job_id, super_zone_id, admin_id):

    print("🚀 AUTO ASSIGN STARTED", super_zone_id)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE sz_assign_jobs
                SET status='running'
                WHERE id=%s
            """, (job_id,))
            conn.commit()

        # 🔥 DEBUG
        print("👉 Calling auto_assign_internal")

        auto_assign_internal(super_zone_id, admin_id)

        print("✅ Auto assign completed")

        with conn.cursor() as cur:
            cur.execute("""
                UPDATE sz_assign_jobs
                SET status='done'
                WHERE id=%s
            """, (job_id,))
            conn.commit()

    except Exception as e:
        print("❌ AUTO ASSIGN ERROR:", e)

        with conn.cursor() as cur:
            cur.execute("""
                UPDATE sz_assign_jobs
                SET status='error', error_msg=%s
                WHERE id=%s
            """, (str(e), job_id))
            conn.commit()

    finally:
        conn.close()



@admin_bp.route("/assign/start/<int:super_zone_id>", methods=["POST"])
@admin_required
def start_assignment(super_zone_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                INSERT INTO sz_assign_jobs (super_zone_id, created_by)
                VALUES (%s,%s)
            """, (super_zone_id, request.user["id"]))

            job_id = cur.lastrowid

        conn.commit()

        # 🚀 run in background
        thread = threading.Thread(
            target=run_auto_assign_job,
            args=(job_id, super_zone_id, request.user["id"])
        )
        thread.start()

    finally:
        conn.close()

    return ok({"jobId": job_id}, "Assignment started")

@admin_bp.route("/assign/status/<int:job_id>", methods=["GET"])
@admin_required
def check_job(job_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT * FROM sz_assign_jobs
                WHERE id=%s
            """, (job_id,))

            job = cur.fetchone()

    finally:
        conn.close()

    return ok(job)


@admin_bp.route("/center/<int:id>/custom-rule", methods=["POST"])
@admin_required
def set_custom_rule(id):

    body = request.get_json() or {}
    rule_id = body.get("ruleId")

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                UPDATE matdan_sthal
                SET custom_rule_id=%s
                WHERE id=%s
            """, (rule_id, id))

        conn.commit()
    finally:
        conn.close()

    return ok(None, "Custom rule applied")

@admin_bp.route("/lock/<int:super_zone_id>", methods=["POST"])
@admin_required
def lock_sz(super_zone_id):

    body = request.get_json() or {}
    reason = body.get("reason", "")

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                INSERT INTO sz_duty_locks (super_zone_id, is_locked, status, unlock_reason)
                VALUES (%s,1,'locked',%s)
                ON DUPLICATE KEY UPDATE
                is_locked=1, status='locked', unlock_reason=%s
            """, (super_zone_id, reason, reason))

        conn.commit()
    finally:
        conn.close()

    return ok(None, "Locked")



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

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT 
                    sz.id,
                    sz.name,

                    COUNT(DISTINCT ms.id) AS center_count,

                    COALESCE(l.is_locked, 0) AS is_locked

                FROM super_zones sz
                LEFT JOIN zones z ON z.super_zone_id = sz.id
                LEFT JOIN sectors s ON s.zone_id = z.id
                LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
                LEFT JOIN matdan_sthal ms ON ms.gram_panchayat_id = gp.id
                LEFT JOIN sz_duty_locks l ON l.super_zone_id = sz.id

                WHERE sz.admin_id=%s
                GROUP BY sz.id
            """, (request.user["id"],))

            rows = cur.fetchall()

    finally:
        conn.close()

    return ok(rows)




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

@admin_bp.route("/gram-panchayats/<int:gp_id>/centers", methods=["POST"])
@admin_required
def create_center(gp_id):

    body = request.get_json() or {}

    name        = body.get("name")
    address     = body.get("address")
    thana       = body.get("thana")
    bus_no      = body.get("busNo")
    center_type = body.get("centerType")
    booth_count = body.get("boothCount")
    lat         = body.get("latitude")
    lng         = body.get("longitude")

    # ✅ VALIDATION
    if not name or not center_type:
        return err("name and centerType required")

    try:
        booth_count = int(booth_count or 1)
    except:
        booth_count = 1

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # ✅ 1. CREATE CENTER
            cur.execute("""
                INSERT INTO matdan_sthal
                (gram_panchayat_id, name, address, thana, bus_no,
                 center_type, booth_count, latitude, longitude)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """, (
                gp_id,
                name,
                address,
                thana,
                bus_no,
                center_type,
                booth_count,
                lat,
                lng,
            ))

            center_id = cur.lastrowid

            # 🔥 2. CLEAN OLD ROOMS (safety, future-proof)
            cur.execute("""
                DELETE FROM matdan_kendra
                WHERE matdan_sthal_id=%s
            """, (center_id,))

            # 🔥 3. CREATE ROOMS = BOOTHS
            for i in range(1, booth_count + 1):
                cur.execute("""
                    INSERT INTO matdan_kendra
                    (matdan_sthal_id, room_number)
                    VALUES (%s, %s)
                """, (center_id, str(i)))   # simple numbering: 1,2,3...

        conn.commit()

    except Exception as e:
        conn.rollback()
        print("❌ CREATE CENTER ERROR:", e)
        return err(f"Create failed: {e}", 500)

    finally:
        conn.close()

    return ok({
        "centerId": center_id,
        "boothCount": booth_count
    }, "Center created with rooms")




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

            # ✅ COUNT
            cur.execute(f"""
                SELECT COUNT(*) AS cnt 
                FROM matdan_sthal ms 
                WHERE ms.gram_panchayat_id=%s {where_extra}
            """, params)
            total = cur.fetchone()["cnt"]

            # ✅ FETCH
            cur.execute(f"""
                SELECT ms.*,
                    (SELECT COUNT(*) FROM duty_assignments da WHERE da.sthal_id=ms.id) AS duty_count,
                    (SELECT COUNT(*) FROM matdan_kendra mk WHERE mk.matdan_sthal_id=ms.id) AS room_count
                FROM matdan_sthal ms
                WHERE ms.gram_panchayat_id=%s {where_extra}
                ORDER BY ms.name
                LIMIT %s OFFSET %s
            """, params + [limit, offset])

            centers = cur.fetchall()

            if not centers:
                return _paginated([], total, page, limit)

            # ✅ IDS
            center_ids = [c["id"] for c in centers if c.get("id")]
            staff_by_center = {}

            if center_ids:
                c_ph = ",".join(["%s"] * len(center_ids))

                cur.execute(f"""
                    SELECT da.sthal_id, u.id, u.name, u.pno, u.mobile, u.user_rank
                    FROM duty_assignments da 
                    JOIN users u ON u.id = da.staff_id
                    WHERE da.sthal_id IN ({c_ph})
                """, center_ids)

                for row in cur.fetchall():
                    staff_by_center.setdefault(row["sthal_id"], []).append({
                        "id": row.get("id"),
                        "name": row.get("name") or "",
                        "pno": row.get("pno") or "",
                        "mobile": row.get("mobile") or "",
                        "rank": row.get("user_rank") or ""
                    })

            # ✅ RULES SAFE
            rules = {}
            try:
                d_ids = _district_admin_ids()

                if d_ids:
                    d_ph, d_params = _district_placeholder(d_ids)

                    cur.execute(f"""
                        SELECT sensitivity, user_rank, required_count 
                        FROM booth_rules 
                        WHERE admin_id IN ({d_ph})
                    """, d_params)

                    for r in cur.fetchall():
                        rules.setdefault(r["sensitivity"], {})[r["user_rank"]] = r["required_count"]

            except Exception as e:
                print("⚠ RULE FETCH ERROR:", e)

    except Exception as e:
        print("❌ GET CENTERS ERROR:", e)   # 🔥 IMPORTANT LOG
        return err(f"Server error: {e}", 500)

    finally:
        conn.close()

    # ✅ FORMAT
    data = []

    for c in centers:
        try:
            center_type = c.get("center_type") or "C"
            assigned = staff_by_center.get(c.get("id"), [])

            assigned_rank_count = {}
            for s in assigned:
                rank = s.get("rank")
                if rank:
                    assigned_rank_count[rank] = assigned_rank_count.get(rank, 0) + 1

            missing = []
            center_rules = rules.get(center_type, {})

            for rank, required in center_rules.items():
                have = assigned_rank_count.get(rank, 0)
                if have < required:
                    missing.append({
                        "rank": rank,
                        "required": required,
                        "available": have,
                        "lowerRankSuggestion": _get_lower_rank(rank)
                    })

            data.append({
                "id": c.get("id"),
                "name": c.get("name") or "",
                "address": c.get("address") or "",
                "thana": c.get("thana") or "",

                "centerType": center_type,
                "boothCount": int(c.get("booth_count") or 1),
                "busNo": c.get("bus_no") or "",

                "latitude": float(c["latitude"]) if c.get("latitude") else None,
                "longitude": float(c["longitude"]) if c.get("longitude") else None,

                "dutyCount": int(c.get("duty_count") or 0),
                "roomCount": int(c.get("room_count") or 0),

                "assignedStaff": assigned,
                "missingRanks": missing,
            })

        except Exception as e:
            print("⚠ CENTER FORMAT ERROR:", e)

    return _paginated(data, total, page, limit)




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

    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = []
            where_parts = ["u.role='staff'"]

            # 🔍 SEARCH
            if search:
                where_parts.append(
                    "(u.name LIKE %s OR u.pno LIKE %s OR u.mobile LIKE %s "
                    "OR u.thana LIKE %s OR u.district LIKE %s)"
                )
                like = f"%{search}%"
                params.extend([like, like, like, like, like])

            # 🎖️ RANK FILTER
            if rank_filter:
                where_parts.append("u.user_rank = %s")
                params.append(rank_filter)

            # 🔥 FIXED: INCLUDE DISTRICT DUTY
            OFFICER_EXISTS = """(
                EXISTS (SELECT 1 FROM duty_assignments da WHERE da.staff_id=u.id)
                OR EXISTS (SELECT 1 FROM kshetra_officers ko WHERE ko.user_id=u.id)
                OR EXISTS (SELECT 1 FROM zonal_officers zo WHERE zo.user_id=u.id)
                OR EXISTS (SELECT 1 FROM sector_officers so WHERE so.user_id=u.id)
                OR EXISTS (SELECT 1 FROM district_duty_assignments dda WHERE dda.staff_id=u.id)
            )"""

            # 🎯 ASSIGNED FILTER
            if assigned == "yes":
                where_parts.append(OFFICER_EXISTS)
            elif assigned == "no":
                where_parts.append(f"NOT {OFFICER_EXISTS}")

            # 🔫 ARMED FILTER
            if armed == "yes":
                where_parts.append("u.is_armed = 1")
            elif armed == "no":
                where_parts.append("u.is_armed = 0")

            where_sql = " AND ".join(where_parts)

            # 📊 COUNT
            cur.execute(f"""
                SELECT COUNT(*) AS cnt FROM users u WHERE {where_sql}
            """, params)
            total = cur.fetchone()["cnt"]

            # 📥 FETCH DATA
            cur.execute(f"""
                SELECT
                    u.id, u.name, u.pno, u.mobile, u.thana,
                    u.district, u.user_rank, u.is_armed,

                    -- Booth
                    (SELECT ms.name FROM duty_assignments da
                     JOIN matdan_sthal ms ON ms.id=da.sthal_id
                     WHERE da.staff_id=u.id LIMIT 1) AS center_name,

                    -- Kshetra
                    (SELECT sz.name FROM kshetra_officers ko
                     JOIN super_zones sz ON sz.id=ko.super_zone_id
                     WHERE ko.user_id=u.id LIMIT 1) AS sz_name,

                    -- Zone
                    (SELECT z.name FROM zonal_officers zo
                     JOIN zones z ON z.id=zo.zone_id
                     WHERE zo.user_id=u.id LIMIT 1) AS zone_name,

                    -- Sector
                    (SELECT s.name FROM sector_officers so
                     JOIN sectors s ON s.id=so.sector_id
                     WHERE so.user_id=u.id LIMIT 1) AS sector_name,

                    -- ✅ NEW: District Duty
                    (SELECT dda.duty_type FROM district_duty_assignments dda
                     WHERE dda.staff_id=u.id LIMIT 1) AS district_duty

                FROM users u
                WHERE {where_sql}
                ORDER BY u.name
                LIMIT %s OFFSET %s
            """, params + [limit, offset])

            rows = cur.fetchall()

    finally:
        conn.close()

    # 🎯 FORMAT RESPONSE
    data = []
    for r in rows:

        # 🔥 PRIORITY: District first
        if r["district_duty"]:
            assign_type  = "district"
            assign_label = r["district_duty"]

        elif r["center_name"]:
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
    body = request.get_json() or {}
    print("REQUEST BODY:", body)  # 🔍 debug

    # ✅ Flexible key handling (Flutter safe)
    staff_id = body.get("staffId") or body.get("staff_id")
    sthal_id = body.get("centerId") or body.get("center_id") or body.get("sthal_id")
    mode     = body.get("mode")  # optional

    # ❌ Validation
    if not staff_id or not sthal_id:
        return err(f"Missing data: staffId={staff_id}, centerId={sthal_id}")

    conn = get_db()

    try:
        with conn.cursor() as cur:

            # 🔍 CHECK CENTER EXISTS
            cur.execute("SELECT id FROM matdan_sthal WHERE id=%s", (sthal_id,))
            if not cur.fetchone():
                return err(f"Invalid centerId: {sthal_id}")

            # 🔒 LOCK CHECK (SAFE LEFT JOIN)
            cur.execute("""
                SELECT 
                    c.id AS center,
                    IFNULL(l.is_locked, 0) AS is_locked
                FROM matdan_sthal c
                LEFT JOIN gram_panchayats gp ON c.gram_panchayat_id = gp.id
                LEFT JOIN sectors s ON gp.sector_id = s.id
                LEFT JOIN zones z ON s.zone_id = z.id
                LEFT JOIN sz_duty_locks l ON l.super_zone_id = z.super_zone_id
                WHERE c.id = %s
            """, (sthal_id,))

            row = cur.fetchone()
            print("DEBUG CENTER:", row)

            if row and row["is_locked"] == 1:
                return err("❌ This Super Zone is LOCKED. Cannot assign duty.")

            # 🔍 CHECK STAFF EXISTS
            cur.execute("SELECT id FROM users WHERE id=%s", (staff_id,))
            if not cur.fetchone():
                return err(f"Invalid staffId: {staff_id}")

            # ⚠️ OPTIONAL: prevent duplicate assignment
            cur.execute("""
                SELECT id FROM duty_assignments
                WHERE staff_id=%s AND sthal_id=%s
            """, (staff_id, sthal_id))
            if cur.fetchone():
                return err("⚠️ Staff already assigned to this center")

            # ✅ INSERT DUTY
            cur.execute("""
                INSERT INTO duty_assignments (staff_id, sthal_id, mode, assigned_by)
                VALUES (%s, %s, %s, %s)
            """, (staff_id, sthal_id, mode, request.user["id"]))

        conn.commit()
        return ok({"message": "✅ Duty assigned successfully"})

    except Exception as e:
        conn.rollback()
        print("ERROR:", str(e))
        return err(f"Server error: {str(e)}")

    finally:
        conn.close()

@admin_bp.route("/duties/<int:duty_id>", methods=["DELETE"])
@admin_required
def delete_duty(duty_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # 🔍 FIND CENTER
            cur.execute("""
                SELECT sthal_id FROM duty_assignments
                WHERE id = %s
            """, (duty_id,))
            row = cur.fetchone()

            if not row:
                return err("Duty not found")

            sthal_id = row["sthal_id"]

            # 🔒 CHECK LOCK
            cur.execute("""
                SELECT IFNULL(l.is_locked, 0) AS is_locked
                FROM matdan_sthal c
                JOIN gram_panchayats gp ON c.gram_panchayat_id = gp.id
                JOIN sectors s ON gp.sector_id = s.id
                JOIN zones z ON s.zone_id = z.id
                LEFT JOIN sz_duty_locks l ON l.super_zone_id = z.super_zone_id
                WHERE c.id = %s
            """, (sthal_id,))

            lock = cur.fetchone()

            if lock and lock["is_locked"] == 1:
                return err("Locked — cannot remove")

            # ✅ DELETE
            cur.execute("DELETE FROM duty_assignments WHERE id=%s", (duty_id,))

        conn.commit()
        return ok(None, "Deleted successfully")

    except Exception as e:
        conn.rollback()
        return err(str(e))
    finally:
        conn.close()



@admin_bp.route("/staff/<int:staff_id>/duty", methods=["DELETE"])
@admin_required
def remove_staff_duty(staff_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # 🔹 STEP 1: Get assigned center
            cur.execute("""
                SELECT sthal_id 
                FROM duty_assignments
                WHERE staff_id = %s
                LIMIT 1
            """, (staff_id,))
            duty = cur.fetchone()

            print("DUTY FETCH:", duty)

            if not duty:
                return err("No duty assigned")

            sthal_id = duty["sthal_id"]

            # 🔹 STEP 2: Check lock via super zone
            cur.execute("""
                SELECT 
                    z.super_zone_id,
                    IFNULL(l.is_locked, 0) AS is_locked
                FROM matdan_sthal c
                JOIN gram_panchayats gp ON c.gram_panchayat_id = gp.id
                JOIN sectors s ON gp.sector_id = s.id
                JOIN zones z ON s.zone_id = z.id
                LEFT JOIN sz_duty_locks l ON l.super_zone_id = z.super_zone_id
                WHERE c.id = %s
            """, (sthal_id,))

            lock = cur.fetchone()

            print("LOCK CHECK RESULT:", lock)

            # 🔴 CRITICAL CHECK
            if lock and lock["is_locked"] == 1:
                return err("❌ Locked Super Zone. Cannot remove duty.")

            # 🔹 STEP 3: Delete
            cur.execute("""
                DELETE FROM duty_assignments
                WHERE staff_id = %s
            """, (staff_id,))

        conn.commit()
        return ok({"message": "Duty removed"})

    except Exception as e:
        conn.rollback()
        print("ERROR:", str(e))
        return err(str(e))

    finally:
        conn.close()


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


@admin_bp.route("/config", methods=["GET"])
@admin_required
def get_admin_config():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT `key`, value FROM app_config")
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok({r["key"]: r["value"] for r in rows})

# ══════════════════════════════════════════════════════════════════════════
#  मानक v2 — BOOTH RULES (per sensitivity × booth count)
# ══════════════════════════════════════════════════════════════════════════
 

VALID_SENS = ("A++", "A", "B", "C")
 
 
def _serialize_booth_rule(r):
    return {
        "boothCount":        r["booth_count"],

        "siArmedCount":      r["si_armed_count"],
        "siUnarmedCount":    r["si_unarmed_count"],

        "hcArmedCount":      r["hc_armed_count"],
        "hcUnarmedCount":    r["hc_unarmed_count"],

        "constArmedCount":   r["const_armed_count"],
        "constUnarmedCount": r["const_unarmed_count"],

        # ✅ NEW
        "auxArmedCount":     r["aux_armed_count"],
        "auxUnarmedCount":   r["aux_unarmed_count"],

        "pacCount":          float(r["pac_count"] or 0),
    }
 
@admin_bp.route("/booth-rules", methods=["GET"])
@admin_required
def get_booth_rules():

    sens = (request.args.get("sensitivity") or "").strip()

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            if sens:
                if sens not in VALID_SENS:
                    return err("invalid sensitivity")

                cur.execute(f"""
                    SELECT * FROM booth_rules
                    WHERE admin_id IN ({d_ph}) AND sensitivity = %s
                    ORDER BY booth_count
                """, d_params + [sens])

            else:
                cur.execute(f"""
                    SELECT * FROM booth_rules
                    WHERE admin_id IN ({d_ph})
                    ORDER BY FIELD(sensitivity,'A++','A','B','C'), booth_count
                """, d_params)

            rows = cur.fetchall()

    finally:
        conn.close()

    grouped = {"A++": [], "A": [], "B": [], "C": []}

    for r in rows:
        grouped[r["sensitivity"]].append(_serialize_booth_rule(r))

    return ok(grouped)


 
@admin_bp.route("/booth-rules", methods=["POST"])
@admin_required
def save_booth_rules():

    import math

    body  = request.get_json() or {}
    sens  = (body.get("sensitivity") or "").strip()
    rules = body.get("rules", [])

    if sens not in VALID_SENS:
        return err("sensitivity must be A++, A, B, or C")

    if not isinstance(rules, list):
        return err("rules must be a list")

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # 🔒 LOCK CHECK (IMPORTANT)
            cur.execute("""
                SELECT is_locked FROM sz_duty_locks
                WHERE super_zone_id IN (
                    SELECT id FROM super_zones WHERE admin_id=%s
                )
                LIMIT 1
            """, (_admin_id(),))
            lock = cur.fetchone()

            if lock and lock["is_locked"]:
                return err("Rules locked. Cannot modify.")

            # 🧹 DELETE OLD RULES
            cur.execute(
                f"DELETE FROM booth_rules WHERE admin_id IN ({d_ph}) AND sensitivity=%s",
                d_params + [sens]
            )

            for raw in rules:

                r = normalize_rule(raw)

                bc = int(r.get("booth_count") or 0)

                if bc < 1 or bc > 15:
                    continue

                # ✅ VALIDATION
                total = (
                    r["si_armed_count"] +
                    r["si_unarmed_count"] +
                    r["hc_armed_count"] +
                    r["hc_unarmed_count"] +
                    r["const_armed_count"] +
                    r["const_unarmed_count"] +
                    r["aux_armed_count"] +
                    r["aux_unarmed_count"]
                )

                if total == 0:
                    continue

                if total > 50:
                    return err(f"Too many staff in boothCount {bc}")

                # ✅ INSERT
                cur.execute("""
                    INSERT INTO booth_rules
                    (admin_id, sensitivity, booth_count,

                    si_armed_count, si_unarmed_count,
                    hc_armed_count, hc_unarmed_count,
                    const_armed_count, const_unarmed_count,

                    aux_armed_count, aux_unarmed_count,
                    pac_count)

                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """, (
                    _admin_id(), sens, bc,

                    r["si_armed_count"],
                    r["si_unarmed_count"],
                    r["hc_armed_count"],
                    r["hc_unarmed_count"],
                    r["const_armed_count"],
                    r["const_unarmed_count"],

                    # ✅ NEW
                    r["aux_armed_count"],
                    r["aux_unarmed_count"],

                    math.ceil(float(r["pac_count"] or 0))
                ))

        conn.commit()

    except Exception as e:
        try: conn.rollback()
        except: pass
        write_log("ERROR", f"save_booth_rules: {e}", "Rules")
        return err(f"Save failed: {e}", 500)

    finally:
        conn.close()

    write_log("INFO", f"Booth rules saved: {sens}, {len(rules)} rows by admin {_admin_id()}", "Rules")

    return ok(None, f"{sens} मानक saved")



# ══════════════════════════════════════════════════════════════════════════════
#  DEFAULT DUTY TYPES — 14 fixed entries (always shown)
# ══════════════════════════════════════════════════════════════════════════════
DEFAULT_DISTRICT_DUTIES = [
    ("cluster_mobile",        "क्लस्टर मोबाईल",                   10),
    ("thana_mobile",          "थाना मोबाईल",                      20),
    ("thana_reserve",         "थाना रिजर्व",                      30),
    ("thana_extra_mobile",    "थाना अतिरिक्त मोबाईल",             40),
    ("sector_pol_mag_mobile", "सैक्टर पुलिस / मजिस्ट्रेट मोबाईल", 50),
    ("zonal_pol_mag_mobile",  "जोनल पुलिस / मजिस्ट्रेट मोबाईल",   60),
    ("sdm_co_mobile",         "एसडीएम / सीओ मोबाईल",              70),
    ("chowki_mobile",         "चौकी मोबाईल",                      80),
    ("barrier_picket",        "बैरियर / पिकैट",                   90),
    ("evm_security",          "ईवीएम सुरक्षा",                   100),
    ("adm_sp_mobile",         "एडीएम / एसपी मोबाईल",             110),
    ("dm_sp_mobile",          "डीएम / एसपी मोबाईल",              120),
    ("observer_security",     "पर्यवेक्षक सुरक्षा",              130),
    ("hq_reserve",            "मुख्यालय रिजर्व",                  140),
]

# Set of default duty_type keys (for is_default detection)
_DEFAULT_DUTY_KEYS = {dt for dt, _, _ in DEFAULT_DISTRICT_DUTIES}


def _serialize_district_rule(r):
    return {
        "dutyType":          r["duty_type"],
        "dutyLabelHi":       r["duty_label_hi"] or "",
        "sankhya":           r["sankhya"],
        "siArmedCount":      r["si_armed_count"],
        "siUnarmedCount":    r["si_unarmed_count"],
        "hcArmedCount":      r["hc_armed_count"],
        "hcUnarmedCount":    r["hc_unarmed_count"],
        "constArmedCount":   r["const_armed_count"],
        "constUnarmedCount": r["const_unarmed_count"],
        "auxArmedCount":     r["aux_armed_count"],
        "auxUnarmedCount":   r["aux_unarmed_count"],
        "pacCount":          float(r["pac_count"] or 0),
        "sortOrder":         r["sort_order"],
        "isDefault":         r["duty_type"] in _DEFAULT_DUTY_KEYS,
    }


@admin_bp.route("/district-rules", methods=["GET"])
@admin_required
def get_district_rules():
    """
    Returns ALL duty types merged:
    - 14 hardcoded defaults (with saved values if they exist, else zeros)
    - Any extra custom rows from district_rules that are NOT in the default list
    """
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT * FROM district_rules
                WHERE admin_id IN ({d_ph})
                ORDER BY sort_order, id
            """, d_params)
            rows = cur.fetchall()
    finally:
        conn.close()

    # Map saved rows by duty_type
    saved_map = {r["duty_type"]: r for r in rows}

    result = []

    # 1. Always emit all 14 defaults (with saved data or zeros)
    for dt, label, order in DEFAULT_DISTRICT_DUTIES:
        if dt in saved_map:
            result.append(_serialize_district_rule(saved_map[dt]))
        else:
            result.append({
                "dutyType":          dt,
                "dutyLabelHi":       label,
                "sankhya":           0,
                "siArmedCount":      0, "siUnarmedCount":    0,
                "hcArmedCount":      0, "hcUnarmedCount":    0,
                "constArmedCount":   0, "constUnarmedCount": 0,
                "auxArmedCount":     0, "auxUnarmedCount":   0,
                "pacCount":          0.0,
                "sortOrder":         order,
                "isDefault":         True,
            })

    # 2. Append custom rows (any saved row whose duty_type is NOT a default)
    for r in rows:
        if r["duty_type"] not in _DEFAULT_DUTY_KEYS:
            result.append(_serialize_district_rule(r))

    return ok(result)


@admin_bp.route("/district-rules", methods=["POST"])
@admin_required
def save_district_rules():
    body  = request.get_json() or {}
    rules = body.get("rules", [])

    if not isinstance(rules, list):
        return err("rules must be a list")

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Delete ALL rules for this district (defaults + custom)
            cur.execute(
                f"DELETE FROM district_rules WHERE admin_id IN ({d_ph})",
                d_params
            )

            for r in rules:
                duty_type = (r.get("dutyType") or "").strip()
                if not duty_type:
                    continue

                cur.execute("""
                    INSERT INTO district_rules
                    (admin_id, duty_type, duty_label_hi, sankhya,
                     si_armed_count, si_unarmed_count,
                     hc_armed_count, hc_unarmed_count,
                     const_armed_count, const_unarmed_count,
                     aux_armed_count, aux_unarmed_count,
                     pac_count, sort_order)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """, (
                    _admin_id(),
                    duty_type,
                    (r.get("dutyLabelHi") or "").strip(),
                    int(r.get("sankhya") or 0),
                    int(r.get("siArmedCount")      or 0),
                    int(r.get("siUnarmedCount")    or 0),
                    int(r.get("hcArmedCount")      or 0),
                    int(r.get("hcUnarmedCount")    or 0),
                    int(r.get("constArmedCount")   or 0),
                    int(r.get("constUnarmedCount") or 0),
                    int(r.get("auxArmedCount",     0)),
                    int(r.get("auxUnarmedCount",   0)),
                    float(r.get("pacCount") or 0),
                    int(r.get("sortOrder") or 0),
                ))

        conn.commit()
    except Exception as e:
        try: conn.rollback()
        except: pass
        write_log("ERROR", f"save_district_rules: {e}", "Rules")
        return err(f"Save failed: {e}", 500)
    finally:
        conn.close()

    return ok(None, "जनपदीय मानक saved")

# ── GET: summary of all duty types with assignment counts ────────────────────
@admin_bp.route("/district-duty/summary", methods=["GET"])
@admin_required
def get_district_duty_summary():
    """
    Returns each duty type with:
    - total assigned count
    - number of batches
    - sankhya (required from district_rules)
    """
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
 
            # Get rules for reference (sankhya)
            cur.execute(f"""
                SELECT duty_type, duty_label_hi, sankhya, sort_order
                FROM district_rules
                WHERE admin_id IN ({d_ph})
                ORDER BY sort_order
            """, d_params)
            rules = {r["duty_type"]: r for r in cur.fetchall()}
 
            # Get assignment counts grouped by duty_type
            cur.execute(f"""
                SELECT
                    dda.duty_type,
                    COUNT(DISTINCT dda.staff_id)   AS total_assigned,
                    COUNT(DISTINCT dda.batch_no)   AS batch_count,
                    MAX(dda.batch_no)              AS max_batch
                FROM district_duty_assignments dda
                WHERE dda.admin_id IN ({d_ph})
                GROUP BY dda.duty_type
            """, d_params)
            counts = {r["duty_type"]: r for r in cur.fetchall()}
 
    finally:
        conn.close()
 
    # Merge
    result = {}
    for dt, rule in rules.items():
        cnt = counts.get(dt, {})
        result[dt] = {
            "dutyType":      dt,
            "dutyLabelHi":   rule["duty_label_hi"] or "",
            "sankhya":       rule["sankhya"] or 0,
            "totalAssigned": int(cnt.get("total_assigned") or 0),
            "batchCount":    int(cnt.get("batch_count") or 0),
            "maxBatch":      int(cnt.get("max_batch") or 0),
        }
 
    return ok(result)
 
 
# ── GET: batches for a specific duty type ────────────────────────────────────
@admin_bp.route("/district-duty/<duty_type>/batches", methods=["GET"])
@admin_required
def get_duty_batches(duty_type):
    """
    Returns list of batches for a duty type, each with:
    - batch_no
    - staff count
    - staff list (paginated or full depending on size)
    """
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
 
            # Get batch summary
            cur.execute(f"""
                SELECT
                    dda.batch_no,
                    COUNT(DISTINCT dda.staff_id) AS staff_count
                FROM district_duty_assignments dda
                WHERE dda.admin_id IN ({d_ph}) AND dda.duty_type = %s
                GROUP BY dda.batch_no
                ORDER BY dda.batch_no
            """, d_params + [duty_type])
            batches_raw = cur.fetchall()
 
            if not batches_raw:
                return ok([])
 
            batch_numbers = [b["batch_no"] for b in batches_raw]
 
            # Get all staff for these batches
            b_ph = ",".join(["%s"] * len(batch_numbers))
            cur.execute(f"""
                SELECT
                    dda.id AS assignment_id,
                    dda.batch_no,
                    dda.bus_no,
                    dda.note,
                    dda.created_at,
                    u.id, u.name, u.pno, u.mobile, u.user_rank,
                    u.thana, u.district, u.is_armed
                FROM district_duty_assignments dda
                JOIN users u ON u.id = dda.staff_id
                WHERE dda.admin_id IN ({d_ph})
                  AND dda.duty_type = %s
                  AND dda.batch_no IN ({b_ph})
                ORDER BY dda.batch_no, u.name
            """, d_params + [duty_type] + batch_numbers)
            rows = cur.fetchall()
 
            # Group by batch
            staff_by_batch = {}
            for row in rows:
                bn = row["batch_no"]
                staff_by_batch.setdefault(bn, []).append({
                    "assignmentId": row["assignment_id"],
                    "id":           row["id"],
                    "name":         row["name"]      or "",
                    "pno":          row["pno"]       or "",
                    "mobile":       row["mobile"]    or "",
                    "rank":         row["user_rank"] or "",
                    "thana":        row["thana"]     or "",
                    "district":     row["district"]  or "",
                    "isArmed":      bool(row["is_armed"]),
                    "busNo":        row["bus_no"]    or "",
                    "note":         row["note"]      or "",
                })
 
    finally:
        conn.close()
 
    result = [{
        "batchNo":    b["batch_no"],
        "staffCount": b["staff_count"],
        "staff":      staff_by_batch.get(b["batch_no"], []),
    } for b in batches_raw]
 
    return ok(result)
 
 
# ── GET: single batch detail ─────────────────────────────────────────────────
@admin_bp.route("/district-duty/<duty_type>/batch/<int:batch_no>", methods=["GET"])
@admin_required
def get_duty_batch_detail(duty_type, batch_no):
    """Returns all staff in a specific batch of a duty type."""
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT
                    dda.id AS assignment_id,
                    dda.bus_no, dda.note, dda.created_at,
                    u.id, u.name, u.pno, u.mobile,
                    u.user_rank, u.thana, u.district, u.is_armed
                FROM district_duty_assignments dda
                JOIN users u ON u.id = dda.staff_id
                WHERE dda.admin_id IN ({d_ph})
                  AND dda.duty_type = %s
                  AND dda.batch_no = %s
                ORDER BY u.name
            """, d_params + [duty_type, batch_no])
            rows = cur.fetchall()
    finally:
        conn.close()
 
    return ok([{
        "assignmentId": r["assignment_id"],
        "id":           r["id"],
        "name":         r["name"]      or "",
        "pno":          r["pno"]       or "",
        "mobile":       r["mobile"]    or "",
        "rank":         r["user_rank"] or "",
        "thana":        r["thana"]     or "",
        "district":     r["district"]  or "",
        "isArmed":      bool(r["is_armed"]),
        "busNo":        r["bus_no"]    or "",
        "note":         r["note"]      or "",
    } for r in rows])
 
 
# ── POST: assign staff to a duty type (creates new batch) ───────────────────
@admin_bp.route("/district-duty/<duty_type>/assign", methods=["POST"])
@admin_required
def assign_district_duty_v2(duty_type):
    """
    Assigns staff to a district duty type.
    Creates a new batch automatically (max_batch + 1).
    Body: { staffIds: [int], busNo?: str, note?: str }
    """
    body      = request.get_json() or {}
    staff_ids = body.get("staffIds", [])
    bus_no    = (body.get("busNo") or "").strip()
    note      = (body.get("note") or "").strip()
 
    if not staff_ids:
        return err("staffIds required")
 
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
 
            # Get next batch number
            cur.execute(f"""
                SELECT COALESCE(MAX(batch_no), 0) AS mx
                FROM district_duty_assignments
                WHERE admin_id IN ({d_ph}) AND duty_type = %s
            """, d_params + [duty_type])
            row = cur.fetchone()
            batch_no = (row["mx"] or 0) + 1
 
            assigned = 0
            skipped  = 0
            already  = []
 
            for sid in staff_ids:
                try:
                    cur.execute("""
                        INSERT INTO district_duty_assignments
                            (admin_id, duty_type, batch_no, staff_id,
                             assigned_by, bus_no, note)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                    """, (_admin_id(), duty_type, batch_no, sid,
                          _admin_id(), bus_no, note))
                    assigned += 1
                except Exception:
                    # Likely duplicate (staff already in this duty type)
                    cur.execute("SELECT name FROM users WHERE id=%s", (sid,))
                    u = cur.fetchone()
                    already.append(u["name"] if u else f"id:{sid}")
                    skipped += 1
 
        conn.commit()
 
    except Exception as e:
        try: conn.rollback()
        except: pass
        return err(f"Assign failed: {e}", 500)
    finally:
        conn.close()
 
    write_log("INFO",
              f"District duty '{duty_type}' batch {batch_no}: {assigned} assigned "
              f"by admin {_admin_id()}",
              "DistrictDuty")
 
    return ok({
        "batchNo":  batch_no,
        "assigned": assigned,
        "skipped":  skipped,
        "alreadyAssigned": already,
    }, f"Batch {batch_no} created with {assigned} staff", 201)
 
 
# ── DELETE: remove a single assignment ──────────────────────────────────────
@admin_bp.route("/district-duty/assignment/<int:assignment_id>", methods=["DELETE"])
@admin_required
def delete_district_assignment(assignment_id):
    """Removes a single staff from a district duty assignment."""
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                DELETE FROM district_duty_assignments
                WHERE id = %s AND admin_id IN ({d_ph})
            """, [assignment_id] + d_params)
            if cur.rowcount == 0:
                return err("Assignment not found or access denied", 404)
        conn.commit()
    finally:
        conn.close()
 
    return ok(None, "Removed")
 
 
# ── DELETE: remove entire batch ──────────────────────────────────────────────
@admin_bp.route("/district-duty/<duty_type>/batch/<int:batch_no>", methods=["DELETE"])
@admin_required
def delete_duty_batch(duty_type, batch_no):
    """Removes all staff from a specific batch."""
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                DELETE FROM district_duty_assignments
                WHERE admin_id IN ({d_ph}) AND duty_type = %s AND batch_no = %s
            """, d_params + [duty_type, batch_no])
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()
 
    return ok({"removed": removed}, f"Batch {batch_no} deleted")
 
 
# ── DELETE: remove ALL assignments for a duty type ───────────────────────────
@admin_bp.route("/district-duty/<duty_type>/clear", methods=["DELETE"])
@admin_required
def clear_duty_type(duty_type):
    """Removes ALL assignments for a duty type (all batches)."""
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                DELETE FROM district_duty_assignments
                WHERE admin_id IN ({d_ph}) AND duty_type = %s
            """, d_params + [duty_type])
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()
 
    return ok({"removed": removed}, "All assignments cleared")
 
 
# ── PATCH: update bus_no / note for a batch ──────────────────────────────────
@admin_bp.route("/district-duty/<duty_type>/batch/<int:batch_no>", methods=["PATCH"])
@admin_required
def update_batch_info(duty_type, batch_no):
    """Updates bus_no and/or note for all records in a batch."""
    body   = request.get_json() or {}
    bus_no = (body.get("busNo") or "").strip()
    note   = (body.get("note")  or "").strip()
 
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                UPDATE district_duty_assignments
                SET bus_no = %s, note = %s
                WHERE admin_id IN ({d_ph}) AND duty_type = %s AND batch_no = %s
            """, [bus_no, note] + d_params + [duty_type, batch_no])
        conn.commit()
    finally:
        conn.close()
 
    return ok(None, "Batch updated")
 
 
# ── GET: unassigned staff for a district duty (for picker) ───────────────────
@admin_bp.route("/district-duty/<duty_type>/available-staff", methods=["GET"])
@admin_required
def get_available_for_duty(duty_type):
    """
    Returns staff NOT already assigned to this duty_type.
    Supports pagination + search + rank filter.
    """
    search      = request.args.get("q", "").strip()
    rank_filter = request.args.get("rank", "").strip()
    page, limit, offset = _page_params()
 
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
 
            params = []
            where_parts = [
                "u.role = 'staff'",
                "u.is_active = 1",
                f"""u.id NOT IN (
                    SELECT staff_id FROM district_duty_assignments
                    WHERE admin_id IN ({d_ph}) AND duty_type = %s
                )""",
            ]
            params += d_params + [duty_type]
 
            if search:
                where_parts.append(
                    "(u.name LIKE %s OR u.pno LIKE %s OR u.mobile LIKE %s)"
                )
                like = f"%{search}%"
                params += [like, like, like]
 
            if rank_filter:
                where_parts.append("u.user_rank = %s")
                params.append(rank_filter)
 
            where_sql = " AND ".join(where_parts)
 
            cur.execute(f"SELECT COUNT(*) AS cnt FROM users u WHERE {where_sql}", params)
            total = cur.fetchone()["cnt"]
 
            cur.execute(f"""
                SELECT u.id, u.name, u.pno, u.mobile,
                       u.user_rank, u.thana, u.district, u.is_armed
                FROM users u
                WHERE {where_sql}
                ORDER BY u.name
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            rows = cur.fetchall()
 
    finally:
        conn.close()
 
    return _paginated([{
        "id":       r["id"],
        "name":     r["name"]      or "",
        "pno":      r["pno"]       or "",
        "mobile":   r["mobile"]    or "",
        "rank":     r["user_rank"] or "",
        "thana":    r["thana"]     or "",
        "district": r["district"]  or "",
        "isArmed":  bool(r["is_armed"]),
    } for r in rows], total, page, limit)
 
# ══════════════════════════════════════════════════════════════════════════════
#  CUSTOM DUTY TYPE MANAGEMENT — stored as district_rules rows
#  (no new table — custom types live alongside default ones in district_rules)
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/district-rules/custom", methods=["POST"])
@admin_required
def add_custom_duty_type():
    """
    Creates a placeholder row in district_rules for a new custom duty type.
    All counts are 0 — admin sets them later via the rank editor.
    """
    body     = request.get_json() or {}
    label_hi = (body.get("labelHi") or "").strip()

    if not label_hi:
        return err("labelHi required")

    import re, time
    # Build a safe slug: custom_<sanitised>_<timestamp>
    safe = re.sub(r'[^a-z0-9]', '_', label_hi.lower())[:30]
    duty_type = f"custom_{safe}_{int(time.time()) % 100000}"

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # sort_order = highest existing + 10
            cur.execute(f"""
                SELECT COALESCE(MAX(sort_order), 140) AS mx
                FROM district_rules WHERE admin_id IN ({d_ph})
            """, d_params)
            sort_order = (cur.fetchone()["mx"] or 140) + 10

            cur.execute("""
                INSERT INTO district_rules
                (admin_id, duty_type, duty_label_hi, sankhya,
                 si_armed_count, si_unarmed_count,
                 hc_armed_count, hc_unarmed_count,
                 const_armed_count, const_unarmed_count,
                 aux_armed_count, aux_unarmed_count,
                 pac_count, sort_order)
                VALUES (%s,%s,%s,0,0,0,0,0,0,0,0,0,0,%s)
            """, (_admin_id(), duty_type, label_hi, sort_order))

        conn.commit()
    finally:
        conn.close()

    return ok({
        "dutyType":   duty_type,
        "dutyLabelHi": label_hi,
        "sortOrder":  sort_order,
        "isDefault":  False,
        "sankhya": 0,
        "siArmedCount": 0, "siUnarmedCount": 0,
        "hcArmedCount": 0, "hcUnarmedCount": 0,
        "constArmedCount": 0, "constUnarmedCount": 0,
        "auxArmedCount": 0, "auxUnarmedCount": 0,
        "pacCount": 0.0,
    }, "Custom duty type added", 201)


@admin_bp.route("/district-rules/custom/<duty_type>", methods=["PUT"])
@admin_required
def rename_custom_duty_type(duty_type):
    """Renames the label of a custom duty type."""
    if duty_type in _DEFAULT_DUTY_KEYS:
        return err("Cannot rename a default duty type", 400)

    body     = request.get_json() or {}
    label_hi = (body.get("labelHi") or "").strip()
    if not label_hi:
        return err("labelHi required")

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                UPDATE district_rules
                SET duty_label_hi=%s
                WHERE duty_type=%s AND admin_id IN ({d_ph})
            """, [label_hi, duty_type] + d_params)
            if cur.rowcount == 0:
                return err("Duty type not found", 404)
        conn.commit()
    finally:
        conn.close()

    return ok(None, "Renamed")


@admin_bp.route("/district-rules/custom/<duty_type>", methods=["DELETE"])
@admin_required
def delete_custom_duty_type(duty_type):
    """Deletes a custom duty type row from district_rules."""
    if duty_type in _DEFAULT_DUTY_KEYS:
        return err("Cannot delete a default duty type", 400)

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                DELETE FROM district_rules
                WHERE duty_type=%s AND admin_id IN ({d_ph})
            """, [duty_type] + d_params)
            if cur.rowcount == 0:
                return err("Duty type not found", 404)
        conn.commit()
    finally:
        conn.close()

    return ok(None, "Deleted")


@admin_bp.route("/district-duty/<duty_type>", methods=["GET"])
@admin_required
def get_duty_type_data(duty_type):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT batch_no, COUNT(*) as total
                FROM district_duty_assignments
                WHERE duty_type=%s
                GROUP BY batch_no
            """, (duty_type,))

            batches = cur.fetchall()

    finally:
        conn.close()

    return ok(batches)

@admin_bp.route("/district-duty/<duty_type>/<int:batch>", methods=["GET"])
@admin_required
def get_batch_staff(duty_type, batch):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT u.id, u.name, u.user_rank, u.mobile, u.is_armed
                FROM district_duty_assignments da
                JOIN users u ON u.id = da.staff_id
                WHERE da.duty_type=%s AND da.batch_no=%s
            """, (duty_type, batch))

            rows = cur.fetchall()

    finally:
        conn.close()

    return ok(rows)


@admin_bp.route("/district-duty/refresh/<duty_type>", methods=["POST"])
@admin_required
def refresh_duty_type(duty_type):

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                DELETE FROM district_duty_assignments
                WHERE duty_type=%s
            """, (duty_type,))
        conn.commit()
    finally:
        conn.close()

    return ok(None, "Cleared")



@admin_bp.route("/district-duty/auto-assign/start", methods=["POST"])
@admin_required
def start_district_assign():

    admin_id = request.user["id"]

    result = auto_assign_district(
        admin_id,
        request.user["id"]
    )

    return ok(result, "District auto assign completed")
# ✅ ADD THIS AT TOP (MANDATORY)
FALLBACK = {
    "SI": ["Head Constable", "Constable", "Aux"],
    "Head Constable": ["Constable", "Aux"],
    "Constable": ["Aux"],
    "Aux": []
}


def auto_assign_district(admin_id, created_by):

    conn = get_db()

    try:
        with conn.cursor() as cur:

            # 🟢 GLOBAL TRACKING (VERY IMPORTANT)
            globally_used_ids = set()
            shortages = []

            # 🟢 1. Create job
            cur.execute("""
                INSERT INTO district_duty_jobs (admin_id, status, created_by)
                VALUES (%s, 'running', %s)
            """, (admin_id, created_by))
            job_id = cur.lastrowid

            # 🟢 2. Get rules
            cur.execute("""
                SELECT * FROM district_rules
                WHERE admin_id=%s
                ORDER BY sort_order ASC
            """, (admin_id,))
            rules = cur.fetchall()

            total_types = len(rules)

            cur.execute("""
                UPDATE district_duty_jobs
                SET total_types=%s
                WHERE id=%s
            """, (total_types, job_id))

            assigned_total = 0
            skipped_total = 0
            done_types = 0

            # 🟢 3. LOOP RULES
            for rule in rules:

                duty_type = rule["duty_type"]
                sankhya = rule["sankhya"]

                if sankhya <= 0:
                    continue

                # 🟢 4. Batch number
                cur.execute("""
                    SELECT COALESCE(MAX(batch_no),0)+1 AS b
                    FROM district_duty_assignments
                    WHERE admin_id=%s AND duty_type=%s
                """, (admin_id, duty_type))
                batch_no = cur.fetchone()["b"]

                # 🟢 5. PICK FUNCTION
                def pick(rank, armed, count, exclude_ids):

                    if count <= 0:
                        return []

                    query = """
                        SELECT id FROM users
                        WHERE role='staff'
                        AND user_rank=%s
                        AND is_armed=%s
                        AND is_active=1
                    """

                    params = [rank, armed]

                    # 🔥 exclude local + global
                    all_excludes = set(exclude_ids) | globally_used_ids

                    if all_excludes:
                        placeholders = ",".join(["%s"] * len(all_excludes))
                        query += f" AND id NOT IN ({placeholders})"
                        params.extend(list(all_excludes))

                    query += " ORDER BY RAND() LIMIT %s"
                    params.append(count)

                    cur.execute(query, tuple(params))
                    return cur.fetchall()

                # 🟢 6. LOOP sankhya
                for _ in range(sankhya):

                    used_ids = set()
                    staff_list = []

                    def smart_collect(rank, armed, count, used_ids):

                        selected = []

                        # 1️⃣ Exact rank
                        rows = pick(rank, armed, count, list(used_ids))
                        for r in rows:
                            used_ids.add(r["id"])
                            globally_used_ids.add(r["id"])   # ✅ global lock
                        selected += rows

                        remaining = count - len(rows)

                        # 2️⃣ Fallback
                        if remaining > 0:
                            for fb_rank in FALLBACK.get(rank, []):
                                rows = pick(fb_rank, armed, remaining, list(used_ids))
                                for r in rows:
                                    used_ids.add(r["id"])
                                    globally_used_ids.add(r["id"])
                                selected += rows

                                remaining -= len(rows)

                                if remaining <= 0:
                                    break

                        # 3️⃣ Track shortage
                        if remaining > 0:
                            shortages.append({
                                "duty_type": duty_type,
                                "rank": rank,
                                "armed": armed,
                                "missing": remaining
                            })

                        return selected

                    # 🔹 Collect staff
                    staff_list += smart_collect("SI", 1, rule["si_armed_count"], used_ids)
                    staff_list += smart_collect("SI", 0, rule["si_unarmed_count"], used_ids)

                    staff_list += smart_collect("Head Constable", 1, rule["hc_armed_count"], used_ids)
                    staff_list += smart_collect("Head Constable", 0, rule["hc_unarmed_count"], used_ids)

                    staff_list += smart_collect("Constable", 1, rule["const_armed_count"], used_ids)
                    staff_list += smart_collect("Constable", 0, rule["const_unarmed_count"], used_ids)

                    staff_list += smart_collect("Aux", 1, rule["aux_armed_count"], used_ids)
                    staff_list += smart_collect("Aux", 0, rule["aux_unarmed_count"], used_ids)

                    # ✅ SAFE MODE
                    if not staff_list:
                        skipped_total += 1
                        continue

                    # 🟢 INSERT
                    for s in staff_list:
                        try:
                            cur.execute("""
                                INSERT INTO district_duty_assignments
                                (admin_id, duty_type, batch_no, staff_id, assigned_by)
                                VALUES (%s,%s,%s,%s,%s)
                            """, (admin_id, duty_type, batch_no, s["id"], created_by))

                            assigned_total += 1

                        except Exception:
                            skipped_total += 1

                    batch_no += 1

                done_types += 1

                # 🟢 Update progress
                cur.execute("""
                    UPDATE district_duty_jobs
                    SET done_types=%s,
                        assigned=%s,
                        skipped=%s
                    WHERE id=%s
                """, (done_types, assigned_total, skipped_total, job_id))

            # 🟢 Finish
            cur.execute("""
                UPDATE district_duty_jobs
                SET status='done'
                WHERE id=%s
            """, (job_id,))

        conn.commit()

        return {
            "jobId": job_id,
            "assigned": assigned_total,
            "skipped": skipped_total,
            "shortages": shortages   # ✅ IMPORTANT OUTPUT
        }

    except Exception as e:
        conn.rollback()

        with conn.cursor() as cur:
            cur.execute("""
                UPDATE district_duty_jobs
                SET status='error', error_msg=%s
                WHERE id=%s
            """, (str(e), job_id))

        return {"error": str(e)}

    finally:
        conn.close()


@admin_bp.route("/district-duty/auto-assign/start", methods=["POST"])
@admin_required
def start_district_auto_assign():

    conn = get_db()

    try:
        with conn.cursor() as cur:

            # 1️⃣ create job
            cur.execute("""
                INSERT INTO district_duty_jobs
                (admin_id, status, total_types, done_types, assigned, skipped, created_by)
                VALUES (%s, 'running', 0, 0, 0, 0, %s)
            """, (_admin_id(), _admin_id()))

            job_id = cur.lastrowid

            # 2️⃣ get all duty types
            cur.execute("""
                SELECT duty_type FROM district_rules
                WHERE admin_id=%s
            """, (_admin_id(),))

            duty_types = [r["duty_type"] for r in cur.fetchall()]

            # update total
            cur.execute("""
                UPDATE district_duty_jobs
                SET total_types=%s
                WHERE id=%s
            """, (len(duty_types), job_id))

        conn.commit()

    finally:
        conn.close()

    # 🔥 RUN IN BACKGROUND
    threading.Thread(
        target=_run_district_assign_job,
        args=(job_id, duty_types, _admin_id())
    ).start()

    return ok({"jobId": job_id})

def _run_district_assign_job(job_id, duty_types, admin_id):

    conn = get_db()

    assigned_total = 0
    skipped_total = 0

    try:
        for i, duty_type in enumerate(duty_types):

            try:
                # 👉 CALL YOUR EXISTING FUNCTION
                res = _auto_assign_single_duty(conn, duty_type, admin_id)

                assigned_total += res.get("assigned", 0)
                skipped_total += res.get("skipped", 0)

            except Exception as e:
                print("❌ Error in duty:", duty_type, e)

            # update progress
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE district_duty_jobs
                    SET done_types=%s,
                        assigned=%s,
                        skipped=%s
                    WHERE id=%s
                """, (i+1, assigned_total, skipped_total, job_id))
            conn.commit()

        # ✅ DONE
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE district_duty_jobs
                SET status='done'
                WHERE id=%s
            """, (job_id,))
        conn.commit()

    except Exception as e:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE district_duty_jobs
                SET status='error', error_msg=%s
                WHERE id=%s
            """, (str(e), job_id))
        conn.commit()

    finally:
        conn.close()

@admin_bp.route("/district-duty/auto-assign/status/<int:job_id>", methods=["GET"])
@admin_required
def get_district_job_status(job_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT * FROM district_duty_jobs
                WHERE id=%s
            """, (job_id,))
            job = cur.fetchone()

    finally:
        conn.close()

    if not job:
        return err("Job not found")

    return ok(job)

def _auto_assign_single_duty(conn, duty_type, admin_id):
    assigned = 0
    skipped = 0

    try:
        with conn.cursor() as cur:

            # 1️⃣ Get rule
            cur.execute("""
                SELECT male_count, female_count
                FROM district_rules
                WHERE duty_type=%s AND admin_id=%s
            """, (duty_type, admin_id))
            rule = cur.fetchone()

            if not rule:
                return {"assigned": 0, "skipped": 0}

            male_needed = rule["male_count"]
            female_needed = rule["female_count"]

            # 2️⃣ Get available staff
            cur.execute("""
                SELECT id, gender
                FROM staff
                WHERE admin_id=%s
                AND id NOT IN (
                    SELECT staff_id FROM district_duty_assignments
                )
                ORDER BY RAND()
            """, (admin_id,))
            staff_list = cur.fetchall()

            # 3️⃣ Split by gender
            males = [s for s in staff_list if s["gender"] == "male"]
            females = [s for s in staff_list if s["gender"] == "female"]

            selected = []

            # 4️⃣ Pick males
            if len(males) >= male_needed:
                selected += males[:male_needed]
            else:
                selected += males
                skipped += (male_needed - len(males))

            # 5️⃣ Pick females
            if len(females) >= female_needed:
                selected += females[:female_needed]
            else:
                selected += females
                skipped += (female_needed - len(females))

            # 6️⃣ Insert assignments
            for s in selected:
                cur.execute("""
                    INSERT INTO district_duty_assignments
                    (admin_id, staff_id, duty_type)
                    VALUES (%s, %s, %s)
                """, (admin_id, s["id"], duty_type))

            assigned = len(selected)

        conn.commit()

    except Exception as e:
        print("❌ ERROR:", e)
        conn.rollback()

    return {
        "assigned": assigned,
        "skipped": skipped
    }


def _auto_assign_district_duties_internal(job_id: int, admin_id: int):
    """
    Auto-assigns staff to all district duty types based on district_rules.
    Rank priority: SI Armed → SI Unarmed → HC Armed → HC Unarmed →
                   Const Armed → Const Unarmed → Aux Armed → Aux Unarmed
    Staff already in booth duty_assignments are excluded.
    """
    conn = get_db()
    try:
        # Mark running
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE district_duty_jobs SET status='running', updated_at=NOW() WHERE id=%s",
                (job_id,)
            )
        conn.commit()
 
        # Get district admin IDs
        with conn.cursor() as cur:
            cur.execute("SELECT district FROM users WHERE id=%s", (admin_id,))
            row = cur.fetchone()
            district = (row["district"] or "").strip() if row else ""
 
        if district:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT id FROM users WHERE role IN ('admin','super_admin') AND district=%s",
                    (district,)
                )
                rows = cur.fetchall()
                d_ids = [r["id"] for r in rows]
                if admin_id not in d_ids:
                    d_ids.append(admin_id)
        else:
            d_ids = [admin_id]
 
        d_ph = ",".join(["%s"] * len(d_ids))
 
        # Load ALL district rules for this district
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT * FROM district_rules
                WHERE admin_id IN ({d_ph})
                ORDER BY sort_order, duty_type
            """, d_ids)
            rules = cur.fetchall()
 
        total_assigned = 0
        total_skipped  = 0
        done_types     = 0
 
        # Update total_types
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE district_duty_jobs SET total_types=%s WHERE id=%s",
                (len(rules), job_id)
            )
        conn.commit()
 
        # Rank assignment order: (rank_name, is_armed, rule_column)
        RANK_ASSIGN_ORDER = [
            ("SI",             1, "si_armed_count"),
            ("SI",             0, "si_unarmed_count"),
            ("Head Constable", 1, "hc_armed_count"),
            ("Head Constable", 0, "hc_unarmed_count"),
            ("Constable",      1, "const_armed_count"),
            ("Constable",      0, "const_unarmed_count"),
            ("Constable",      1, "aux_armed_count"),
            ("Constable",      0, "aux_unarmed_count"),
        ]
 
        for rule in rules:
            duty_type = rule["duty_type"]
            sankhya   = int(rule["sankhya"] or 0)
 
            if sankhya <= 0:
                done_types += 1
                _update_job_progress(conn, job_id, done_types, total_assigned, total_skipped)
                continue
 
            # How many already assigned to this duty_type?
            with conn.cursor() as cur:
                cur.execute(f"""
                    SELECT COUNT(DISTINCT staff_id) AS cnt
                    FROM district_duty_assignments
                    WHERE admin_id IN ({d_ph}) AND duty_type=%s
                """, d_ids + [duty_type])
                already_total = cur.fetchone()["cnt"] or 0
 
            shortage = sankhya - already_total
            if shortage <= 0:
                done_types += 1
                _update_job_progress(conn, job_id, done_types, total_assigned, total_skipped)
                continue
 
            # Get next batch number
            with conn.cursor() as cur:
                cur.execute(f"""
                    SELECT COALESCE(MAX(batch_no), 0) AS mx
                    FROM district_duty_assignments
                    WHERE admin_id IN ({d_ph}) AND duty_type=%s
                """, d_ids + [duty_type])
                batch_no = (cur.fetchone()["mx"] or 0) + 1
 
            batch_assigned = 0
 
            for rank, is_armed, count_col in RANK_ASSIGN_ORDER:
                needed = int(rule.get(count_col) or 0)
                if needed <= 0 or batch_assigned >= shortage:
                    continue
 
                # How many of this rank+armed already in this duty?
                with conn.cursor() as cur:
                    cur.execute(f"""
                        SELECT COUNT(*) AS cnt
                        FROM district_duty_assignments dda
                        JOIN users u ON u.id = dda.staff_id
                        WHERE dda.admin_id IN ({d_ph})
                          AND dda.duty_type = %s
                          AND u.user_rank   = %s
                          AND u.is_armed    = %s
                    """, d_ids + [duty_type, rank, is_armed])
                    rank_already = cur.fetchone()["cnt"] or 0
 
                rank_shortage = needed - rank_already
                if rank_shortage <= 0:
                    continue
 
                to_pick = min(rank_shortage, shortage - batch_assigned)
                if to_pick <= 0:
                    continue
 
                # Pick unassigned staff — exclude those in ANY district duty
                # AND those already in booth duty_assignments
                with conn.cursor() as cur:
                    cur.execute(f"""
                        SELECT u.id FROM users u
                        WHERE u.role      = 'staff'
                          AND u.user_rank = %s
                          AND u.is_armed  = %s
                          AND u.is_active = 1
                          AND u.id NOT IN (
                              SELECT staff_id FROM district_duty_assignments
                              WHERE admin_id IN ({d_ph})
                          )
                          AND u.id NOT IN (
                              SELECT staff_id FROM duty_assignments
                          )
                        ORDER BY u.id
                        LIMIT %s
                    """, [rank, is_armed] + d_ids + [to_pick])
                    candidates = cur.fetchall()
 
                for s in candidates:
                    if batch_assigned >= shortage:
                        break
                    try:
                        with conn.cursor() as cur:
                            cur.execute("""
                                INSERT INTO district_duty_assignments
                                    (admin_id, duty_type, batch_no, staff_id, assigned_by)
                                VALUES (%s, %s, %s, %s, %s)
                            """, (admin_id, duty_type, batch_no, s["id"], admin_id))
                        conn.commit()
                        batch_assigned += 1
                        total_assigned += 1
                    except Exception:
                        total_skipped += 1
 
            done_types += 1
            _update_job_progress(conn, job_id, done_types, total_assigned, total_skipped)
 
        # Mark done
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE district_duty_jobs
                SET status='done', done_types=%s, assigned=%s, skipped=%s, updated_at=NOW()
                WHERE id=%s
            """, (done_types, total_assigned, total_skipped, job_id))
        conn.commit()
 
        write_log("INFO",
            f"District auto-assign done: {total_assigned} assigned, "
            f"{total_skipped} skipped (admin {admin_id})",
            "DistrictAutoAssign")
 
    except Exception as e:
        write_log("ERROR", f"District auto-assign error: {e}", "DistrictAutoAssign")
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE district_duty_jobs
                    SET status='error', error_msg=%s, updated_at=NOW()
                    WHERE id=%s
                """, (str(e), job_id))
            conn.commit()
        except Exception:
            pass
    finally:
        try:
            conn.close()
        except Exception:
            pass
 
 
def _update_job_progress(conn, job_id, done_types, assigned, skipped):
    """Helper: update job progress row."""
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE district_duty_jobs
                SET done_types=%s, assigned=%s, skipped=%s, updated_at=NOW()
                WHERE id=%s
            """, (done_types, assigned, skipped, job_id))
        conn.commit()
    except Exception:
        pass
 
 
def run_district_duty_job(job_id: int, admin_id: int):
    """Thread target."""
    print(f"🚀 DISTRICT AUTO ASSIGN START — job={job_id} admin={admin_id}")
    _auto_assign_district_duties_internal(job_id, admin_id)
    print(f"✅ DISTRICT AUTO ASSIGN DONE  — job={job_id}")
 
 
def run_district_duty_job(job_id: int, admin_id: int):
    """Thread target for district duty auto-assign."""
    print(f"🚀 DISTRICT AUTO ASSIGN STARTED — job_id={job_id} admin_id={admin_id}")
    _auto_assign_district_duties_internal(job_id, admin_id)
    print(f"✅ DISTRICT AUTO ASSIGN FINISHED — job_id={job_id}")
 
 
# ══════════════════════════════════════════════════════════════════════════════
#  ROUTES  — paste these into admin_bp  in admin.py
# ══════════════════════════════════════════════════════════════════════════════
 
 
  
 
 

@admin_bp.route("/district-duty/auto-assign/status/<int:job_id>", methods=["GET"])
@admin_required
def district_auto_assign_status(job_id: int):
    """Poll status of a district duty auto-assign job."""
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT id, status, total_types, done_types,
                       assigned, skipped, error_msg, created_at, updated_at
                FROM district_duty_jobs
                WHERE id=%s AND admin_id IN ({d_ph})
            """, [job_id] + d_params)
            job = cur.fetchone()
    finally:
        conn.close()
 
    if not job:
        return err("Job not found", 404)
 
    total = job["total_types"] or 0
    done  = job["done_types"]  or 0
    pct   = int((done / total) * 100) if total > 0 else 0
    if job["status"] == "done":
        pct = 100
 
    return ok({
        "jobId":      job["id"],
        "status":     job["status"],
        "totalTypes": total,
        "doneTypes":  done,
        "assigned":   job["assigned"] or 0,
        "skipped":    job["skipped"]  or 0,
        "pct":        pct,
        "errorMsg":   job["error_msg"] or "",
        "createdAt":  str(job["created_at"]),
        "updatedAt":  str(job["updated_at"]),
    })
 
 
 

@admin_bp.route("/district-duty/auto-assign/latest", methods=["GET"])
@admin_required
def district_auto_assign_latest():
    """Returns the most recent auto-assign job for this admin's district."""
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT id, status, total_types, done_types,
                       assigned, skipped, error_msg, created_at, updated_at
                FROM district_duty_jobs
                WHERE admin_id IN ({d_ph})
                ORDER BY id DESC LIMIT 1
            """, d_params)
            job = cur.fetchone()
    finally:
        conn.close()
 
    if not job:
        return ok(None)
 
    total = job["total_types"] or 0
    done  = job["done_types"]  or 0
    pct   = int((done / total) * 100) if total > 0 else 0
    if job["status"] == "done":
        pct = 100
 
    return ok({
        "jobId":      job["id"],
        "status":     job["status"],
        "totalTypes": total,
        "doneTypes":  done,
        "assigned":   job["assigned"] or 0,
        "skipped":    job["skipped"]  or 0,
        "pct":        pct,
        "errorMsg":   job["error_msg"] or "",
        "createdAt":  str(job["created_at"]),
        "updatedAt":  str(job["updated_at"]),
    })
 
 
@admin_bp.route("/district-duty/auto-assign/clear-all", methods=["DELETE"])
@admin_required
def clear_all_district_assignments():
    """Removes ALL district duty assignments for this district."""
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                DELETE FROM district_duty_assignments
                WHERE admin_id IN ({d_ph})
            """, d_params)
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()
 
    write_log("INFO",
        f"All district duty assignments cleared ({removed} rows) by admin {_admin_id()}",
        "DistrictAutoAssign")
 
    return ok({"removed": removed}, "All district assignments cleared")
 
 

def _assign_one_center(conn, center, admin_id):
    assigned_count = 0

    try:
        with conn.cursor() as cur:

            # 1️⃣ Get rule
            cur.execute("""
                SELECT * FROM booth_rules
                WHERE sensitivity=%s AND booth_count=%s
                LIMIT 1
            """, (center["center_type"], min(center["booth_count"], 15)))

            rule = cur.fetchone()

            if not rule:
                print(f"⚠ No rule for center {center['id']}")
                return 0

            # 2️⃣ STAFF PICK FUNCTION (NO DISTRICT FILTER 🚀)
            def pick_staff(rank, is_armed, count):
                if count <= 0:
                    return []

                # 🔥 MAIN CHANGE → REMOVED district filter
                cur.execute("""
                    SELECT id FROM users
                    WHERE role='staff'
                    AND user_rank=%s
                    AND is_armed=%s
                    AND is_active=1
                    AND id NOT IN (
                        SELECT staff_id FROM duty_assignments
                    )
                    LIMIT %s
                """, (rank, is_armed, count))

                rows = cur.fetchall()

                # 🔁 FALLBACK (lower rank)
                if len(rows) < count:
                    lower = _get_lower_rank(rank)
                    if lower:
                        cur.execute("""
                            SELECT id FROM users
                            WHERE role='staff'
                            AND user_rank=%s
                            AND is_armed=%s
                            AND is_active=1
                            AND id NOT IN (
                                SELECT staff_id FROM duty_assignments
                            )
                            LIMIT %s
                        """, (lower, is_armed, count - len(rows)))

                        rows += cur.fetchall()

                return rows

            assignments = []

            # 3️⃣ APPLY RULES

            # SI
            assignments += pick_staff("SI", 1, rule["si_armed_count"])
            assignments += pick_staff("SI", 0, rule["si_unarmed_count"])

            # HC
            assignments += pick_staff("Head Constable", 1, rule["hc_armed_count"])
            assignments += pick_staff("Head Constable", 0, rule["hc_unarmed_count"])

            # CONST
            assignments += pick_staff("Constable", 1, rule["const_armed_count"])
            assignments += pick_staff("Constable", 0, rule["const_unarmed_count"])

            # AUX FORCE (NEW)
            assignments += pick_staff("Aux", 1, rule.get("aux_armed_count", 0))
            assignments += pick_staff("Aux", 0, rule.get("aux_unarmed_count", 0))

            # 4️⃣ INSERT INTO DB
            for s in assignments:
                cur.execute("""
                    INSERT INTO duty_assignments
                    (staff_id, sthal_id, assigned_by)
                    VALUES (%s, %s, %s)
                """, (s["id"], center["id"], admin_id))

                assigned_count += 1

        conn.commit()

        print(f"✅ Center {center['id']} assigned {assigned_count} staff")

    except Exception as e:
        conn.rollback()
        print("❌ Assign error:", e)

    return assigned_count

@admin_bp.route("/swap", methods=["POST"])
@admin_required
def swap_staff():

    body = request.get_json() or {}
    remove_id = body.get("removeStaffId")
    add_id = body.get("addStaffId")
    sthal_id = body.get("centerId")

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # ✅ CHECK LOCK
            cur.execute("""
                SELECT z.super_zone_id
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s ON s.id = gp.sector_id
                JOIN zones z ON z.id = s.zone_id
                WHERE ms.id=%s
            """, (sthal_id,))
            row = cur.fetchone()

            if row:
                cur.execute("""
                    SELECT is_locked FROM sz_duty_locks
                    WHERE super_zone_id=%s
                """, (row["super_zone_id"],))
                lock = cur.fetchone()

                if lock and lock["is_locked"]:
                    return err("Zone is locked")

            # ❌ remove old
            cur.execute("""
                DELETE FROM duty_assignments
                WHERE staff_id=%s AND sthal_id=%s
            """, (remove_id, sthal_id))

            # ❗ ensure new is reserve
            cur.execute("""
                SELECT id FROM duty_assignments WHERE staff_id=%s
            """, (add_id,))
            if cur.fetchone():
                return err("New staff already assigned")

            # ✅ add new
            cur.execute("""
                INSERT INTO duty_assignments
                (staff_id, sthal_id, assigned_by)
                VALUES (%s,%s,%s)
            """, (add_id, sthal_id, request.user["id"]))

        conn.commit()
    finally:
        conn.close()

    return ok(None, "Swapped successfully")

@admin_bp.route("/unlock/approve/<int:req_id>", methods=["POST"])
@admin_required
def approve_unlock(req_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT super_zone_id FROM sz_unlock_requests
                WHERE id=%s
            """, (req_id,))
            req = cur.fetchone()

            if not req:
                return err("Request not found")

            # ✅ approve request
            cur.execute("""
                UPDATE sz_unlock_requests
                SET status='approved', reviewed_by=%s
                WHERE id=%s
            """, (request.user["id"], req_id))

            # ✅ unlock zone
            cur.execute("""
                UPDATE sz_duty_locks
                SET is_locked=0, status='unlocked'
                WHERE super_zone_id=%s
            """, (req["super_zone_id"],))

        conn.commit()
    finally:
        conn.close()

    return ok(None, "Unlocked successfully")

@admin_bp.route("/unlock/reject/<int:req_id>", methods=["POST"])
@admin_required
def reject_unlock(req_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                UPDATE sz_unlock_requests
                SET status='rejected', reviewed_by=%s
                WHERE id=%s
            """, (request.user["id"], req_id))

        conn.commit()
    finally:
        conn.close()

    return ok(None, "Request rejected")


@admin_bp.route("/super-zones/<int:sz_id>/job-status", methods=["GET"])
@admin_required
def get_job_status(sz_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT * FROM sz_assign_jobs
                WHERE super_zone_id=%s
                ORDER BY id DESC LIMIT 1
            """, (sz_id,))
            job = cur.fetchone()
    finally:
        conn.close()

    return ok(job or {})



@admin_bp.route("/refresh/<int:super_zone_id>", methods=["POST"])
@admin_required
def refresh_super_zone(super_zone_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # 🔒 check lock
            cur.execute("""
                SELECT is_locked FROM sz_duty_locks
                WHERE super_zone_id=%s
            """, (super_zone_id,))
            lock = cur.fetchone()

            if lock and lock["is_locked"]:
                return err("Duties are locked")

            # ❌ DELETE → makes all staff RESERVE
            cur.execute("""
                DELETE da FROM duty_assignments da
                JOIN matdan_sthal ms ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s ON s.id = gp.sector_id
                JOIN zones z ON z.id = s.zone_id
                WHERE z.super_zone_id=%s
            """, (super_zone_id,))

        conn.commit()
    finally:
        conn.close()

    return ok(None, "All staff moved to reserve")


@admin_bp.route("/unlock/request", methods=["POST"])
@admin_required
def request_unlock():

    body = request.get_json() or {}
    sz_id = body.get("superZoneId")
    reason = body.get("reason")

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                INSERT INTO sz_unlock_requests
                (super_zone_id, requested_by, reason)
                VALUES (%s,%s,%s)
            """, (sz_id, request.user["id"], reason))

            cur.execute("""
                UPDATE sz_duty_locks
                SET status='unlock_requested'
                WHERE super_zone_id=%s
            """, (sz_id,))

        conn.commit()
    finally:
        conn.close()

    return ok(None, "Unlock request sent")

@admin_bp.route("/auto-assign/<int:super_zone_id>", methods=["POST"])
@admin_required
def auto_assign(super_zone_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # 🔒 LOCK CHECK
            cur.execute("""
                SELECT is_locked FROM sz_duty_locks
                WHERE super_zone_id=%s
            """, (super_zone_id,))
            lock = cur.fetchone()

            if lock and lock["is_locked"]:
                return err("Duties are locked for this Super Zone")

            # 🧹 CLEAR OLD (→ RESERVE)
            cur.execute("""
                DELETE da FROM duty_assignments da
                JOIN matdan_sthal ms ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s ON s.id = gp.sector_id
                JOIN zones z ON z.id = s.zone_id
                WHERE z.super_zone_id=%s
            """, (super_zone_id,))

            # 📍 GET CENTERS
            cur.execute("""
                SELECT ms.id, ms.center_type, ms.booth_count
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s ON s.id = gp.sector_id
                JOIN zones z ON z.id = s.zone_id
                WHERE z.super_zone_id=%s
            """, (super_zone_id,))
            centers = cur.fetchall()

            # 🎯 LOOP
            for c in centers:

                booth_count = min(c["booth_count"], 15)

                cur.execute("""
                    SELECT * FROM booth_rules
                    WHERE admin_id=%s
                    AND sensitivity=%s
                    AND booth_count=%s
                """, (request.user["id"], c["center_type"], booth_count))

                rule = cur.fetchone()

                # ✅ SAFETY LOG
                if not rule:
                    write_log(
                        "WARNING",
                        f"No rule for {c['center_type']} booth {booth_count}",
                        "AutoAssign"
                    )
                    continue

                # 🧠 ASSIGN FUNCTION
                def assign(rank, armed, count):
                    if count <= 0:
                        return

                    cur.execute("""
                        SELECT id FROM users
                        WHERE role='staff'
                        AND user_rank=%s
                        AND is_armed=%s
                        AND is_active=1
                        AND id NOT IN (
                            SELECT staff_id FROM duty_assignments
                        )
                        LIMIT %s
                    """, (rank, armed, count))

                    staff_list = cur.fetchall()

                    for s in staff_list:
                        cur.execute("""
                            INSERT INTO duty_assignments
                            (staff_id, sthal_id, assigned_by)
                            VALUES (%s,%s,%s)
                        """, (s["id"], c["id"], request.user["id"]))

                # 🚔 APPLY RULE
                assign("SI", 1, rule["si_armed_count"])
                assign("SI", 0, rule["si_unarmed_count"])
                assign("Head Constable", 1, rule["hc_armed_count"])
                assign("Head Constable", 0, rule["hc_unarmed_count"])
                assign("Constable", 1, rule["const_armed_count"])
                assign("Constable", 0, rule["const_unarmed_count"])
                # ✅ ADD THIS
                assign("Constable", 1, rule["aux_armed_count"])
                assign("Constable", 0, rule["aux_unarmed_count"])

        conn.commit()

    finally:
        conn.close()

    return ok(None, "Auto assignment completed")



@admin_bp.route("/reserve-staff", methods=["GET"])
@admin_required
def get_reserve_staff():

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT id, name, user_rank, mobile
                FROM users
                WHERE role='staff'
                AND is_active=1
                AND id NOT IN (
                    SELECT staff_id FROM duty_assignments
                )
                ORDER BY name ASC
            """)

            rows = cur.fetchall()

    finally:
        conn.close()

    return ok(rows)



@admin_bp.route("/center/<int:sthal_id>/staff", methods=["GET"])
@admin_required
def get_center_staff(sthal_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT u.id, u.name, u.user_rank, u.mobile
                FROM duty_assignments da
                JOIN users u ON u.id = da.staff_id
                WHERE da.sthal_id=%s
            """, (sthal_id,))

            rows = cur.fetchall()

    finally:
        conn.close()

    return ok(rows)

@admin_bp.route("/assign", methods=["POST"])
@admin_required
def manual_assign():

    body = request.get_json() or {}
    staff_id = body.get("staffId")
    sthal_id = body.get("centerId")

    if not staff_id or not sthal_id:
        return err("staffId and centerId required")

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # ❗ ensure staff is RESERVE
            cur.execute("""
                SELECT id FROM duty_assignments
                WHERE staff_id=%s
            """, (staff_id,))
            if cur.fetchone():
                return err("Staff already assigned")

            cur.execute("""
                INSERT INTO duty_assignments
                (staff_id, sthal_id, assigned_by)
                VALUES (%s,%s,%s)
            """, (staff_id, sthal_id, request.user["id"]))

        conn.commit()
    finally:
        conn.close()

    return ok(None, "Staff assigned")


def auto_assign_internal(super_zone_id, admin_id):

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # CLEAR OLD
            cur.execute("""
                DELETE da FROM duty_assignments da
                JOIN matdan_sthal ms ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s ON s.id = gp.sector_id
                JOIN zones z ON z.id = s.zone_id
                WHERE z.super_zone_id=%s
            """, (super_zone_id,))

            # GET CENTERS
            cur.execute("""
                SELECT ms.id, ms.center_type, ms.booth_count
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s ON s.id = gp.sector_id
                JOIN zones z ON z.id = s.zone_id
                WHERE z.super_zone_id=%s
            """, (super_zone_id,))
            centers = cur.fetchall()

            for c in centers:

                booth_count = min(c["booth_count"], 15)

                cur.execute("""
                    SELECT * FROM booth_rules
                    WHERE admin_id=%s
                    AND sensitivity=%s
                    AND booth_count=%s
                """, (admin_id, c["center_type"], booth_count))

                rule = cur.fetchone()
                if not rule:
                    continue

                def assign(rank, armed, count):
                    if count <= 0:
                        return

                    cur.execute("""
                        SELECT id FROM users
                        WHERE role='staff'
                        AND user_rank=%s
                        AND is_armed=%s
                        AND is_active=1
                        AND id NOT IN (SELECT staff_id FROM duty_assignments)
                        LIMIT %s
                    """, (rank, armed, count))

                    for s in cur.fetchall():
                        cur.execute("""
                            INSERT INTO duty_assignments (staff_id, sthal_id, assigned_by)
                            VALUES (%s,%s,%s)
                        """, (s["id"], c["id"], admin_id))

                assign("SI", 1, rule["si_armed_count"])
                assign("SI", 0, rule["si_unarmed_count"])
                assign("Head Constable", 1, rule["hc_armed_count"])
                assign("Head Constable", 0, rule["hc_unarmed_count"])
                assign("Constable", 1, rule["const_armed_count"])
                assign("Constable", 0, rule["const_unarmed_count"])
                assign("Constable", 1, rule["aux_armed_count"])
                assign("Constable", 0, rule["aux_unarmed_count"])

        conn.commit()

    finally:
        conn.close()


        