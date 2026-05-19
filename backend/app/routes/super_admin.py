import time
from urllib.parse import unquote          # ← NEW: decode URI-encoded district header
from flask import Blueprint, request
from db import hash_password
from db import get_db
from app.routes import (
    ok, err, write_log,
    super_admin_required,
    super_or_multi_required,
    resolve_active_district,
)
import jwt
from config import Config
import traceback

super_admin_bp = Blueprint("super_admin", __name__, url_prefix="/api/super")


# ──────────────────────────────────────────────────────────────────────────────
#  DISTRICT RESOLVER
#  Returns (district_string, error_response_or_None).
#
#  FIX: The Flutter client URI-encodes the district name before putting it in
#  the X-Active-District header (RFC-7230 requires ASCII-only header values).
#  e.g. "बागपत" → "%E0%A4%AC%E0%A4%BE%E0%A4%97%E0%A4%AA%E0%A4%A4"
#
#  We must unquote() it here, PLUS accept the district as a ?district= query
#  param as a belt-and-suspenders fallback.
#
#  Also handles the case where resolve_active_district() itself raises, which
#  was the root cause of the 500 errors seen in the screenshots.
# ──────────────────────────────────────────────────────────────────────────────
def _district():
    """
    Resolves the active district for this request.
    Returns (district: str, error_response: Flask response | None).

    Priority order:
      1. X-Active-District header  (URI-decoded)
      2. ?district= query param    (URI-decoded by Flask automatically)
      3. JWT 'district' claim      (for plain super_admin only)

    For super_admin   → JWT district (steps 1-2 are ignored / override allowed).
    For multi_super   → header or query param is REQUIRED.
    For master        → header or query param (no validation against assignments).
    """
    role = (getattr(request, 'user', {}).get('role') or '').lower()

    # ── Step 1: Try resolve_active_district() (uses header) ──────────────────
    district = None
    try:
        d, error = resolve_active_district()
        if not error and d:
            # URI-decode in case resolve_active_district() doesn't do it
            district = unquote((d or '').strip())
    except Exception:
        # resolve_active_district() raised — fall through to manual resolution
        district = None

    # ── Step 2: Manual header read with URI-decode ────────────────────────────
    if not district:
        raw_header = (request.headers.get('X-Active-District') or '').strip()
        if raw_header:
            district = unquote(raw_header)

    # ── Step 3: ?district= query param fallback ───────────────────────────────
    if not district:
        raw_param = (request.args.get('district') or '').strip()
        if raw_param:
            district = unquote(raw_param)   # Flask already URL-decodes, but be safe

    # ── Step 4: JWT district (only valid for super_admin) ─────────────────────
    if not district and role == 'super_admin':
        district = (getattr(request, 'user', {}).get('district') or '').strip()

    district = (district or '').strip()

    if not district:
        if role == 'multi_super_admin':
            return None, err(
                "District context required for multi_super_admin. "
                "Send X-Active-District header or ?district= query param.",
                400,
            )
        if role == 'master':
            return None, err(
                "District context required. "
                "Send X-Active-District header or ?district= query param.",
                400,
            )
        return None, err(
            "District context required. "
            "Send X-Active-District header or check your token.",
            400,
        )

    # ── Step 5: For multi_super_admin — verify assignment ─────────────────────
    #    (master is trusted to access any district)
    if role == 'multi_super_admin':
        uid = getattr(request, 'user', {}).get('id')
        if uid:
            try:
                conn = get_db()
                try:
                    with conn.cursor() as cur:
                        cur.execute(
                            "SELECT 1 FROM user_districts "
                            "WHERE user_id = %s "
                            "  AND TRIM(LOWER(district)) = TRIM(LOWER(%s))",
                            (uid, district),
                        )
                        if not cur.fetchone():
                            return None, err(
                                f"District '{district}' is not assigned to this user.",
                                403,
                            )
                finally:
                    conn.close()
            except Exception as e:
                # DB error during assignment check — fail closed with a clear message
                return None, err(
                    f"Could not verify district assignment: {e}", 500
                )

    return district, None


# ══════════════════════════════════════════════════════════════════════════════
#  PROFILE    GET /api/super/profile
#  Used by SuperDashboard._loadIdentity() for ALL roles (super_admin,
#  multi_super_admin, master). Returns the caller's profile + resolved district.
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/profile", methods=["GET"])
@super_or_multi_required
def get_profile():
    uid  = request.user.get("id")
    role = (request.user.get("role") or "").lower()

    # Resolve district — for profile we gracefully fall back to JWT district
    # rather than returning a 400, so the dashboard header always shows something.
    district, resp = _district()
    if resp:
        # Graceful degradation: use JWT district instead of failing
        district = (request.user.get("district") or "").strip()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, name, username, district, role, is_active
                FROM users WHERE id = %s
            """, (uid,))
            row = cur.fetchone()
    finally:
        conn.close()

    if not row:
        return err("User not found", 404)

    # For multi_super_admin the "active district" is from the header,
    # not from their own user record (which may be blank or a home district).
    active_district = district or row.get("district") or ""

    return ok({
        "id":          row["id"],
        "name":        row["name"]     or "",
        "username":    row["username"] or "",
        "district":    active_district,
        "ownDistrict": row["district"] or "",
        "role":        row["role"]     or "",
        "isActive":    bool(row["is_active"]),
    })


# ══════════════════════════════════════════════════════════════════════════════
#  1. GET ALL ADMINS    GET /api/super/admins
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins", methods=["GET"])
@super_or_multi_required
def get_admins():
    district, resp = _district()
    if resp:
        return resp

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Fetch admins + booth/staff counts
            cur.execute("""
                SELECT
                    u.id, u.name, u.username, u.district,
                    u.is_active, u.created_at,
                    COUNT(DISTINCT ms.id)  AS total_booths,
                    COUNT(DISTINCT da.id)  AS assigned_staff
                FROM users u
                LEFT JOIN super_zones sz ON sz.admin_id = u.id
                LEFT JOIN zones z        ON z.super_zone_id  = sz.id
                LEFT JOIN sectors s      ON s.zone_id        = z.id
                LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
                LEFT JOIN matdan_sthal ms    ON ms.gram_panchayat_id = gp.id
                LEFT JOIN duty_assignments da ON da.sthal_id = ms.id
                WHERE u.role = 'admin'
                  AND TRIM(LOWER(u.district)) = TRIM(LOWER(%s))
                GROUP BY u.id
                ORDER BY u.created_at DESC
            """, (district,))
            rows = cur.fetchall()
            admin_ids = [r["id"] for r in rows]

            # Election status per admin
            election_map = {}
            if admin_ids:
                ph = ",".join(["%s"] * len(admin_ids))
                cur.execute(f"""
                    SELECT
                        ec.id                 AS election_id,
                        ec.election_name,
                        ec.election_date,
                        ec.is_active,
                        ec.is_finalized,
                        ec.auto_finalized,
                        sz2.admin_id
                    FROM election_configs ec
                    JOIN super_zones sz2
                        ON TRIM(LOWER(sz2.district)) = TRIM(LOWER(ec.district))
                    WHERE sz2.admin_id IN ({ph})
                      AND ec.is_archived = 0
                    ORDER BY ec.is_active DESC, ec.id DESC
                """, admin_ids)
                for row in cur.fetchall():
                    aid = row["admin_id"]
                    if aid not in election_map:
                        election_map[aid] = row

            # Booth duty progress per admin
            duty_map = {}
            if admin_ids:
                ph = ",".join(["%s"] * len(admin_ids))
                cur.execute(f"""
                    SELECT
                        sz3.admin_id,
                        COUNT(DISTINCT ms2.id) AS total,
                        COUNT(DISTINCT da2.id) AS assigned
                    FROM super_zones sz3
                    LEFT JOIN zones z3   ON z3.super_zone_id     = sz3.id
                    LEFT JOIN sectors s3 ON s3.zone_id           = z3.id
                    LEFT JOIN gram_panchayats gp3 ON gp3.sector_id = s3.id
                    LEFT JOIN matdan_sthal ms2  ON ms2.gram_panchayat_id = gp3.id
                    LEFT JOIN duty_assignments da2 ON da2.sthal_id = ms2.id
                    WHERE sz3.admin_id IN ({ph})
                    GROUP BY sz3.admin_id
                """, admin_ids)
                for row in cur.fetchall():
                    duty_map[row["admin_id"]] = {
                        "total":    row["total"]    or 0,
                        "assigned": row["assigned"] or 0,
                    }

    finally:
        conn.close()

    result = []
    for r in rows:
        aid = r["id"]
        ec  = election_map.get(aid)
        dp  = duty_map.get(aid, {"total": 0, "assigned": 0})

        is_finalized = False
        elec_name    = None
        if ec:
            is_finalized = bool(ec.get("is_finalized")) or bool(ec.get("auto_finalized"))
            elec_name    = ec.get("election_name") or None

        result.append({
            "id":                  r["id"],
            "name":                r["name"]     or "",
            "username":            r["username"] or "",
            "district":            r["district"] or "",
            "isActive":            bool(r["is_active"]),
            "createdAt":           str(r["created_at"]) if r["created_at"] else "",
            "totalBooths":         r["total_booths"]   or 0,
            "assignedStaff":       r["assigned_staff"] or 0,
            "activeElectionName":  elec_name,
            "isElectionFinalized": is_finalized,
            "boothDutyProgress":   dp,
        })

    return ok(result)


# ══════════════════════════════════════════════════════════════════════════════
#  2. CREATE ADMIN      POST /api/super/admins
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins", methods=["POST"])
@super_or_multi_required
def create_admin():
    district, resp = _district()
    if resp:
        return resp

    body = request.get_json() or {}

    # Enforce district scope — cannot create for another district
    requested_district = (body.get("district") or "").strip()
    if requested_district and requested_district.lower() != district.lower():
        return err("Cannot create admin for a different district", 403)

    name     = (body.get("name")     or "").strip()
    username = (body.get("username") or "").strip()
    password =  body.get("password") or ""

    if not name or not username or not password:
        return err("name, username, password required")
    if len(password) < 6:
        return err("Password must be at least 6 characters")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE username = %s", (username,))
            if cur.fetchone():
                return err("Username already exists", 409)

            cur.execute("""
                INSERT INTO users
                    (name, username, password, role, district, is_active, created_by)
                VALUES (%s, %s, %s, 'admin', %s, 1, %s)
            """, (
                name, username, hash_password(password),
                district, request.user["id"],
            ))
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Admin '{name}' created in district '{district}'", "Auth")
    return ok(None, "Admin created")


# ══════════════════════════════════════════════════════════════════════════════
#  3. DELETE ADMIN      DELETE /api/super/admins/<id>
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/<int:admin_id>", methods=["DELETE"])
@super_or_multi_required
def delete_admin(admin_id):
    district, resp = _district()
    if resp:
        return resp

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT name, district FROM users WHERE id = %s AND role = 'admin'",
                (admin_id,))
            row = cur.fetchone()
            if not row:
                return err("Admin not found", 404)
            if row["district"].lower() != district.lower():
                return err("Cannot delete admin from another district", 403)
            cur.execute("DELETE FROM users WHERE id = %s", (admin_id,))
        conn.commit()
    finally:
        conn.close()

    write_log("WARN", f"Admin '{row['name']}' (ID:{admin_id}) deleted", "Auth")
    return ok(None, f"Admin '{row['name']}' deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  4. OVERVIEW STATS    GET /api/super/overview
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/overview", methods=["GET"])
@super_or_multi_required
def overview():
    district, resp = _district()
    if resp:
        return resp

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT COUNT(*) AS cnt FROM users
                WHERE LOWER(role) = 'admin'
                  AND TRIM(LOWER(district)) = TRIM(LOWER(%s))
                  AND is_active = 1
            """, (district,))
            admin_count = (cur.fetchone() or {}).get("cnt", 0)

            cur.execute("""
                SELECT COUNT(DISTINCT ms.id) AS cnt
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id  = ms.gram_panchayat_id
                JOIN sectors s          ON s.id   = gp.sector_id
                JOIN zones z            ON z.id   = s.zone_id
                JOIN super_zones sz     ON sz.id  = z.super_zone_id
                WHERE TRIM(LOWER(sz.district)) = TRIM(LOWER(%s))
            """, (district,))
            total_booths = (cur.fetchone() or {}).get("cnt", 0)

            cur.execute("""
                SELECT COUNT(DISTINCT da.id) AS cnt
                FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id  = da.sthal_id
                JOIN gram_panchayats gp ON gp.id  = ms.gram_panchayat_id
                JOIN sectors s          ON s.id   = gp.sector_id
                JOIN zones z            ON z.id   = s.zone_id
                JOIN super_zones sz     ON sz.id  = z.super_zone_id
                WHERE TRIM(LOWER(sz.district)) = TRIM(LOWER(%s))
            """, (district,))
            assigned_duties = (cur.fetchone() or {}).get("cnt", 0)

            cur.execute("""
                SELECT COUNT(*) AS cnt FROM users
                WHERE LOWER(role) = 'staff'
                  AND TRIM(LOWER(district)) = TRIM(LOWER(%s))
            """, (district,))
            total_staff = (cur.fetchone() or {}).get("cnt", 0)

            # Active election for this district
            cur.execute("""
                SELECT election_name, election_date, is_finalized, auto_finalized
                FROM election_configs
                WHERE TRIM(LOWER(district)) = TRIM(LOWER(%s))
                  AND is_active = 1
                  AND is_archived = 0
                ORDER BY id DESC LIMIT 1
            """, (district,))
            ec = cur.fetchone()

    finally:
        conn.close()

    return ok({
        "totalAdmins":    int(admin_count     or 0),
        "totalBooths":    int(total_booths    or 0),
        "assignedDuties": int(assigned_duties or 0),
        "totalStaff":     int(total_staff     or 0),
        "activeElection": {
            "name":        ec["election_name"] if ec else None,
            "date":        str(ec["election_date"]) if ec and ec["election_date"] else None,
            "isFinalized": bool(
                ec.get("is_finalized") or ec.get("auto_finalized")
            ) if ec else False,
        } if ec else None,
    })


# ══════════════════════════════════════════════════════════════════════════════
#  6. GET SINGLE ADMIN   GET /api/super/admins/<id>
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/<int:admin_id>", methods=["GET"])
@super_or_multi_required
def get_single_admin(admin_id):
    district, resp = _district()
    if resp:
        return resp

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
            if row["district"].strip().lower() != district.lower():
                return err("Admin not in your district", 403)
    finally:
        conn.close()

    return ok({
        "id":        row["id"],
        "name":      row["name"]     or "",
        "username":  row["username"] or "",
        "district":  row["district"] or "",
        "isActive":  bool(row["is_active"]),
        "createdAt": row["created_at"].isoformat() if row["created_at"] else None,
    })


# ══════════════════════════════════════════════════════════════════════════════
#  7. UPDATE ADMIN       PUT /api/super/admins/<id>
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/<int:admin_id>", methods=["PUT"])
@super_or_multi_required
def update_admin(admin_id):
    district, resp = _district()
    if resp:
        return resp

    body     = request.get_json() or {}
    name     = (body.get("name")     or "").strip()
    username = (body.get("username") or "").strip()

    if not name or not username:
        return err("name and username required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT district FROM users WHERE id = %s AND role = 'admin'",
                (admin_id,))
            row = cur.fetchone()
            if not row:
                return err("Admin not found", 404)
            if row["district"].strip().lower() != district.lower():
                return err("Admin not in your district", 403)

            cur.execute(
                "SELECT id FROM users WHERE username = %s AND id != %s",
                (username, admin_id))
            if cur.fetchone():
                return err("Username already taken", 409)

            cur.execute(
                "UPDATE users SET name = %s, username = %s WHERE id = %s",
                (name, username, admin_id))
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Admin updated ID:{admin_id}", "Auth")
    return ok(None, "Admin updated successfully")


# ══════════════════════════════════════════════════════════════════════════════
#  8. TOGGLE ACTIVE      PATCH /api/super/admins/<id>/toggle
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/<int:admin_id>/toggle", methods=["PATCH"])
@super_or_multi_required
def toggle_admin(admin_id):
    district, resp = _district()
    if resp:
        return resp

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT is_active, district FROM users WHERE id = %s AND role = 'admin'",
                (admin_id,))
            row = cur.fetchone()
            if not row:
                return err("Admin not found", 404)
            if row["district"].strip().lower() != district.lower():
                return err("Admin not in your district", 403)

            new_status = 0 if row["is_active"] else 1
            cur.execute(
                "UPDATE users SET is_active = %s WHERE id = %s",
                (new_status, admin_id))
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Admin status toggled ID:{admin_id} -> {new_status}", "Auth")
    return ok({"isActive": bool(new_status)}, "Status updated")


# ══════════════════════════════════════════════════════════════════════════════
#  9. RESET PASSWORD     PATCH /api/super/admins/<id>/reset-password
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/<int:admin_id>/reset-password", methods=["PATCH"])
@super_or_multi_required
def reset_password(admin_id):
    district, resp = _district()
    if resp:
        return resp

    body     = request.get_json() or {}
    password = body.get("password", "")
    if len(password) < 6:
        return err("Password must be at least 6 characters")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT district FROM users WHERE id = %s AND role = 'admin'",
                (admin_id,))
            row = cur.fetchone()
            if not row:
                return err("Admin not found", 404)
            if row["district"].strip().lower() != district.lower():
                return err("Admin not in your district", 403)

            cur.execute(
                "UPDATE users SET password = %s WHERE id = %s",
                (hash_password(password), admin_id))
        conn.commit()
    finally:
        conn.close()

    write_log("WARN", f"Password reset for admin ID:{admin_id}", "Auth")
    return ok(None, "Password reset successful")


# ══════════════════════════════════════════════════════════════════════════════
# 10. BULK DELETE        DELETE /api/super/admins/bulk
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/admins/bulk", methods=["DELETE"])
@super_or_multi_required
def bulk_delete_admins():
    district, resp = _district()
    if resp:
        return resp

    body = request.get_json() or {}
    ids  = body.get("ids", [])
    if not ids or not isinstance(ids, list):
        return err("ids list required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            ph = ",".join(["%s"] * len(ids))
            cur.execute(
                f"DELETE FROM users "
                f"WHERE id IN ({ph}) AND role='admin' "
                f"AND TRIM(LOWER(district)) = TRIM(LOWER(%s))",
                ids + [district])
        conn.commit()
    finally:
        conn.close()

    write_log("WARN", f"Bulk delete admins: {ids} in {district}", "Auth")
    return ok(None, "Admins deleted successfully")


# ══════════════════════════════════════════════════════════════════════════════
# 11. FORM DATA SUMMARY   GET /api/super/form-data
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/form-data", methods=["GET"])
@super_or_multi_required
def get_form_data():

    try:
        # Resolve active district
        district, resp = _district()

        if resp:
            return resp

        conn = get_db()

        try:
            with conn.cursor() as cur:

                cur.execute("""
                    SELECT
                        u.id        AS adminId,
                        u.name      AS adminName,
                        u.district  AS district,

                        COUNT(DISTINCT sz.id) AS superZones,
                        COUNT(DISTINCT z.id)  AS zones,
                        COUNT(DISTINCT s.id)  AS sectors,
                        COUNT(DISTINCT gp.id) AS gramPanchayats,
                        COUNT(DISTINCT ms.id) AS centers

                    FROM users u

                    LEFT JOIN super_zones sz
                        ON sz.admin_id = u.id

                    LEFT JOIN zones z
                        ON z.super_zone_id = sz.id

                    LEFT JOIN sectors s
                        ON s.zone_id = z.id

                    LEFT JOIN gram_panchayats gp
                        ON gp.sector_id = s.id

                    LEFT JOIN matdan_sthal ms
                        ON ms.gram_panchayat_id = gp.id

                    WHERE LOWER(u.role) = 'admin'
                      AND TRIM(LOWER(u.district)) =
                          TRIM(LOWER(%s))

                    GROUP BY
                        u.id,
                        u.name,
                        u.district

                    ORDER BY u.id DESC
                """, (district,))

                rows = cur.fetchall()

        finally:
            conn.close()

        result = []

        for r in rows:

            result.append({
                "adminId":        r.get("adminId"),
                "adminName":      r.get("adminName") or "",
                "district":       r.get("district") or "",

                "superZones":     int(r.get("superZones") or 0),
                "zones":          int(r.get("zones") or 0),
                "sectors":        int(r.get("sectors") or 0),
                "gramPanchayats": int(r.get("gramPanchayats") or 0),
                "centers":        int(r.get("centers") or 0),
            })

        return ok(result)

    except Exception as e:

        print("\n========= FORM DATA ERROR =========")
        traceback.print_exc()
        print("===================================\n")

        return err(str(e), 500)
    
# ══════════════════════════════════════════════════════════════════════════════
# 12. UNLOCK REQUESTS    GET /api/super/unlock-requests
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/unlock-requests", methods=["GET"])
@super_or_multi_required
def get_unlock_requests():
    district, resp = _district()
    if resp:
        return resp

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Try to include election_name — gracefully degrade if column missing
            try:
                cur.execute("""
                    SELECT
                        r.id, r.super_zone_id, r.reason, r.status, r.created_at,
                        sz.name AS super_zone_name,
                        u.name  AS admin_name,
                        COALESCE(ec.election_name, '') AS electionName
                    FROM sz_unlock_requests r
                    JOIN super_zones sz ON sz.id = r.super_zone_id
                    JOIN users u        ON u.id  = r.requested_by
                    LEFT JOIN election_configs ec
                        ON TRIM(LOWER(ec.district)) = TRIM(LOWER(sz.district))
                        AND ec.is_active  = 1
                        AND ec.is_archived = 0
                    WHERE TRIM(LOWER(sz.district)) = TRIM(LOWER(%s))
                    ORDER BY r.created_at DESC
                """, (district,))
            except Exception:
                # Fallback without election join
                cur.execute("""
                    SELECT
                        r.id, r.super_zone_id, r.reason, r.status, r.created_at,
                        sz.name AS super_zone_name,
                        u.name  AS admin_name,
                        ''      AS electionName
                    FROM sz_unlock_requests r
                    JOIN super_zones sz ON sz.id = r.super_zone_id
                    JOIN users u        ON u.id  = r.requested_by
                    WHERE TRIM(LOWER(sz.district)) = TRIM(LOWER(%s))
                    ORDER BY r.created_at DESC
                """, (district,))
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":              r["id"],
        "super_zone_id":   r["super_zone_id"],
        "super_zone_name": r["super_zone_name"] or "",
        "admin_name":      r["admin_name"]      or "",
        "reason":          r["reason"]          or "",
        "status":          r["status"]          or "pending",
        "created_at":      str(r["created_at"]) if r["created_at"] else "",
        "electionName":    r.get("electionName") or "",
    } for r in rows])


# ══════════════════════════════════════════════════════════════════════════════
# 13. HANDLE UNLOCK REQUEST  POST /api/super/unlock-requests/<id>/action
# ══════════════════════════════════════════════════════════════════════════════
@super_admin_bp.route("/unlock-requests/<int:req_id>/action", methods=["POST"])
@super_or_multi_required
def handle_unlock_request(req_id):
    district, resp = _district()
    if resp:
        return resp

    body   = request.get_json() or {}
    action = body.get("action")
    if action not in ("approve", "reject"):
        return err("action must be 'approve' or 'reject'")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT r.*, sz.district AS sz_district
                FROM sz_unlock_requests r
                JOIN super_zones sz ON sz.id = r.super_zone_id
                WHERE r.id = %s AND r.status = 'pending'
            """, (req_id,))
            req = cur.fetchone()
            if not req:
                return err("Unlock request not found or already resolved", 404)

            # Scope check
            if req["sz_district"].strip().lower() != district.lower():
                return err("This request is not in your district", 403)

            if action == "approve":
                cur.execute("""
                    UPDATE sz_duty_locks
                    SET is_locked = 0, status = 'unlocked'
                    WHERE super_zone_id = %s
                """, (req["super_zone_id"],))
                new_status = "approved"
            else:
                cur.execute("""
                    UPDATE sz_duty_locks
                    SET status = 'locked'
                    WHERE super_zone_id = %s
                """, (req["super_zone_id"],))
                new_status = "rejected"

            cur.execute("""
                UPDATE sz_unlock_requests
                SET status = %s, reviewed_by = %s
                WHERE id = %s
            """, (new_status, request.user["id"], req_id))

        conn.commit()
    finally:
        conn.close()

    write_log(
        "INFO",
        f"Unlock request {req_id} {new_status} by user {request.user['id']}",
        "SuperAdmin",
    )
    return ok(None, f"Request {new_status}")