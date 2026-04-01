from flask import Blueprint, request
from db import get_db
from app.routes import ok, err, login_required

staff_bp = Blueprint("staff", __name__, url_prefix="/api/staff")


@staff_bp.route("/my-duty", methods=["GET"])
@login_required
def my_duty():
    staff_id = request.user["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    da.id AS duty_id,
                    da.bus_no,
                    ms.id AS center_id,
                    ms.name AS center_name,
                    ms.address AS center_address,
                    ms.thana,
                    ms.center_type,
                    ms.latitude,
                    ms.longitude,
                    gp.name  AS gp_name,
                    gp.address AS gp_address,
                    s.name   AS sector_name,
                    z.name   AS zone_name,
                    z.hq_address AS zone_hq,
                    sz.name  AS super_zone_name,
                    u2.name  AS assigned_by_name
                FROM duty_assignments da
                JOIN matdan_sthal ms      ON ms.id = da.sthal_id
                JOIN gram_panchayats gp   ON gp.id = ms.gram_panchayat_id
                JOIN sectors s            ON s.id  = gp.sector_id
                JOIN zones z              ON z.id  = s.zone_id
                JOIN super_zones sz       ON sz.id = z.super_zone_id
                LEFT JOIN users u2        ON u2.id = da.assigned_by
                WHERE da.staff_id = %s
            """, (staff_id,))
            row = cur.fetchone()

            # All staff at the same center
            other_staff = []
            if row:
                cur.execute("""
                    SELECT u.name, u.pno, u.mobile, u.thana
                    FROM duty_assignments da2
                    JOIN users u ON u.id = da2.staff_id
                    WHERE da2.sthal_id = %s
                    ORDER BY u.name
                """, (row["center_id"],))
                other_staff = cur.fetchall()
    finally:
        conn.close()

    if not row:
        return ok(None, "No duty assigned yet")

    return ok({
        "dutyId":        row["duty_id"],
        "busNo":         row["bus_no"],
        "centerId":      row["center_id"],
        "centerName":    row["center_name"],
        "centerAddress": row["center_address"],
        "thana":         row["thana"],
        "centerType":    row["center_type"],
        "latitude":      float(row["latitude"])  if row["latitude"]  else None,
        "longitude":     float(row["longitude"]) if row["longitude"] else None,
        "gpName":        row["gp_name"],
        "gpAddress":     row["gp_address"],
        "sectorName":    row["sector_name"],
        "zoneName":      row["zone_name"],
        "zoneHq":        row["zone_hq"],
        "superZoneName": row["super_zone_name"],
        "assignedBy":    row["assigned_by_name"],
        "allStaff": [{
            "name":   s["name"],
            "pno":    s["pno"],
            "mobile": s["mobile"],
            "thana":  s["thana"],
        } for s in other_staff],
    })


@staff_bp.route("/profile", methods=["GET"])
@login_required
def my_profile():
    staff_id = request.user["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, name, pno, mobile, thana, district, is_active
                FROM users WHERE id = %s
            """, (staff_id,))
            row = cur.fetchone()
    finally:
        conn.close()
    if not row:
        return err("User not found", 404)
    return ok({
        "id":       row["id"],
        "name":     row["name"],
        "pno":      row["pno"],
        "mobile":   row["mobile"],
        "thana":    row["thana"],
        "district": row["district"],
        "isActive": bool(row["is_active"]),
    })