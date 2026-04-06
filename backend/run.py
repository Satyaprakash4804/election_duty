# from flask import Flask
# from flask_cors import CORS
# from config import Config
# from db import init_db

# # ── Import all blueprints ──────────────────────────────────────────────────────
# from app.routes.auth        import auth_bp
# from app.routes.master      import master_bp
# from app.routes.super_admin import super_admin_bp
# from app.routes.admin       import admin_bp
# from app.routes.staff       import staff_bp
# from app.routes.hierarchy   import hierarchy
# from app.routes.hierarchyweb  import hierarchy_bp

# def create_app():
#     app = Flask(__name__)
#     app.config.from_object(Config)

#     # CORS — allow Flutter app on any origin during development
 

#     CORS(app,
#      supports_credentials=True,
#      origins=["http://localhost:5173"])

#     # ── Register Blueprints ───────────────────────────────────────────────────
#     app.register_blueprint(auth_bp)          # /api/login, /api/logout
#     app.register_blueprint(master_bp)        # /master/...
#     app.register_blueprint(super_admin_bp)   # /super/...
#     app.register_blueprint(admin_bp)         # /admin/...
#     app.register_blueprint(staff_bp) 
#     app.register_blueprint(hierarchy)
#     app.register_blueprint(hierarchy_bp)
#     # ── Health ping (no auth) ────────────────────────────────────────────────
#     @app.route("/ping")
#     def ping():
#         return {"status": "ok", "message": "Election API running"}, 200

#     return app


# if __name__ == "__main__":
#     # Initialise DB tables on first run
#     init_db()

#     app = create_app()
#     app.run(
#         host  = Config.HOST,
#         port  = Config.PORT,
#         debug = Config.DEBUG,
#     )








from flask import Flask, request, jsonify
from flask_cors import CORS
from config import Config
from db import init_db, get_db

# 🔥 Firebase Admin
import firebase_admin
from firebase_admin import credentials, messaging

# ── Import all blueprints ──────────────────────────────────────────────────────
from app.routes.auth        import auth_bp
from app.routes.master      import master_bp
from app.routes.super_admin import super_admin_bp
from app.routes.admin       import admin_bp
from app.routes.staff       import staff_bp
from app.routes.hierarchy   import hierarchy
from app.routes.hierarchyweb import hierarchy_bp


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)

    # ✅ CORS (React + Flutter)
    CORS(
        app,
        supports_credentials=True,
        origins=["http://localhost:5173"]
    )

    # 🔥 Firebase Init (only once)
    if not firebase_admin._apps:
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred)

    # ── Register Blueprints ───────────────────────────────────────────────────
    app.register_blueprint(auth_bp)
    app.register_blueprint(master_bp)
    app.register_blueprint(super_admin_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(staff_bp)
    app.register_blueprint(hierarchy)
    app.register_blueprint(hierarchy_bp)

    # ── Health ping ───────────────────────────────────────────────────────────
    @app.route("/ping")
    def ping():
        return {"status": "ok", "message": "Election API running"}, 200

    # ── 🔥 SAVE FCM TOKEN (DB) ────────────────────────────────────────────────
    @app.route("/save-token", methods=["POST"])
    def save_fcm_token():
        try:
            data = request.json

            token = data.get("token")
            user_id = data.get("user_id")

            user_agent = data.get("user_agent") or request.headers.get("User-Agent", "")
            device_name = data.get("device_name") or "Unknown Device"

            if not token or not user_id:
                return jsonify({"error": "Token or user_id missing"}), 400

            ip_address = request.remote_addr

            # Default values
            browser = "Unknown"
            os_name = "Unknown"

            # Safe parsing like Django
            try:
                from user_agents import parse
                ua = parse(user_agent)
                browser = ua.browser.family
                os_name = ua.os.family
            except Exception:
                pass  # Never crash

            conn = get_db()

            try:
                with conn.cursor() as cur:

                    # 🔴 1. Deactivate all previous tokens of user
                    cur.execute("""
                        UPDATE fcm_tokens
                        SET is_active = 0
                        WHERE user_id = %s
                    """, (user_id,))

                    # 🟢 2. Insert or update current token
                    cur.execute("""
                        INSERT INTO fcm_tokens 
                        (user_id, token, device_name, browser, os, user_agent, ip_address, is_active)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, 1)
                        ON DUPLICATE KEY UPDATE
                            user_id = VALUES(user_id),
                            device_name = VALUES(device_name),
                            browser = VALUES(browser),
                            os = VALUES(os),
                            user_agent = VALUES(user_agent),
                            ip_address = VALUES(ip_address),
                            is_active = 1
                    """, (
                        user_id,
                        token,
                        device_name,
                        browser,
                        os_name,
                        user_agent,
                        ip_address
                    ))

                conn.commit()
                return jsonify({"status": "saved"}), 200

            except Exception as e:
                conn.rollback()
                print("FCM SAVE ERROR:", str(e))
                return jsonify({"error": "Server error"}), 500

            finally:
                conn.close()

        except Exception as e:
            print("FCM OUTER ERROR:", str(e))
            return jsonify({"error": "Server error"}), 500

    # ── 🔔 SEND NOTIFICATION (FROM DB TOKENS) ─────────────────────────────────
    @app.route("/send-notification", methods=["GET"])
    def send_notification():
        conn = get_db()

        try:
            with conn.cursor() as cur:
                cur.execute("SELECT token FROM fcm_tokens")
                rows = cur.fetchall()

            if not rows:
                return jsonify({"message": "No tokens found"}), 400

            success = 0
            failed = 0

            for row in rows:
                token = row["token"]

                try:
                    message = messaging.Message(
                        notification=messaging.Notification(
                            title="Election Update",
                            body="Notification sent using DB tokens 🚀",
                        ),
                        token=token,
                    )
                    messaging.send(message)
                    success += 1

                except Exception as e:
                    print("❌ Error sending:", e)
                    failed += 1

            return jsonify({
                "message": "Notification process completed",
                "success": success,
                "failed": failed
            }), 200

        finally:
            conn.close()

    return app


if __name__ == "__main__":
    # 🔥 Initialise DB tables (including fcm_tokens)
    init_db()

    app = create_app()
    app.run(
        host=Config.HOST,
        port=Config.PORT,
        debug=Config.DEBUG,
    )