from flask import Flask, request, jsonify
from flask_cors import CORS
from config import Config
from db import init_db, get_db

# 🔥 Firebase Admin
import firebase_admin
from firebase_admin import credentials, messaging

# ── Import all blueprints ──────────────────────────────────────────────────────
from app.routes.auth                    import auth_bp
from app.routes.master                  import master_bp
from app.routes.super_admin             import super_admin_bp
from app.routes.admin                   import admin_bp
from app.routes.staff                   import staff_bp
from app.routes.hierarchy               import hierarchy
from app.routes.hierarchyweb            import hierarchy_bp
from app.routes.election_finalize       import election_finalize_bp   # was: finalize_bp
from app.routes.election_history_report_routes import history_report_bp      # updated path
from app.routes.multi_super import multi_super_bp
# ── Election guard utilities (used internally by blueprints, not routes) ───────
from app.election_guard import (
    get_active_election,
    require_active_election,
    run_auto_finalize_if_due,
)

# ── Global API request logging hooks ──────────────────────────────────────────
from app.routes import start_request_timer, log_request_end, log_exception


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)

    CORS(
        app,
        supports_credentials=True,
        origins=["http://localhost:5173"],
    )

    # ── Firebase Init ─────────────────────────────────────────────────────────
    if not firebase_admin._apps:
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred)

    # ══════════════════════════════════════════════════════════════════════════
    #  GLOBAL REQUEST LOGGING
    #  Logs every request (method, path, status, duration, user, IP, body)
    #  and captures unhandled 500 errors with stack trace.
    # ══════════════════════════════════════════════════════════════════════════
    app.before_request(start_request_timer)
    app.after_request(log_request_end)
    app.register_error_handler(Exception, log_exception)

    # ── Register Blueprints ───────────────────────────────────────────────────
    app.register_blueprint(auth_bp)
    app.register_blueprint(master_bp)
    app.register_blueprint(super_admin_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(staff_bp)
    app.register_blueprint(hierarchy)
    app.register_blueprint(hierarchy_bp)
    app.register_blueprint(election_finalize_bp)   # /api/admin/election/...
    app.register_blueprint(history_report_bp)      # /api/admin/election/history/...
    app.register_blueprint(multi_super_bp) 

    # ── Health ping ───────────────────────────────────────────────────────────
    @app.route("/ping")
    def ping():
        return {"status": "ok", "message": "Election API running"}, 200

    # ── Save FCM Token ────────────────────────────────────────────────────────
    @app.route("/save-token", methods=["POST"])
    def save_fcm_token():
        try:
            data        = request.json or {}
            token       = data.get("token")
            user_id     = data.get("user_id")
            user_agent  = data.get("user_agent") or request.headers.get("User-Agent", "")
            device_name = data.get("device_name") or "Unknown Device"

            if not token or not user_id:
                return jsonify({"error": "Token or user_id missing"}), 400

            ip_address = request.remote_addr
            browser    = "Unknown"
            os_name    = "Unknown"
            try:
                from user_agents import parse as ua_parse
                ua      = ua_parse(user_agent)
                browser = ua.browser.family
                os_name = ua.os.family
            except Exception:
                pass

            conn = get_db()
            try:
                with conn.cursor() as cur:
                    # Deactivate all existing tokens for this user
                    cur.execute(
                        "UPDATE fcm_tokens SET is_active = 0 WHERE user_id = %s",
                        (user_id,)
                    )
                    # Upsert the new token
                    cur.execute("""
                        INSERT INTO fcm_tokens
                            (user_id, token, device_name, browser, os,
                             user_agent, ip_address, is_active)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, 1)
                        ON DUPLICATE KEY UPDATE
                            user_id     = VALUES(user_id),
                            device_name = VALUES(device_name),
                            browser     = VALUES(browser),
                            os          = VALUES(os),
                            user_agent  = VALUES(user_agent),
                            ip_address  = VALUES(ip_address),
                            is_active   = 1
                    """, (user_id, token, device_name, browser, os_name,
                          user_agent, ip_address))
                conn.commit()
                return jsonify({"status": "saved"}), 200
            except Exception as e:
                conn.rollback()
                print("FCM SAVE ERROR:", e)
                return jsonify({"error": "Server error"}), 500
            finally:
                conn.close()

        except Exception as e:
            print("FCM OUTER ERROR:", e)
            return jsonify({"error": "Server error"}), 500

    # ── Send Notification ─────────────────────────────────────────────────────
    @app.route("/send-notification", methods=["GET"])
    def send_notification():
        conn = get_db()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT token FROM fcm_tokens WHERE is_active = 1")
                rows = cur.fetchall()

            if not rows:
                return jsonify({"message": "No active tokens found"}), 400

            success, failed = 0, 0
            for row in rows:
                try:
                    message = messaging.Message(
                        notification=messaging.Notification(
                            title="Election Update",
                            body="Notification sent using DB tokens 🚀",
                        ),
                        token=row["token"],
                    )
                    messaging.send(message)
                    success += 1
                except Exception as e:
                    print("❌ FCM send error:", e)
                    failed += 1

            return jsonify({
                "message": "Notification process completed",
                "success": success,
                "failed":  failed,
            }), 200
        finally:
            conn.close()

    return app


if __name__ == "__main__":
    init_db()
    app = create_app()
    app.run(
        host=Config.HOST,
        port=Config.PORT,
        debug=Config.DEBUG,
    )