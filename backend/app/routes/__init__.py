import time
import json
import traceback
from functools import wraps
from flask import request, jsonify, g
from config import Config
import jwt


# ─────────────────────────────────────────────
#  RESPONSE HELPERS
# ─────────────────────────────────────────────
def ok(data=None, message="success", code=200):
    return jsonify({"status": "success", "message": message, "data": data}), code

def err(message="error", code=400):
    return jsonify({"status": "error", "message": message}), code


# ─────────────────────────────────────────────
#  TOKEN DECODE
# ─────────────────────────────────────────────
def decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, Config.JWT_SECRET, algorithms=["HS256"])
    except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
        return None


def _get_payload():
    """
    Extract token from Authorization header OR cookie ('token').
    """
    token = None
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        token = auth.split(" ", 1)[1]
    else:
        # Fallback to cookie (web client)
        token = request.cookies.get("token")

    if not token:
        return None, err("Missing or malformed token", 401)

    payload = decode_token(token)
    if not payload:
        return None, err("Invalid or expired token", 401)

    # 🆕 Check token revocation (force logout by role)
    if _is_token_revoked(payload):
        return None, err("Session expired — please log in again", 401)

    return payload, None


# ─────────────────────────────────────────────
#  🆕 TOKEN REVOCATION CHECK (for force-logout)
# ─────────────────────────────────────────────
def _is_token_revoked(payload: dict) -> bool:
    """
    Returns True if this token was issued BEFORE a revocation timestamp
    set by master for the token's role.
    """
    try:
        from db import get_db
        role = payload.get("role")
        iat  = payload.get("iat")
        if not role or not iat:
            return False

        conn = get_db()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT revoke_before FROM token_revocations WHERE role=%s LIMIT 1",
                    (role,)
                )
                row = cur.fetchone()
                if not row:
                    return False
                return int(iat) < int(row["revoke_before"])
        finally:
            conn.close()
    except Exception:
        return False   # Fail open on DB errors — don't lock users out


# ─────────────────────────────────────────────
#  ROLE-BASED DECORATORS
# ─────────────────────────────────────────────
def _role_guard(*allowed_roles):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            payload, error = _get_payload()
            if error:
                return error
            if payload.get("role") not in allowed_roles:
                return err(f"Access denied — requires one of: {allowed_roles}", 403)
            request.user = payload
            return f(*args, **kwargs)
        return wrapper
    return decorator


def master_required(f):
    return _role_guard("master")(f)

def super_admin_required(f):
    return _role_guard("master", "super_admin")(f)

def admin_required(f):
    return _role_guard("master", "super_admin", "admin")(f)

def login_required(f):
    return _role_guard("master", "super_admin", "admin", "staff")(f)


# ─────────────────────────────────────────────
#  LEGACY LOG WRITER (system_logs table)
# ─────────────────────────────────────────────
def write_log(level: str, message: str, module: str):
    try:
        from db import get_db
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


# ─────────────────────────────────────────────
#  🆕 API REQUEST LOGGER
#  Called by the global before_request / after_request hooks in run.py
# ─────────────────────────────────────────────
def write_api_log(method, path, status_code, duration_ms,
                  user_id=None, username=None, role=None,
                  ip=None, user_agent=None, request_body=None,
                  error_message=None):
    try:
        from db import get_db

        # Auto-pick level from status code
        if status_code >= 500:
            level = "ERROR"
        elif status_code >= 400:
            level = "WARN"
        else:
            level = "INFO"

        # Truncate long bodies
        if request_body and len(request_body) > 2000:
            request_body = request_body[:2000] + "…(truncated)"

        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO api_request_logs
                    (method, path, status_code, duration_ms, user_id, username,
                     role, ip_address, user_agent, request_body, error_message, level)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """, (
                method, path, status_code, duration_ms,
                user_id, username, role, ip, user_agent,
                request_body, error_message, level
            ))
        conn.commit()
        conn.close()
    except Exception:
        pass   # never let logging crash the app


def _extract_user_from_request():
    """
    Best-effort extraction of user info from incoming JWT (no raise).
    Returns (user_id, username, role).
    """
    try:
        token = None
        auth = request.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            token = auth.split(" ", 1)[1]
        else:
            token = request.cookies.get("token")

        if not token:
            return None, None, None

        payload = decode_token(token)
        if not payload:
            return None, None, None

        return payload.get("id"), payload.get("username"), payload.get("role")
    except Exception:
        return None, None, None


def start_request_timer():
    """Register on Flask's before_request."""
    g._req_start = time.time()


def log_request_end(response):
    """Register on Flask's after_request."""
    try:
        # Skip some noisy paths
        path = request.path or ""
        if path in ("/ping",) or path.startswith("/static"):
            return response

        duration_ms = int((time.time() - getattr(g, "_req_start", time.time())) * 1000)

        # Grab body safely (only for non-GET + small JSON)
        body_str = None
        if request.method in ("POST", "PUT", "PATCH", "DELETE"):
            try:
                if request.is_json:
                    raw = request.get_json(silent=True) or {}
                    # scrub passwords
                    safe = {k: ("***" if "password" in k.lower() else v)
                            for k, v in raw.items()} if isinstance(raw, dict) else raw
                    body_str = json.dumps(safe, ensure_ascii=False)[:2000]
            except Exception:
                body_str = None

        user_id, username, role = _extract_user_from_request()

        err_msg = None
        if response.status_code >= 400:
            try:
                data = response.get_json(silent=True)
                if data and isinstance(data, dict):
                    err_msg = data.get("message") or data.get("error")
            except Exception:
                err_msg = None

        write_api_log(
            method       = request.method,
            path         = path[:500],
            status_code  = response.status_code,
            duration_ms  = duration_ms,
            user_id      = user_id,
            username     = username,
            role         = role,
            ip           = request.remote_addr,
            user_agent   = (request.headers.get("User-Agent") or "")[:500],
            request_body = body_str,
            error_message= err_msg,
        )
    except Exception:
        pass
    return response


def log_exception(e):
    """Register on Flask's errorhandler(Exception) for 500s."""
    try:
        duration_ms = int((time.time() - getattr(g, "_req_start", time.time())) * 1000)
        user_id, username, role = _extract_user_from_request()
        tb = traceback.format_exc()
        write_api_log(
            method       = request.method,
            path         = (request.path or "")[:500],
            status_code  = 500,
            duration_ms  = duration_ms,
            user_id      = user_id,
            username     = username,
            role         = role,
            ip           = request.remote_addr,
            user_agent   = (request.headers.get("User-Agent") or "")[:500],
            request_body = None,
            error_message= f"{type(e).__name__}: {str(e)}\n{tb[:1500]}",
        )
    except Exception:
        pass
    return err("Internal server error", 500)