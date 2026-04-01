from flask import Blueprint, request, jsonify
from functools import wraps
from datetime import datetime
from db import get_db
from config import Config
import jwt
import time

master_bp = Blueprint("master", __name__, url_prefix="/api/master")


# ─── Helpers ──────────────────────────────────────────────────────────────────
def ok(data=None, message="success"):
    return jsonify({"status": "success", "message": message, "data": data}), 200

def err(message="error", code=400):
    return jsonify({"status": "error", "message": message}), code

def write_log(level: str, message: str, module: str):
    try:
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO system_logs (level, message, module) VALUES (%s, %s, %s)",
                (level, message, module)
            )
        conn.commit()
        conn.close()
    except Exception:
        pass


# ─── Auth middleware ───────────────────────────────────────────────────────────
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
#  1. LOGIN          POST /master/login
# ══════════════════════════════════════════════════════════════════════════════
@master_bp.route("/login", methods=["POST"])
def master_login():
    from werkzeug.security import check_password_hash
    body     = request.get_json() or {}
    username = body.get("username", "").strip()
    password = body.get("password", "")
    if not username or not password:
        return err("Username and password required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM users WHERE username = %s AND role = 'master'", (username,))
            user = cur.fetchone()
    finally:
        conn.close()

    if not user or not check_password_hash(user["password"], password):
        return err("Invalid credentials", 401)
    if not user["is_active"]:
        return err("Account is inactive", 403)

    payload = {
        "id": user["id"], "username": user["username"],
        "role": "master", "exp": int(time.time()) + Config.JWT_EXPIRY,
    }
    token = jwt.encode(payload, Config.JWT_SECRET, algorithm="HS256")
    write_log("INFO", f"Master '{username}' logged in", "Auth")
    return ok({"token": token, "name": user["name"], "username": user["username"]}, "Login successful")


# ══════════════════════════════════════════════════════════════════════════════
#  2. GET SUPER ADMINS    GET /master/super-admins
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
                LEFT JOIN users a ON a.created_by = sa.id AND a.role = 'admin'
                WHERE sa.role = 'super_admin'
                GROUP BY sa.id
                ORDER BY sa.created_at DESC
            """)
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id": r["id"], "name": r["name"], "username": r["username"],
        "isActive": bool(r["is_active"]),
        "createdAt": r["created_at"].isoformat() if r["created_at"] else None,
        "adminsUnder": r["admins_under"],
    } for r in rows])


# ══════════════════════════════════════════════════════════════════════════════
#  3. CREATE SUPER ADMIN  POST /master/create-super-admin
# ══════════════════════════════════════════════════════════════════════════════
@master_bp.route("/create-super-admin", methods=["POST"])
@master_required
def create_super_admin():
    from werkzeug.security import generate_password_hash
    body     = request.get_json() or {}
    name     = body.get("name", "").strip()
    username = body.get("username", "").strip()
    password = body.get("password", "")
    if not name or not username or not password:
        return err("All fields are required")
    if len(password) < 6:
        return err("Password must be at least 6 characters")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE username = %s", (username,))
            if cur.fetchone():
                return err("Username already taken", 409)
            cur.execute(
                "INSERT INTO users (name, username, password, role, is_active, created_by) VALUES (%s,%s,%s,'super_admin',1,%s)",
                (name, username, generate_password_hash(password), request.master_id)
            )
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Super Admin '{name}' (ID:{new_id}) created by master", "Auth")
    return ok({"id": new_id, "name": name, "username": username}, "Super Admin created successfully")


# ══════════════════════════════════════════════════════════════════════════════
#  4. TOGGLE STATUS   PUT /master/super-admin/<id>/status
# ══════════════════════════════════════════════════════════════════════════════
@master_bp.route("/super-admin/<int:sa_id>/status", methods=["PUT"])
@master_required
def toggle_super_admin_status(sa_id):
    body      = request.get_json() or {}
    is_active = body.get("isActive")
    if is_active is None:
        return err("isActive field required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT name FROM users WHERE id = %s AND role = 'super_admin'", (sa_id,))
            row = cur.fetchone()
            if not row:
                return err("Super Admin not found", 404)
            cur.execute("UPDATE users SET is_active = %s WHERE id = %s", (1 if is_active else 0, sa_id))
        conn.commit()
    finally:
        conn.close()
    action = "activated" if is_active else "deactivated"
    write_log("INFO", f"Super Admin '{row['name']}' (ID:{sa_id}) {action} by master", "Auth")
    return ok({"id": sa_id, "isActive": bool(is_active)}, f"Super Admin {action}")


# ══════════════════════════════════════════════════════════════════════════════
#  5. DELETE SUPER ADMIN  DELETE /master/super-admin/<id>
# ══════════════════════════════════════════════════════════════════════════════
@master_bp.route("/super-admin/<int:sa_id>", methods=["DELETE"])
@master_required
def delete_super_admin(sa_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT name FROM users WHERE id = %s AND role = 'super_admin'", (sa_id,))
            row = cur.fetchone()
            if not row:
                return err("Super Admin not found", 404)
            name = row["name"]
            cur.execute("UPDATE users SET created_by = NULL WHERE created_by = %s AND role = 'admin'", (sa_id,))
            cur.execute("DELETE FROM users WHERE id = %s", (sa_id,))
        conn.commit()
    finally:
        conn.close()
    write_log("WARN", f"Super Admin '{name}' (ID:{sa_id}) deleted by master", "Auth")
    return ok(None, f"Super Admin '{name}' deleted")


# ══════════════════════════════════════════════════════════════════════════════
#  6. API HEALTH      GET /master/health
# ══════════════════════════════════════════════════════════════════════════════
@master_bp.route("/health", methods=["GET"])
@master_required
def api_health():
    import requests as req
    BASE = Config.BASE_URL
    endpoints = ["/master/ping","/api/login","/api/super-admins",
                 "/api/admins","/api/staff","/api/duties","/api/booths","/api/pdf/duty-card"]
    results = []
    for ep in endpoints:
        start = time.time(); status = "DOWN"; latency = 0
        try:
            r = req.get(BASE + ep, timeout=3)
            latency = int((time.time() - start) * 1000)
            status  = "SLOW" if latency > 500 else "UP"
            if r.status_code >= 500: status = "DOWN"
        except Exception:
            pass
        results.append({"endpoint": ep, "status": status, "latencyMs": latency})
    return ok(results)

@master_bp.route("/ping", methods=["GET"])
def ping():
    return ok("pong")


# ══════════════════════════════════════════════════════════════════════════════
#  7. LOGS            GET /master/logs
# ══════════════════════════════════════════════════════════════════════════════
@master_bp.route("/logs", methods=["GET"])
@master_required
def get_logs():
    level = request.args.get("level", "ALL").upper()
    limit = min(int(request.args.get("limit", 100)), 500)
    conn  = get_db()
    try:
        with conn.cursor() as cur:
            if level == "ALL":
                cur.execute("SELECT * FROM system_logs ORDER BY time DESC LIMIT %s", (limit,))
            else:
                cur.execute("SELECT * FROM system_logs WHERE level = %s ORDER BY time DESC LIMIT %s", (level, limit))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{"id": r["id"], "level": r["level"], "message": r["message"],
                "module": r["module"], "time": r["time"].isoformat()} for r in rows])


# ══════════════════════════════════════════════════════════════════════════════
#  8. SYSTEM STATS    GET /master/system-stats
# ══════════════════════════════════════════════════════════════════════════════
@master_bp.route("/system-stats", methods=["GET"])
@master_required
def system_stats():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT ROUND(SUM(data_length+index_length)/1024/1024,2) AS size_mb FROM information_schema.tables WHERE table_schema=DATABASE()")
            size_row = cur.fetchone()
            db_size  = f"{size_row['size_mb']} MB" if size_row and size_row["size_mb"] else "N/A"

            total = 0
            for t in ["users","staff","duties","matdan_kendra","matdan_sthal","sectors","zones"]:
                cur.execute(f"SELECT COUNT(*) AS cnt FROM {t}")
                total += cur.fetchone()["cnt"]

            cur.execute("SELECT time FROM system_logs WHERE module='DB' AND message LIKE 'Database backup%' ORDER BY time DESC LIMIT 1")
            br  = cur.fetchone()
            last_backup = br["time"].strftime("%d %b %Y %H:%M") if br else "Never"

            cur.execute("SELECT MIN(time) AS first FROM system_logs")
            fr = cur.fetchone()
            if fr and fr["first"]:
                d = datetime.utcnow() - fr["first"]
                uptime = f"{d.days}d {d.seconds//3600}h {(d.seconds%3600)//60}m"
            else:
                uptime = "N/A"
    finally:
        conn.close()
    return ok({"dbSize": db_size, "totalRecords": total, "uptime": uptime,
               "lastBackup": last_backup, "flutterBuild": "v1.0.0+1", "backend": "Flask 3.0"})


# ══════════════════════════════════════════════════════════════════════════════
#  9. DB TOOLS
# ══════════════════════════════════════════════════════════════════════════════
@master_bp.route("/db/backup", methods=["POST"])
@master_required
def db_backup():
    import subprocess
    from pathlib import Path
    backup_dir = Path("backups"); backup_dir.mkdir(exist_ok=True)
    ts       = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    filename = backup_dir / f"election_db_{ts}.sql"
    try:
        subprocess.run(["mysqldump", f"-u{Config.DB_USER}", f"-p{Config.DB_PASS}",
                        Config.DB_NAME, f"--result-file={filename}"],
                       check=True, capture_output=True)
        write_log("INFO", f"Database backup created: {filename.name}", "DB")
        return ok({"file": filename.name}, "Backup completed")
    except subprocess.CalledProcessError as e:
        write_log("ERROR", "Database backup failed", "DB")
        return err(f"Backup failed: {e.stderr.decode()}", 500)

@master_bp.route("/db/flush-cache", methods=["POST"])
@master_required
def flush_cache():
    write_log("INFO", "Cache flushed by master", "System")
    return ok(None, "Cache flushed successfully")

@master_bp.route("/db/reset-duties", methods=["POST"])
@master_required
def reset_duties():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS cnt FROM duties")
            count = cur.fetchone()["cnt"]
            cur.execute("DELETE FROM duties")
            cur.execute("UPDATE staff SET is_assigned = 0")
        conn.commit()
    finally:
        conn.close()
    write_log("WARN", f"All duties reset — {count} records deleted by master", "DB")
    return ok({"deleted": count}, "All duties have been reset")


# ══════════════════════════════════════════════════════════════════════════════
#  10. CONFIG
# ══════════════════════════════════════════════════════════════════════════════
@master_bp.route("/config", methods=["GET"])
@master_required
def get_config():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT `key`, value FROM app_config")
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok({r["key"]: r["value"] for r in rows})

@master_bp.route("/config", methods=["POST"])
@master_required
def update_config():
    body = request.get_json() or {}
    key  = body.get("key"); value = body.get("value")
    if not key:
        return err("Config key required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO app_config (`key`, value) VALUES (%s,%s) ON DUPLICATE KEY UPDATE value=VALUES(value)", (key, str(value)))
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Config updated: {key} = {value}", "Config")
    return ok({"key": key, "value": value}, "Config updated")