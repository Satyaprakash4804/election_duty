import time
from flask import Blueprint, request
from werkzeug.security import check_password_hash
from db import get_db
from config import Config
from app.routes import ok, err, write_log
import jwt

auth_bp = Blueprint("auth", __name__, url_prefix="/api")


@auth_bp.route("/login", methods=["POST"])
def login():
    body     = request.get_json() or {}
    # Accept both 'username' and 'pno' as the identifier field
    username = (body.get("username") or body.get("pno") or "").strip()
    password = body.get("password", "")

    if not username or not password:
        return err("Username/PNO and password are required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Match on username OR pno field
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

    if not check_password_hash(user["password"], password):
        write_log("WARN", f"Failed login attempt for '{username}'", "Auth")
        return err("Invalid credentials", 401)

    # Build JWT
    payload = {
        "id":       user["id"],
        "username": user["username"] or user["pno"],
        "name":     user["name"],
        "role":     user["role"],
        "district": user.get("district"),
        "exp":      int(time.time()) + Config.JWT_EXPIRY,
    }
    token = jwt.encode(payload, Config.JWT_SECRET, algorithm="HS256")

    write_log("INFO", f"User '{user['name']}' ({user['role']}) logged in", "Auth")

    return ok({
        "token": token,
        "user": {
            "id":       user["id"],
            "name":     user["name"],
            "username": user["username"],
            "pno":      user["pno"],
            "role":     user["role"].upper(),   # Flutter reads uppercase: MASTER, SUPER_ADMIN, ADMIN, STAFF
            "district": user.get("district"),
            "mobile":   user.get("mobile"),
        }
    }, "Login successful")


@auth_bp.route("/logout", methods=["POST"])
def logout():
    # JWT is stateless; client just discards the token.
    # Optionally add a token blacklist table here later.
    return ok(None, "Logged out")