import time
from flask import Blueprint, request
from db import hash_password
from db import get_db
from app.routes import ok, err, write_log, super_admin_required
import jwt
from config import Config

super_admin_bp = Blueprint("super_admin", __name__, url_prefix="/api/super")

def _district():
    return (request.user.get("district") or "").strip()


# ══════════════════════════════════════════════════════════════
#  1. GET ALL ADMINS    GET /super/admins
# ══════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins", methods=["GET"])
@super_admin_required
def get_admins():

    district = _district()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    u.id, u.name, u.username, u.district,
                    u.is_active, u.created_at,
                    (SELECT COUNT(*) FROM matdan_sthal ms
                     JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                     JOIN sectors s ON s.id = gp.sector_id
                     JOIN zones z ON z.id = s.zone_id
                     JOIN super_zones sz ON sz.id = z.super_zone_id
                     WHERE sz.admin_id = u.id
                    ) AS total_booths,
                    (SELECT COUNT(*) FROM duty_assignments da
                     JOIN matdan_sthal ms2 ON ms2.id = da.sthal_id
                     JOIN gram_panchayats gp2 ON gp2.id = ms2.gram_panchayat_id
                     JOIN sectors s2 ON s2.id = gp2.sector_id
                     JOIN zones z2 ON z2.id = s2.zone_id
                     JOIN super_zones sz2 ON sz2.id = z2.super_zone_id
                     WHERE sz2.admin_id = u.id
                    ) AS assigned_staff
                FROM users u
                WHERE u.role = 'admin'
                AND TRIM(LOWER(u.district)) = TRIM(LOWER(%s))
                ORDER BY u.created_at DESC
            """, (district,))
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id": r["id"],
        "name": r["name"],
        "username": r["username"],
        "district": r["district"],
        "isActive": bool(r["is_active"]),
        "createdAt": r["created_at"],
        "totalBooths": r["total_booths"] or 0,
        "assignedStaff": r["assigned_staff"] or 0,
    } for r in rows])



# ══════════════════════════════════════════════════════════════
#  2. CREATE ADMIN      POST /super/admins
# ══════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins", methods=["POST"])
@super_admin_required
def create_admin():

    body = request.get_json() or {}

    district = _district()

    if body.get("district") != district:
        return err("Cannot create admin for another district", 403)

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("SELECT id FROM users WHERE username=%s", (body["username"],))
            if cur.fetchone():
                return err("Username exists")

            cur.execute("""
                INSERT INTO users (name, username, password, role, district, is_active, created_by)
                VALUES (%s,%s,%s,'admin',%s,1,%s)
            """, (
                body["name"],
                body["username"],
                hash_password(body["password"]),
                district,
                request.user["id"]
            ))

        conn.commit()
    finally:
        conn.close()

    return ok(None, "Admin created")


# ══════════════════════════════════════════════════════════════
#  3. DELETE ADMIN      DELETE /super/admins/<id>
# ══════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/<int:admin_id>", methods=["DELETE"])
@super_admin_required
def delete_admin(admin_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT name FROM users WHERE id = %s AND role = 'admin'", (admin_id,))
            row = cur.fetchone()
            if not row:
                return err("Admin not found", 404)
            cur.execute("DELETE FROM users WHERE id = %s", (admin_id,))
        conn.commit()
    finally:
        conn.close()
    write_log("WARN", f"Admin '{row['name']}' (ID:{admin_id}) deleted", "Auth")
    return ok(None, f"Admin '{row['name']}' deleted")


# ══════════════════════════════════════════════════════════════
#  4. OVERVIEW STATS    GET /super/overview
# ══════════════════════════════════════════════════════════════
@super_admin_bp.route("/overview", methods=["GET"])
@super_admin_required
def overview():

    district = _district()

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT COUNT(*) AS cnt FROM users
                WHERE role='admin' AND district=%s
            """, (district,))
            admins = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT COUNT(DISTINCT ms.id) AS cnt
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
                JOIN sectors s ON s.id=gp.sector_id
                JOIN zones z ON z.id=s.zone_id
                JOIN super_zones sz ON sz.id=z.super_zone_id
                WHERE sz.district=%s
            """, (district,))
            booths = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT COUNT(*) AS cnt
                FROM duty_assignments da
                JOIN matdan_sthal ms ON ms.id=da.sthal_id
                JOIN gram_panchayats gp ON gp.id=ms.gram_panchayat_id
                JOIN sectors s ON s.id=gp.sector_id
                JOIN zones z ON z.id=s.zone_id
                JOIN super_zones sz ON sz.id=z.super_zone_id
                WHERE sz.district=%s
            """, (district,))
            duties = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT COUNT(*) AS cnt
                FROM users
                WHERE role='staff' AND district=%s
            """, (district,))
            staff = cur.fetchone()["cnt"]

    finally:
        conn.close()

    return ok({
        "totalAdmins": admins,
        "totalBooths": booths,
        "assignedDuties": duties,
        "totalStaff": staff
    })



    
# ══════════════════════════════════════════════════════════════
#  6. GET SINGLE ADMIN   GET /super/admins/<id>
# ══════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/<int:admin_id>", methods=["GET"])
@super_admin_required
def get_single_admin(admin_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, name, username, district, is_active, created_at
                FROM users
                WHERE id = %s AND role = 'admin'
            """, (admin_id,))
            row = cur.fetchone()

            if not row:
                return err("Admin not found", 404)

    finally:
        conn.close()

    return ok({
        "id": row["id"],
        "name": row["name"],
        "username": row["username"],
        "district": row["district"],
        "isActive": bool(row["is_active"]),
        "createdAt": row["created_at"].isoformat() if row["created_at"] else None
    })


# ══════════════════════════════════════════════════════════════
#  7. UPDATE ADMIN       PUT /super/admins/<id>
# ══════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/<int:admin_id>", methods=["PUT"])
@super_admin_required
def update_admin(admin_id):
    body = request.get_json() or {}

    name     = body.get("name", "").strip()
    username = body.get("username", "").strip()
    district = body.get("district", "").strip()

    if not name or not username or not district:
        return err("name, username, district required")

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # check exists
            cur.execute("SELECT id FROM users WHERE id=%s AND role='admin'", (admin_id,))
            if not cur.fetchone():
                return err("Admin not found", 404)

            # username unique check
            cur.execute("SELECT id FROM users WHERE username=%s AND id!=%s", (username, admin_id))
            if cur.fetchone():
                return err("Username already taken", 409)

            cur.execute("""
                UPDATE users
                SET name=%s, username=%s, district=%s
                WHERE id=%s
            """, (name, username, district, admin_id))

        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Admin updated ID:{admin_id}", "Auth")

    return ok(None, "Admin updated successfully")


# ══════════════════════════════════════════════════════════════
#  8. TOGGLE ACTIVE      PATCH /super/admins/<id>/toggle
# ══════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/<int:admin_id>/toggle", methods=["PATCH"])
@super_admin_required
def toggle_admin(admin_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT is_active FROM users
                WHERE id=%s AND role='admin'
            """, (admin_id,))
            row = cur.fetchone()

            if not row:
                return err("Admin not found", 404)

            new_status = 0 if row["is_active"] else 1

            cur.execute("""
                UPDATE users
                SET is_active=%s
                WHERE id=%s
            """, (new_status, admin_id))

        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Admin status toggled ID:{admin_id} -> {new_status}", "Auth")

    return ok({
        "isActive": bool(new_status)
    }, "Status updated")


# ══════════════════════════════════════════════════════════════
#  9. RESET PASSWORD     PATCH /super/admins/<id>/reset-password
# ══════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/<int:admin_id>/reset-password", methods=["PATCH"])
@super_admin_required
def reset_password(admin_id):
    body = request.get_json() or {}
    password = body.get("password", "")

    if len(password) < 6:
        return err("Password must be at least 6 characters")

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("SELECT id FROM users WHERE id=%s AND role='admin'", (admin_id,))
            if not cur.fetchone():
                return err("Admin not found", 404)

            cur.execute("""
                UPDATE users
                SET password=%s
                WHERE id=%s
            """, (hash_password(password), admin_id))

        conn.commit()
    finally:
        conn.close()

    write_log("WARN", f"Password reset for admin ID:{admin_id}", "Auth")

    return ok(None, "Password reset successful")


# ══════════════════════════════════════════════════════════════
# 10. BULK DELETE        DELETE /super/admins/bulk
# ══════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/bulk", methods=["DELETE"])
@super_admin_required
def bulk_delete_admins():
    body = request.get_json() or {}
    ids = body.get("ids", [])

    if not ids or not isinstance(ids, list):
        return err("ids list required")

    conn = get_db()
    try:
        with conn.cursor() as cur:

            format_strings = ','.join(['%s'] * len(ids))

            cur.execute(f"""
                DELETE FROM users
                WHERE id IN ({format_strings}) AND role='admin'
            """, ids)

        conn.commit()
    finally:
        conn.close()

    write_log("WARN", f"Bulk delete admins: {ids}", "Auth")

    return ok(None, "Admins deleted successfully")

# ══════════════════════════════════════════════════════════════
# 11. FORM DATA SUMMARY   GET /super/form-data
# ══════════════════════════════════════════════════════════════
@super_admin_bp.route("/form-data", methods=["GET"])
@super_admin_required
def get_form_data():

    district = _district()

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT 
                    u.id AS adminId,
                    u.name AS adminName,
                    u.district,

                    COUNT(DISTINCT sz.id) AS superZones,
                    COUNT(DISTINCT z.id) AS zones,
                    COUNT(DISTINCT s.id) AS sectors,
                    COUNT(DISTINCT gp.id) AS gramPanchayats,
                    COUNT(DISTINCT ms.id) AS centers

                FROM users u
                LEFT JOIN super_zones sz ON sz.admin_id = u.id
                LEFT JOIN zones z ON z.super_zone_id = sz.id
                LEFT JOIN sectors s ON s.zone_id = z.id
                LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
                LEFT JOIN matdan_sthal ms ON ms.gram_panchayat_id = gp.id

                WHERE u.role='admin'
                AND TRIM(LOWER(u.district)) = TRIM(LOWER(%s))

                GROUP BY u.id
                ORDER BY u.id DESC
            """, (district,))

            rows = cur.fetchall()

    finally:
        conn.close()

    return ok(rows)

@super_admin_bp.route("/unlock-requests", methods=["GET"])
@super_admin_required
def get_unlock_requests():

    district = _district()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT r.*, sz.name AS super_zone_name, u.name AS admin_name
                FROM sz_unlock_requests r
                JOIN super_zones sz ON sz.id = r.super_zone_id
                JOIN users u ON u.id = r.requested_by
                WHERE sz.district=%s
                ORDER BY r.created_at DESC
            """, (district,))

            rows = cur.fetchall()
    finally:
        conn.close()

    return ok(rows)


@super_admin_bp.route("/unlock-requests/<int:req_id>/action", methods=["POST"])
@super_admin_required
def handle_unlock_request(req_id):

    body = request.get_json() or {}
    action = body.get("action")

    if action not in ["approve", "reject"]:
        return err("Invalid action")

    conn = get_db()
    try:
        with conn.cursor() as cur:

            cur.execute("""
                SELECT * FROM sz_unlock_requests
                WHERE id=%s AND status='pending'
            """, (req_id,))
            req = cur.fetchone()

            if not req:
                return err("Request not found")

            if action == "approve":

                # 🔓 UNLOCK
                cur.execute("""
                    UPDATE sz_duty_locks
                    SET is_locked=0, status='unlocked'
                    WHERE super_zone_id=%s
                """, (req["super_zone_id"],))

                new_status = "approved"

            else:
                new_status = "rejected"

                # 🔁 revert status
                cur.execute("""
                    UPDATE sz_duty_locks
                    SET status='locked'
                    WHERE super_zone_id=%s
                """, (req["super_zone_id"],))

            cur.execute("""
                UPDATE sz_unlock_requests
                SET status=%s, reviewed_by=%s
                WHERE id=%s
            """, (new_status, request.user["id"], req_id))

        conn.commit()
    finally:
        conn.close()

    return ok(None, f"Request {new_status}")

