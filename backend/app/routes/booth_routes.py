from flask import Blueprint, request
from db import get_db
from app.routes import ok, err, write_log, admin_required

booth_bp = Blueprint("booth", __name__, url_prefix="/api/admin/booth")


def _admin_id():
    return request.user["id"]


# ══════════════════════════════════════════════════════════════════════════════
#  1. GET ALL CENTERS  (main list for booth page)
#     GET /api/admin/booth/centers
# ══════════════════════════════════════════════════════════════════════════════

@booth_bp.route("/centers", methods=["GET"])
@admin_required
def get_booth_centers():
    """
    Returns all election centers under this admin with duty count,
    GP, sector, zone, super-zone details for the booth page list.
    """
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    ms.id,
                    ms.name,
                    ms.address,
                    ms.thana,
                    ms.center_type,
                    ms.bus_no,
                    ms.latitude,
                    ms.longitude,
                    gp.name  AS gp_name,
                    s.id     AS sector_id,
                    s.name   AS sector_name,
                    z.id     AS zone_id,
                    z.name   AS zone_name,
                    sz.id    AS super_zone_id,
                    sz.name  AS super_zone_name,
                    COUNT(da.id) AS duty_count
                FROM matdan_sthal ms
                JOIN gram_panchayats gp  ON gp.id  = ms.gram_panchayat_id
                JOIN sectors s           ON s.id   = gp.sector_id
                JOIN zones z             ON z.id   = s.zone_id
                JOIN super_zones sz      ON sz.id  = z.super_zone_id
                LEFT JOIN duty_assignments da ON da.sthal_id = ms.id
                WHERE sz.admin_id = %s
                GROUP BY ms.id
                ORDER BY ms.name
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
        "sectorId":      r["sector_id"],
        "sectorName":    r["sector_name"]     or "",
        "zoneId":        r["zone_id"],
        "zoneName":      r["zone_name"]       or "",
        "superZoneId":   r["super_zone_id"],
        "superZoneName": r["super_zone_name"] or "",
        "dutyCount":     r["duty_count"],
    } for r in rows])


# ══════════════════════════════════════════════════════════════════════════════
#  2. GET ASSIGNED STAFF FOR A CENTER
#     GET /api/admin/booth/centers/<center_id>/duties
# ══════════════════════════════════════════════════════════════════════════════

@booth_bp.route("/centers/<int:center_id>/duties", methods=["GET"])
@admin_required
def get_center_duties(center_id):
    """
    Returns all staff assigned to a specific election center.
    """
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    da.id,
                    da.bus_no,
                    u.id        AS staff_id,
                    u.name,
                    u.pno,
                    u.mobile,
                    u.thana,
                    u.user_rank AS rank,
                    u.district
                FROM duty_assignments da
                JOIN users u ON u.id = da.staff_id
                WHERE da.sthal_id = %s
                ORDER BY u.name
            """, (center_id,))
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":       r["id"],
        "busNo":    r["bus_no"]   or "",
        "staffId":  r["staff_id"],
        "name":     r["name"]     or "",
        "pno":      r["pno"]      or "",
        "mobile":   r["mobile"]   or "",
        "thana":    r["thana"]    or "",
        "rank":     r["rank"]     or "",
        "district": r["district"] or "",
    } for r in rows])


# ══════════════════════════════════════════════════════════════════════════════
#  3. ASSIGN STAFF TO CENTER
#     POST /api/admin/booth/duties
# ══════════════════════════════════════════════════════════════════════════════

@booth_bp.route("/duties", methods=["POST"])
@admin_required
def assign_booth_duty():
    """
    Assigns a staff member to an election center.
    Body: { staffId, centerId, busNo? }
    """
    body     = request.get_json() or {}
    staff_id = body.get("staffId")
    sthal_id = body.get("centerId")

    if not staff_id or not sthal_id:
        return err("staffId and centerId are required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Verify center belongs to this admin
            cur.execute("""
                SELECT ms.id FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE ms.id = %s AND sz.admin_id = %s
            """, (sthal_id, _admin_id()))
            if not cur.fetchone():
                return err("Center not found or access denied", 403)

            cur.execute("""
                INSERT INTO duty_assignments (staff_id, sthal_id, bus_no, assigned_by)
                VALUES (%s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    bus_no      = VALUES(bus_no),
                    assigned_by = VALUES(assigned_by)
            """, (staff_id, sthal_id, body.get("busNo", ""), _admin_id()))

        conn.commit()
    finally:
        conn.close()

    write_log("INFO",
              f"Booth duty: staff {staff_id} → center {sthal_id} by admin {_admin_id()}",
              "Duty")
    return ok(None, "Duty assigned", 201)


# ══════════════════════════════════════════════════════════════════════════════
#  4. REMOVE DUTY
#     DELETE /api/admin/booth/duties/<duty_id>
# ══════════════════════════════════════════════════════════════════════════════

@booth_bp.route("/duties/<int:duty_id>", methods=["DELETE"])
@admin_required
def remove_booth_duty(duty_id):
    """
    Removes a duty assignment by its ID.
    """
    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Security: ensure the duty belongs to this admin's centers
            cur.execute("""
                SELECT da.id FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id  = da.sthal_id
                JOIN gram_panchayats gp ON gp.id  = ms.gram_panchayat_id
                JOIN sectors s          ON s.id   = gp.sector_id
                JOIN zones z            ON z.id   = s.zone_id
                JOIN super_zones sz     ON sz.id  = z.super_zone_id
                WHERE da.id = %s AND sz.admin_id = %s
            """, (duty_id, _admin_id()))
            if not cur.fetchone():
                return err("Duty not found or access denied", 403)

            cur.execute("DELETE FROM duty_assignments WHERE id = %s", (duty_id,))
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Booth duty {duty_id} removed by admin {_admin_id()}", "Duty")
    return ok(None, "Duty removed")


# ══════════════════════════════════════════════════════════════════════════════
#  5. SEARCH STAFF  (live search for the picker bottom sheet)
#     GET /api/admin/booth/staff/search?q=...&unassigned=true&limit=50
# ══════════════════════════════════════════════════════════════════════════════

@booth_bp.route("/staff/search", methods=["GET"])
@admin_required
def search_booth_staff():
    """
    Smart staff search for the booth page staff picker.
    Searches across: name, pno, mobile, thana, district, rank.
    ?q=          search term (optional — returns all if blank)
    ?unassigned= true (default) | false
    ?limit=      max results (default 50, max 200)
    """
    q           = request.args.get("q", "").strip()
    only_free   = request.args.get("unassigned", "true").lower() == "true"
    district    = request.user.get("district")
    limit       = min(int(request.args.get("limit", 50)), 200)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            conditions = ["u.role = 'staff'", "u.is_active = 1"]
            params     = []

            # Restrict to admin's district
            if district:
                conditions.append("u.district = %s")
                params.append(district)

            # Only unassigned staff
            if only_free:
                conditions.append("""
                    NOT EXISTS (
                        SELECT 1 FROM duty_assignments da2
                        WHERE da2.staff_id = u.id
                    )
                """)

            # Full-text smart search
            if q:
                like = f"%{q}%"
                conditions.append("""(
                    u.name      LIKE %s OR
                    u.pno       LIKE %s OR
                    u.mobile    LIKE %s OR
                    u.thana     LIKE %s OR
                    u.district  LIKE %s OR
                    u.user_rank LIKE %s
                )""")
                params += [like, like, like, like, like, like]

            where = " AND ".join(conditions)

            cur.execute(f"""
                SELECT
                    u.id,
                    u.name,
                    u.pno,
                    u.mobile,
                    u.thana,
                    u.district,
                    u.user_rank AS rank
                FROM users u
                WHERE {where}
                ORDER BY u.name
                LIMIT %s
            """, params + [limit])

            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":       r["id"],
        "name":     r["name"]     or "",
        "pno":      r["pno"]      or "",
        "mobile":   r["mobile"]   or "",
        "thana":    r["thana"]    or "",
        "district": r["district"] or "",
        "rank":     r["rank"]     or "",
    } for r in rows])


# ══════════════════════════════════════════════════════════════════════════════
#  6. GET ALL UNASSIGNED STAFF  (initial load for picker)
#     GET /api/admin/booth/staff/unassigned
# ══════════════════════════════════════════════════════════════════════════════

@booth_bp.route("/staff/unassigned", methods=["GET"])
@admin_required
def get_unassigned_staff():
    """
    Returns all unassigned staff for the admin's district.
    Used for the initial load of the staff picker bottom sheet.
    """
    district = request.user.get("district")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            d_clause = "AND u.district = %s" if district else ""
            d_param  = (district,) if district else ()

            cur.execute(f"""
                SELECT
                    u.id,
                    u.name,
                    u.pno,
                    u.mobile,
                    u.thana,
                    u.district,
                    u.user_rank AS rank
                FROM users u
                WHERE u.role = 'staff'
                  AND u.is_active = 1
                  {d_clause}
                  AND NOT EXISTS (
                      SELECT 1 FROM duty_assignments da
                      WHERE da.staff_id = u.id
                  )
                ORDER BY u.name
            """, d_param)
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":       r["id"],
        "name":     r["name"]     or "",
        "pno":      r["pno"]      or "",
        "mobile":   r["mobile"]   or "",
        "thana":    r["thana"]    or "",
        "district": r["district"] or "",
        "rank":     r["rank"]     or "",
    } for r in rows])


# ══════════════════════════════════════════════════════════════════════════════
#  7. BOOTH PAGE STATS  (summary numbers for stat pills)
#     GET /api/admin/booth/stats
# ══════════════════════════════════════════════════════════════════════════════

@booth_bp.route("/stats", methods=["GET"])
@admin_required
def get_booth_stats():
    """
    Returns summary stats for the booth page header:
    total centers, assigned centers, unassigned staff, type breakdown.
    """
    district = request.user.get("district")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Total centers under admin
            cur.execute("""
                SELECT COUNT(DISTINCT ms.id) AS total,
                       SUM(CASE WHEN ms.center_type='A' THEN 1 ELSE 0 END) AS type_a,
                       SUM(CASE WHEN ms.center_type='B' THEN 1 ELSE 0 END) AS type_b,
                       SUM(CASE WHEN ms.center_type='C' THEN 1 ELSE 0 END) AS type_c
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id = %s
            """, (_admin_id(),))
            center_row = cur.fetchone()

            # Centers that have at least 1 duty assigned
            cur.execute("""
                SELECT COUNT(DISTINCT da.sthal_id) AS assigned_centers
                FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id = %s
            """, (_admin_id(),))
            assigned_row = cur.fetchone()

            # Unassigned staff count
            d_clause = "AND district = %s" if district else ""
            d_param  = (district,) if district else ()
            cur.execute(f"""
                SELECT COUNT(*) AS free_staff
                FROM users
                WHERE role = 'staff'
                  AND is_active = 1
                  {d_clause}
                  AND NOT EXISTS (
                      SELECT 1 FROM duty_assignments da
                      WHERE da.staff_id = users.id
                  )
            """, d_param)
            free_row = cur.fetchone()

            # Total staff count
            cur.execute(f"""
                SELECT COUNT(*) AS total_staff
                FROM users
                WHERE role = 'staff' AND is_active = 1 {d_clause}
            """, d_param)
            total_staff_row = cur.fetchone()

    finally:
        conn.close()

    return ok({
        "totalCenters":    center_row["total"]            or 0,
        "assignedCenters": assigned_row["assigned_centers"] or 0,
        "freeStaff":       free_row["free_staff"]         or 0,
        "totalStaff":      total_staff_row["total_staff"] or 0,
        "typeA":           center_row["type_a"]           or 0,
        "typeB":           center_row["type_b"]           or 0,
        "typeC":           center_row["type_c"]           or 0,
    })
