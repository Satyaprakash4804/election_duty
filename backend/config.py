import os
import pymysql
import pymysql.cursors
from dotenv import load_dotenv

load_dotenv()

# ─────────────────────────────────────────────
#  APP CONFIG
# ─────────────────────────────────────────────
class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "fallback_secret_key")
    DEBUG      = os.getenv("DEBUG", "False") == "True"
    HOST       = os.getenv("HOST", "0.0.0.0")
    PORT       = int(os.getenv("PORT", 5000))

    # Database
    DB_HOST = os.getenv("DB_HOST")
    DB_USER = os.getenv("DB_USER")
    DB_PASS = os.getenv("DB_PASS")
    DB_NAME = os.getenv("DB_NAME")

    # JWT
    JWT_SECRET  = os.getenv("JWT_SECRET", SECRET_KEY)
    JWT_EXPIRY  = int(os.getenv("JWT_EXPIRY", 36000))   # seconds (10 hours)

    # Base URL — used by health checker and any internal calls
    BASE_URL = os.getenv("BASE_URL", "http://192.168.1.5:5000")
    MYSQLDUMP_PATH = os.getenv("MYSQLDUMP_PATH")

# ─────────────────────────────────────────────
#  DATABASE CONNECTION
# ─────────────────────────────────────────────
def get_db():
    return pymysql.connect(
        host       = Config.DB_HOST,
        user       = Config.DB_USER,
        password   = Config.DB_PASS,
        database   = Config.DB_NAME,
        cursorclass= pymysql.cursors.DictCursor,
        autocommit = False,
    )