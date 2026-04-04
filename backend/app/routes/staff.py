from flask import Blueprint, request
from db import get_db
from app.routes import ok, err, login_required
from werkzeug.security import check_password_hash, generate_password_hash

staff_bp = Blueprint("staff", __name__, url_prefix="/api/staff")

@staff_bp.route("/my-duty", methods=["GET"])
@login_required
def my_duty():
    staff_id = request.user["id"]
    conn = get_db()

    try:
        with conn.cursor() as cur:

            # ─── MAIN DUTY ───
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

                    gp.id AS gp_id,
                    s.id  AS sector_id,
                    z.id  AS zone_id,
                    sz.id AS super_zone_id,

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

            if not row:
                return ok(None, "No duty assigned yet")

            # ─── ALL STAFF (FIXED rank bug) ───
            cur.execute("""
                SELECT 
                    u.name,
                    u.pno,
                    u.mobile,
                    u.thana,
                    u.district,
                    u.user_rank
                FROM duty_assignments da2
                JOIN users u ON u.id = da2.staff_id
                WHERE da2.sthal_id = %s
                ORDER BY u.name
            """, (row["center_id"],))
            other_staff = cur.fetchall()

            # ─── SECTOR OFFICERS ───
            cur.execute("""
                SELECT 
                    COALESCE(u.name, so.name) AS name,
                    COALESCE(u.pno, so.pno) AS pno,
                    COALESCE(u.mobile, so.mobile) AS mobile,
                    COALESCE(u.user_rank, so.user_rank) AS user_rank
                FROM sector_officers so
                LEFT JOIN users u ON u.id = so.user_id
                WHERE so.sector_id = %s
            """, (row["sector_id"],))
            sector_officers = cur.fetchall()

            # ─── ZONAL OFFICERS ───
            cur.execute("""
                SELECT 
                    COALESCE(u.name, zo.name) AS name,
                    COALESCE(u.pno, zo.pno) AS pno,
                    COALESCE(u.mobile, zo.mobile) AS mobile,
                    COALESCE(u.user_rank, zo.user_rank) AS user_rank
                FROM zonal_officers zo
                LEFT JOIN users u ON u.id = zo.user_id
                WHERE zo.zone_id = %s
            """, (row["zone_id"],))
            zonal_officers = cur.fetchall()

            # ─── SUPER ZONE OFFICERS (kshetra_officers) ───
            cur.execute("""
                SELECT 
                    COALESCE(u.name, ko.name) AS name,
                    COALESCE(u.pno, ko.pno) AS pno,
                    COALESCE(u.mobile, ko.mobile) AS mobile,
                    COALESCE(u.user_rank, ko.user_rank) AS user_rank
                FROM kshetra_officers ko
                LEFT JOIN users u ON u.id = ko.user_id
                WHERE ko.super_zone_id = %s
            """, (row["super_zone_id"],))
            super_officers = cur.fetchall()

    finally:
        conn.close()

    return ok({
        "dutyId": row["duty_id"],
        "busNo": row["bus_no"],
        "centerId": row["center_id"],
        "centerName": row["center_name"],
        "centerAddress": row["center_address"],
        "thana": row["thana"],
        "centerType": row["center_type"],
        "latitude": float(row["latitude"]) if row["latitude"] else None,
        "longitude": float(row["longitude"]) if row["longitude"] else None,

        "gpName": row["gp_name"],
        "gpAddress": row["gp_address"],
        "sectorName": row["sector_name"],
        "zoneName": row["zone_name"],
        "zoneHq": row["zone_hq"],
        "superZoneName": row["super_zone_name"],
        "assignedBy": row["assigned_by_name"],

        "allStaff": other_staff,

        # ✅ FRONTEND FIX
        "sectorOfficers": sector_officers,
        "zonalOfficers": zonal_officers,
        "superOfficers": super_officers,
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
    
@staff_bp.route("/change-password", methods=["POST"])
@login_required
def change_password():
    body = request.get_json() or {}
    current  = body.get("currentPassword", "")
    new_pass = body.get("newPassword", "")
    if len(new_pass) < 6:
        return err("पासवर्ड कम से कम 6 अक्षर का होना चाहिए")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT password FROM users WHERE id=%s", (request.user["id"],))
            row = cur.fetchone()
            if not check_password_hash(row["password"], current):
                return err("वर्तमान पासवर्ड गलत है", 401)
            cur.execute("UPDATE users SET password=%s WHERE id=%s",
                        (generate_password_hash(new_pass), request.user["id"]))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "पासवर्ड बदल दिया गया")