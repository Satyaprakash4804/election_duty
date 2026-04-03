from flask import Flask
from flask_cors import CORS
from config import Config
from db import init_db

# ── Import all blueprints ──────────────────────────────────────────────────────
from app.routes.auth        import auth_bp
from app.routes.master      import master_bp
from app.routes.super_admin import super_admin_bp
from app.routes.admin       import admin_bp
from app.routes.staff       import staff_bp


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)

    # CORS — allow Flutter app on any origin during development
    CORS(app, resources={r"/*": {"origins": "*"}})

    # ── Register Blueprints ───────────────────────────────────────────────────
    app.register_blueprint(auth_bp)          # /api/login, /api/logout
    app.register_blueprint(master_bp)        # /master/...
    app.register_blueprint(super_admin_bp)   # /super/...
    app.register_blueprint(admin_bp)         # /admin/...
    app.register_blueprint(staff_bp) 
    # ── Health ping (no auth) ────────────────────────────────────────────────
    @app.route("/ping")
    def ping():
        return {"status": "ok", "message": "Election API running"}, 200

    return app


if __name__ == "__main__":
    # Initialise DB tables on first run
    init_db()

    app = create_app()
    app.run(
        host  = Config.HOST,
        port  = Config.PORT,
        debug = Config.DEBUG,
    )