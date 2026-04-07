from flask import Blueprint, request
from werkzeug.security import generate_password_hash
from db import get_db
from app.routes import ok, err, write_log, admin_required

admin_bp = Blueprint("admin", __name__, url_prefix="/api/admin")


def _admin_id():
    return request.user["id"]


# ─── shared officer row serialiser ────────────────────────────────────────────
def _o(r):
    return {
        "id":     r["id"],
        "userId": r["user_id"],
        "name":   r["name"]      or "",
        "pno":    r["pno"]       or "",
        "mobile": r["mobile"]    or "",
        "rank":   r["user_rank"] or "",
    }


# ─── fetch staff list for picker ─────────────────────────────────────────────
# ✅ FIXED: was using r["rank"] which caused KeyError — column is user_rank
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
            "rank":   r["user_rank"] or "",   # ✅ fixed key
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
                SELECT sz.*, COUNT(DISTINCT z.id) AS zone_count
                FROM super_zones sz
                LEFT JOIN zones z ON z.super_zone_id = sz.id
                WHERE sz.admin_id = %s
                GROUP BY sz.id ORDER BY sz.id
            """, (_admin_id(),))
            zones = cur.fetchall()
            result = []
            for sz in zones:
                cur.execute(
                    "SELECT * FROM kshetra_officers WHERE super_zone_id=%s ORDER BY id",
                    (sz["id"],)
                )
                result.append({
                    "id":        sz["id"],
                    "name":      sz["name"]     or "",
                    "district":  sz["district"] or "",
                    "block":     sz["block"]    or "",
                    "zoneCount": sz["zone_count"],
                    "officers":  [_o(r) for r in cur.fetchall()],
                })
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
                SELECT z.*, COUNT(DISTINCT s.id) AS sector_count
                FROM zones z LEFT JOIN sectors s ON s.zone_id=z.id
                WHERE z.super_zone_id=%s GROUP BY z.id ORDER BY z.id
            """, (sz_id,))
            zones = cur.fetchall()
            result = []
            for z in zones:
                cur.execute(
                    "SELECT * FROM zonal_officers WHERE zone_id=%s ORDER BY id",
                    (z["id"],)
                )
                result.append({
                    "id":          z["id"],
                    "name":        z["name"]       or "",
                    "hqAddress":   z["hq_address"] or "",
                    "sectorCount": z["sector_count"],
                    "officers":    [_o(r) for r in cur.fetchall()],
                })
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
                SELECT s.*, COUNT(DISTINCT gp.id) AS gp_count
                FROM sectors s LEFT JOIN gram_panchayats gp ON gp.sector_id=s.id
                WHERE s.zone_id=%s GROUP BY s.id ORDER BY s.id
            """, (z_id,))
            sectors = cur.fetchall()
            result = []
            for s in sectors:
                cur.execute(
                    "SELECT * FROM sector_officers WHERE sector_id=%s ORDER BY id",
                    (s["id"],)
                )
                result.append({
                    "id":       s["id"],
                    "name":     s["name"] or "",
                    "gpCount":  s["gp_count"],
                    "officers": [_o(r) for r in cur.fetchall()],
                })
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
    conn = get_db()
    try:
        with conn.cursor() as cur:
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
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "name": name}, "Center added", 201)


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
#  STAFF
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/staff", methods=["GET"])
@admin_required
def get_staff():
    search   = request.args.get("q", "").strip()
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

    conn = get_db()
    try:
        with conn.cursor() as cur:
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

            if search:
                like = f"%{search}%"
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

            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":         r["id"],
        "name":       r["name"]       or "",
        "pno":        r["pno"]        or "",
        "mobile":     r["mobile"]     or "",
        "thana":      r["thana"]      or "",
        "district":   r["district"]   or "",
        "rank":       r["user_rank"]  or "",
        "isArmed":    bool(r["is_armed"]),   # ← NEW
        "isAssigned": r["sthal_id"] is not None,
        "centerName": r["center_name"] or "",
    } for r in rows])
    
    
@admin_bp.route("/staff", methods=["POST"])
@admin_required
def add_staff():
    body = request.get_json() or {}

    name = body.get("name", "").strip()
    pno  = body.get("pno", "").strip()
    rank = str(body.get("rank", "")).strip()

    if not name or not pno:
        return err("name and pno required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # 🔍 Check duplicate PNO
            cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
            if cur.fetchone():
                return err(f"PNO {pno} already registered", 409)

            # 🔍 Ensure unique username
            cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
            username = pno if not cur.fetchone() else f"{pno}_{_admin_id()}"

            # 🔥 FIX: ALWAYS use admin district
            district = request.user.get("district") or ""

            cur.execute("""
                INSERT INTO users
                    (name, pno, username, password, mobile, thana, district, user_rank, role, is_active, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
            """, (
                name,
                pno,
                username,
                generate_password_hash(pno),
                body.get("mobile", ""),
                body.get("thana", ""),
                district,                       # ✅ FIXED
                body.get("rank", ""),
                _admin_id(),
            ))

            new_id = cur.lastrowid

        conn.commit()

    finally:
        conn.close()

    write_log("INFO", f"Staff '{name}' PNO:{pno} added by admin {_admin_id()}", "Staff")

    return ok({"id": new_id, "name": name, "pno": pno}, "Staff added", 201)

@admin_bp.route("/staff/bulk", methods=["POST"])
@admin_required
def add_staff_bulk():
    body  = request.get_json() or {}
    items = body.get("staff", [])

    if not items:
        return err("staff list empty")

    added, skipped = 0, []

    conn = get_db()
    
    try:
        with conn.cursor() as cur:
            for s in items:
                pno  = str(s.get("pno", "") or "").strip()
                name = str(s.get("name", "") or "").strip()
                rank = str(s.get("rank", "") or "").strip()

                if not pno or not name:
                    skipped.append(pno or "(empty)")
                    continue

                # 🔍 Duplicate check
                cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
                if cur.fetchone():
                    skipped.append(pno)
                    continue

                # 🔍 Username check
                cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
                username = pno if not cur.fetchone() else f"{pno}_{added}"

                # 🔥 FIX: ALWAYS use admin district
                district = request.user.get("district") or ""

                cur.execute("""
                    INSERT INTO users
                        (name, pno, username, password, mobile, thana, district, user_rank, role, is_active, created_by)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
                """, (
                    name,
                    pno,
                    username,
                    generate_password_hash(pno),
                    str(s.get("mobile") or ""),
                    str(s.get("thana") or ""),
                    district,
                    rank,                  # ✅ FIXED
                    _admin_id(),
                ))

                added += 1

        conn.commit()

    finally:
        conn.close()

    write_log("INFO", f"Bulk: {added} added, {len(skipped)} skipped (admin {_admin_id()})", "Import")

    return ok({
        "added": added,
        "skipped": skipped,
        "total": len(items)
    }, f"{added} staff added")


@admin_bp.route("/staff/<int:staff_id>", methods=["PUT"])
@admin_required
def update_staff(staff_id):
    body = request.get_json() or {}

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE users
                SET name=%s,
                    pno=%s,
                    mobile=%s,
                    thana=%s,
                    user_rank=%s
                WHERE id=%s AND role='staff'
            """, (
                body.get("name", ""),
                body.get("pno", ""),
                body.get("mobile", ""),
                body.get("thana", ""),
                body.get("rank", ""),
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
                (staff_id,)
            )
        conn.commit()
    finally:
        conn.close()

    return ok(None, "Staff deleted")



# ══════════════════════════════════════════════════════════════════════════════
#  DUTY ASSIGNMENTS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/duties", methods=["GET"])
@admin_required
def get_duties():
    # ✅ NEW: optional center_id filter
    center_id_filter = request.args.get("center_id", type=int)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
 
            where_extra = ""
            params = [_admin_id()]
            if center_id_filter:
                where_extra = "AND ms.id = %s"
                params.append(center_id_filter)
 
            cur.execute(f"""
                SELECT da.id, da.bus_no,
                       u.id AS staff_id, u.name, u.pno, u.mobile,
                       u.thana, u.user_rank, u.district,
 
                       ms.id   AS center_id,
                       ms.name AS center_name,
                       ms.center_type,
 
                       gp.name AS gp_name,
                       s.id    AS sector_id,  s.name AS sector_name,
                       z.id    AS zone_id,    z.name AS zone_name,
                       sz.id   AS super_zone_id, sz.name AS super_zone_name,
                       sz.block AS block_name
 
                FROM duty_assignments da
                JOIN users u             ON u.id  = da.staff_id
                JOIN matdan_sthal ms     ON ms.id = da.sthal_id
                JOIN gram_panchayats gp  ON gp.id = ms.gram_panchayat_id
                JOIN sectors s           ON s.id  = gp.sector_id
                JOIN zones z             ON z.id  = s.zone_id
                JOIN super_zones sz      ON sz.id = z.super_zone_id
                WHERE sz.admin_id = %s {where_extra}
                ORDER BY ms.name, u.name
            """, params)
 
            rows = cur.fetchall()
            result = []
 
            for r in rows:
 
                cur.execute("""
                    SELECT name, pno, mobile, user_rank
                    FROM kshetra_officers WHERE super_zone_id=%s
                """, (r["super_zone_id"],))
                super_officers = cur.fetchall()
 
                cur.execute("""
                    SELECT name, pno, mobile, user_rank
                    FROM zonal_officers WHERE zone_id=%s
                """, (r["zone_id"],))
                zonal_officers = cur.fetchall()
 
                cur.execute("""
                    SELECT name, pno, mobile, user_rank
                    FROM sector_officers WHERE sector_id=%s
                """, (r["sector_id"],))
                sector_officers = cur.fetchall()
 
                cur.execute("""
                    SELECT u.name, u.pno, u.mobile, u.thana, u.user_rank, u.district
                    FROM duty_assignments da2
                    JOIN users u ON u.id = da2.staff_id
                    WHERE da2.sthal_id = %s
                """, (r["center_id"],))
                sahyogi = cur.fetchall()
 
                result.append({
                    "id":         r["id"],
                    # ✅ include center_id so Flutter can filter by it
                    "centerId":   r["center_id"],
                    "name":       r["name"]       or "",
                    "pno":        r["pno"]         or "",
                    "mobile":     r["mobile"]      or "",
                    "staffThana": r["thana"]        or "",
                    "rank":       r["user_rank"]    or "",
                    "district":   r["district"]     or "",
 
                    "centerName":    r["center_name"]    or "",
                    "gpName":        r["gp_name"]         or "",
                    "sectorName":    r["sector_name"]     or "",
                    "zoneName":      r["zone_name"]       or "",
                    "superZoneName": r["super_zone_name"] or "",
                    "blockName":     r["block_name"]      or "",
 
                    "busNo": r["bus_no"] or "",
 
                    "superOfficers":  super_officers,
                    "zonalOfficers":  zonal_officers,
                    "sectorOfficers": sector_officers,
                    "sahyogi":        sahyogi,
                })
 
    finally:
        conn.close()
 
    return ok(result)
 

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
#  ALL CENTERS  (map view)
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/centers/all", methods=["GET"])
@admin_required
def all_centers():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT ms.id, ms.name, ms.address, ms.thana,
                       ms.center_type, ms.bus_no,
                       ms.latitude, ms.longitude,
                       gp.name AS gp_name,
                       s.name  AS sector_name,
                       z.name  AS zone_name,
                       sz.name AS super_zone_name,
                       -- ✅ include block name from super_zones
                       sz.block AS block_name,
                       COUNT(da.id) AS duty_count
                FROM matdan_sthal ms
                JOIN gram_panchayats gp  ON gp.id  = ms.gram_panchayat_id
                JOIN sectors s           ON s.id   = gp.sector_id
                JOIN zones z             ON z.id   = s.zone_id
                JOIN super_zones sz      ON sz.id  = z.super_zone_id
                LEFT JOIN duty_assignments da ON da.sthal_id = ms.id
                WHERE sz.admin_id = %s
                GROUP BY ms.id ORDER BY ms.name
            """, (_admin_id(),))
            rows = cur.fetchall()
    finally:
        conn.close()
 
    return ok([{
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
        "blockName":     r["block_name"]      or "",   # ✅ NEW
        "dutyCount":     r["duty_count"],
    } for r in rows])


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
        "superZones":    sz,
        "totalBooths":   booths,
        "totalStaff":    staff,
        "assignedDuties": assigned,
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
 
 
    