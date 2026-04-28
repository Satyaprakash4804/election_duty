import time
import subprocess
from datetime import datetime, date
from flask import Blueprint, request, jsonify
from functools import wraps
from db import get_db, hash_password, verify_password
from config import Config
import jwt

master_bp = Blueprint("master", __name__, url_prefix="/api/master")


# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def ok(data=None, message="success", code=200):
    return jsonify({"status": "success", "message": message, "data": data}), code

def err(message="error", code=400):
    return jsonify({"status": "error", "message": message}), code

def write_log(level: str, message: str, module: str):
    try:
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO system_logs (level, message, module) VALUES (%s,%s,%s)",
                (level, message, module)
            )
        conn.commit()
        conn.close()
    except Exception:
        pass

def _get_config_map(cur):
    """Returns all app_config rows as a plain dict (global settings only)."""
    cur.execute("SELECT `key`, value FROM app_config")
    return {r["key"]: r["value"] for r in cur.fetchall()}


def _serialize_election_config(r):
    """Normalise an election_configs row into JSON-friendly dict."""
    return {
        "id":            r["id"],
        "district":      r["district"] or "",
        "state":         r["state"] or "",
        "electionType":  r["election_type"] or "",
        "electionName":  r["election_name"] or "",
        "phase":         r["phase"] or "",
        "electionYear":  r["election_year"] or "",
        "electionDate":  r["election_date"].isoformat() if r.get("election_date") else "",
        "pratahSamay":   r.get("pratah_samay") or "",
        "sayaSamay":     r.get("saya_samay") or "",
        "instructions":  r["instructions"] or "",
        "isActive":      bool(r["is_active"]),
        "isArchived":    bool(r["is_archived"]),
        "archivedAt":    r["archived_at"].isoformat() if r.get("archived_at") else None,
        "createdAt":     r["created_at"].isoformat() if r.get("created_at") else None,
        "updatedAt":     r["updated_at"].isoformat() if r.get("updated_at") else None,
    }


def _auto_archive_expired(cur):
    """
    Archive any active election_configs whose election_date is BEFORE today.
    Strategy: 'day AFTER electionDate' — so configs remain active ON the
    election day itself, and become archived from the next day onwards.
    Returns count of newly archived rows.
    """
    cur.execute("""
        UPDATE election_configs
           SET is_active = 0, is_archived = 1, archived_at = NOW()
         WHERE is_active = 1
           AND is_archived = 0
           AND election_date IS NOT NULL
           AND election_date < CURDATE()
    """)
    return cur.rowcount


# ══════════════════════════════════════════════════════════════════════════════
#  AUTH DECORATOR
# ══════════════════════════════════════════════════════════════════════════════

def master_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        token = None
        if auth.startswith("Bearer "):
            token = auth.split(" ")[1]
        else:
            token = request.cookies.get("token")

        if not token:
            return err("Missing token", 401)

        try:
            payload = jwt.decode(token, Config.JWT_SECRET, algorithms=["HS256"])
            if payload.get("role") != "master":
                return err("Forbidden — master access only", 403)

            # 🆕 Check token revocation (force-logout awareness)
            # Master protects itself — master tokens are not revoked via role=master;
            # but we still honour the check in case someone revokes manually.
            conn = get_db()
            try:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT revoke_before FROM token_revocations WHERE role='master' LIMIT 1"
                    )
                    row = cur.fetchone()
                    if row and payload.get("iat") and int(payload["iat"]) < int(row["revoke_before"]):
                        return err("Session expired — please log in again", 401)
            finally:
                conn.close()

            request.master_id = payload["id"]
            request.user = payload   # for API-log extractor consistency
        except jwt.ExpiredSignatureError:
            return err("Token expired", 401)
        except jwt.InvalidTokenError:
            return err("Invalid token", 401)
        return f(*args, **kwargs)
    return decorated


# ══════════════════════════════════════════════════════════════════════════════
#  1. LOGIN          POST /api/master/login
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/login", methods=["POST"])
def master_login():
    body     = request.get_json() or {}
    username = body.get("username", "").strip()
    password = body.get("password", "")
    if not username or not password:
        return err("Username and password required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM users WHERE username=%s AND role='master' AND is_active=1",
                (username,)
            )
            user = cur.fetchone()
    finally:
        conn.close()

    if not user:
        return err("Invalid credentials", 401)
    if not verify_password(password, user["password"]):
        return err("Invalid credentials", 401)

    now = int(time.time())
    payload = {
        "id":       user["id"],
        "username": user["username"],
        "role":     "master",
        "iat":      now,                                # 🆕 for revocation
        "exp":      now + Config.JWT_EXPIRY,
    }
    token = jwt.encode(payload, Config.JWT_SECRET, algorithm="HS256")
    write_log("INFO", f"Master '{username}' logged in", "Auth")
    return ok({
        "token":    token,
        "name":     user["name"],
        "username": user["username"],
    }, "Login successful")


# ══════════════════════════════════════════════════════════════════════════════
#  2. CHANGE MASTER PASSWORD    PATCH /api/master/change-password
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/change-password", methods=["PATCH"])
@master_required
def change_master_password():
    body         = request.get_json() or {}
    old_password = body.get("oldPassword", "")
    new_password = body.get("newPassword", "")

    if not old_password or not new_password:
        return err("oldPassword and newPassword required")
    if len(new_password) < 6:
        return err("New password must be at least 6 characters")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT password FROM users WHERE id=%s", (request.master_id,))
            row = cur.fetchone()
            if not row or not verify_password(old_password, row["password"]):
                return err("Current password is incorrect", 401)
            cur.execute(
                "UPDATE users SET password=%s WHERE id=%s",
                (hash_password(new_password), request.master_id)
            )
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Master ID:{request.master_id} changed password", "Auth")
    return ok(None, "Password changed successfully")


# ══════════════════════════════════════════════════════════════════════════════
#  3. GLOBAL APP CONFIG  (maintenanceMode, allowStaffLogin, etc.)
#     NOTE: election details moved to /election-configs (district-wise)
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/config", methods=["GET"])
@master_required
def get_config():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            config = _get_config_map(cur)
    finally:
        conn.close()
    return ok(config)


@master_bp.route("/config", methods=["POST"])
@master_required
def set_config():
    """Global app settings only (maintenanceMode, allowStaffLogin, forcePasswordReset)."""
    body = request.get_json() or {}
    if not body:
        return err("Request body is empty")

    if "key" in body and "value" in body and len(body) == 2:
        pairs = {body["key"]: body["value"]}
    else:
        pairs = body

    if not pairs:
        return err("No config keys provided")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            for k, v in pairs.items():
                cur.execute(
                    "INSERT INTO app_config (`key`, value) VALUES (%s,%s) "
                    "ON DUPLICATE KEY UPDATE value=VALUES(value)",
                    (str(k), str(v))
                )
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Config updated: {list(pairs.keys())} by master ID:{request.master_id}", "Config")
    return ok(pairs, "Config updated successfully")


@master_bp.route("/config/<string:config_key>", methods=["DELETE"])
@master_required
def delete_config(config_key):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM app_config WHERE `key`=%s", (config_key,))
            if cur.rowcount == 0:
                return err("Config key not found", 404)
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Config key '{config_key}' deleted by master", "Config")
    return ok(None, f"Config key '{config_key}' deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  🆕 3B. DISTRICT-WISE ELECTION CONFIGS
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/election-configs", methods=["GET"])
@master_required
def list_election_configs():
    """
    Query params:
      district=<name>   → only that district
      includeArchived=1 → include archived entries (default: only active)
    """
    district         = (request.args.get("district") or "").strip()
    include_archived = request.args.get("includeArchived") in ("1", "true", "True")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # 🆕 Auto-archive expired configs first (lazy strategy)
            archived = _auto_archive_expired(cur)
            if archived:
                conn.commit()

            sql = "SELECT * FROM election_configs WHERE 1=1"
            params = []
            if district:
                sql += " AND district = %s"
                params.append(district)
            if not include_archived:
                sql += " AND is_archived = 0"
            sql += " ORDER BY is_active DESC, is_archived ASC, created_at DESC"
            cur.execute(sql, params)
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([_serialize_election_config(r) for r in rows])


@master_bp.route("/election-configs/<int:cfg_id>", methods=["GET"])
@master_required
def get_election_config(cfg_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM election_configs WHERE id=%s", (cfg_id,))
            row = cur.fetchone()
            if not row:
                return err("Config not found", 404)
    finally:
        conn.close()
    return ok(_serialize_election_config(row))


@master_bp.route("/election-configs", methods=["POST"])
@master_required
def create_election_config():
    """
    Body:
    {
      "district": "आगरा",              (required)
      "state":         "UP",
      "electionType":  "Lok Sabha",    (e.g. Panchayat / Vidhan Sabha / Lok Sabha)
      "electionName":  "General Election 2026",
      "phase":         "Phase 1",
      "electionYear":  "2026",
      "electionDate":  "2026-05-14",
      "electionTime":  "07:00",
      "instructions":  "..."
    }

    Rule: if an active (non-archived) config already exists for that district,
    it will be ARCHIVED automatically and the new one becomes active.
    """
    body = request.get_json() or {}

    district      = (body.get("district") or "").strip()
    state         = (body.get("state") or "").strip()
    election_type = (body.get("electionType") or "").strip()
    election_name = (body.get("electionName") or "").strip()
    phase         = (body.get("phase") or "").strip()
    year          = (body.get("electionYear") or "").strip()
    date_str      = (body.get("electionDate") or "").strip()
    pratah_samay  = (body.get("pratahSamay") or "").strip()
    saya_samay    = (body.get("sayaSamay") or "").strip()
    instructions  = body.get("instructions") or ""

    if not district:
        return err("district is required")
    if not election_type:
        return err("electionType is required")
    
    election_type = (body.get("electionType") or "").strip()
    year          = (body.get("electionYear") or "").strip()
    election_name = (body.get("electionName") or "").strip()
    
    if not election_name:
        election_name = f"{election_type} {year}"
    if not year:
        return err("electionYear is required")
    if not date_str:
        return err("electionDate is required")

    # Validate date
    try:
        date_obj = datetime.strptime(date_str, "%Y-%m-%d").date()
    except ValueError:
        return err("electionDate must be in YYYY-MM-DD format")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # 🔁 Auto-archive any configs whose date already passed
            _auto_archive_expired(cur)

            # 🔁 Archive any existing active config for this district
            cur.execute("""
                UPDATE election_configs
                   SET is_active = 0, is_archived = 1, archived_at = NOW()
                 WHERE district = %s AND is_active = 1 AND is_archived = 0
            """, (district,))
            archived_count = cur.rowcount

            # Insert new active one
            cur.execute("""
                INSERT INTO election_configs
                    (district, state, election_type, election_name, phase,
                     election_year, election_date, pratah_samay, saya_samay,
                     instructions, is_active, is_archived, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,1,0,%s)
            """, (
                district, state, election_type, election_name, phase,
                year, date_obj, pratah_samay, saya_samay,
                instructions, request.master_id
            ))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()

    write_log(
        "INFO",
        f"Election config created for district '{district}' "
        f"(archived {archived_count} previous) by master ID:{request.master_id}",
        "ElectionConfig"
    )

    return ok(
        {"id": new_id, "archivedPrevious": archived_count},
        f"Election config created for {district}",
        201
    )


@master_bp.route("/election-configs/<int:cfg_id>", methods=["PUT"])
@master_required
def update_election_config(cfg_id):
    """
    Update fields of an EXISTING (still-active) config.
    Archived configs cannot be edited — create a new one instead.
    """
    body = request.get_json() or {}

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM election_configs WHERE id=%s", (cfg_id,))
            row = cur.fetchone()
            if not row:
                return err("Config not found", 404)
            if row["is_archived"]:
                return err("Cannot edit archived config. Create a new one instead.", 400)

            # Build dynamic update
            fields = []
            params = []

            field_map = {
                "state":        ("state", str),
                "electionType": ("election_type", str),
                "electionName": ("election_name", str),
                "phase":        ("phase", str),
                "electionYear": ("election_year", str),
                "pratahSamay":  ("pratah_samay", str),
                "sayaSamay":    ("saya_samay", str),
                "instructions": ("instructions", str),
            }

            for body_key, (col, caster) in field_map.items():
                if body_key in body:
                    fields.append(f"{col}=%s")
                    params.append(caster(body[body_key] or "").strip() if caster is str else caster(body[body_key]))

            # electionDate
            if "electionDate" in body:
                date_str = (body.get("electionDate") or "").strip()
                if date_str:
                    try:
                        date_obj = datetime.strptime(date_str, "%Y-%m-%d").date()
                        fields.append("election_date=%s")
                        params.append(date_obj)
                    except ValueError:
                        return err("electionDate must be in YYYY-MM-DD format")

            if not fields:
                return err("Nothing to update")

            params.append(cfg_id)
            cur.execute(
                f"UPDATE election_configs SET {', '.join(fields)} WHERE id=%s",
                params
            )
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Election config ID:{cfg_id} updated by master", "ElectionConfig")
    return ok(None, "Config updated")


@master_bp.route("/election-configs/<int:cfg_id>/archive", methods=["PATCH"])
@master_required
def archive_election_config(cfg_id):
    """Manually archive an active config (e.g. election cancelled)."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id, district FROM election_configs WHERE id=%s", (cfg_id,))
            row = cur.fetchone()
            if not row:
                return err("Config not found", 404)
            cur.execute("""
                UPDATE election_configs
                   SET is_active=0, is_archived=1, archived_at=NOW()
                 WHERE id=%s
            """, (cfg_id,))
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Election config ID:{cfg_id} (dist:{row['district']}) archived by master", "ElectionConfig")
    return ok(None, "Config archived")


@master_bp.route("/election-configs/<int:cfg_id>", methods=["DELETE"])
@master_required
def delete_election_config(cfg_id):
    """Permanently delete. Usually you want archive instead."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM election_configs WHERE id=%s", (cfg_id,))
            if cur.rowcount == 0:
                return err("Config not found", 404)
        conn.commit()
    finally:
        conn.close()
    write_log("WARN", f"Election config ID:{cfg_id} DELETED by master", "ElectionConfig")
    return ok(None, "Config deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  🆕 3D. MANUAL AUTO-ARCHIVE TRIGGER
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/election-configs/auto-archive", methods=["POST"])
@master_required
def auto_archive_now():
    """
    Manually triggers archival of all configs whose election_date has passed.
    Useful for cron jobs or admin button.
    """
    conn = get_db()
    try:
        with conn.cursor() as cur:
            archived = _auto_archive_expired(cur)
        conn.commit()
    finally:
        conn.close()
    if archived:
        write_log("INFO", f"Auto-archive: {archived} expired configs moved to history", "ElectionConfig")
    return ok({"archived": archived}, f"{archived} expired config(s) archived")


# ══════════════════════════════════════════════════════════════════════════════
#  🆕 3C. HELPER ENDPOINT — used by super-admin / admin to read their
#  active election config by district. Access: any logged-in non-staff.
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/election-configs/active/<string:district>", methods=["GET"])
def get_active_election_config_for_district(district):
    """
    Authenticated read: returns active config for a district.
    Any logged-in user may call this so super_admin and admin dashboards
    can read their district's election details.
    """
    auth = request.headers.get("Authorization", "")
    token = None
    if auth.startswith("Bearer "):
        token = auth.split(" ")[1]
    else:
        token = request.cookies.get("token")
    if not token:
        return err("Missing token", 401)
    try:
        jwt.decode(token, Config.JWT_SECRET, algorithms=["HS256"])
    except Exception:
        return err("Invalid or expired token", 401)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # 🆕 Auto-archive expired before lookup
            archived = _auto_archive_expired(cur)
            if archived:
                conn.commit()

            cur.execute("""
                SELECT * FROM election_configs
                 WHERE district=%s AND is_active=1 AND is_archived=0
                 ORDER BY created_at DESC LIMIT 1
            """, (district,))
            row = cur.fetchone()
    finally:
        conn.close()

    if not row:
        return ok(None, "No active config for this district")
    return ok(_serialize_election_config(row))


# ══════════════════════════════════════════════════════════════════════════════
#  4. SUPER ADMINS
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/super-admins", methods=["GET"])
@master_required
def get_super_admins():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT sa.id, sa.name, sa.username, sa.district, sa.is_active, sa.created_at,
                       COUNT(a.id) AS admins_under
                FROM users sa
                LEFT JOIN users a ON a.created_by=sa.id AND a.role='admin'
                WHERE sa.role='super_admin'
                GROUP BY sa.id
                ORDER BY sa.created_at DESC
            """)
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":          r["id"],
        "name":        r["name"],
        "username":    r["username"],
        "district":    r.get("district") or "",
        "isActive":    bool(r["is_active"]),
        "createdAt":   r["created_at"].isoformat() if r["created_at"] else None,
        "adminsUnder": r["admins_under"],
    } for r in rows])


@master_bp.route("/super-admins", methods=["POST"])
@master_required
def create_super_admin():
    body     = request.get_json() or {}
    name     = body.get("name", "").strip()
    username = body.get("username", "").strip()
    password = body.get("password", "")
    district = body.get("district", "").strip()

    if not name or not username or not password or not district:
        return err("name, username, password and district are required")
    if len(password) < 6:
        return err("Password must be at least 6 characters")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE username=%s", (username,))
            if cur.fetchone():
                return err("Username already taken", 409)

            cur.execute(
                "INSERT INTO users (name, username, password, role, district, is_active, created_by) "
                "VALUES (%s,%s,%s,'super_admin',%s,1,%s)",
                (name, username, hash_password(password), district, request.master_id)
            )
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()

    return ok({
        "id": new_id, "name": name, "username": username, "district": district
    }, "Super Admin created", 201)


@master_bp.route("/super-admins/<int:sa_id>", methods=["GET"])
@master_required
def get_super_admin(sa_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, username, district, is_active, created_at "
                "FROM users WHERE id=%s AND role='super_admin'",
                (sa_id,)
            )
            row = cur.fetchone()
            if not row:
                return err("Super Admin not found", 404)
    finally:
        conn.close()
    return ok({
        "id":        row["id"],
        "name":      row["name"],
        "username":  row["username"],
        "district":  row.get("district") or "",
        "isActive":  bool(row["is_active"]),
        "createdAt": row["created_at"].isoformat() if row["created_at"] else None,
    })


@master_bp.route("/super-admins/<int:sa_id>", methods=["PUT"])
@master_required
def update_super_admin(sa_id):
    body = request.get_json() or {}
    name     = body.get("name", "").strip()
    username = body.get("username", "").strip()
    district = body.get("district", "").strip()
    if not name or not username:
        return err("name and username required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE id=%s AND role='super_admin'", (sa_id,))
            if not cur.fetchone():
                return err("Super Admin not found", 404)
            cur.execute("SELECT id FROM users WHERE username=%s AND id!=%s", (username, sa_id))
            if cur.fetchone():
                return err("Username already taken", 409)

            if district:
                cur.execute(
                    "UPDATE users SET name=%s, username=%s, district=%s WHERE id=%s",
                    (name, username, district, sa_id)
                )
            else:
                cur.execute(
                    "UPDATE users SET name=%s, username=%s WHERE id=%s",
                    (name, username, sa_id)
                )
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Super Admin ID:{sa_id} updated by master", "Auth")
    return ok(None, "Super Admin updated")


@master_bp.route("/super-admins/<int:sa_id>", methods=["DELETE"])
@master_required
def delete_super_admin(sa_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT name FROM users WHERE id=%s AND role='super_admin'", (sa_id,))
            row = cur.fetchone()
            if not row:
                return err("Super Admin not found", 404)
            name = row["name"]
            cur.execute(
                "UPDATE users SET created_by=NULL WHERE created_by=%s AND role='admin'",
                (sa_id,)
            )
            cur.execute("DELETE FROM users WHERE id=%s", (sa_id,))
        conn.commit()
    finally:
        conn.close()
    write_log("WARN", f"Super Admin '{name}' (ID:{sa_id}) deleted by master", "Auth")
    return ok(None, f"Super Admin '{name}' deleted")


@master_bp.route("/super-admins/<int:sa_id>/status", methods=["PATCH"])
@master_required
def toggle_super_admin_status(sa_id):
    body      = request.get_json() or {}
    is_active = body.get("isActive")
    if is_active is None:
        return err("isActive field required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT name FROM users WHERE id=%s AND role='super_admin'", (sa_id,))
            row = cur.fetchone()
            if not row:
                return err("Super Admin not found", 404)
            cur.execute("UPDATE users SET is_active=%s WHERE id=%s", (1 if is_active else 0, sa_id))
        conn.commit()
    finally:
        conn.close()

    action = "activated" if is_active else "deactivated"
    write_log("INFO", f"Super Admin '{row['name']}' (ID:{sa_id}) {action} by master", "Auth")
    return ok({"id": sa_id, "isActive": bool(is_active)}, f"Super Admin {action}")


@master_bp.route("/super-admins/<int:sa_id>/reset-password", methods=["PATCH"])
@master_required
def reset_super_admin_password(sa_id):
    body     = request.get_json() or {}
    password = body.get("password", "")
    if len(password) < 6:
        return err("Password must be at least 6 characters")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE id=%s AND role='super_admin'", (sa_id,))
            if not cur.fetchone():
                return err("Super Admin not found", 404)
            cur.execute(
                "UPDATE users SET password=%s WHERE id=%s",
                (hash_password(password), sa_id)
            )
        conn.commit()
    finally:
        conn.close()

    write_log("WARN", f"Password reset for Super Admin ID:{sa_id} by master", "Auth")
    return ok(None, "Password reset successful")


# ══════════════════════════════════════════════════════════════════════════════
#  5. ADMINS
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/admins", methods=["GET"])
@master_required
def get_admins():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT u.id, u.name, u.username, u.district, u.is_active, u.created_at,
                       creator.name AS created_by_name,
                       (SELECT COUNT(*) FROM super_zones sz WHERE sz.admin_id=u.id) AS super_zone_count
                FROM users u
                LEFT JOIN users creator ON creator.id=u.created_by
                WHERE u.role='admin'
                ORDER BY u.created_at DESC
            """)
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":             r["id"],
        "name":           r["name"],
        "username":       r["username"],
        "district":       r["district"] or "",
        "isActive":       bool(r["is_active"]),
        "createdAt":      r["created_at"].isoformat() if r["created_at"] else None,
        "createdBy":      r["created_by_name"] or "master",
        "superZoneCount": r["super_zone_count"],
    } for r in rows])


@master_bp.route("/admins", methods=["POST"])
@master_required
def create_admin():
    body     = request.get_json() or {}
    name     = body.get("name", "").strip()
    username = body.get("username", "").strip()
    district = body.get("district", "").strip()
    password = body.get("password", "")

    if not name or not username or not district or not password:
        return err("name, username, district and password are all required")
    if len(password) < 6:
        return err("Password must be at least 6 characters")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE username=%s", (username,))
            if cur.fetchone():
                return err("Username already taken", 409)

            cur.execute(
                "INSERT INTO users (name, username, password, role, district, is_active, created_by) "
                "VALUES (%s,%s,%s,'admin',%s,1,%s)",
                (name, username, hash_password(password), district, request.master_id)
            )
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Admin '{name}' (district:{district}) created directly by master", "Auth")
    return ok(
        {"id": new_id, "name": name, "username": username, "district": district},
        "Admin created", 201
    )


@master_bp.route("/admins/<int:admin_id>", methods=["PUT"])
@master_required
def update_admin(admin_id):
    body     = request.get_json() or {}
    name     = body.get("name", "").strip()
    username = body.get("username", "").strip()
    district = body.get("district", "").strip()
    if not name or not username or not district:
        return err("name, username and district required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE id=%s AND role='admin'", (admin_id,))
            if not cur.fetchone():
                return err("Admin not found", 404)
            cur.execute("SELECT id FROM users WHERE username=%s AND id!=%s", (username, admin_id))
            if cur.fetchone():
                return err("Username already taken", 409)
            cur.execute(
                "UPDATE users SET name=%s, username=%s, district=%s WHERE id=%s",
                (name, username, district, admin_id)
            )
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Admin ID:{admin_id} updated by master", "Auth")
    return ok(None, "Admin updated")


@master_bp.route("/admins/<int:admin_id>", methods=["DELETE"])
@master_required
def delete_admin(admin_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT name FROM users WHERE id=%s AND role='admin'", (admin_id,))
            row = cur.fetchone()
            if not row:
                return err("Admin not found", 404)
            cur.execute("DELETE FROM users WHERE id=%s", (admin_id,))
        conn.commit()
    finally:
        conn.close()
    write_log("WARN", f"Admin '{row['name']}' (ID:{admin_id}) deleted by master", "Auth")
    return ok(None, f"Admin '{row['name']}' deleted")


@master_bp.route("/admins/<int:admin_id>/status", methods=["PATCH"])
@master_required
def toggle_admin_status(admin_id):
    body      = request.get_json() or {}
    is_active = body.get("isActive")
    if is_active is None:
        return err("isActive field required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT name FROM users WHERE id=%s AND role='admin'", (admin_id,))
            row = cur.fetchone()
            if not row:
                return err("Admin not found", 404)
            cur.execute("UPDATE users SET is_active=%s WHERE id=%s", (1 if is_active else 0, admin_id))
        conn.commit()
    finally:
        conn.close()

    action = "activated" if is_active else "deactivated"
    write_log("INFO", f"Admin ID:{admin_id} {action} by master", "Auth")
    return ok({"id": admin_id, "isActive": bool(is_active)}, f"Admin {action}")


@master_bp.route("/admins/<int:admin_id>/reset-password", methods=["PATCH"])
@master_required
def reset_admin_password(admin_id):
    body     = request.get_json() or {}
    password = body.get("password", "")
    if len(password) < 6:
        return err("Password must be at least 6 characters")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE id=%s AND role='admin'", (admin_id,))
            if not cur.fetchone():
                return err("Admin not found", 404)
            cur.execute(
                "UPDATE users SET password=%s WHERE id=%s",
                (hash_password(password), admin_id)
            )
        conn.commit()
    finally:
        conn.close()

    write_log("WARN", f"Password reset for Admin ID:{admin_id} by master", "Auth")
    return ok(None, "Password reset successful")


# ══════════════════════════════════════════════════════════════════════════════
#  🆕 6. FORCE-LOGOUT BY ROLE
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/force-logout", methods=["POST"])
@master_required
def force_logout():
    """
    Invalidate all JWTs for a given role (or multiple roles) that were
    issued BEFORE this moment. Users will be bounced on their next API call
    with 401 → client should route them to /login.

    Body: { "roles": ["super_admin","admin","staff"] }  OR  { "role": "staff" }
    """
    body = request.get_json() or {}

    roles = body.get("roles")
    if not roles and body.get("role"):
        roles = [body.get("role")]

    if not roles or not isinstance(roles, list):
        return err("Provide 'roles' (list) or 'role' (string)")

    roles = [str(r).strip().lower() for r in roles if r]
    valid = {"super_admin", "admin", "staff", "master"}
    bad = [r for r in roles if r not in valid]
    if bad:
        return err(f"Invalid role(s): {bad}. Allowed: {sorted(valid)}")

    # 🛡️ Master self-protection — silently drop 'master' from the list
    if "master" in roles:
        roles = [r for r in roles if r != "master"]
        write_log(
            "WARN",
            f"Master ID:{request.master_id} attempted to force-logout 'master' — ignored (self-protection)",
            "Auth"
        )

    if not roles:
        return err("No valid roles to revoke (master role cannot be force-logged-out)")

    now = int(time.time())
    reason = (body.get("reason") or "").strip()[:255]

    conn = get_db()
    try:
        with conn.cursor() as cur:
            for role in roles:
                cur.execute("""
                    INSERT INTO token_revocations (role, revoke_before, revoked_by, reason)
                    VALUES (%s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                        revoke_before = VALUES(revoke_before),
                        revoked_by    = VALUES(revoked_by),
                        reason        = VALUES(reason),
                        created_at    = NOW()
                """, (role, now, request.master_id, reason))
        conn.commit()
    finally:
        conn.close()

    write_log("WARN", f"Force-logout triggered for roles {roles} by master ID:{request.master_id}", "Auth")
    return ok({"roles": roles, "revokedBefore": now}, f"All sessions for {roles} invalidated")


@master_bp.route("/force-logout/status", methods=["GET"])
@master_required
def force_logout_status():
    """Shows the last revocation timestamp per role."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT role, revoke_before, revoked_by, reason, created_at FROM token_revocations")
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "role":         r["role"],
        "revokeBefore": r["revoke_before"],
        "revokedBy":    r["revoked_by"],
        "reason":       r["reason"] or "",
        "createdAt":    r["created_at"].isoformat() if r["created_at"] else None,
    } for r in rows])


# ══════════════════════════════════════════════════════════════════════════════
#  7. SYSTEM OVERVIEW
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/overview", methods=["GET"])
@master_required
def overview():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS cnt FROM users WHERE role='super_admin'")
            super_admins = cur.fetchone()["cnt"]

            cur.execute("SELECT COUNT(*) AS cnt FROM users WHERE role='admin'")
            admins = cur.fetchone()["cnt"]

            cur.execute("SELECT COUNT(*) AS cnt FROM users WHERE role='staff' AND is_active=1")
            staff = cur.fetchone()["cnt"]

            cur.execute("SELECT COUNT(*) AS cnt FROM matdan_sthal")
            booths = cur.fetchone()["cnt"]

            cur.execute("SELECT COUNT(*) AS cnt FROM duty_assignments")
            duties = cur.fetchone()["cnt"]

            cur.execute("SELECT COUNT(*) AS cnt FROM election_configs WHERE is_active=1 AND is_archived=0")
            active_configs = cur.fetchone()["cnt"]

            cur.execute("SELECT COUNT(*) AS cnt FROM election_configs WHERE is_archived=1")
            archived_configs = cur.fetchone()["cnt"]
    finally:
        conn.close()

    return ok({
        "totalSuperAdmins":       super_admins,
        "totalAdmins":            admins,
        "totalStaff":             staff,
        "totalBooths":            booths,
        "assignedDuties":         duties,
        "activeElectionConfigs":  active_configs,
        "archivedElectionConfigs":archived_configs,
    })


# ══════════════════════════════════════════════════════════════════════════════
#  8. SYSTEM STATS
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/system-stats", methods=["GET"])
@master_required
def system_stats():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT ROUND(SUM(data_length+index_length)/1024/1024,2) AS size_mb
                FROM information_schema.tables
                WHERE table_schema=DATABASE()
            """)
            size_row = cur.fetchone()
            db_size  = f"{size_row['size_mb']} MB" if size_row and size_row["size_mb"] else "N/A"

            total = 0
            for t in ["users","duty_assignments","matdan_kendra","matdan_sthal",
                      "sectors","zones","super_zones","gram_panchayats",
                      "election_configs","api_request_logs"]:
                try:
                    cur.execute(f"SELECT COUNT(*) AS cnt FROM `{t}`")
                    total += cur.fetchone()["cnt"]
                except Exception:
                    pass

            cur.execute("""
                SELECT time FROM system_logs
                WHERE module='DB' AND message LIKE 'Database backup%'
                ORDER BY time DESC LIMIT 1
            """)
            br = cur.fetchone()
            last_backup = br["time"].strftime("%d %b %Y %H:%M") if br else "Never"

            cur.execute("SELECT MIN(time) AS first FROM system_logs")
            fr = cur.fetchone()
            if fr and fr["first"]:
                d      = datetime.utcnow() - fr["first"]
                uptime = f"{d.days}d {d.seconds//3600}h {(d.seconds%3600)//60}m"
            else:
                uptime = "N/A"
    finally:
        conn.close()

    return ok({
        "dbSize":       db_size,
        "totalRecords": total,
        "uptime":       uptime,
        "lastBackup":   last_backup,
        "backend":      "Flask",
    })


# ══════════════════════════════════════════════════════════════════════════════
#  9. LEGACY LOGS (system_logs)
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/logs", methods=["GET"])
@master_required
def get_logs():
    level  = request.args.get("level", "ALL").upper()
    limit  = min(int(request.args.get("limit", 100)), 500)
    offset = max(0, int(request.args.get("offset", 0)))
    conn   = get_db()
    try:
        with conn.cursor() as cur:
            if level == "ALL":
                cur.execute(
                    "SELECT * FROM system_logs ORDER BY time DESC LIMIT %s OFFSET %s",
                    (limit, offset)
                )
            else:
                cur.execute(
                    "SELECT * FROM system_logs WHERE level=%s ORDER BY time DESC LIMIT %s OFFSET %s",
                    (level, limit, offset)
                )
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok([{
        "id":      r["id"],
        "level":   r["level"],
        "message": r["message"],
        "module":  r["module"],
        "time":    r["time"].isoformat(),
    } for r in rows])


# ══════════════════════════════════════════════════════════════════════════════
#  🆕 10. API REQUEST LOGS — every HTTP hit
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/api-logs", methods=["GET"])
@master_required
def get_api_logs():
    """
    Query params:
      level   = INFO | WARN | ERROR | ALL
      method  = GET | POST | PUT | PATCH | DELETE | ALL
      role    = master | super_admin | admin | staff | ALL
      status  = 200 | 400 | 500 ... or range like '4xx' / '5xx'
      q       = substring to search in path/username/error
      limit   = default 100, max 500
      offset  = default 0
    """
    level  = request.args.get("level",  "ALL").upper()
    method = request.args.get("method", "ALL").upper()
    role   = (request.args.get("role",   "ALL") or "ALL").lower()
    status = (request.args.get("status", "ALL") or "ALL").lower()
    q      = (request.args.get("q")     or "").strip()
    limit  = min(int(request.args.get("limit", 100)), 500)
    offset = max(0, int(request.args.get("offset", 0)))

    where = []
    params = []

    if level != "ALL":
        where.append("level = %s")
        params.append(level)
    if method != "ALL":
        where.append("method = %s")
        params.append(method)
    if role != "all":
        where.append("role = %s")
        params.append(role)
    if status == "4xx":
        where.append("status_code BETWEEN 400 AND 499")
    elif status == "5xx":
        where.append("status_code BETWEEN 500 AND 599")
    elif status == "2xx":
        where.append("status_code BETWEEN 200 AND 299")
    elif status != "all" and status.isdigit():
        where.append("status_code = %s")
        params.append(int(status))
    if q:
        where.append("(path LIKE %s OR username LIKE %s OR error_message LIKE %s)")
        like = f"%{q}%"
        params.extend([like, like, like])

    sql_where = ("WHERE " + " AND ".join(where)) if where else ""

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # total count
            cur.execute(f"SELECT COUNT(*) AS cnt FROM api_request_logs {sql_where}", params)
            total = cur.fetchone()["cnt"]

            # rows
            cur.execute(
                f"""SELECT * FROM api_request_logs {sql_where}
                     ORDER BY created_at DESC LIMIT %s OFFSET %s""",
                params + [limit, offset]
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    return ok({
        "total":  total,
        "limit":  limit,
        "offset": offset,
        "items": [{
            "id":           r["id"],
            "method":       r["method"],
            "path":         r["path"],
            "statusCode":   r["status_code"],
            "durationMs":   r["duration_ms"],
            "userId":       r["user_id"],
            "username":     r["username"] or "",
            "role":         r["role"] or "",
            "ipAddress":    r["ip_address"] or "",
            "userAgent":    (r["user_agent"] or "")[:120],
            "requestBody":  r["request_body"] or "",
            "errorMessage": r["error_message"] or "",
            "level":        r["level"],
            "createdAt":    r["created_at"].isoformat() if r["created_at"] else None,
        } for r in rows],
    })


@master_bp.route("/api-logs/clear", methods=["DELETE"])
@master_required
def clear_api_logs():
    """Delete API logs older than N days (default 30)."""
    days = int(request.args.get("days", 30))
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM api_request_logs WHERE created_at < (NOW() - INTERVAL %s DAY)",
                (days,)
            )
            deleted = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"API logs older than {days}d cleared ({deleted} rows)", "DB")
    return ok({"deleted": deleted}, f"Cleared {deleted} log(s) older than {days} days")


@master_bp.route("/api-logs/stats", methods=["GET"])
@master_required
def api_log_stats():
    """Summary counts for dashboard."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    SUM(CASE WHEN level='INFO'  THEN 1 ELSE 0 END) AS info_count,
                    SUM(CASE WHEN level='WARN'  THEN 1 ELSE 0 END) AS warn_count,
                    SUM(CASE WHEN level='ERROR' THEN 1 ELSE 0 END) AS error_count,
                    COUNT(*) AS total
                FROM api_request_logs
                WHERE created_at > (NOW() - INTERVAL 24 HOUR)
            """)
            day = cur.fetchone() or {}

            cur.execute("""
                SELECT path, COUNT(*) AS cnt
                FROM api_request_logs
                WHERE created_at > (NOW() - INTERVAL 1 HOUR)
                GROUP BY path ORDER BY cnt DESC LIMIT 5
            """)
            top = cur.fetchall()
    finally:
        conn.close()

    return ok({
        "last24h": {
            "info":  int(day.get("info_count")  or 0),
            "warn":  int(day.get("warn_count")  or 0),
            "error": int(day.get("error_count") or 0),
            "total": int(day.get("total")       or 0),
        },
        "topPaths1h": [{"path": r["path"], "count": r["cnt"]} for r in top]
    })


# ══════════════════════════════════════════════════════════════════════════════
#  11. DB TOOLS
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/db/backup", methods=["POST"])
@master_required
def db_backup():
    from pathlib import Path
    backup_dir = Path("backups")
    backup_dir.mkdir(exist_ok=True)
    ts       = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    filename = backup_dir / f"election_db_{ts}.sql"

    mysqldump_path = getattr(Config, "MYSQLDUMP_PATH", None)
    if mysqldump_path:
        mysqldump_path = mysqldump_path.replace('r"', '').replace('"', '').strip()
    if not mysqldump_path:
        mysqldump_path = "mysqldump"

    try:
        subprocess.run(
            [mysqldump_path,
             f"-u{Config.DB_USER}",
             f"-p{Config.DB_PASS}",
             Config.DB_NAME,
             f"--result-file={filename}"],
            check=True, capture_output=True,
        )
        write_log("INFO", f"Database backup created: {filename.name}", "DB")
        return ok({"file": filename.name}, "Backup completed")
    except FileNotFoundError:
        return err("mysqldump not found. Set MYSQLDUMP_PATH in config.", 500)
    except subprocess.CalledProcessError as e:
        return err(f"Backup failed: {e.stderr.decode()}", 500)


@master_bp.route("/db/flush-cache", methods=["POST"])
@master_required
def flush_cache():
    write_log("INFO", "Cache flushed by master", "System")
    return ok(None, "Cache flushed successfully")


@master_bp.route("/migrate", methods=["POST"])
@master_required
def migrate():
    from db import init_db, run_migrations
    try:
        init_db()
        result = run_migrations()
        write_log("INFO", "Migration run by master", "DB")
        return ok(result, "Migration completed")
    except Exception as e:
        return err(f"Migration error: {str(e)}", 500)


@master_bp.route("/ping", methods=["GET"])
def ping():
    return ok("pong")