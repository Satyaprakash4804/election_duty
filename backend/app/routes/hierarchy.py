"""
hierarchy.py  –  /api/admin/hierarchy/*
Full CRUD for the election admin hierarchy tree:
  super_zone → zone → sector → gram_panchayat → matdan_sthal → matdan_kendra
  officers: kshetra_officers / zonal_officers / sector_officers
  duty:     duty_assignments

Designed to match HierarchyReportPage (Flutter) exactly.
"""

from flask import Blueprint, request, jsonify
from db import get_db
from app.routes import admin_required, ok, err
import hashlib

hierarchy = Blueprint("hierarchy", __name__, url_prefix="/api/admin/hierarchy")

SALT = "election_2026_secure_key"

# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def _hash(pno: str) -> str:
    return hashlib.sha256((pno + SALT).encode()).hexdigest()


def _admin_id():
    return request.user["id"]


def _officer_row(r: dict) -> dict:
    """Serialise any *_officers row into the shape Flutter expects."""
    return {
        "id":        r["id"],
        "user_id":   r.get("user_id"),
        "name":      r.get("name")      or "",
        "pno":       r.get("pno")       or "",
        "mobile":    r.get("mobile")    or "",
        "user_rank": r.get("user_rank") or "",
    }


def _fetch_officers(cur, table: str, fk_col: str, fk_val: int) -> list:
    cur.execute(
        f"SELECT * FROM {table} WHERE {fk_col} = %s ORDER BY id",
        (fk_val,)
    )
    return [_officer_row(r) for r in cur.fetchall()]


def _fetch_kendras(cur, sthal_id: int) -> list:
    cur.execute(
        "SELECT id, room_number FROM matdan_kendra WHERE matdan_sthal_id = %s ORDER BY id",
        (sthal_id,)
    )
    return [{"id": r["id"], "room_number": r["room_number"] or ""} for r in cur.fetchall()]


def _fetch_duty_officers(cur, sthal_id: int) -> list:
    """Staff assigned to a matdan_sthal (duty_assignments → users)."""
    cur.execute("""
        SELECT u.id, u.name, u.pno, u.mobile, u.user_rank, u.thana,
               da.id AS duty_id, da.bus_no
        FROM duty_assignments da
        JOIN users u ON u.id = da.staff_id
        WHERE da.sthal_id = %s
        ORDER BY u.name
    """, (sthal_id,))
    return [
        {
            "id":        r["duty_id"],
            "user_id":   r["id"],
            "name":      r["name"]      or "",
            "pno":       r["pno"]       or "",
            "mobile":    r["mobile"]    or "",
            "user_rank": r["user_rank"] or "",
            "thana":     r["thana"]     or "",
            "bus_no":    r["bus_no"]    or "",
        }
        for r in cur.fetchall()
    ]


def _ensure_user(cur, name: str, pno: str, mobile: str, rank: str,
                 created_by: int) -> int | None:
    """Return existing user id, or create a new staff user. Returns None if no pno."""
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


def _insert_officer(cur, table: str, fk_col: str, fk_val: int, o: dict):
    name   = (o.get("name")      or "").strip()
    pno    = (o.get("pno")       or "").strip()
    mobile = (o.get("mobile")    or "").strip()
    rank   = (o.get("user_rank") or o.get("rank") or "").strip()
    uid    = o.get("user_id") or o.get("userId") or None

    if not uid:
        uid = _ensure_user(cur, name, pno, mobile, rank, _admin_id())

    cur.execute(
        f"INSERT INTO {table} ({fk_col}, user_id, name, pno, mobile, user_rank) "
        f"VALUES (%s,%s,%s,%s,%s,%s)",
        (fk_val, uid, name, pno, mobile, rank)
    )
    return cur.lastrowid


# ══════════════════════════════════════════════════════════════════════════════
#  FULL HIERARCHY TREE  (Tab 1 / 2 / 3 data source)
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/full", methods=["GET", "OPTIONS"])
@admin_required
def get_full_hierarchy():
    """
    Role-based full hierarchy:
    admin        → district-based data
    super_admin  → ALL data
    master       → ALL data
    """

    conn = get_db()
    try:
        with conn.cursor() as cur:

            user = request.user
            role = user.get("role")

            print("USER 👉", user)
            print("ROLE 👉", role)

            # 🔥 ROLE-BASED FILTER
            if role == "admin":
                district = user.get("district")

                print("Admin district 👉", district)

                cur.execute("""
                    SELECT * FROM super_zones
                    WHERE district = %s
                    ORDER BY id
                """, (district,))

            else:
                # ✅ super_admin + master → ALL DATA
                print("Loading ALL data (no filter)")
                cur.execute("""
                    SELECT * FROM super_zones
                    ORDER BY id
                """)

            super_zones = cur.fetchall()
            result = []

            for sz in super_zones:
                sz_id = sz["id"]

                # 🔹 ZONES
                cur.execute("""
                    SELECT * FROM zones
                    WHERE super_zone_id = %s
                    ORDER BY id
                """, (sz_id,))
                zone_list = []

                for z in cur.fetchall():
                    z_id = z["id"]

                    # 🔹 SECTORS
                    cur.execute("""
                        SELECT * FROM sectors
                        WHERE zone_id = %s
                        ORDER BY id
                    """, (z_id,))
                    sector_list = []

                    for s in cur.fetchall():
                        s_id = s["id"]

                        # 🔹 PANCHAYATS
                        cur.execute("""
                            SELECT * FROM gram_panchayats
                            WHERE sector_id = %s
                            ORDER BY id
                        """, (s_id,))
                        gp_list = []

                        for gp in cur.fetchall():
                            gp_id = gp["id"]

                            # 🔹 CENTERS (NO updated_at ❌)
                            cur.execute("""
                                SELECT id, name, address, thana,
                                       center_type, bus_no,
                                       latitude, longitude
                                FROM matdan_sthal
                                WHERE gram_panchayat_id = %s
                                ORDER BY id
                            """, (gp_id,))

                            center_list = []

                            for ms in cur.fetchall():
                                ms_id = ms["id"]

                                center_list.append({
                                    "id":           ms["id"],
                                    "name":         ms["name"] or "",
                                    "address":      ms["address"] or "",
                                    "thana":        ms["thana"] or "",
                                    "center_type":  ms["center_type"] or "C",
                                    "bus_no":       ms["bus_no"] or "",
                                    "latitude":     float(ms["latitude"]) if ms["latitude"] else None,
                                    "longitude":    float(ms["longitude"]) if ms["longitude"] else None,
                                    "kendras":       _fetch_kendras(cur, ms_id),
                                    "duty_officers": _fetch_duty_officers(cur, ms_id),
                                })

                            gp_list.append({
                                "id":      gp["id"],
                                "name":    gp["name"] or "",
                                "address": gp["address"] or "",
                                "thana":   gp.get("thana", ""),
                                "centers": center_list,
                            })

                        sector_list.append({
                            "id":         s["id"],
                            "name":       s["name"] or "",
                            "hq":         s.get("hq_address") or "",
                            "officers":   _fetch_officers(cur, "sector_officers", "sector_id", s_id),
                            "panchayats": gp_list,
                        })

                    zone_list.append({
                        "id":         z["id"],
                        "name":       z["name"] or "",
                        "hq_address": z["hq_address"] or "",
                        "officers":   _fetch_officers(cur, "zonal_officers", "zone_id", z_id),
                        "sectors":    sector_list,
                    })

                result.append({
                    "id":       sz["id"],
                    "name":     sz["name"] or "",
                    "district": sz["district"] or "",
                    "block":    sz["block"] or "",
                    "officers": _fetch_officers(cur, "kshetra_officers", "super_zone_id", sz_id),
                    "zones":    zone_list,
                })

        return jsonify(result)

    except Exception as e:
        print("❌ ERROR:", str(e))
        return jsonify({"error": str(e)}), 500

    finally:
        conn.close()
        
# ══════════════════════════════════════════════════════════════════════════════
#  SUPER ZONES   PUT /hierarchy/super-zone/<id>   DELETE /hierarchy/super-zone/<id>
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/super-zone/<int:sz_id>", methods=["PUT"])
@admin_required
def update_super_zone(sz_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE super_zones SET name=%s, district=%s, block=%s "
                "WHERE id=%s AND admin_id=%s",
                (body.get("name", ""), body.get("district", ""),
                 body.get("block", ""), sz_id, _admin_id())
            )
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Super Zone updated")


@hierarchy.route("/super-zone/<int:sz_id>", methods=["DELETE"])
@admin_required
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
#  SECTOR   PUT /hierarchy/sector/<id>   DELETE /hierarchy/sector/<id>
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/sector/<int:s_id>", methods=["PUT"])
@admin_required
def update_sector(s_id):
    body = request.get_json() or {}
    name = (body.get("name") or "").strip()
    if not name:
        return err("name required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE sectors SET name=%s WHERE id=%s",
                (name, s_id)
            )
        conn.commit()
    finally:
        conn.close()
    return ok({"id": s_id, "name": name}, "Sector updated")


@hierarchy.route("/sector/<int:s_id>", methods=["DELETE"])
@admin_required
def delete_sector(s_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM sectors WHERE id=%s", (s_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Sector deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  MATDAN STHAL   PUT /hierarchy/sthal/<id>   DELETE /hierarchy/sthal/<id>
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/sthal/<int:ms_id>", methods=["PUT"])
@admin_required
def update_sthal(ms_id):
    body = request.get_json() or {}
    center_type = (body.get("centerType") or body.get("center_type") or "C").strip().upper()
    if center_type not in ("A++", "A", "B", "C"):
        center_type = "C"
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE matdan_sthal
                SET name        = %s,
                    address     = %s,
                    thana       = %s,
                    center_type = %s,
                    bus_no      = %s
                WHERE id = %s
            """, (
                (body.get("name")    or "").strip(),
                (body.get("address") or "").strip(),
                (body.get("thana")   or "").strip(),
                center_type,
                (body.get("busNo")   or body.get("bus_no") or "").strip(),
                ms_id,
            ))
        conn.commit()
    finally:
        conn.close()
    return ok({"center_type": center_type}, "Sthal updated")


@hierarchy.route("/sthal/<int:ms_id>", methods=["DELETE"])
@admin_required
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
#  KSHETRA OFFICERS  (super zone level)
#  GET  /hierarchy/super-zones/<sz_id>/officers
#  POST /hierarchy/super-zones/<sz_id>/officers
#  PUT  /hierarchy/kshetra-officers/<o_id>
#  DEL  /hierarchy/kshetra-officers/<o_id>
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/super-zones/<int:sz_id>/officers", methods=["GET"])
@admin_required
def get_kshetra_officers(sz_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            officers = _fetch_officers(cur, "kshetra_officers", "super_zone_id", sz_id)
    finally:
        conn.close()
    return ok({"officers": officers})


@hierarchy.route("/super-zones/<int:sz_id>/officers", methods=["POST"])
@admin_required
def add_kshetra_officer(sz_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(cur, "kshetra_officers", "super_zone_id", sz_id, body)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id}, "Officer added", 201)


@hierarchy.route("/kshetra-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_kshetra_officer(o_id):
    body = request.get_json() or {}
    _update_officer(o_id, "kshetra_officers", body)
    return ok(None, "Updated")


@hierarchy.route("/kshetra-officers/<int:o_id>", methods=["DELETE"])
@admin_required
def delete_kshetra_officer(o_id):
    _delete_officer(o_id, "kshetra_officers")
    return ok(None, "Deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  ZONAL OFFICERS  (zone level)
#  GET  /hierarchy/zones/<z_id>/officers
#  POST /hierarchy/zones/<z_id>/officers
#  PUT  /hierarchy/zonal-officers/<o_id>
#  DEL  /hierarchy/zonal-officers/<o_id>
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/zones/<int:z_id>/officers", methods=["GET"])
@admin_required
def get_zonal_officers(z_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            officers = _fetch_officers(cur, "zonal_officers", "zone_id", z_id)
    finally:
        conn.close()
    return ok({"officers": officers})


@hierarchy.route("/zones/<int:z_id>/officers", methods=["POST"])
@admin_required
def add_zonal_officer(z_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(cur, "zonal_officers", "zone_id", z_id, body)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id}, "Officer added", 201)


@hierarchy.route("/zonal-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_zonal_officer(o_id):
    body = request.get_json() or {}
    _update_officer(o_id, "zonal_officers", body)
    return ok(None, "Updated")


@hierarchy.route("/zonal-officers/<int:o_id>", methods=["DELETE"])
@admin_required
def delete_zonal_officer(o_id):
    _delete_officer(o_id, "zonal_officers")
    return ok(None, "Deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  SECTOR OFFICERS  (sector level)
#  GET  /hierarchy/sectors/<s_id>/officers
#  POST /hierarchy/sectors/<s_id>/officers
#  PUT  /hierarchy/sector-officers/<o_id>
#  DEL  /hierarchy/sector-officers/<o_id>
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/sectors/<int:s_id>/officers", methods=["GET"])
@admin_required
def get_sector_officers(s_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            officers = _fetch_officers(cur, "sector_officers", "sector_id", s_id)
    finally:
        conn.close()
    return ok({"officers": officers})


@hierarchy.route("/sectors/<int:s_id>/officers", methods=["POST"])
@admin_required
def add_sector_officer(s_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(cur, "sector_officers", "sector_id", s_id, body)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id}, "Officer added", 201)


@hierarchy.route("/sector-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_sector_officer(o_id):
    body = request.get_json() or {}
    _update_officer(o_id, "sector_officers", body)
    return ok(None, "Updated")


@hierarchy.route("/sector-officers/<int:o_id>", methods=["DELETE"])
@admin_required
def delete_sector_officer(o_id):
    _delete_officer(o_id, "sector_officers")
    return ok(None, "Deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  REPLACE ALL OFFICERS for a node  (Flutter _OfficersDialog calls this)
#
#  POST /hierarchy/super-zones/<sz_id>/officers/replace
#  POST /hierarchy/zones/<z_id>/officers/replace
#  POST /hierarchy/sectors/<s_id>/officers/replace
#
#  Body: { "officers": [ {name, pno, mobile, user_rank}, ... ] }
#
#  Deletes existing officers then inserts the new list in one transaction.
# ══════════════════════════════════════════════════════════════════════════════

def _replace_officers(table: str, fk_col: str, fk_val: int, officers: list):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM {table} WHERE {fk_col} = %s", (fk_val,))
            for o in officers:
                if (o.get("name") or "").strip():
                    _insert_officer(cur, table, fk_col, fk_val, o)
        conn.commit()
    finally:
        conn.close()


@hierarchy.route("/super-zones/<int:sz_id>/officers/replace", methods=["POST"])
@admin_required
def replace_kshetra_officers(sz_id):
    body = request.get_json() or {}
    _replace_officers("kshetra_officers", "super_zone_id", sz_id, body.get("officers", []))
    return ok(None, "Officers replaced")


@hierarchy.route("/zones/<int:z_id>/officers/replace", methods=["POST"])
@admin_required
def replace_zonal_officers(z_id):
    body = request.get_json() or {}
    _replace_officers("zonal_officers", "zone_id", z_id, body.get("officers", []))
    return ok(None, "Officers replaced")


@hierarchy.route("/sectors/<int:s_id>/officers/replace", methods=["POST"])
@admin_required
def replace_sector_officers(s_id):
    body = request.get_json() or {}
    _replace_officers("sector_officers", "sector_id", s_id, body.get("officers", []))
    return ok(None, "Officers replaced")


# ══════════════════════════════════════════════════════════════════════════════
#  DUTY ASSIGNMENTS   (Tab 3 / _PaginatedStaffDialog)
#  POST /hierarchy/duties          assign staff to sthal
#  DELETE /hierarchy/duties/<id>   remove a duty assignment
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/duties", methods=["POST"])
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
            cur.execute("""
                INSERT INTO duty_assignments (staff_id, sthal_id, bus_no, assigned_by)
                VALUES (%s,%s,%s,%s)
                ON DUPLICATE KEY UPDATE
                    sthal_id    = VALUES(sthal_id),
                    bus_no      = VALUES(bus_no),
                    assigned_by = VALUES(assigned_by)
            """, (staff_id, sthal_id, body.get("busNo", ""), _admin_id()))
            duty_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": duty_id}, "Duty assigned", 201)


@hierarchy.route("/duties/<int:duty_id>", methods=["DELETE"])
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
#  AVAILABLE STAFF  (unassigned)  — _PaginatedStaffDialog paginated search
#  GET /hierarchy/staff/available?page=1&limit=30&q=search_term&assigned=no
# ══════════════════════════════════════════════════════════════════════════════

@hierarchy.route("/staff/available", methods=["GET"])
@admin_required
def get_available_staff():
    """
    Paginated, searchable list of staff NOT yet assigned to any booth or officer role.
    Mirrors /admin/staff?assigned=no but lives here for clean separation.
    """
    q     = (request.args.get("q", "") or "").strip()
    page  = max(1, request.args.get("page",  1,  type=int))
    limit = min(200, max(1, request.args.get("limit", 30, type=int)))
    offset = (page - 1) * limit

    NOT_ASSIGNED = """
        NOT (
            EXISTS (SELECT 1 FROM duty_assignments     da WHERE da.staff_id   = u.id)
         OR EXISTS (SELECT 1 FROM kshetra_officers     ko WHERE ko.user_id    = u.id)
         OR EXISTS (SELECT 1 FROM zonal_officers       zo WHERE zo.user_id    = u.id)
         OR EXISTS (SELECT 1 FROM sector_officers      so WHERE so.user_id    = u.id)
        )
    """

    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = []
            search_clause = ""
            if q:
                search_clause = "AND (u.name LIKE %s OR u.pno LIKE %s OR u.thana LIKE %s)"
                like = f"%{q}%"
                params.extend([like, like, like])

            cur.execute(
                f"SELECT COUNT(*) AS cnt FROM users u "
                f"WHERE u.role='staff' AND u.is_active=1 AND {NOT_ASSIGNED} {search_clause}",
                params
            )
            total = cur.fetchone()["cnt"]

            cur.execute(
                f"""SELECT u.id, u.name, u.pno, u.mobile, u.thana, u.user_rank
                    FROM users u
                    WHERE u.role='staff' AND u.is_active=1 AND {NOT_ASSIGNED} {search_clause}
                    ORDER BY u.name
                    LIMIT %s OFFSET %s""",
                params + [limit, offset]
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    data = [
        {
            "id":        r["id"],
            "name":      r["name"]      or "",
            "pno":       r["pno"]       or "",
            "mobile":    r["mobile"]    or "",
            "thana":     r["thana"]     or "",
            "user_rank": r["user_rank"] or "",
        }
        for r in rows
    ]

    return ok({
        "data":       data,
        "total":      total,
        "page":       page,
        "limit":      limit,
        "totalPages": -(-total // limit),
    })


# ══════════════════════════════════════════════════════════════════════════════
#  PRIVATE HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def _update_officer(o_id: int, table: str, body: dict):
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
                    "UPDATE users SET name=%s, mobile=%s, user_rank=%s WHERE id=%s AND role='staff'",
                    (name, mobile, rank, uid)
                )
            cur.execute(
                f"UPDATE {table} SET name=%s, pno=%s, mobile=%s, user_rank=%s, user_id=%s WHERE id=%s",
                (name, pno, mobile, rank, uid, o_id)
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