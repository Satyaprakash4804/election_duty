from flask import Blueprint, request
from werkzeug.security import generate_password_hash
from db import get_db
from app.routes import ok, err, write_log, admin_required

admin_bp = Blueprint("admin", __name__, url_prefix="/api/admin")


# ══════════════════════════════════════════════════════════════
#  HELPER — get admin_id from token
# ══════════════════════════════════════════════════════════════
def _admin_id():
    return request.user["id"]


# ══════════════════════════════════════════════════════════════════════════════
#  STRUCTURE — Super Zones
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/super-zones", methods=["GET"])
@admin_required
def get_super_zones():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT sz.*,
                    COUNT(DISTINCT z.id) AS zone_count
                FROM super_zones sz
                LEFT JOIN zones z ON z.super_zone_id = sz.id
                WHERE sz.admin_id = %s
                GROUP BY sz.id
                ORDER BY sz.id
            """, (_admin_id(),))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id": r["id"], "name": r["name"],
        "district": r["district"], "zoneCount": r["zone_count"],
    } for r in rows])


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
                "INSERT INTO super_zones (name, district, admin_id) VALUES (%s,%s,%s)",
                (name, request.user.get("district"), _admin_id()))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "name": name}, "Super Zone added", 201)


@admin_bp.route("/super-zones/<int:sz_id>", methods=["DELETE"])
@admin_required
def delete_super_zone(sz_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM super_zones WHERE id=%s AND admin_id=%s",
                        (sz_id, _admin_id()))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  STRUCTURE — Zones
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/super-zones/<int:sz_id>/zones", methods=["GET"])
@admin_required
def get_zones(sz_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT z.*, COUNT(DISTINCT s.id) AS sector_count
                FROM zones z
                LEFT JOIN sectors s ON s.zone_id = z.id
                WHERE z.super_zone_id = %s
                GROUP BY z.id ORDER BY z.id
            """, (sz_id,))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id": r["id"], "name": r["name"],
        "hqAddress":     r["hq_address"],
        "officerName":   r["officer_name"],
        "officerPno":    r["officer_pno"],
        "officerMobile": r["officer_mobile"],
        "sectorCount":   r["sector_count"],
    } for r in rows])


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
            cur.execute("""
                INSERT INTO zones
                    (name, hq_address, officer_name, officer_pno, officer_mobile, super_zone_id)
                VALUES (%s,%s,%s,%s,%s,%s)
            """, (name, body.get("hqAddress"), body.get("officerName"),
                  body.get("officerPno"), body.get("officerMobile"), sz_id))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "name": name}, "Zone added", 201)


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


# ══════════════════════════════════════════════════════════════════════════════
#  STRUCTURE — Sectors
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/zones/<int:z_id>/sectors", methods=["GET"])
@admin_required
def get_sectors(z_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT s.*, COUNT(DISTINCT gp.id) AS gp_count
                FROM sectors s
                LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
                WHERE s.zone_id = %s
                GROUP BY s.id ORDER BY s.id
            """, (z_id,))
            sectors = cur.fetchall()

            for s in sectors:
                cur.execute("""
                    SELECT id, name, pno, mobile FROM sector_officers
                    WHERE sector_id = %s ORDER BY id
                """, (s["id"],))
                s["officers"] = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id": s["id"], "name": s["name"], "gpCount": s["gp_count"],
        "officers": [{"id": o["id"], "name": o["name"],
                      "pno": o["pno"], "mobile": o["mobile"]}
                     for o in s["officers"]],
    } for s in sectors])


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
                "INSERT INTO sectors (name, zone_id) VALUES (%s,%s)",
                (name, z_id))
            new_id = cur.lastrowid

            # Add officers if provided
            for o in body.get("officers", []):
                cur.execute("""
                    INSERT INTO sector_officers (sector_id, name, pno, mobile)
                    VALUES (%s,%s,%s,%s)
                """, (new_id, o.get("name"), o.get("pno"), o.get("mobile")))
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "name": name}, "Sector added", 201)


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


# Sector officers CRUD
@admin_bp.route("/sectors/<int:s_id>/officers", methods=["POST"])
@admin_required
def add_officer(s_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO sector_officers (sector_id, name, pno, mobile)
                VALUES (%s,%s,%s,%s)
            """, (s_id, body.get("name"), body.get("pno"), body.get("mobile")))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id}, "Officer added", 201)


@admin_bp.route("/officers/<int:o_id>", methods=["DELETE"])
@admin_required
def delete_officer(o_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM sector_officers WHERE id=%s", (o_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  STRUCTURE — Gram Panchayats
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
                LEFT JOIN matdan_sthal ms ON ms.gram_panchayat_id = gp.id
                WHERE gp.sector_id = %s
                GROUP BY gp.id ORDER BY gp.id
            """, (s_id,))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id": r["id"], "name": r["name"],
        "address": r["address"], "centerCount": r["center_count"],
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
                "INSERT INTO gram_panchayats (name, address, sector_id) VALUES (%s,%s,%s)",
                (name, body.get("address"), s_id))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "name": name}, "Gram Panchayat added", 201)


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
#  STRUCTURE — Matdan Sthal (Election Centers)
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/gram-panchayats/<int:gp_id>/centers", methods=["GET"])
@admin_required
def get_centers(gp_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT ms.*,
                    (SELECT COUNT(*) FROM duty_assignments da WHERE da.sthal_id = ms.id) AS duty_count
                FROM matdan_sthal ms
                WHERE ms.gram_panchayat_id = %s
                ORDER BY ms.id
            """, (gp_id,))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id":          r["id"],
        "name":        r["name"],
        "address":     r["address"],
        "thana":       r["thana"],
        "centerType":  r["center_type"],
        "busNo":       r["bus_no"],
        "latitude":    float(r["latitude"])  if r["latitude"]  else None,
        "longitude":   float(r["longitude"]) if r["longitude"] else None,
        "dutyCount":   r["duty_count"],
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
            """, (name, body.get("address"), gp_id,
                  body.get("thana"), body.get("centerType", "C"),
                  body.get("busNo"),
                  body.get("latitude"), body.get("longitude")))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "name": name}, "Center added", 201)


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


# ══════════════════════════════════════════════════════════════════════════════
#  STAFF — add / list / upload
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/staff", methods=["GET"])
@admin_required
def get_staff():
    search   = request.args.get("q", "").strip()
    district = request.user.get("district")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            if search:
                cur.execute("""
                    SELECT u.*,
                        da.sthal_id,
                        ms.name AS center_name
                    FROM users u
                    LEFT JOIN duty_assignments da ON da.staff_id = u.id
                    LEFT JOIN matdan_sthal ms ON ms.id = da.sthal_id
                    WHERE u.role = 'staff'
                    AND u.district = %s
                    AND (u.name LIKE %s OR u.pno LIKE %s OR u.mobile LIKE %s)
                    ORDER BY u.name
                """, (district, f"%{search}%", f"%{search}%", f"%{search}%"))
            else:
                cur.execute("""
                    SELECT u.*,
                        da.sthal_id,
                        ms.name AS center_name
                    FROM users u
                    LEFT JOIN duty_assignments da ON da.staff_id = u.id
                    LEFT JOIN matdan_sthal ms ON ms.id = da.sthal_id
                    WHERE u.role = 'staff' AND u.district = %s
                    ORDER BY u.name
                """, (district,))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id":          r["id"],
        "name":        r["name"],
        "pno":         r["pno"],
        "mobile":      r["mobile"],
        "thana":       r["thana"],
        "district":    r["district"],
        "isAssigned":  r["sthal_id"] is not None,
        "centerName":  r["center_name"],
    } for r in rows])


@admin_bp.route("/staff", methods=["POST"])
@admin_required
def add_staff():
    body = request.get_json() or {}
    name = body.get("name", "").strip()
    pno  = body.get("pno",  "").strip()
    if not name or not pno:
        return err("name and pno are required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE pno = %s", (pno,))
            if cur.fetchone():
                return err(f"PNO {pno} already registered", 409)

            cur.execute("""
                INSERT INTO users
                    (name, pno, username, password, mobile, thana, district, role, is_active, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
            """, (
                name, pno,
                pno,                              # username = PNO for staff
                generate_password_hash(pno),      # default password = PNO
                body.get("mobile"), body.get("thana"),
                body.get("district", request.user.get("district")),
                _admin_id(),
            ))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "name": name, "pno": pno}, "Staff added", 201)


@admin_bp.route("/staff/bulk", methods=["POST"])
@admin_required
def add_staff_bulk():
    """Accepts a list of staff records from Excel upload"""
    body   = request.get_json() or {}
    items  = body.get("staff", [])
    if not items:
        return err("staff list is empty")

    added  = 0
    skipped = []
    conn = get_db()
    try:
        with conn.cursor() as cur:
            for s in items:
                pno  = str(s.get("pno",  "")).strip()
                name = str(s.get("name", "")).strip()
                if not pno or not name:
                    continue
                cur.execute("SELECT id FROM users WHERE pno = %s", (pno,))
                if cur.fetchone():
                    skipped.append(pno)
                    continue
                cur.execute("""
                    INSERT INTO users
                        (name, pno, username, password, mobile, thana, district, role, is_active, created_by)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
                """, (
                    name, pno, pno, generate_password_hash(pno),
                    s.get("mobile"), s.get("thana"),
                    s.get("district", request.user.get("district")),
                    _admin_id(),
                ))
                added += 1
        conn.commit()
    finally:
        conn.close()
    write_log("INFO",
              f"Bulk staff upload: {added} added, {len(skipped)} skipped (admin ID:{_admin_id()})",
              "Import")
    return ok({"added": added, "skipped": skipped, "total": len(items)},
              f"{added} staff added")


# ══════════════════════════════════════════════════════════════════════════════
#  DUTY ASSIGNMENT
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/duties", methods=["GET"])
@admin_required
def get_duties():
    sthal_id = request.args.get("center_id")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            if sthal_id:
                cur.execute("""
                    SELECT da.id, da.bus_no,
                           u.id AS staff_id, u.name, u.pno, u.mobile, u.thana,
                           ms.name AS center_name, ms.thana AS center_thana,
                           ms.center_type,
                           gp.name AS gp_name,
                           s.name  AS sector_name,
                           z.name  AS zone_name,
                           sz.name AS super_zone_name
                    FROM duty_assignments da
                    JOIN users u ON u.id = da.staff_id
                    JOIN matdan_sthal ms ON ms.id = da.sthal_id
                    JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                    JOIN sectors s ON s.id = gp.sector_id
                    JOIN zones z ON z.id = s.zone_id
                    JOIN super_zones sz ON sz.id = z.super_zone_id
                    WHERE da.sthal_id = %s
                    ORDER BY u.name
                """, (sthal_id,))
            else:
                cur.execute("""
                    SELECT da.id, da.bus_no,
                           u.id AS staff_id, u.name, u.pno, u.mobile, u.thana,
                           ms.name AS center_name, ms.thana AS center_thana,
                           ms.center_type,
                           gp.name AS gp_name,
                           s.name  AS sector_name,
                           z.name  AS zone_name,
                           sz.name AS super_zone_name
                    FROM duty_assignments da
                    JOIN users u ON u.id = da.staff_id
                    JOIN matdan_sthal ms ON ms.id = da.sthal_id
                    JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                    JOIN sectors s ON s.id = gp.sector_id
                    JOIN zones z ON z.id = s.zone_id
                    JOIN super_zones sz ON sz.id = z.super_zone_id
                    WHERE sz.admin_id = %s
                    ORDER BY ms.name, u.name
                """, (_admin_id(),))
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":           r["id"],
        "busNo":        r["bus_no"],
        "staffId":      r["staff_id"],
        "name":         r["name"],
        "pno":          r["pno"],
        "mobile":       r["mobile"],
        "staffThana":   r["thana"],
        "centerName":   r["center_name"],
        "centerThana":  r["center_thana"],
        "centerType":   r["center_type"],
        "gpName":       r["gp_name"],
        "sectorName":   r["sector_name"],
        "zoneName":     r["zone_name"],
        "superZoneName":r["super_zone_name"],
    } for r in rows])


@admin_bp.route("/duties", methods=["POST"])
@admin_required
def assign_duty():
    body     = request.get_json() or {}
    staff_id = body.get("staffId")
    sthal_id = body.get("centerId")
    bus_no   = body.get("busNo")
    if not staff_id or not sthal_id:
        return err("staffId and centerId are required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO duty_assignments (staff_id, sthal_id, bus_no, assigned_by)
                VALUES (%s,%s,%s,%s)
                ON DUPLICATE KEY UPDATE bus_no=VALUES(bus_no), assigned_by=VALUES(assigned_by)
            """, (staff_id, sthal_id, bus_no, _admin_id()))
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Duty assigned: staff {staff_id} → center {sthal_id}", "Duty")
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
#  ALL CENTERS (for map + overview)
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/centers/all", methods=["GET"])
@admin_required
def all_centers():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT ms.id, ms.name, ms.address, ms.thana,
                       ms.center_type, ms.latitude, ms.longitude,
                       gp.name AS gp_name,
                       s.name  AS sector_name,
                       z.name  AS zone_name,
                       sz.name AS super_zone_name,
                       COUNT(da.id) AS duty_count
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s ON s.id = gp.sector_id
                JOIN zones z ON z.id = s.zone_id
                JOIN super_zones sz ON sz.id = z.super_zone_id
                LEFT JOIN duty_assignments da ON da.sthal_id = ms.id
                WHERE sz.admin_id = %s
                GROUP BY ms.id
                ORDER BY ms.name
            """, (_admin_id(),))
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":           r["id"],
        "name":         r["name"],
        "address":      r["address"],
        "thana":        r["thana"],
        "centerType":   r["center_type"],
        "latitude":     float(r["latitude"])  if r["latitude"]  else None,
        "longitude":    float(r["longitude"]) if r["longitude"] else None,
        "gpName":       r["gp_name"],
        "sectorName":   r["sector_name"],
        "zoneName":     r["zone_name"],
        "superZoneName":r["super_zone_name"],
        "dutyCount":    r["duty_count"],
    } for r in rows])


# ══════════════════════════════════════════════════════════════════════════════
#  OVERVIEW STATS
# ══════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/overview", methods=["GET"])
@admin_required
def admin_overview():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT COUNT(*) AS cnt FROM super_zones WHERE admin_id=%s
            """, (_admin_id(),))
            sz = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT COUNT(DISTINCT ms.id) AS cnt
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
                JOIN sectors s ON s.id=gp.sector_id
                JOIN zones z ON z.id=s.zone_id
                JOIN super_zones szn ON szn.id=z.super_zone_id
                WHERE szn.admin_id=%s
            """, (_admin_id(),))
            booths = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT COUNT(*) AS cnt FROM users
                WHERE role='staff' AND district=%s
            """, (request.user.get("district"),))
            staff = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT COUNT(da.id) AS cnt
                FROM duty_assignments da
                JOIN matdan_sthal ms ON ms.id=da.sthal_id
                JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
                JOIN sectors s ON s.id=gp.sector_id
                JOIN zones z ON z.id=s.zone_id
                JOIN super_zones szn ON szn.id=z.super_zone_id
                WHERE szn.admin_id=%s
            """, (_admin_id(),))
            assigned = cur.fetchone()["cnt"]
    finally:
        conn.close()

    return ok({
        "superZones":    sz,
        "totalBooths":   booths,
        "totalStaff":    staff,
        "assignedDuties":assigned,
    })