import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from flask import Blueprint, request, Response, stream_with_context
from werkzeug.security import generate_password_hash
from db import get_db
from app.routes import ok, err, write_log, admin_required
 
admin_bp = Blueprint("admin", __name__, url_prefix="/api/admin")

# ── Constants ─────────────────────────────────────────────────────────────────
DEFAULT_PAGE_SIZE = 50
MAX_PAGE_SIZE     = 200
BULK_CHUNK_SIZE   = 1000   # rows per INSERT chunk
HASH_WORKERS     = 10  
BULK_HASH_METHOD = 'pbkdf2:sha256:260000'
 
 
def _fast_hash(pno: str) -> str:
    """Lower iteration count for bulk ops — still 260k rounds of PBKDF2."""
    return generate_password_hash(pno, method=BULK_HASH_METHOD)
 
 
def _sse(data: dict) -> bytes:
    return f"data: {json.dumps(data, ensure_ascii=False)}\n\n".encode("utf-8")

def _admin_id():
    return request.user["id"]


# ── shared officer row serialiser ─────────────────────────────────────────────
def _o(r):
    return {
        "id":     r["id"],
        "userId": r["user_id"],
        "name":   r["name"]      or "",
        "pno":    r["pno"]       or "",
        "mobile": r["mobile"]    or "",
        "rank":   r["user_rank"] or "",
    }


# ── pagination helper ─────────────────────────────────────────────────────────
def _page_params():
    """Return (page, limit, offset). page is 1-based."""
    page  = max(1, request.args.get("page", 1, type=int))
    limit = min(MAX_PAGE_SIZE, max(1, request.args.get("limit", DEFAULT_PAGE_SIZE, type=int)))
    return page, limit, (page - 1) * limit


def _paginated(data, total, page, limit):
    return ok({
        "data":       data,
        "total":      total,
        "page":       page,
        "limit":      limit,
        "totalPages": -(-total // limit),   # ceiling division
    })


# ── fetch staff list for picker (kept lean – only id/name/pno/rank) ───────────
def _staff_list(cur, district=None):
    if district:
        cur.execute(
            """SELECT id, name, pno, mobile, thana, user_rank
               FROM users
               WHERE role='staff' AND district=%s AND is_active=1
               ORDER BY name""",
            (district,)
        )
    else:
        cur.execute(
            """SELECT id, name, pno, mobile, thana, user_rank
               FROM users
               WHERE role='staff' AND is_active=1
               ORDER BY name"""
        )
    return [
        {
            "id":     r["id"],
            "name":   r["name"]      or "",
            "pno":    r["pno"]       or "",
            "mobile": r["mobile"]    or "",
            "rank":   r["user_rank"] or "",
        }
        for r in cur.fetchall()
    ]


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
                SELECT sz.id, sz.name, sz.district, sz.block,
                       COUNT(DISTINCT z.id) AS zone_count
                FROM super_zones sz
                LEFT JOIN zones z ON z.super_zone_id = sz.id
                WHERE sz.admin_id = %s
                GROUP BY sz.id ORDER BY sz.id
            """, (_admin_id(),))
            zones = cur.fetchall()
            if not zones:
                return ok([])

            sz_ids = [sz["id"] for sz in zones]
            placeholders = ",".join(["%s"] * len(sz_ids))

            cur.execute(
                f"SELECT * FROM kshetra_officers WHERE super_zone_id IN ({placeholders}) ORDER BY super_zone_id, id",
                sz_ids
            )
            officers_by_sz = {}
            for row in cur.fetchall():
                officers_by_sz.setdefault(row["super_zone_id"], []).append(_o(row))

            result = [{
                "id":        sz["id"],
                "name":      sz["name"]     or "",
                "district":  sz["district"] or "",
                "block":     sz["block"]    or "",
                "zoneCount": sz["zone_count"],
                "officers":  officers_by_sz.get(sz["id"], []),
            } for sz in zones]
    finally:
        conn.close()
    return ok(result)


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
            cur.execute(
                "INSERT INTO super_zones (name,district,block,admin_id) VALUES (%s,%s,%s,%s)",
                (
                    name,
                    body.get("district", request.user.get("district") or ""),
                    body.get("block", ""),
                    _admin_id(),
                )
            )
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
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE super_zones SET name=%s,district=%s,block=%s WHERE id=%s AND admin_id=%s",
                (body.get("name", ""), body.get("district", ""), body.get("block", ""),
                 sz_id, _admin_id())
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
    return ok(None, "Deleted")


# ── Kshetra officers sub-resource ─────────────────────────────────────────────

@admin_bp.route("/super-zones/<int:sz_id>/officers", methods=["GET"])
@admin_required
def get_kshetra_officers(sz_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM kshetra_officers WHERE super_zone_id=%s ORDER BY id",
                (sz_id,)
            )
            rows  = cur.fetchall()
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
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id}, "Officer added", 201)


@admin_bp.route("/kshetra-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_kshetra_officer(o_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE kshetra_officers SET name=%s,pno=%s,mobile=%s,user_rank=%s,user_id=%s WHERE id=%s",
                (body.get("name", ""), body.get("pno", ""), body.get("mobile", ""),
                 body.get("rank", ""), body.get("userId") or None, o_id)
            )
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
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT z.id, z.name, z.hq_address,
                       COUNT(DISTINCT s.id) AS sector_count
                FROM zones z LEFT JOIN sectors s ON s.zone_id=z.id
                WHERE z.super_zone_id=%s GROUP BY z.id ORDER BY z.id
            """, (sz_id,))
            zones = cur.fetchall()
            if not zones:
                return ok([])

            z_ids = [z["id"] for z in zones]
            placeholders = ",".join(["%s"] * len(z_ids))
            cur.execute(
                f"SELECT * FROM zonal_officers WHERE zone_id IN ({placeholders}) ORDER BY zone_id, id",
                z_ids
            )
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
    return ok(result)


@admin_bp.route("/super-zones/<int:sz_id>/zones", methods=["POST"])
@admin_required
def add_zone(sz_id):
    body = request.get_json() or {}
    name = body.get("name", "").strip()
    if not name:
        return err("name required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO zones (name,hq_address,super_zone_id) VALUES (%s,%s,%s)",
                (name, body.get("hqAddress", ""), sz_id)
            )
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
                (body.get("name", ""), body.get("hqAddress", ""), z_id)
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


# ── Zonal officers sub-resource ───────────────────────────────────────────────

@admin_bp.route("/zones/<int:z_id>/officers", methods=["GET"])
@admin_required
def get_zonal_officers(z_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM zonal_officers WHERE zone_id=%s ORDER BY id",
                (z_id,)
            )
            rows  = cur.fetchall()
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
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id}, "Officer added", 201)


@admin_bp.route("/zonal-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_zonal_officer(o_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE zonal_officers SET name=%s,pno=%s,mobile=%s,user_rank=%s,user_id=%s WHERE id=%s",
                (body.get("name", ""), body.get("pno", ""), body.get("mobile", ""),
                 body.get("rank", ""), body.get("userId") or None, o_id)
            )
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
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT s.id, s.name, COUNT(DISTINCT gp.id) AS gp_count
                FROM sectors s LEFT JOIN gram_panchayats gp ON gp.sector_id=s.id
                WHERE s.zone_id=%s GROUP BY s.id ORDER BY s.id
            """, (z_id,))
            sectors = cur.fetchall()
            if not sectors:
                return ok([])

            s_ids = [s["id"] for s in sectors]
            placeholders = ",".join(["%s"] * len(s_ids))
            cur.execute(
                f"SELECT * FROM sector_officers WHERE sector_id IN ({placeholders}) ORDER BY sector_id, id",
                s_ids
            )
            officers_by_sector = {}
            for row in cur.fetchall():
                officers_by_sector.setdefault(row["sector_id"], []).append(_o(row))

            result = [{
                "id":       s["id"],
                "name":     s["name"] or "",
                "gpCount":  s["gp_count"],
                "officers": officers_by_sector.get(s["id"], []),
            } for s in sectors]
    finally:
        conn.close()
    return ok(result)


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
                "INSERT INTO sectors (name,zone_id) VALUES (%s,%s)",
                (name, z_id)
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
    conn = get_db()
    try:
        with conn.cursor() as cur:
            if body.get("name"):
                cur.execute(
                    "UPDATE sectors SET name=%s WHERE id=%s",
                    (body["name"], s_id)
                )
            cur.execute("DELETE FROM sector_officers WHERE sector_id=%s", (s_id,))
            for o in body.get("officers", []):
                if o.get("name", "").strip():
                    _insert_officer(cur, "sector_officers", "sector_id", s_id, o)
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Updated")


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


# ── Sector officers sub-resource ──────────────────────────────────────────────

@admin_bp.route("/sectors/<int:s_id>/officers", methods=["GET"])
@admin_required
def get_sector_officers(s_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM sector_officers WHERE sector_id=%s ORDER BY id",
                (s_id,)
            )
            rows  = cur.fetchall()
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
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id}, "Officer added", 201)


@admin_bp.route("/sector-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_sector_officer(o_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE sector_officers SET name=%s,pno=%s,mobile=%s,user_rank=%s,user_id=%s WHERE id=%s",
                (body.get("name", ""), body.get("pno", ""), body.get("mobile", ""),
                 body.get("rank", ""), body.get("userId") or None, o_id)
            )
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


# ── helper to insert into any officer table ───────────────────────────────────
def _insert_officer(cur, table, fk_col, fk_val, o):
    uid    = o.get("userId") or o.get("user_id") or None
    name   = o.get("name",   "").strip()
    pno    = o.get("pno",    "").strip()
    mobile = o.get("mobile", "").strip()
    rank   = o.get("rank",   "").strip()

    if uid:
        cur.execute(
            "SELECT name, pno, mobile, user_rank FROM users WHERE id=%s",
            (uid,)
        )
        u = cur.fetchone()
        if u:
            if not name:   name   = u["name"]      or ""
            if not pno:    pno    = u["pno"]       or ""
            if not mobile: mobile = u["mobile"]    or ""
            if not rank:   rank   = u["user_rank"] or ""

    cur.execute(
        f"""INSERT INTO {table} ({fk_col}, user_id, name, pno, mobile, user_rank)
            VALUES (%s, %s, %s, %s, %s, %s)""",
        (fk_val, uid or None, name, pno, mobile, rank)
    )
    return cur.lastrowid


# ══════════════════════════════════════════════════════════════════════════════
#  GRAM PANCHAYATS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/sectors/<int:s_id>/gram-panchayats", methods=["GET"])
@admin_required
def get_gram_panchayats(s_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT gp.*, COUNT(ms.id) AS center_count
                FROM gram_panchayats gp
                LEFT JOIN matdan_sthal ms ON ms.gram_panchayat_id=gp.id
                WHERE gp.sector_id=%s GROUP BY gp.id ORDER BY gp.id
            """, (s_id,))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id":          r["id"],
        "name":        r["name"]    or "",
        "address":     r["address"] or "",
        "centerCount": r["center_count"],
    } for r in rows])


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
            cur.execute(
                "INSERT INTO gram_panchayats (name,address,sector_id) VALUES (%s,%s,%s)",
                (name, body.get("address", ""), s_id)
            )
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
            cur.execute(
                "UPDATE gram_panchayats SET name=%s,address=%s WHERE id=%s",
                (body.get("name", ""), body.get("address", ""), gp_id)
            )
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
#  ELECTION CENTERS (Matdan Sthal)
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/gram-panchayats/<int:gp_id>/centers", methods=["GET"])
@admin_required
def get_centers(gp_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT ms.*,
                    (SELECT COUNT(*) FROM duty_assignments da WHERE da.sthal_id=ms.id) AS duty_count
                FROM matdan_sthal ms
                WHERE ms.gram_panchayat_id=%s ORDER BY ms.id
            """, (gp_id,))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id":         r["id"],
        "name":       r["name"]        or "",
        "address":    r["address"]     or "",
        "thana":      r["thana"]       or "",
        "centerType": r["center_type"],
        "busNo":      r["bus_no"]      or "",
        "latitude":   float(r["latitude"])  if r["latitude"]  else None,
        "longitude":  float(r["longitude"]) if r["longitude"] else None,
        "dutyCount":  r["duty_count"],
    } for r in rows])


@admin_bp.route("/gram-panchayats/<int:gp_id>/centers", methods=["POST"])
@admin_required
def add_center(gp_id):
    body = request.get_json() or {}
    name = body.get("name", "").strip()
    if not name:
        return err("name required")

    staff_requirements = body.get("staffRequirements", {})  # e.g. {"inspector": 1, "constable": 4}
    district = request.user.get("district")

    RANK_ALIAS = {
        "asp":       ["asp", "additional sp", "additional superintendent of police"],
        "dsp":       ["dsp", "deputy sp", "deputy superintendent of police"],
        "co":        ["co", "circle officer"],
        "inspector": ["inspector", "निरीक्षक"],
        "sho":       ["sho", "station house officer"],
        "si":        ["si", "sub-inspector", "sub inspector"],
        "hc":        ["hc", "head constable"],
        "constable": ["constable", "कांस्टेबल"],
    }

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Insert the center first
            cur.execute("""
                INSERT INTO matdan_sthal
                    (name, address, gram_panchayat_id, thana, center_type, bus_no, latitude, longitude)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
            """, (
                name, body.get("address", ""), gp_id,
                body.get("thana", ""), body.get("centerType", "C"),
                body.get("busNo", ""), body.get("latitude"), body.get("longitude"),
            ))
            new_id = cur.lastrowid

            # Auto-assign duties based on staffRequirements
            assigned_staff = []
            d_clause = "AND u.district=%s" if district else ""
            d_param  = (district,) if district else ()

            for rank_key, count in staff_requirements.items():
                count = int(count or 0)
                if count <= 0:
                    continue

                aliases = RANK_ALIAS.get(rank_key, [rank_key])
                placeholders = ", ".join(["%s"] * len(aliases))

                # Get unassigned staff of this rank
                cur.execute(f"""
                    SELECT u.id FROM users u
                    LEFT JOIN duty_assignments da ON da.staff_id = u.id
                    WHERE u.role = 'staff'
                      AND da.id IS NULL
                      AND LOWER(TRIM(u.user_rank)) IN ({placeholders})
                      {d_clause}
                    LIMIT %s
                """, tuple(a.lower() for a in aliases) + d_param + (count,))

                staff_rows = cur.fetchall()
                for s in staff_rows:
                    cur.execute("""
                        INSERT INTO duty_assignments (staff_id, sthal_id, bus_no, assigned_by)
                        VALUES (%s, %s, %s, %s)
                        ON DUPLICATE KEY UPDATE assigned_by=VALUES(assigned_by)
                    """, (s["id"], new_id, body.get("busNo", ""), _admin_id()))
                    assigned_staff.append(s["id"])

        conn.commit()
    finally:
        conn.close()

    return ok({
        "id": new_id,
        "name": name,
        "assignedCount": len(assigned_staff)
    }, f"Center added, {len(assigned_staff)} staff auto-assigned", 201)

@admin_bp.route("/centers/<int:c_id>", methods=["PUT"])
@admin_required
def update_center(c_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE matdan_sthal
                SET name=%s, address=%s, thana=%s, center_type=%s,
                    bus_no=%s, latitude=%s, longitude=%s
                WHERE id=%s
            """, (
                body.get("name", ""), body.get("address", ""), body.get("thana", ""),
                body.get("centerType", "C"), body.get("busNo", ""),
                body.get("latitude"), body.get("longitude"), c_id,
            ))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Updated")


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


# ── Matdan Kendra (rooms) ─────────────────────────────────────────────────────

@admin_bp.route("/centers/<int:c_id>/rooms", methods=["GET"])
@admin_required
def get_rooms(c_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, room_number FROM matdan_kendra WHERE matdan_sthal_id=%s ORDER BY id",
                (c_id,)
            )
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
            cur.execute(
                "INSERT INTO matdan_kendra (room_number,matdan_sthal_id) VALUES (%s,%s)",
                (rn, c_id)
            )
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
#
#  GET /api/admin/staff?q=&page=1&limit=50&assigned=
#      assigned: "yes" | "no" | "" (all)
#  GET /api/admin/staff/search?q=…  (lightweight typeahead, max 20)
#
#  FIX: Use subquery for duty assignment to avoid row duplication from
#       staff with multiple duty rows. DISTINCT on u.id via subquery.
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/staff", methods=["GET"])
@admin_required
def get_staff():
    search   = request.args.get("q", "").strip()
<<<<<<< HEAD
    assigned = request.args.get("assigned", "").strip().lower()   # "yes"|"no"|""
    district = request.user.get("district")
    page, limit, offset = _page_params()
=======
    rank     = request.args.get("rank", "").strip()
    armed    = request.args.get("armed", "").strip()   # ← NEW: "1", "0", or ""
    district = request.user.get("district")

    RANK_ALIAS = {
        "sp":        ["sp", "पुलिस अधीक्षक"],
        "inspector": ["inspector", "निरीक्षक"],
        "si":        ["si", "sub-inspector", "sub inspector", "उप-निरीक्षक"],
        "hc":        ["hc", "head constable", "हेड कांस्टेबल"],
        "constable": ["constable", "कांस्टेबल"],
        "chaukidar": ["chaukidar", "चौकीदार", "watchman", "guard"],
    }
>>>>>>> 61f41be47df11909eb975b32890183a7db5363ae

    conn = get_db()
    try:
        with conn.cursor() as cur:
<<<<<<< HEAD
            params      = []
            where_parts = ["u.role='staff'"]

            if district:
                where_parts.append("u.district=%s")
                params.append(district)
=======
            d_clause = "AND u.district=%s" if district else ""
            d_param  = (district,) if district else ()

            rank_clause = ""
            rank_params = ()
            if rank and rank in RANK_ALIAS:
                aliases = RANK_ALIAS[rank]
                placeholders = ", ".join(["%s"] * len(aliases))
                rank_clause = f"AND LOWER(TRIM(u.user_rank)) IN ({placeholders})"
                rank_params = tuple(a.lower() for a in aliases)

            # ← NEW: armed filter clause
            armed_clause = ""
            armed_params = ()
            if armed == "1":
                armed_clause = "AND u.is_armed = 1"
            elif armed == "0":
                armed_clause = "AND u.is_armed = 0"
>>>>>>> 61f41be47df11909eb975b32890183a7db5363ae

            if search:
                where_parts.append(
                    "(u.name LIKE %s OR u.pno LIKE %s OR u.mobile LIKE %s OR u.thana LIKE %s)"
                )
                like = f"%{search}%"
<<<<<<< HEAD
                params.extend([like, like, like, like])

            # Use EXISTS/NOT EXISTS to avoid row duplication caused by LEFT JOIN
            if assigned == "yes":
                where_parts.append(
                    "EXISTS (SELECT 1 FROM duty_assignments da WHERE da.staff_id=u.id)"
                )
            elif assigned == "no":
                where_parts.append(
                    "NOT EXISTS (SELECT 1 FROM duty_assignments da WHERE da.staff_id=u.id)"
                )

            where_sql = " AND ".join(where_parts)

            # Count total
            cur.execute(f"""
                SELECT COUNT(*) AS cnt
                FROM users u
                WHERE {where_sql}
            """, params)
            total = cur.fetchone()["cnt"]

            # Paginated fetch — join duty only for assigned fields, use subquery
            cur.execute(f"""
                SELECT u.id, u.name, u.pno, u.mobile, u.thana, u.district, u.user_rank,
                       da.id AS duty_id, da.sthal_id, ms.name AS center_name
                FROM users u
                LEFT JOIN duty_assignments da ON da.staff_id=u.id
                LEFT JOIN matdan_sthal ms     ON ms.id=da.sthal_id
                WHERE {where_sql}
                ORDER BY u.name
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
=======
                cur.execute(f"""
                    SELECT u.id, u.name, u.pno, u.mobile, u.thana, u.district,
                           u.user_rank, u.is_armed,
                           da.sthal_id, ms.name AS center_name
                    FROM users u
                    LEFT JOIN duty_assignments da ON da.staff_id = u.id
                    LEFT JOIN matdan_sthal ms     ON ms.id = da.sthal_id
                    WHERE u.role = 'staff' {d_clause} {rank_clause} {armed_clause}
                      AND (u.name LIKE %s OR u.pno LIKE %s OR u.mobile LIKE %s OR u.thana LIKE %s)
                    ORDER BY u.name
                """, d_param + rank_params + armed_params + (like, like, like, like))
            else:
                cur.execute(f"""
                    SELECT u.id, u.name, u.pno, u.mobile, u.thana, u.district,
                           u.user_rank, u.is_armed,
                           da.sthal_id, ms.name AS center_name
                    FROM users u
                    LEFT JOIN duty_assignments da ON da.staff_id = u.id
                    LEFT JOIN matdan_sthal ms     ON ms.id = da.sthal_id
                    WHERE u.role = 'staff' {d_clause} {rank_clause} {armed_clause}
                    ORDER BY u.name
                """, d_param + rank_params + armed_params)
>>>>>>> 61f41be47df11909eb975b32890183a7db5363ae

            rows = cur.fetchall()
    finally:
        conn.close()

<<<<<<< HEAD
    data = [{
=======
    return ok([{
>>>>>>> 61f41be47df11909eb975b32890183a7db5363ae
        "id":         r["id"],
        "name":       r["name"]       or "",
        "pno":        r["pno"]        or "",
        "mobile":     r["mobile"]     or "",
        "thana":      r["thana"]      or "",
        "district":   r["district"]   or "",
        "rank":       r["user_rank"]  or "",
        "isArmed":    bool(r["is_armed"]),   # ← NEW
        "isAssigned": r["sthal_id"] is not None,
        "dutyId":     r["duty_id"],          # NEW: expose duty_id directly
        "centerName": r["center_name"] or "",
    } for r in rows]

    return _paginated(data, total, page, limit)


# ── Lightweight typeahead endpoint (no pagination overhead) ───────────────────
# FIX: original had wrong param order — district param was appended after LIKE
#      params but the query placed %s before the LIKE clause.
# ─────────────────────────────────────────────────────────────────────────────
@admin_bp.route("/staff/search", methods=["GET"])
@admin_required
def search_staff():
    q        = request.args.get("q", "").strip()
    district = request.user.get("district")
    if not q:
        return ok([])

    like   = f"%{q}%"
    # Build params in correct order: district first (if present), then LIKEs
    params = []
    d_sql  = ""
    if district:
        d_sql = "AND district=%s"
        params.append(district)         # district param FIRST

    params.extend([like, like, like])   # LIKE params AFTER district

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT id, name, pno, mobile, thana, user_rank
                FROM users
                WHERE role='staff' {d_sql}
                  AND (name LIKE %s OR pno LIKE %s OR mobile LIKE %s)
                ORDER BY name LIMIT 20
            """, params)
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":     r["id"],
        "name":   r["name"]      or "",
        "pno":    r["pno"]       or "",
        "mobile": r["mobile"]    or "",
        "thana":  r["thana"]     or "",
        "rank":   r["user_rank"] or "",
    } for r in rows])
<<<<<<< HEAD


=======
    
    
>>>>>>> 61f41be47df11909eb975b32890183a7db5363ae
@admin_bp.route("/staff", methods=["POST"])
@admin_required
def add_staff():
    body = request.get_json() or {}
    name = body.get("name", "").strip()
    pno  = body.get("pno", "").strip()

    if not name or not pno:
        return err("name and pno required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
            if cur.fetchone():
                return err(f"PNO {pno} already registered", 409)

            cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
            username = pno if not cur.fetchone() else f"{pno}_{_admin_id()}"
            district = request.user.get("district") or ""

            cur.execute("""
                INSERT INTO users
                    (name, pno, username, password, mobile, thana, district, user_rank, role, is_active, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
            """, (
                name, pno, username,
                generate_password_hash(pno),
                body.get("mobile", ""),
                body.get("thana", ""),
                district,
                body.get("rank", ""),
                _admin_id(),
            ))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Staff '{name}' PNO:{pno} added by admin {_admin_id()}", "Staff")
    return ok({"id": new_id, "name": name, "pno": pno}, "Staff added", 201)


# ── BULK UPLOAD ───────────────────────────────────────────────────────────────
#  Returns: { added, skipped: [...pnos], total }
# ─────────────────────────────────────────────────────────────────────────────
@admin_bp.route("/staff/bulk", methods=["POST"])
@admin_required
def add_staff_bulk():
    """
    Streams SSE progress events while inserting staff in bulk.
 
    Events:
      {"phase":"parse",  "pct":5,  "msg":"Validating rows..."}
      {"phase":"hash",   "pct":N,  "msg":"Hashing passwords N/total"}
      {"phase":"insert", "pct":N,  "added":N, "total":N}
      {"phase":"done",   "added":N, "skipped":[...], "total":N}
      {"phase":"error",  "message":"..."}
    """
    body  = request.get_json(force=True, silent=True) or {}
    items = body.get("staff", [])
 
    if not items:
        # Return plain JSON for empty — no need for SSE
        return err("staff list empty")
 
    district = (request.user.get("district") or "").strip()
    admin_id = request.user["id"]
    total_input = len(items)
 
    def generate():
        try:
            # ── PHASE 1: Validate & dedup input list (fast, in-memory) ────────
            yield _sse({"phase": "parse", "pct": 2, "msg": "Validating rows..."})
 
            clean, skipped = [], []
            seen_pnos = set()
            for s in items:
                pno  = str(s.get("pno",  "") or "").strip()
                name = str(s.get("name", "") or "").strip()
                if not pno or not name:
                    skipped.append(pno or "(empty)")
                    continue
                if pno in seen_pnos:
                    skipped.append(pno)
                    continue
                seen_pnos.add(pno)
                clean.append({
                    "pno":    pno,
                    "name":   name,
                    "rank":   str(s.get("rank",   "") or "").strip(),
                    "mobile": str(s.get("mobile", "") or "").strip(),
                    "thana":  str(s.get("thana",  "") or "").strip(),
                })
 
            yield _sse({"phase": "parse", "pct": 8, "msg": f"{len(clean)} valid rows found"})
 
            if not clean:
                yield _sse({"phase": "done", "added": 0,
                            "skipped": skipped, "total": total_input})
                return
 
            # ── PHASE 2: DB dedup — find existing PNOs in one query ───────────
            yield _sse({"phase": "parse", "pct": 12, "msg": "Checking existing records..."})
 
            conn = get_db()
            try:
                with conn.cursor() as cur:
                    all_pnos = [r["pno"] for r in clean]
                    ph = ",".join(["%s"] * len(all_pnos))
 
                    cur.execute(f"SELECT pno FROM users WHERE pno IN ({ph})", all_pnos)
                    existing_pnos = {r["pno"] for r in cur.fetchall()}
 
                    yield _sse({"phase": "parse", "pct": 18,
                                "msg": f"{len(existing_pnos)} duplicates found"})
 
                    # Get existing usernames for those PNOs only
                    cur.execute(
                        f"SELECT username FROM users WHERE username IN ({ph})",
                        all_pnos
                    )
                    existing_usernames = {r["username"] for r in cur.fetchall()}
 
                # Build insert list (PNO, name, username — no hash yet)
                pre_insert = []
                for r in clean:
                    if r["pno"] in existing_pnos:
                        skipped.append(r["pno"])
                        continue
                    uname = r["pno"] if r["pno"] not in existing_usernames \
                            else f"{r['pno']}_{admin_id}"
                    pre_insert.append({**r, "username": uname})
 
                yield _sse({"phase": "parse", "pct": 22,
                            "msg": f"{len(pre_insert)} rows to insert"})
 
                if not pre_insert:
                    yield _sse({"phase": "done", "added": 0,
                                "skipped": skipped, "total": total_input})
                    return
 
                # ── PHASE 3: Hash passwords in parallel ───────────────────────
                # This is the #1 bottleneck. ThreadPoolExecutor parallelises it.
                total_to_hash = len(pre_insert)
                hashed = [None] * total_to_hash
                hashed_count = 0
 
                yield _sse({"phase": "hash", "pct": 25,
                            "msg": f"Hashing 0/{total_to_hash}..."})
 
                with ThreadPoolExecutor(max_workers=HASH_WORKERS) as pool:
                    future_to_idx = {
                        pool.submit(_fast_hash, r["pno"]): i
                        for i, r in enumerate(pre_insert)
                    }
                    for future in as_completed(future_to_idx):
                        idx = future_to_idx[future]
                        hashed[idx] = future.result()
                        hashed_count += 1
 
                        # Emit progress every 5% or every 200 rows
                        if hashed_count % max(1, total_to_hash // 20) == 0 \
                                or hashed_count == total_to_hash:
                            pct = 25 + int((hashed_count / total_to_hash) * 30)
                            yield _sse({
                                "phase": "hash",
                                "pct":   pct,
                                "msg":   f"Hashing {hashed_count}/{total_to_hash}..."
                            })
 
                yield _sse({"phase": "hash", "pct": 55,
                            "msg": "Passwords hashed, inserting..."})
 
                # ── PHASE 4: Chunked INSERT with executemany ──────────────────
                # executemany is ~3-5× faster than building a giant VALUES string
                added = 0
                total_ins = len(pre_insert)
 
                with conn.cursor() as cur:
                    for chunk_start in range(0, total_ins, BULK_CHUNK_SIZE):
                        chunk_end  = min(chunk_start + BULK_CHUNK_SIZE, total_ins)
                        chunk      = pre_insert[chunk_start:chunk_end]
                        chunk_hashes = hashed[chunk_start:chunk_end]
 
                        rows = [
                            (
                                r["name"], r["pno"], r["username"],
                                chunk_hashes[i],
                                r["mobile"], r["thana"], district,
                                r["rank"], admin_id,
                            )
                            for i, r in enumerate(chunk)
                        ]
 
                        cur.executemany(
                            """INSERT IGNORE INTO users
                               (name, pno, username, password, mobile, thana,
                                district, user_rank, role, is_active, created_by)
                               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)""",
                            rows
                        )
                        conn.commit()
                        added += len(chunk)
 
                        pct = 55 + int((added / total_ins) * 43)  # 55% → 98%
                        yield _sse({
                            "phase":  "insert",
                            "pct":    pct,
                            "added":  added,
                            "total":  total_ins,
                            "msg":    f"Inserted {added}/{total_ins} rows",
                        })
 
                write_log(
                    "INFO",
                    f"Bulk: {added} added, {len(skipped)} skipped (admin {admin_id})",
                    "Import",
                )
                yield _sse({
                    "phase":   "done",
                    "added":   added,
                    "skipped": skipped,
                    "total":   total_input,
                    "pct":     100,
                })
 
            except Exception as e:
                conn.rollback()
                raise
            finally:
                conn.close()
 
        except Exception as e:
            yield _sse({"phase": "error", "message": str(e)})
 
    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={
            "Cache-Control":      "no-cache, no-store",
            "X-Accel-Buffering":  "no",      # nginx: never buffer SSE
            "X-Content-Type-Options": "nosniff",
            "Connection":         "keep-alive",
        },
        direct_passthrough=True,             # Werkzeug: don't buffer, stream raw
    )
 

@admin_bp.route("/staff/<int:staff_id>", methods=["PUT"])
@admin_required
def update_staff(staff_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE users
                SET name=%s, pno=%s, mobile=%s, thana=%s, user_rank=%s
                WHERE id=%s AND role='staff'
            """, (
                body.get("name", ""), body.get("pno", ""),
                body.get("mobile", ""), body.get("thana", ""),
                body.get("rank", ""), staff_id,
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
                "DELETE FROM users WHERE id=%s AND role='staff'", (staff_id,)
            )
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Staff deleted")


# ── NEW: Remove duty by staff_id directly ─────────────────────────────────────
# Avoids the Flutter client needing to search for duty_id separately.
# DELETE /api/admin/staff/<staff_id>/duty
# ─────────────────────────────────────────────────────────────────────────────
@admin_bp.route("/staff/<int:staff_id>/duty", methods=["DELETE"])
@admin_required
def remove_duty_by_staff(staff_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM duty_assignments WHERE staff_id=%s",
                (staff_id,)
            )
            affected = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    if affected == 0:
        return err("No duty found for this staff", 404)
    write_log("INFO", f"Duty removed for staff {staff_id}", "Duty")
    return ok(None, "Duty removed")


# ══════════════════════════════════════════════════════════════════════════════
#  DUTY ASSIGNMENTS — paginated, N+1 eliminated
#
#  GET /api/admin/duties?center_id=&page=1&limit=50&q=
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/duties", methods=["GET"])
@admin_required
def get_duties():
    center_id_filter = request.args.get("center_id", type=int)
    search           = request.args.get("q", "").strip()
    page, limit, offset = _page_params()

    conn = get_db()
    try:
        with conn.cursor() as cur:

            where_parts = ["sz.admin_id = %s"]
            params      = [_admin_id()]

            if center_id_filter:
                where_parts.append("ms.id = %s")
                params.append(center_id_filter)

            if search:
                where_parts.append(
                    "(u.name LIKE %s OR u.pno LIKE %s OR ms.name LIKE %s)"
                )
                like = f"%{search}%"
                params.extend([like, like, like])

            where_sql = " AND ".join(where_parts)

            cur.execute(f"""
                SELECT COUNT(*) AS cnt
                FROM duty_assignments da
                JOIN users u             ON u.id  = da.staff_id
                JOIN matdan_sthal ms     ON ms.id = da.sthal_id
                JOIN gram_panchayats gp  ON gp.id = ms.gram_panchayat_id
                JOIN sectors s           ON s.id  = gp.sector_id
                JOIN zones z             ON z.id  = s.zone_id
                JOIN super_zones sz      ON sz.id = z.super_zone_id
                WHERE {where_sql}
            """, params)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT da.id, da.bus_no,
                       u.id AS staff_id, u.name, u.pno, u.mobile,
                       u.thana, u.user_rank, u.district,
                       ms.id   AS center_id,   ms.name AS center_name, ms.center_type,
                       gp.name AS gp_name,
                       s.id    AS sector_id,   s.name AS sector_name,
                       z.id    AS zone_id,     z.name AS zone_name,
                       sz.id   AS super_zone_id, sz.name AS super_zone_name, sz.block AS block_name
                FROM duty_assignments da
                JOIN users u             ON u.id  = da.staff_id
                JOIN matdan_sthal ms     ON ms.id = da.sthal_id
                JOIN gram_panchayats gp  ON gp.id = ms.gram_panchayat_id
                JOIN sectors s           ON s.id  = gp.sector_id
                JOIN zones z             ON z.id  = s.zone_id
                JOIN super_zones sz      ON sz.id = z.super_zone_id
                WHERE {where_sql}
                ORDER BY ms.name, u.name
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            rows = cur.fetchall()

            if not rows:
                return _paginated([], total, page, limit)

            sz_ids     = list({r["super_zone_id"] for r in rows})
            z_ids      = list({r["zone_id"]       for r in rows})
            s_ids      = list({r["sector_id"]     for r in rows})
            center_ids = list({r["center_id"]     for r in rows})

            def _fetch_map(sql, id_list):
                if not id_list:
                    return {}
                ph = ",".join(["%s"] * len(id_list))
                cur.execute(sql.format(ph=ph), id_list)
                result = {}
                for row in cur.fetchall():
                    key = list(row.values())[0]
                    result.setdefault(key, []).append(dict(row))
                return result

            super_off_map = _fetch_map(
                "SELECT super_zone_id AS _fk, name, pno, mobile, user_rank "
                "FROM kshetra_officers WHERE super_zone_id IN ({ph})",
                sz_ids
            )
            zonal_off_map = _fetch_map(
                "SELECT zone_id AS _fk, name, pno, mobile, user_rank "
                "FROM zonal_officers WHERE zone_id IN ({ph})",
                z_ids
            )
            sector_off_map = _fetch_map(
                "SELECT sector_id AS _fk, name, pno, mobile, user_rank "
                "FROM sector_officers WHERE sector_id IN ({ph})",
                s_ids
            )
            sahyogi_map = _fetch_map(
                "SELECT da2.sthal_id AS _fk, u2.name, u2.pno, u2.mobile, u2.thana, "
                "u2.user_rank, u2.district "
                "FROM duty_assignments da2 JOIN users u2 ON u2.id=da2.staff_id "
                "WHERE da2.sthal_id IN ({ph})",
                center_ids
            )

            def _strip_fk(lst):
                return [{k: v for k, v in d.items() if k != "_fk"} for d in lst]

            result = [{
                "id":            r["id"],
                "centerId":      r["center_id"],
                "name":          r["name"]          or "",
                "pno":           r["pno"]           or "",
                "mobile":        r["mobile"]        or "",
                "staffThana":    r["thana"]         or "",
                "rank":          r["user_rank"]     or "",
                "district":      r["district"]      or "",
                "centerName":    r["center_name"]   or "",
                "gpName":        r["gp_name"]       or "",
                "sectorName":    r["sector_name"]   or "",
                "zoneName":      r["zone_name"]     or "",
                "superZoneName": r["super_zone_name"] or "",
                "blockName":     r["block_name"]    or "",
                "busNo":         r["bus_no"]        or "",
                "superOfficers":  _strip_fk(super_off_map.get(r["super_zone_id"], [])),
                "zonalOfficers":  _strip_fk(zonal_off_map.get(r["zone_id"],       [])),
                "sectorOfficers": _strip_fk(sector_off_map.get(r["sector_id"],    [])),
                "sahyogi":        _strip_fk(sahyogi_map.get(r["center_id"],        [])),
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
            cur.execute("""
                INSERT INTO duty_assignments (staff_id, sthal_id, bus_no, assigned_by)
                VALUES (%s,%s,%s,%s)
                ON DUPLICATE KEY UPDATE bus_no=VALUES(bus_no), assigned_by=VALUES(assigned_by)
            """, (staff_id, sthal_id, body.get("busNo", ""), _admin_id()))
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Duty: staff {staff_id} → center {sthal_id}", "Duty")
    return ok(None, "Duty assigned", 201)


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
#  ALL CENTERS  (map view) — paginated
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/centers/all", methods=["GET"])
@admin_required
def all_centers():
    search = request.args.get("q", "").strip()
    page, limit, offset = _page_params()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            params      = [_admin_id()]
            where_extra = ""
            if search:
                where_extra = "AND (ms.name LIKE %s OR ms.thana LIKE %s OR gp.name LIKE %s)"
                like = f"%{search}%"
                params.extend([like, like, like])

            cur.execute(f"""
                SELECT COUNT(DISTINCT ms.id) AS cnt
                FROM matdan_sthal ms
                JOIN gram_panchayats gp  ON gp.id  = ms.gram_panchayat_id
                JOIN sectors s           ON s.id   = gp.sector_id
                JOIN zones z             ON z.id   = s.zone_id
                JOIN super_zones sz      ON sz.id  = z.super_zone_id
                WHERE sz.admin_id = %s {where_extra}
            """, params)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT ms.id, ms.name, ms.address, ms.thana,
                       ms.center_type, ms.bus_no,
                       ms.latitude, ms.longitude,
                       gp.name AS gp_name,
                       s.name  AS sector_name,
                       z.name  AS zone_name,
                       sz.name AS super_zone_name,
                       sz.block AS block_name,
                       COUNT(da.id) AS duty_count
                FROM matdan_sthal ms
                JOIN gram_panchayats gp  ON gp.id  = ms.gram_panchayat_id
                JOIN sectors s           ON s.id   = gp.sector_id
                JOIN zones z             ON z.id   = s.zone_id
                JOIN super_zones sz      ON sz.id  = z.super_zone_id
                LEFT JOIN duty_assignments da ON da.sthal_id = ms.id
                WHERE sz.admin_id = %s {where_extra}
                GROUP BY ms.id ORDER BY ms.name
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            rows = cur.fetchall()
    finally:
        conn.close()

    data = [{
        "id":            r["id"],
        "name":          r["name"]            or "",
        "address":       r["address"]         or "",
        "thana":         r["thana"]           or "",
        "centerType":    r["center_type"]     or "C",
        "busNo":         r["bus_no"]          or "",
        "latitude":      float(r["latitude"])  if r["latitude"]  else None,
        "longitude":     float(r["longitude"]) if r["longitude"] else None,
        "gpName":        r["gp_name"]         or "",
        "sectorName":    r["sector_name"]     or "",
        "zoneName":      r["zone_name"]       or "",
        "superZoneName": r["super_zone_name"] or "",
        "blockName":     r["block_name"]      or "",
        "dutyCount":     r["duty_count"],
    } for r in rows]

    return _paginated(data, total, page, limit)


# ══════════════════════════════════════════════════════════════════════════════
#  OVERVIEW
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/overview", methods=["GET"])
@admin_required
def admin_overview():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) AS cnt FROM super_zones WHERE admin_id=%s",
                (_admin_id(),)
            )
            sz = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT COUNT(DISTINCT ms.id) AS cnt
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones szn    ON szn.id = z.super_zone_id
                WHERE szn.admin_id=%s
            """, (_admin_id(),))
            booths = cur.fetchone()["cnt"]

            d = request.user.get("district")
            if d:
                cur.execute(
                    "SELECT COUNT(*) AS cnt FROM users WHERE role='staff' AND district=%s",
                    (d,)
                )
            else:
                cur.execute("SELECT COUNT(*) AS cnt FROM users WHERE role='staff'")
            staff = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT COUNT(da.id) AS cnt
                FROM duty_assignments da
                JOIN matdan_sthal ms     ON ms.id = da.sthal_id
                JOIN gram_panchayats gp  ON gp.id = ms.gram_panchayat_id
                JOIN sectors s           ON s.id  = gp.sector_id
                JOIN zones z             ON z.id  = s.zone_id
                JOIN super_zones szn     ON szn.id = z.super_zone_id
                WHERE szn.admin_id=%s
            """, (_admin_id(),))
            assigned = cur.fetchone()["cnt"]
    finally:
        conn.close()
    return ok({
        "superZones":     sz,
        "totalBooths":    booths,
        "totalStaff":     staff,
        "assignedDuties": assigned,
<<<<<<< HEAD
    })
=======
    })
  
@admin_bp.route("/staff/rank-summary", methods=["GET"])
@admin_required
def staff_rank_summary():
    """
    Returns count of staff per rank, split by assigned/unassigned.
    Used by the frontend rank tabs to show badge counts without a full fetch.
    Response shape:
    {
      "data": [
        { "rank": "inspector", "total": 12, "assigned": 8, "unassigned": 4 },
        ...
      ]
    }
    """
    district = request.user.get("district")
    d_clause = "AND u.district=%s" if district else ""
    d_param  = (district,) if district else ()
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT
                    LOWER(TRIM(u.user_rank)) AS rank_key,
                    COUNT(*) AS total,
                    SUM(CASE WHEN da.id IS NOT NULL THEN 1 ELSE 0 END) AS assigned
                FROM users u
                LEFT JOIN duty_assignments da ON da.staff_id = u.id
                WHERE u.role = 'staff' {d_clause}
                GROUP BY LOWER(TRIM(u.user_rank))
                ORDER BY rank_key
            """, d_param)
            rows = cur.fetchall()
    finally:
        conn.close()
 
    return ok([{
        "rank":       r["rank_key"]  or "अन्य",
        "total":      r["total"],
        "assigned":   r["assigned"]   or 0,
        "unassigned": r["total"] - (r["assigned"] or 0),
    } for r in rows])
 
 
# ══════════════════════════════════════════════════════════════════════════════
#  STAFF AVAILABILITY CHECK
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/staff/check-availability", methods=["POST"])
@admin_required
def check_staff_availability():
    """
    Body: { "requirements": { "inspector": 2, "constable": 4, ... } }
    Returns: { "available": true/false, "details": { "inspector": { "required": 2, "available": 5 }, ... } }
    """
    body = request.get_json() or {}
    requirements = body.get("requirements", {})
    district = request.user.get("district")

    RANK_ALIAS = {
        "asp":       ["asp", "additional sp", "additional superintendent of police"],
        "dsp":       ["dsp", "deputy sp", "deputy superintendent of police"],
        "co":        ["co", "circle officer"],
        "inspector": ["inspector", "निरीक्षक"],
        "sho":       ["sho", "station house officer"],
        "si":        ["si", "sub-inspector", "sub inspector"],
        "hc":        ["hc", "head constable"],
        "constable": ["constable", "कांस्टेबल"],
    }

    conn = get_db()
    try:
        with conn.cursor() as cur:
            d_clause = "AND u.district=%s" if district else ""
            d_param  = (district,) if district else ()

            details = {}
            all_ok = True

            for rank_key, required_count in requirements.items():
                if not required_count or int(required_count) <= 0:
                    continue

                aliases = RANK_ALIAS.get(rank_key, [rank_key])
                placeholders = ", ".join(["%s"] * len(aliases))

                # Count unassigned staff of this rank
                cur.execute(f"""
                    SELECT COUNT(*) AS cnt
                    FROM users u
                    LEFT JOIN duty_assignments da ON da.staff_id = u.id
                    WHERE u.role = 'staff'
                      AND da.id IS NULL
                      AND LOWER(TRIM(u.user_rank)) IN ({placeholders})
                      {d_clause}
                """, tuple(a.lower() for a in aliases) + d_param)

                available = cur.fetchone()["cnt"]
                required  = int(required_count)

                details[rank_key] = {
                    "required":  required,
                    "available": available,
                    "ok":        available >= required,
                }
                if available < required:
                    all_ok = False

    finally:
        conn.close()

    return ok({"available": all_ok, "details": details})  
>>>>>>> 61f41be47df11909eb975b32890183a7db5363ae
