from flask import Blueprint, request, jsonify
from functools import wraps
from datetime import datetime
import jwt
import time
import os

# ─────────────────────────────────────────────
#  BLUEPRINT
# ─────────────────────────────────────────────
master_bp = Blueprint("master", __name__, url_prefix="/master")

SECRET_KEY = os.environ.get("JWT_SECRET", "your_secret_key")

# ─────────────────────────────────────────────
#  AUTH MIDDLEWARE  (Developer / Master only)
# ─────────────────────────────────────────────
def master_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return jsonify({"error": "Missing token"}), 401
        token = auth.split(" ")[1]
        try:
            payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
            if payload.get("role") != "master":
                return jsonify({"error": "Forbidden"}), 403
            request.master_id = payload["id"]
        except jwt.ExpiredSignatureError:
            return jsonify({"error": "Token expired"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"error": "Invalid token"}), 401
        return f(*args, **kwargs)
    return decorated


# ─────────────────────────────────────────────
#  HELPER — uniform response
# ─────────────────────────────────────────────
def ok(data=None, message="success"):
    return jsonify({"status": "success", "message": message, "data": data}), 200

def err(message="error", code=400):
    return jsonify({"status": "error", "message": message}), code


# ══════════════════════════════════════════════
#  1.  MASTER LOGIN
#      POST /master/login
# ══════════════════════════════════════════════
@master_bp.route("/login", methods=["POST"])
def master_login():
    """
    Body: { "username": str, "password": str }
    Returns JWT token with role=master
    """
    from models import MasterAdmin          # your SQLAlchemy model
    from werkzeug.security import check_password_hash

    body = request.get_json() or {}
    username = body.get("username", "").strip()
    password = body.get("password", "")

    if not username or not password:
        return err("Username and password required")

    master = MasterAdmin.query.filter_by(username=username).first()
    if not master or not check_password_hash(master.password_hash, password):
        return err("Invalid credentials", 401)

    payload = {
        "id":       master.id,
        "username": master.username,
        "role":     "master",
        "exp":      int(time.time()) + 36000,   # 10 hours
    }
    token = jwt.encode(payload, SECRET_KEY, algorithm="HS256")

    return ok({
        "token":    token,
        "name":     master.name,
        "username": master.username,
    }, "Login successful")


# ══════════════════════════════════════════════
#  2.  GET ALL SUPER ADMINS
#      GET /master/super-admins
# ══════════════════════════════════════════════
@master_bp.route("/super-admins", methods=["GET"])
@master_required
def get_super_admins():
    """
    Returns list of all super admins with their admin count.
    """
    from models import SuperAdmin, Admin    # your SQLAlchemy models

    supers = SuperAdmin.query.order_by(SuperAdmin.created_at.desc()).all()

    result = []
    for sa in supers:
        admin_count = Admin.query.filter_by(super_admin_id=sa.id).count()
        result.append({
            "id":           sa.id,
            "name":         sa.name,
            "username":     sa.username,
            "createdAt":    sa.created_at.isoformat(),
            "adminsUnder":  admin_count,
            "isActive":     sa.is_active,
        })

    return ok(result)


# ══════════════════════════════════════════════
#  3.  CREATE SUPER ADMIN
#      POST /master/create-super-admin
# ══════════════════════════════════════════════
@master_bp.route("/create-super-admin", methods=["POST"])
@master_required
def create_super_admin():
    """
    Body: { "name": str, "username": str, "password": str }
    """
    from models import SuperAdmin, db
    from werkzeug.security import generate_password_hash

    body = request.get_json() or {}
    name     = body.get("name", "").strip()
    username = body.get("username", "").strip()
    password = body.get("password", "")

    if not name or not username or not password:
        return err("All fields are required")

    if len(password) < 6:
        return err("Password must be at least 6 characters")

    existing = SuperAdmin.query.filter_by(username=username).first()
    if existing:
        return err("Username already taken", 409)

    sa = SuperAdmin(
        name          = name,
        username      = username,
        password_hash = generate_password_hash(password),
        is_active     = True,
        created_at    = datetime.utcnow(),
    )
    db.session.add(sa)
    db.session.commit()

    # Log the action
    _write_log("INFO", f"Super Admin {sa.id} ({name}) created by master", "Auth")

    return ok({
        "id":       sa.id,
        "name":     sa.name,
        "username": sa.username,
    }, "Super Admin created successfully")


# ══════════════════════════════════════════════
#  4.  TOGGLE SUPER ADMIN STATUS
#      PUT /master/super-admin/<id>/status
# ══════════════════════════════════════════════
@master_bp.route("/super-admin/<int:sa_id>/status", methods=["PUT"])
@master_required
def toggle_super_admin_status(sa_id):
    """
    Body: { "isActive": bool }
    """
    from models import SuperAdmin, db

    sa = SuperAdmin.query.get(sa_id)
    if not sa:
        return err("Super Admin not found", 404)

    body     = request.get_json() or {}
    is_active = body.get("isActive")

    if is_active is None:
        return err("isActive field required")

    sa.is_active = bool(is_active)
    db.session.commit()

    action = "activated" if sa.is_active else "deactivated"
    _write_log("INFO", f"Super Admin {sa.id} ({sa.name}) {action}", "Auth")

    return ok({"id": sa.id, "isActive": sa.is_active}, f"Super Admin {action}")


# ══════════════════════════════════════════════
#  5.  DELETE SUPER ADMIN
#      DELETE /master/super-admin/<id>
# ══════════════════════════════════════════════
@master_bp.route("/super-admin/<int:sa_id>", methods=["DELETE"])
@master_required
def delete_super_admin(sa_id):
    """
    Deletes a super admin. Cascades to admins under them (handle in DB or here).
    """
    from models import SuperAdmin, Admin, db

    sa = SuperAdmin.query.get(sa_id)
    if not sa:
        return err("Super Admin not found", 404)

    name = sa.name

    # Optional: reassign or delete admins under this super admin
    Admin.query.filter_by(super_admin_id=sa_id).delete()

    db.session.delete(sa)
    db.session.commit()

    _write_log("WARN", f"Super Admin {sa_id} ({name}) deleted by master", "Auth")

    return ok(None, f"Super Admin '{name}' deleted")


# ══════════════════════════════════════════════
#  6.  API HEALTH CHECK
#      GET /master/health
# ══════════════════════════════════════════════
@master_bp.route("/health", methods=["GET"])
@master_required
def api_health():
    """
    Pings a list of internal endpoints and returns their status.
    """
    import requests as req

    BASE = f"http://localhost:{os.environ.get('PORT', 5000)}"

    endpoints = [
        "/api/login",
        "/api/super-admins",
        "/api/admins",
        "/api/staff",
        "/api/duties",
        "/api/booths",
        "/api/assign-duty",
        "/api/pdf/duty-card",
    ]

    results = []
    for ep in endpoints:
        start = time.time()
        status = "DOWN"
        latency = 0
        try:
            r = req.get(BASE + ep, timeout=3)
            latency = int((time.time() - start) * 1000)
            if r.status_code < 500:
                status = "SLOW" if latency > 500 else "UP"
            else:
                status = "DOWN"
        except Exception:
            latency = 0
            status  = "DOWN"

        results.append({
            "endpoint":  ep,
            "status":    status,
            "latencyMs": latency,
        })

    return ok(results)


# ══════════════════════════════════════════════
#  7.  SYSTEM LOGS
#      GET /master/logs
# ══════════════════════════════════════════════
@master_bp.route("/logs", methods=["GET"])
@master_required
def get_logs():
    """
    Returns system log entries. Supports ?level=INFO|WARN|ERROR&limit=50
    """
    from models import SystemLog    # your model, see schema below

    level = request.args.get("level", "ALL").upper()
    limit = min(int(request.args.get("limit", 100)), 500)

    query = SystemLog.query.order_by(SystemLog.time.desc())
    if level != "ALL":
        query = query.filter_by(level=level)

    logs = query.limit(limit).all()

    return ok([{
        "id":      l.id,
        "level":   l.level,
        "message": l.message,
        "module":  l.module,
        "time":    l.time.isoformat(),
    } for l in logs])


# ══════════════════════════════════════════════
#  8.  SYSTEM STATS
#      GET /master/system-stats
# ══════════════════════════════════════════════
@master_bp.route("/system-stats", methods=["GET"])
@master_required
def system_stats():
    """
    Returns DB size, record counts, uptime, last backup info etc.
    """
    from models import db
    from sqlalchemy import text

    stats = {}

    # DB size (MySQL)
    try:
        result = db.session.execute(text(
            "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb "
            "FROM information_schema.tables "
            "WHERE table_schema = DATABASE()"
        ))
        row = result.fetchone()
        stats["dbSize"] = f"{row[0]} MB" if row and row[0] else "N/A"
    except Exception:
        stats["dbSize"] = "N/A"

    # Record counts
    try:
        from models import SuperAdmin, Admin, Staff, Duty
        stats["totalRecords"] = (
            SuperAdmin.query.count() +
            Admin.query.count() +
            Staff.query.count() +
            Duty.query.count()
        )
    except Exception:
        stats["totalRecords"] = 0

    stats["flutterBuild"] = "v1.0.0+1"
    stats["backend"]      = "Flask 3.0"
    stats["lastBackup"]   = _get_last_backup_date()

    return ok(stats)


# ══════════════════════════════════════════════
#  9.  DATABASE TOOLS
#      POST /master/db/backup
#      POST /master/db/flush-cache
#      POST /master/db/reset-duties
# ══════════════════════════════════════════════
@master_bp.route("/db/backup", methods=["POST"])
@master_required
def db_backup():
    """Trigger a mysqldump and save to /backups/"""
    import subprocess
    from pathlib import Path

    backup_dir = Path("/backups")
    backup_dir.mkdir(exist_ok=True)

    ts       = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    filename = backup_dir / f"election_db_{ts}.sql"

    db_user = os.environ.get("DB_USER", "root")
    db_pass = os.environ.get("DB_PASS", "")
    db_name = os.environ.get("DB_NAME", "election_db")

    try:
        subprocess.run(
            ["mysqldump", f"-u{db_user}", f"-p{db_pass}", db_name,
             f"--result-file={filename}"],
            check=True, capture_output=True
        )
        _write_log("INFO", f"Database backup created: {filename.name}", "DB")
        return ok({"file": filename.name}, "Backup completed")
    except subprocess.CalledProcessError as e:
        return err(f"Backup failed: {e.stderr.decode()}", 500)


@master_bp.route("/db/flush-cache", methods=["POST"])
@master_required
def flush_cache():
    """Clear any server-side cache (extend as needed)."""
    # If you use Flask-Caching:
    # from extensions import cache; cache.clear()
    _write_log("INFO", "Cache flushed by master", "System")
    return ok(None, "Cache flushed successfully")


@master_bp.route("/db/reset-duties", methods=["POST"])
@master_required
def reset_duties():
    """Delete ALL duty assignments — IRREVERSIBLE."""
    from models import Duty, db

    count = Duty.query.count()
    Duty.query.delete()
    db.session.commit()

    _write_log("WARN", f"All duties reset ({count} records deleted) by master", "DB")
    return ok({"deleted": count}, "All duties have been reset")


# ══════════════════════════════════════════════
#  10. CONFIG TOGGLES
#      GET  /master/config
#      POST /master/config
# ══════════════════════════════════════════════
@master_bp.route("/config", methods=["GET"])
@master_required
def get_config():
    """Returns current app config toggles."""
    from models import AppConfig   # key-value config model

    rows = AppConfig.query.all()
    config = {r.key: r.value for r in rows}
    return ok(config)


@master_bp.route("/config", methods=["POST"])
@master_required
def update_config():
    """
    Body: { "key": str, "value": str|bool }
    Updates a single config key.
    """
    from models import AppConfig, db

    body  = request.get_json() or {}
    key   = body.get("key")
    value = body.get("value")

    if not key:
        return err("Config key required")

    row = AppConfig.query.filter_by(key=key).first()
    if row:
        row.value = str(value)
    else:
        db.session.add(AppConfig(key=key, value=str(value)))

    db.session.commit()
    _write_log("INFO", f"Config updated: {key} = {value}", "Config")
    return ok({"key": key, "value": value}, "Config updated")


# ─────────────────────────────────────────────
#  INTERNAL HELPER — write log to DB
# ─────────────────────────────────────────────
def _write_log(level: str, message: str, module: str):
    """Call this from any route to persist a log entry."""
    try:
        from models import SystemLog, db
        db.session.add(SystemLog(
            level   = level,
            message = message,
            module  = module,
            time    = datetime.utcnow(),
        ))
        db.session.commit()
    except Exception:
        pass   # never crash the main request because of logging


def _get_last_backup_date() -> str:
    from pathlib import Path
    backup_dir = Path("/backups")
    if not backup_dir.exists():
        return "Never"
    files = sorted(backup_dir.glob("*.sql"), reverse=True)
    if not files:
        return "Never"
    ts = files[0].stem.split("_", 2)
    if len(ts) >= 2:
        try:
            d = datetime.strptime(ts[1] + ts[2][:6], "%Y%m%d%H%M%S")
            return d.strftime("%d %b %Y %H:%M")
        except Exception:
            pass
    return files[0].name


# ─────────────────────────────────────────────
#  DATABASE MODELS (add to your models.py)
# ─────────────────────────────────────────────
"""
PASTE THESE INTO models.py
───────────────────────────

class SuperAdmin(db.Model):
    __tablename__ = "super_admins"
    id            = db.Column(db.Integer, primary_key=True)
    name          = db.Column(db.String(100), nullable=False)
    username      = db.Column(db.String(50), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    is_active     = db.Column(db.Boolean, default=True)
    created_at    = db.Column(db.DateTime, default=datetime.utcnow)
    admins        = db.relationship("Admin", backref="super_admin",
                                    lazy=True, cascade="all, delete")

class MasterAdmin(db.Model):
    __tablename__ = "master_admins"
    id            = db.Column(db.Integer, primary_key=True)
    name          = db.Column(db.String(100), nullable=False)
    username      = db.Column(db.String(50), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    created_at    = db.Column(db.DateTime, default=datetime.utcnow)

class SystemLog(db.Model):
    __tablename__ = "system_logs"
    id      = db.Column(db.Integer, primary_key=True)
    level   = db.Column(db.String(10), nullable=False)   # INFO|WARN|ERROR
    message = db.Column(db.String(500), nullable=False)
    module  = db.Column(db.String(50), nullable=False)
    time    = db.Column(db.DateTime, default=datetime.utcnow)

class AppConfig(db.Model):
    __tablename__ = "app_config"
    id    = db.Column(db.Integer, primary_key=True)
    key   = db.Column(db.String(100), unique=True, nullable=False)
    value = db.Column(db.String(500), nullable=False)
"""


# ─────────────────────────────────────────────
#  REGISTER IN app.py
# ─────────────────────────────────────────────
"""
from master import master_bp
app.register_blueprint(master_bp)
"""