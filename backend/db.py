import pymysql
import pymysql.cursors
from pymysql.connections import Connection
from config import Config
from werkzeug.security import generate_password_hash

# ── Optional connection pool (use if your framework supports it) ──────────────
# Install: pip install DBUtils
# Falls back to plain pymysql.connect if DBUtils is not installed.
try:
    from dbutils.pooled_db import PooledDB
    _pool = PooledDB(
        creator=pymysql,
        maxconnections=20,      # hard cap — tune to your DB server's max_connections
        mincached=4,            # keep 4 connections warm
        maxcached=10,
        blocking=True,          # block instead of raising when pool is exhausted
        ping=4,                 # re-ping stale connections (4 = on every execute)
        host=Config.DB_HOST,
        user=Config.DB_USER,
        password=Config.DB_PASS,
        database=Config.DB_NAME,
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        charset="utf8mb4",
    )
    def get_db() -> Connection:
        return _pool.connection()

    print("✅  Using DBUtils connection pool")

except ImportError:
    # Graceful fallback — works fine for low-concurrency or dev environments
    def get_db() -> Connection:
        return pymysql.connect(
            host=Config.DB_HOST,
            user=Config.DB_USER,
            password=Config.DB_PASS,
            database=Config.DB_NAME,
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=False,
            charset="utf8mb4",
            connect_timeout=10,
            read_timeout=30,
            write_timeout=30,
        )

    print("⚠️  DBUtils not installed — using plain pymysql (pip install DBUtils for pooling)")


# ══════════════════════════════════════════════════════════════════════════════
#  INIT DB
# ══════════════════════════════════════════════════════════════════════════════

def init_db():
    # Use a plain connection without database selected so we can CREATE it
    conn = pymysql.connect(
        host=Config.DB_HOST,
        user=Config.DB_USER,
        password=Config.DB_PASS,
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        charset="utf8mb4",
    )
    try:
        with conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS `{Config.DB_NAME}` "
                        f"CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
            cur.execute(f"USE `{Config.DB_NAME}`")

            # users
            cur.execute("""CREATE TABLE IF NOT EXISTS users (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(150) NOT NULL,
                username VARCHAR(100) UNIQUE NOT NULL,
                password VARCHAR(255) NOT NULL,
                mobile VARCHAR(15) DEFAULT '',
                role ENUM('master','super_admin','admin','staff') NOT NULL DEFAULT 'staff',
                district VARCHAR(100) DEFAULT '',
                thana VARCHAR(100) DEFAULT '',
                pno VARCHAR(50) UNIQUE,
                user_rank VARCHAR(100) DEFAULT  '',
                is_active TINYINT(1) NOT NULL DEFAULT 1,
                created_by INT, assigned_by INT,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                FOREIGN KEY (created_by)  REFERENCES users(id) ON DELETE SET NULL,
                FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # ── super_zones ───────────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS super_zones (
                    id         INT AUTO_INCREMENT PRIMARY KEY,
                    name       VARCHAR(100) NOT NULL,
                    district   VARCHAR(100) DEFAULT '',
                    block      VARCHAR(100) DEFAULT '',
                    admin_id   INT          DEFAULT NULL,
                    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    INDEX idx_admin_id (admin_id),

                    FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── kshetra_officers ──────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS kshetra_officers (
                    id            INT AUTO_INCREMENT PRIMARY KEY,
                    super_zone_id INT NOT NULL,
                    user_id       INT DEFAULT NULL,
                    name          VARCHAR(150) NOT NULL DEFAULT '',
                    pno           VARCHAR(50)  DEFAULT '',
                    mobile        VARCHAR(15)  DEFAULT '',
                    user_rank     VARCHAR(100) DEFAULT '',
                    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    INDEX idx_super_zone_id (super_zone_id),

                    FOREIGN KEY (super_zone_id) REFERENCES super_zones(id) ON DELETE CASCADE,
                    FOREIGN KEY (user_id)       REFERENCES users(id)       ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── zones ─────────────────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS zones (
                    id            INT AUTO_INCREMENT PRIMARY KEY,
                    name          VARCHAR(100) NOT NULL,
                    hq_address    TEXT,
                    super_zone_id INT NOT NULL,
                    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    INDEX idx_super_zone_id (super_zone_id),

                    FOREIGN KEY (super_zone_id) REFERENCES super_zones(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── zonal_officers ────────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS zonal_officers (
                    id         INT AUTO_INCREMENT PRIMARY KEY,
                    zone_id    INT NOT NULL,
                    user_id    INT DEFAULT NULL,
                    name       VARCHAR(150) NOT NULL DEFAULT '',
                    pno        VARCHAR(50)  DEFAULT '',
                    mobile     VARCHAR(15)  DEFAULT '',
                    user_rank  VARCHAR(100) DEFAULT '',
                    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    INDEX idx_zone_id (zone_id),

                    FOREIGN KEY (zone_id)  REFERENCES zones(id) ON DELETE CASCADE,
                    FOREIGN KEY (user_id)  REFERENCES users(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── sectors ───────────────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS sectors (
                    id         INT AUTO_INCREMENT PRIMARY KEY,
                    name       VARCHAR(100) NOT NULL,
                    zone_id    INT NOT NULL,
                    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    INDEX idx_zone_id (zone_id),

                    FOREIGN KEY (zone_id) REFERENCES zones(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── sector_officers ───────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS sector_officers (
                    id         INT AUTO_INCREMENT PRIMARY KEY,
                    sector_id  INT NOT NULL,
                    user_id    INT DEFAULT NULL,
                    name       VARCHAR(150) NOT NULL DEFAULT '',
                    pno        VARCHAR(50)  DEFAULT '',
                    mobile     VARCHAR(15)  DEFAULT '',
                    user_rank  VARCHAR(100) DEFAULT '',
                    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    INDEX idx_sector_id (sector_id),

                    FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE CASCADE,
                    FOREIGN KEY (user_id)   REFERENCES users(id)   ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── gram_panchayats ───────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS gram_panchayats (
                    id         INT AUTO_INCREMENT PRIMARY KEY,
                    name       VARCHAR(200) NOT NULL,
                    address    TEXT,
                    sector_id  INT NOT NULL,
                    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    INDEX idx_sector_id (sector_id),
                    INDEX idx_name      (name),

                    FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── matdan_sthal (election centers) ───────────────────────────────
            # Composite index (gp_id, name) covers both the FK join and name sort/search
            cur.execute("""
                CREATE TABLE IF NOT EXISTS matdan_sthal (
                    id                INT AUTO_INCREMENT PRIMARY KEY,
                    name              VARCHAR(250) NOT NULL,
                    address           TEXT,
                    gram_panchayat_id INT          NOT NULL,
                    thana             VARCHAR(150) DEFAULT '',
                    center_type       ENUM('A','B','C') NOT NULL DEFAULT 'C',
                    bus_no            VARCHAR(50)  DEFAULT '',
                    latitude          DECIMAL(10,7),
                    longitude         DECIMAL(10,7),
                    created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    INDEX idx_gp_id        (gram_panchayat_id),
                    INDEX idx_thana        (thana),
                    INDEX idx_name         (name),
                    INDEX idx_center_type  (center_type),

                    FOREIGN KEY (gram_panchayat_id) REFERENCES gram_panchayats(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── matdan_kendra (rooms) ─────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS matdan_kendra (
                    id              INT AUTO_INCREMENT PRIMARY KEY,
                    room_number     VARCHAR(50) NOT NULL,
                    matdan_sthal_id INT         NOT NULL,
                    created_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    INDEX idx_sthal_id (matdan_sthal_id),

                    FOREIGN KEY (matdan_sthal_id) REFERENCES matdan_sthal(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── duty_assignments ──────────────────────────────────────────────
            # UNIQUE (staff_id, sthal_id) prevents duplicate assignments.
            # Covering index on sthal_id speeds up "who is at this center?" queries.
            cur.execute("""
                CREATE TABLE IF NOT EXISTS duty_assignments (
                    id          INT AUTO_INCREMENT PRIMARY KEY,
                    staff_id    INT         NOT NULL,
                    sthal_id    INT         NOT NULL,
                    bus_no      VARCHAR(50) DEFAULT '',
                    assigned_by INT         DEFAULT NULL,
                    created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    UNIQUE KEY uq_staff_sthal (staff_id, sthal_id),
                    INDEX idx_sthal_id    (sthal_id),
                    INDEX idx_assigned_by (assigned_by),

                    FOREIGN KEY (staff_id)    REFERENCES users(id)        ON DELETE CASCADE,
                    FOREIGN KEY (sthal_id)    REFERENCES matdan_sthal(id) ON DELETE CASCADE,
                    FOREIGN KEY (assigned_by) REFERENCES users(id)        ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── system_logs ───────────────────────────────────────────────────
            # Partition by time is ideal for very high log volumes but requires
            # extra setup; INDEX on time covers ORDER BY / range queries fine here.
            cur.execute("""
                CREATE TABLE IF NOT EXISTS system_logs (
                    id      INT AUTO_INCREMENT PRIMARY KEY,
                    level   ENUM('INFO','WARN','ERROR') NOT NULL DEFAULT 'INFO',
                    message TEXT    NOT NULL,
                    module  VARCHAR(80) NOT NULL,
                    time    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    INDEX idx_time   (time),
                    INDEX idx_level  (level),
                    INDEX idx_module (module)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── app_config ────────────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS app_config (
                    `key`      VARCHAR(100) PRIMARY KEY,
                    value      TEXT,
                    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── fcm_tokens ────────────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS fcm_tokens (
                    id          INT AUTO_INCREMENT PRIMARY KEY,
                    user_id     INT          NOT NULL,
                    token       TEXT         NOT NULL,
                    device_name VARCHAR(255) DEFAULT NULL,
                    browser     VARCHAR(100) DEFAULT NULL,
                    os          VARCHAR(100) DEFAULT NULL,
                    user_agent  TEXT,
                    ip_address  VARCHAR(45),
                    is_active   TINYINT(1)   DEFAULT 1,
                    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    UNIQUE KEY uq_token   (token(255)),
                    INDEX      idx_user_id (user_id),

                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── Restore session settings ──────────────────────────────────────
            cur.execute("SET SESSION foreign_key_checks = 1")
            cur.execute("SET SESSION unique_checks = 1")

            # ─────────────────────────────────────────────────────────────────
            #  SEED DATA
            # ─────────────────────────────────────────────────────────────────

            for k, v in [
                ("maintenanceMode",   "false"),
                ("allowStaffLogin",   "true"),
                ("forcePasswordReset","false"),
                ("electionYear",      "2026"),
                ("state",             "Uttar Pradesh"),
                ("phase",             "Phase 1"),
                ("electionDate",      "15 Apr 2026"),
            ]:
                cur.execute(
                    "INSERT INTO app_config (`key`, value) VALUES (%s, %s) "
                    "ON DUPLICATE KEY UPDATE `key`=`key`",
                    (k, v)
                )

            # seed master
            cur.execute("SELECT id FROM users WHERE username='master'")
            if not cur.fetchone():
                cur.execute(
                    "INSERT INTO users (name, username, password, role, is_active) "
                    "VALUES ('Master Admin', 'master', %s, 'master', 1)",
                    (generate_password_hash("master"),)
                )
                print("✅  Seeded master  (user:master / pass:master)")

            # seed super_admin
            cur.execute("SELECT id FROM users WHERE username='super'")
            if not cur.fetchone():
                cur.execute(
                    "INSERT INTO users (name, username, password, role, is_active) "
                    "VALUES ('Super Admin', 'super', %s, 'super_admin', 1)",
                    (generate_password_hash("super"),)
                )
                print("✅  Seeded super   (user:super  / pass:super)")

        conn.commit()
        print("✅  Database initialised")

    except Exception as e:
        conn.rollback()
        print(f"❌  init_db error: {e}")
        raise
    finally:
        conn.close()


# ══════════════════════════════════════════════════════════════════════════════
#  MIGRATION HELPER  — run once on an existing DB to add missing indexes
#  Call from a one-off script or a /api/admin/migrate endpoint (master only).
# ══════════════════════════════════════════════════════════════════════════════

def run_migrations():
    """
    Safely adds indexes that may be missing on existing databases.
    Each ALTER is wrapped individually so a failure on one doesn't block others.
    """
    migrations = [
        # users
        ("users",             "idx_role_district",  "INDEX (role, district)"),
        ("users",             "idx_role_active",    "INDEX (role, is_active)"),
        ("users",             "idx_name",           "INDEX (name)"),
        ("users",             "idx_thana",          "INDEX (thana)"),
        # super_zones
        ("super_zones",       "idx_admin_id",       "INDEX (admin_id)"),
        # kshetra_officers
        ("kshetra_officers",  "idx_super_zone_id",  "INDEX (super_zone_id)"),
        # zones
        ("zones",             "idx_super_zone_id",  "INDEX (super_zone_id)"),
        # zonal_officers
        ("zonal_officers",    "idx_zone_id",        "INDEX (zone_id)"),
        # sectors
        ("sectors",           "idx_zone_id",        "INDEX (zone_id)"),
        # sector_officers
        ("sector_officers",   "idx_sector_id",      "INDEX (sector_id)"),
        # gram_panchayats
        ("gram_panchayats",   "idx_sector_id",      "INDEX (sector_id)"),
        ("gram_panchayats",   "idx_name",           "INDEX (name)"),
        # matdan_sthal
        ("matdan_sthal",      "idx_gp_id",          "INDEX (gram_panchayat_id)"),
        ("matdan_sthal",      "idx_thana",          "INDEX (thana)"),
        ("matdan_sthal",      "idx_name",           "INDEX (name)"),
        ("matdan_sthal",      "idx_center_type",    "INDEX (center_type)"),
        # matdan_kendra
        ("matdan_kendra",     "idx_sthal_id",       "INDEX (matdan_sthal_id)"),
        # duty_assignments
        ("duty_assignments",  "idx_sthal_id",       "INDEX (sthal_id)"),
        ("duty_assignments",  "idx_assigned_by",    "INDEX (assigned_by)"),
        # system_logs
        ("system_logs",       "idx_time",           "INDEX (time)"),
        ("system_logs",       "idx_level",          "INDEX (level)"),
        ("system_logs",       "idx_module",         "INDEX (module)"),
        # fcm_tokens
        ("fcm_tokens",        "idx_user_id",        "INDEX (user_id)"),
    ]

    conn = get_db()
    applied, skipped, failed = [], [], []
    try:
        with conn.cursor() as cur:
            for table, index_name, definition in migrations:
                # Check if index already exists
                cur.execute(
                    "SELECT COUNT(*) AS cnt FROM information_schema.statistics "
                    "WHERE table_schema = %s AND table_name = %s AND index_name = %s",
                    (Config.DB_NAME, table, index_name)
                )
                if cur.fetchone()["cnt"] > 0:
                    skipped.append(f"{table}.{index_name}")
                    continue
                try:
                    cur.execute(
                        f"ALTER TABLE `{table}` ADD {definition.replace('INDEX', f'INDEX `{index_name}`', 1)}"
                    )
                    conn.commit()
                    applied.append(f"{table}.{index_name}")
                    print(f"  ✅  Added  {table}.{index_name}")
                except Exception as e:
                    conn.rollback()
                    failed.append(f"{table}.{index_name}: {e}")
                    print(f"  ❌  Failed {table}.{index_name}: {e}")
    finally:
        conn.close()

    print(f"\nMigration complete — applied: {len(applied)}, "
          f"skipped: {len(skipped)}, failed: {len(failed)}")
    return {"applied": applied, "skipped": skipped, "failed": failed}