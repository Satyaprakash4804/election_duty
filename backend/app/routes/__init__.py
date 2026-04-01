import time
from functools import wraps
from flask import request, jsonify
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
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None, err("Missing or malformed token", 401)
    payload = decode_token(auth.split(" ", 1)[1])
    if not payload:
        return None, err("Invalid or expired token", 401)
    return payload, None


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
#  LOG WRITER (imported by every route file)
# ─────────────────────────────────────────────
def write_log(level: str, message: str, module: str):
    try:
        from backend.db import get_db
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO system_logs (level, message, module) VALUES (%s,%s,%s)",
                (level, message, module),
            )
        conn.commit()
        conn.close()
    except Exception:
        pass   # never let logging crash the app