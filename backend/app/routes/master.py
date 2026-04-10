import time
import subprocess
from datetime import datetime
from flask import Blueprint, request, jsonify
from functools import wraps
from werkzeug.security import generate_password_hash
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
    """Returns all app_config rows as a plain dict."""
    cur.execute("SELECT `key`, value FROM app_config")
    return {r["key"]: r["value"] for r in cur.fetchall()}


# ══════════════════════════════════════════════════════════════════════════════
#  AUTH DECORATOR
# ══════════════════════════════════════════════════════════════════════════════

def master_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return err("Missing token", 401)
        token = auth.split(" ")[1]
        try:
            payload = jwt.decode(token, Config.JWT_SECRET, algorithms=["HS256"])
            if payload.get("role") != "master":
                return err("Forbidden — master access only", 403)
            request.master_id = payload["id"]
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

    payload = {
        "id":       user["id"],
        "username": user["username"],
        "role":     "master",
        "exp":      int(time.time()) + Config.JWT_EXPIRY,
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
#  3. ELECTION CONFIG    GET/POST /api/master/config
#     Master sets all election details here.
#     Super admins receive these details when they log in.
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
    """
    Set one or multiple config keys at once.
    Body: { "key": "value", ... }  OR  { "key": "someKey", "value": "someVal" }

    Standard election keys:
        state, electionYear, electionDate, phase,
        maintenanceMode, allowStaffLogin, forcePasswordReset
    """
    body = request.get_json() or {}
    if not body:
        return err("Request body is empty")

    # Support both batch { k:v, k:v } and single { key: k, value: v }
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
#  4. SUPER ADMINS    GET/POST  /api/master/super-admins
#                    GET/PUT/DELETE/PATCH  /api/master/super-admins/<id>
# ══════════════════════════════════════════════════════════════════════════════

@master_bp.route("/super-admins", methods=["GET"])
@master_required
def get_super_admins():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT sa.id, sa.name, sa.username, sa.is_active, sa.created_at,
                       COUNT(a.id) AS admins_under
                FROM users sa
                LEFT JOIN users a ON a.created_by=sa.id AND a.role='admin'
                WHERE sa.role='super_admin'
                GROUP BY sa.id
                ORDER BY sa.created_at DESC
            """)
            rows = cur.fetchall()
            config = _get_config_map(cur)
    finally:
        conn.close()

    return ok([{
        "id":          r["id"],
        "name":        r["name"],
        "username":    r["username"],
        "isActive":    bool(r["is_active"]),
        "createdAt":   r["created_at"].isoformat() if r["created_at"] else None,
        "adminsUnder": r["admins_under"],
        # Pass current election info so frontend can display it
        "electionInfo": {
            "state":        config.get("state", ""),
            "electionYear": config.get("electionYear", ""),
            "electionDate": config.get("electionDate", ""),
            "phase":        config.get("phase", ""),
        }
    } for r in rows])


@master_bp.route("/super-admins", methods=["POST"])
@master_required
def create_super_admin():
    body     = request.get_json() or {}
    name     = body.get("name", "").strip()
    username = body.get("username", "").strip()
    password = body.get("password", "")

    if not name or not username or not password:
        return err("name, username and password are required")
    if len(password) < 6:
        return err("Password must be at least 6 characters")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE username=%s", (username,))
            if cur.fetchone():
                return err("Username already taken", 409)
            cur.execute(
                "INSERT INTO users (name, username, password, role, is_active, created_by) "
                "VALUES (%s,%s,%s,'super_admin',1,%s)",
                (name, username, hash_password(password), request.master_id)
            )
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()

    write_log("INFO", f"Super Admin '{name}' (ID:{new_id}) created by master", "Auth")
    return ok({"id": new_id, "name": name, "username": username}, "Super Admin created", 201)


@master_bp.route("/super-admins/<int:sa_id>", methods=["GET"])
@master_required
def get_super_admin(sa_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, username, is_active, created_at "
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
        "isActive":  bool(row["is_active"]),
        "createdAt": row["created_at"].isoformat() if row["created_at"] else None,
    })


@master_bp.route("/super-admins/<int:sa_id>", methods=["PUT"])
@master_required
def update_super_admin(sa_id):
    body = request.get_json() or {}
    name     = body.get("name", "").strip()
    username = body.get("username", "").strip()
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
            # Null-out created_by on admins they created so admins are not deleted
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
#  5. ADMINS (master can also create/manage admins directly)
#     GET/POST  /api/master/admins
#     PUT/DELETE/PATCH  /api/master/admins/<id>
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
    """Master creates an admin directly (not via super admin)."""
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
    return ok({"id": new_id, "name": name, "username": username, "district": district},
              "Admin created", 201)


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
#  6. SYSTEM OVERVIEW   GET /api/master/overview
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

            config = _get_config_map(cur)
    finally:
        conn.close()

    return ok({
        "totalSuperAdmins": super_admins,
        "totalAdmins":      admins,
        "totalStaff":       staff,
        "totalBooths":      booths,
        "assignedDuties":   duties,
        "electionInfo": {
            "state":        config.get("state", "Not set"),
            "electionYear": config.get("electionYear", "Not set"),
            "electionDate": config.get("electionDate", "Not set"),
            "phase":        config.get("phase", "Not set"),
        }
    })


# ══════════════════════════════════════════════════════════════════════════════
#  7. SYSTEM STATS   GET /api/master/system-stats
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
                      "sectors","zones","super_zones","gram_panchayats"]:
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
#  8. LOGS   GET /api/master/logs
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
#  9. DB BACKUP   POST /api/master/db/backup
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
        mysqldump_path = "mysqldump"   # rely on PATH

    try:
        subprocess.run(
            [mysqldump_path,
             f"-u{Config.DB_USER}",
             f"-p{Config.DB_PASS}",
             Config.DB_NAME,
             f"--result-file={filename}"],
            check=True,
            capture_output=True,
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


# ══════════════════════════════════════════════════════════════════════════════
#  10. MIGRATE   POST /api/master/migrate
# ══════════════════════════════════════════════════════════════════════════════

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


# ── Health / ping ─────────────────────────────────────────────────────────────

@master_bp.route("/ping", methods=["GET"])
def ping():
    return ok("pong")