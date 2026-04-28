import time
from flask import Blueprint, request, make_response
import hashlib
from db import get_db
from config import Config
from app.routes import ok, err, write_log
import jwt

auth_bp = Blueprint("auth", __name__, url_prefix="/api")


@auth_bp.route("/auth/login", methods=["POST"])
def login():
    body     = request.get_json() or {}
    username = (body.get("username") or body.get("pno") or "").strip()
    password = body.get("password", "")

    if not username or not password:
        return err("Username/PNO and password are required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT * FROM users
                WHERE (username = %s OR pno = %s)
                AND is_active = 1
                LIMIT 1
            """, (username, username))
            user = cur.fetchone()
    finally:
        conn.close()

    if not user:
        return err("Invalid credentials", 401)

    SALT = "election_2026_secure_key"
    hashed_input = hashlib.sha256((password + SALT).encode()).hexdigest()

    if hashed_input != user["password"]:
        write_log("WARN", f"Failed login attempt for '{username}'", "Auth")
        return err("Invalid credentials", 401)

    # 🔹 Create JWT — NOTE: `iat` (issued-at) is required for force-logout check
    now = int(time.time())
    payload = {
        "id":       user["id"],
        "username": user["username"] or user["pno"],
        "name":     user["name"],
        "role":     user["role"],
        "district": user.get("district"),
        "iat":      now,                                  # 🆕
        "exp":      now + Config.JWT_EXPIRY,
    }

    token = jwt.encode(payload, Config.JWT_SECRET, algorithm="HS256")

    write_log("INFO", f"User '{user['name']}' ({user['role']}) logged in", "Auth")

    is_web = body.get("platform") == "web"

    response_data = {
        "user": {
            "id":       user["id"],
            "name":     user["name"],
            "username": user["username"],
            "pno":      user["pno"],
            "role":     user["role"].upper(),
            "district": user.get("district"),
            "mobile":   user.get("mobile"),
        }
    }

    if not is_web:
        response_data["token"] = token
        return ok(response_data, "Login successful")

    resp = make_response(ok(response_data, "Login successful"))
    resp.set_cookie(
        "token",
        token,
        httponly=True,
        secure=False,
        samesite="Lax",
        max_age=Config.JWT_EXPIRY
    )
    return resp


@auth_bp.route("/logout", methods=["POST"])
def logout():
    resp = make_response(ok(None, "Logged out"))
    resp.set_cookie("token", "", expires=0)
    return resp