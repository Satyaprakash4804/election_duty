"""
app/routes/multi_super.py
═════════════════════════
Self-contained blueprint for the multi-district Super Admin's OWN endpoints.

This file is INTENTIONALLY independent — it defines its own auth guard
and ensures the `user_districts` table exists on import. You can drop it
in and it will work even if you haven't applied any other patches.

Mount in run.py:
    from app.routes.multi_super import multi_super_bp
    app.register_blueprint(multi_super_bp)

Endpoints
─────────
GET  /api/multi-super/ping
    Health check — no auth required. Useful to verify the blueprint
    actually registered in Flask.

GET  /api/multi-super/my-districts
    Returns the assigned-districts list for the logged-in multi_super_admin,
    each with quick election-status & counts.

POST /api/multi-super/select-district
    Just an audit-log endpoint — the actual "context switch" happens
    client-side by setting the `X-Active-District` header on subsequent
    requests to /api/super/*.
"""

from functools import wraps
from flask import Blueprint, request, jsonify
import jwt

from db import get_db
from config import Config


multi_super_bp = Blueprint("multi_super", __name__, url_prefix="/api/multi-super")


# ─────────────────────────────────────────────────────────────────────────────
#  LOCAL RESPONSE HELPERS
#  (We DON'T import from app.routes so this file works standalone.)
# ─────────────────────────────────────────────────────────────────────────────
def _ok(data=None, message="success", code=200):
    return jsonify({"status": "success", "message": message, "data": data}), code


def _err(message="error", code=400):
    return jsonify({"status": "error", "message": message}), code


def _write_log(level, message, module):
    """Best-effort log write — never raises."""
    try:
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO system_logs (level, message, module) VALUES (%s,%s,%s)",
                (level, message, module),
            )
        conn.commit()
        conn.close()
    except Exception:
        pass


# ─────────────────────────────────────────────────────────────────────────────
#  AUTO-BOOTSTRAP `user_districts` TABLE
#  Runs once on import. Idempotent. Safe even if init_db() already created it.
# ─────────────────────────────────────────────────────────────────────────────
def _ensure_user_districts_table():
    try:
        conn = get_db()
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS user_districts (
                        id          INT AUTO_INCREMENT PRIMARY KEY,
                        user_id     INT          NOT NULL,
                        district    VARCHAR(100) NOT NULL,
                        assigned_by INT          DEFAULT NULL,
                        created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        UNIQUE KEY uq_user_district (user_id, district),
                        INDEX idx_user_id  (user_id),
                        INDEX idx_district (district)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                """)
            conn.commit()
        finally:
            conn.close()
    except Exception as e:
        # Don't crash app import — just log to stderr
        print(f"⚠️  user_districts table bootstrap skipped: {e}")


_ensure_user_districts_table()


# ─────────────────────────────────────────────────────────────────────────────
#  INLINE AUTH GUARD — accepts master OR multi_super_admin tokens.
# ─────────────────────────────────────────────────────────────────────────────
def _multi_super_required(f):
    """
    Decorator: requires a valid JWT with role in {'master', 'multi_super_admin'}.
    On success, sets `request.user = payload`.
    """
    @wraps(f)
    def wrapper(*args, **kwargs):
        # 1) Extract token
        token = None
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header.split(" ", 1)[1]
        else:
            token = request.cookies.get("token")

        if not token:
            return _err("Missing or malformed token", 401)

        # 2) Decode
        try:
            payload = jwt.decode(token, Config.JWT_SECRET, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            return _err("Token expired", 401)
        except jwt.InvalidTokenError:
            return _err("Invalid token", 401)

        # 3) Role check
        role = (payload.get("role") or "").lower()
        if role not in ("master", "multi_super_admin"):
            return _err(
                "Access denied — requires role 'multi_super_admin' or 'master'",
                403,
            )

        # 4) Token-revocation check (best-effort, matches the global pattern)
        try:
            iat = payload.get("iat")
            if iat and role != "master":
                conn = get_db()
                try:
                    with conn.cursor() as cur:
                        cur.execute(
                            "SELECT revoke_before FROM token_revocations "
                            "WHERE role=%s LIMIT 1",
                            (role,),
                        )
                        row = cur.fetchone()
                        if row and int(iat) < int(row["revoke_before"]):
                            return _err(
                                "Session expired — please log in again", 401
                            )
                finally:
                    conn.close()
        except Exception:
            # Fail open on revocation-table errors — don't lock users out
            pass

        # 5) All good — stash payload and proceed
        request.user = payload
        return f(*args, **kwargs)

    return wrapper


# ─────────────────────────────────────────────────────────────────────────────
#  PING — no auth, for verifying registration
# ─────────────────────────────────────────────────────────────────────────────
@multi_super_bp.route("/ping", methods=["GET"])
def ping():
    return _ok("pong", "multi_super blueprint is alive")


# ─────────────────────────────────────────────────────────────────────────────
#  1. MY ASSIGNED DISTRICTS + STATUS
# ─────────────────────────────────────────────────────────────────────────────
@multi_super_bp.route("/my-districts", methods=["GET"])
@_multi_super_required
def my_districts():
    uid = request.user.get("id")
    if not uid:
        return _err("Invalid token (missing id)", 401)

    role = (request.user.get("role") or "").lower()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # ── Load assigned districts ────────────────────────────────────
            # For 'master', return all districts present in user_districts
            # OR in election_configs (so master can preview the same screen).
            if role == "master":
                cur.execute("""
                    SELECT DISTINCT district FROM (
                        SELECT district FROM user_districts WHERE district <> ''
                        UNION
                        SELECT district FROM election_configs WHERE district <> ''
                    ) t
                    ORDER BY district
                """)
            else:
                cur.execute(
                    "SELECT district FROM user_districts "
                    "WHERE user_id=%s ORDER BY district",
                    (uid,),
                )
            districts = [r["district"] for r in cur.fetchall()]

            # ── Build per-district status rows ─────────────────────────────
            out = []
            for d in districts:
                # Most recent config (any state)
                cur.execute("""
                    SELECT id, election_name, election_type, phase,
                           election_year, election_date,
                           is_active, is_archived, is_finalized, auto_finalized,
                           finalized_at, archived_at
                    FROM election_configs
                    WHERE district=%s
                    ORDER BY
                        is_active   DESC,
                        is_archived ASC,
                        COALESCE(updated_at, created_at) DESC
                    LIMIT 1
                """, (d,))
                cfg = cur.fetchone()

                # Counts
                cur.execute(
                    "SELECT COUNT(*) AS cnt FROM users "
                    "WHERE LOWER(role)='admin' AND district=%s AND is_active=1",
                    (d,),
                )
                admin_count = (cur.fetchone() or {}).get("cnt", 0)

                cur.execute(
                    "SELECT COUNT(*) AS cnt FROM users "
                    "WHERE LOWER(role)='super_admin' AND district=%s AND is_active=1",
                    (d,),
                )
                sa_count = (cur.fetchone() or {}).get("cnt", 0)

                # Status calc
                if not cfg:
                    status = "none"
                    name = ""
                    date_s = ""
                elif cfg.get("is_finalized"):
                    status = "auto_final" if cfg.get("auto_finalized") else "finalized"
                    name = cfg.get("election_name") or ""
                    date_s = (
                        cfg["election_date"].isoformat()
                        if cfg.get("election_date") else ""
                    )
                elif cfg.get("is_active") and not cfg.get("is_archived"):
                    status = "active"
                    name = cfg.get("election_name") or ""
                    date_s = (
                        cfg["election_date"].isoformat()
                        if cfg.get("election_date") else ""
                    )
                elif cfg.get("is_archived"):
                    status = "archived"
                    name = cfg.get("election_name") or ""
                    date_s = (
                        cfg["election_date"].isoformat()
                        if cfg.get("election_date") else ""
                    )
                else:
                    status = "none"
                    name = cfg.get("election_name") or ""
                    date_s = ""

                out.append({
                    "district":        d,
                    "status":          status,
                    "electionName":    name,
                    "electionDate":    date_s,
                    "adminCount":      int(admin_count or 0),
                    "superAdminCount": int(sa_count or 0),
                })
    except Exception as e:
        _write_log("ERROR", f"my-districts failed: {e}", "MultiSuper")
        return _err(f"Server error: {e}", 500)
    finally:
        try:
            conn.close()
        except Exception:
            pass

    return _ok({
        "user": {
            "id":       request.user.get("id"),
            "name":     request.user.get("name"),
            "username": request.user.get("username"),
            "role":     role,
        },
        "districts": out,
        "total":     len(out),
    })


# ─────────────────────────────────────────────────────────────────────────────
#  2. SELECT-DISTRICT (audit only — frontend just starts sending the header)
# ─────────────────────────────────────────────────────────────────────────────
@multi_super_bp.route("/select-district", methods=["POST"])
@_multi_super_required
def select_district():
    """
    Body: { "district": "आगरा" }
    Verifies the district is assigned to the user, writes an audit log.
    Returns 200 OK — the client then begins sending X-Active-District.
    """
    body = request.get_json(silent=True) or {}
    district = (body.get("district") or "").strip()
    if not district:
        return _err("district is required")

    uid = request.user.get("id")
    role = (request.user.get("role") or "").lower()

    # Master can switch to any district; multi_super_admin must own it
    if role != "master":
        conn = get_db()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT 1 FROM user_districts "
                    "WHERE user_id=%s AND district=%s",
                    (uid, district),
                )
                if not cur.fetchone():
                    return _err(
                        f"District '{district}' is not assigned to this user",
                        403,
                    )
        finally:
            try:
                conn.close()
            except Exception:
                pass

    _write_log(
        "INFO",
        f"User ID:{uid} ({role}) switched to district '{district}'",
        "Auth",
    )
    return _ok({"district": district}, f"Context set to '{district}'")
