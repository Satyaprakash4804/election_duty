import pymysql
import pymysql.cursors
from pymysql.connections import Connection
from config import Config
import hashlib

# ── SHA256 + Salt password hashing ───────────────────────────────────────────
SALT = "election_2026_secure_key"

def hash_password(plain: str) -> str:
    return hashlib.sha256((plain + SALT).encode()).hexdigest()

def verify_password(plain: str, hashed: str) -> bool:
    return hash_password(plain) == hashed

def create_database_if_not_exists():
    conn = pymysql.connect(
        host=Config.DB_HOST,
        user=Config.DB_USER,
        password=Config.DB_PASS,
        cursorclass=pymysql.cursors.DictCursor,
    )
    try:
        with conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS `{Config.DB_NAME}`")
        conn.commit()
    finally:
        conn.close()

# 🔥 CREATE DATABASE FIRST
create_database_if_not_exists()

# ── Optional connection pool ──────────────────────────────────────────────────
try:
    from dbutils.pooled_db import PooledDB
    _pool = PooledDB(
        creator=pymysql,
        maxconnections=20,
        mincached=4,
        maxcached=10,
        blocking=True,
        ping=4,
        host=Config.DB_HOST,
        user=Config.DB_USER,
        password=Config.DB_PASS,
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        charset="utf8mb4",
    )
    def get_db() -> Connection:
        conn = _pool.connection()
        try:
            with conn.cursor() as cur:
                cur.execute(f"USE `{Config.DB_NAME}`")
        except:
            pass
        return conn

    print("✅  Using DBUtils connection pool")

except ImportError:
    def get_db() -> Connection:
        conn = pymysql.connect(
            host=Config.DB_HOST,
            user=Config.DB_USER,
            password=Config.DB_PASS,
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=False,
            charset="utf8mb4",
            connect_timeout=10,
            read_timeout=30,
            write_timeout=30,
        )
        try:
            with conn.cursor() as cur:
                cur.execute(f"USE `{Config.DB_NAME}`")
        except:
            pass
        return conn


# ══════════════════════════════════════════════════════════════════════════════
#  ENSURE COLUMN — safely adds a column if it doesn't exist
# ══════════════════════════════════════════════════════════════════════════════

def ensure_column(cur, db_name: str, table: str, column_def: str):
    col_name = column_def.strip().split()[0].strip("`")
    cur.execute("""
        SELECT COUNT(*) AS cnt
        FROM information_schema.columns
        WHERE table_schema = %s AND table_name = %s AND column_name = %s
    """, (db_name, table, col_name))
    if cur.fetchone()["cnt"] == 0:
        cur.execute(f"ALTER TABLE `{table}` ADD COLUMN {column_def}")
        print(f"  ✅  Column added: {table}.{col_name}")


# ══════════════════════════════════════════════════════════════════════════════
#  INIT DB
# ══════════════════════════════════════════════════════════════════════════════

def init_db():
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

            cur.execute(
                f"CREATE DATABASE IF NOT EXISTS `{Config.DB_NAME}` "
                f"CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
            )
            cur.execute(f"USE `{Config.DB_NAME}`")

            cur.execute("SET SESSION foreign_key_checks = 0")
            cur.execute("SET SESSION unique_checks = 0")

            # ── users ─────────────────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id          INT AUTO_INCREMENT PRIMARY KEY,
                    name        VARCHAR(150)  NOT NULL,
                    username    VARCHAR(100)  NOT NULL,
                    password    VARCHAR(255)  NOT NULL,
                    mobile      VARCHAR(15)   DEFAULT '',
                    role        ENUM('master','super_admin','admin','staff') NOT NULL DEFAULT 'staff',
                    district    VARCHAR(100)  DEFAULT '',
                    thana       VARCHAR(100)  DEFAULT '',
                    pno         VARCHAR(50)   DEFAULT NULL,
                    user_rank   VARCHAR(100)  DEFAULT '',
                    is_armed TINYINT(1) NOT NULL DEFAULT 0,
                    is_active   TINYINT(1)    NOT NULL DEFAULT 1,
                    created_by  INT           DEFAULT NULL,
                    assigned_by INT           DEFAULT NULL,
                    super_admin_id INT        DEFAULT NULL,
                    created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                              ON UPDATE CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_username  (username),
                    UNIQUE KEY uq_pno       (pno),
                    INDEX idx_role_district (role, district),
                    INDEX idx_role_active   (role, is_active),
                    INDEX idx_name          (name),
                    INDEX idx_thana         (thana),
                    INDEX idx_user_rank     (user_rank),
                    INDEX idx_role_rank     (role, user_rank, is_active)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── app_config ── (kept for global/non-district settings like maintenanceMode)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS app_config (
                    `key`      VARCHAR(100) PRIMARY KEY,
                    value      TEXT,
                    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ══════════════════════════════════════════════════════════════════
            #  🆕 election_configs — district-wise, versioned election details
            # ══════════════════════════════════════════════════════════════════
            cur.execute("""
                CREATE TABLE IF NOT EXISTS election_configs (
                    id              INT AUTO_INCREMENT PRIMARY KEY,
                    district        VARCHAR(100) NOT NULL,
                    state           VARCHAR(100) NOT NULL DEFAULT '',
                    election_type   VARCHAR(100) NOT NULL DEFAULT '',
                    election_name   VARCHAR(200) NOT NULL DEFAULT '',
                    phase           VARCHAR(50)  NOT NULL DEFAULT '',
                    election_year   VARCHAR(10)  NOT NULL DEFAULT '',
                    election_date   DATE         DEFAULT NULL,
                    pratah_samay    VARCHAR(20)  DEFAULT '',
                    saya_samay      VARCHAR(20)  DEFAULT '',
                    instructions    TEXT,
                    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
                    is_archived     TINYINT(1)   NOT NULL DEFAULT 0,
                    archived_at     DATETIME     DEFAULT NULL,
                    created_by      INT          DEFAULT NULL,
                    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                 ON UPDATE CURRENT_TIMESTAMP,
                    INDEX idx_district        (district),
                    INDEX idx_district_active (district, is_active),
                    INDEX idx_archived        (is_archived),
                    INDEX idx_election_date   (election_date),
                    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ══════════════════════════════════════════════════════════════════
            #  🆕 api_request_logs — every API hit (writes + reads + errors)
            # ══════════════════════════════════════════════════════════════════
            cur.execute("""
                CREATE TABLE IF NOT EXISTS api_request_logs (
                    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
                    method          VARCHAR(10)  NOT NULL,
                    path            VARCHAR(500) NOT NULL,
                    status_code     INT          NOT NULL DEFAULT 0,
                    duration_ms     INT          NOT NULL DEFAULT 0,
                    user_id         INT          DEFAULT NULL,
                    username        VARCHAR(100) DEFAULT NULL,
                    role            VARCHAR(30)  DEFAULT NULL,
                    ip_address      VARCHAR(45)  DEFAULT NULL,
                    user_agent      VARCHAR(500) DEFAULT NULL,
                    request_body    TEXT,
                    error_message   TEXT,
                    level           ENUM('INFO','WARN','ERROR') NOT NULL DEFAULT 'INFO',
                    created_at      DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
                    INDEX idx_created_at  (created_at),
                    INDEX idx_status_code (status_code),
                    INDEX idx_path        (path(100)),
                    INDEX idx_user_id     (user_id),
                    INDEX idx_role        (role),
                    INDEX idx_level       (level)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ══════════════════════════════════════════════════════════════════
            #  🆕 token_revocations — for force-logout by role
            #  JWTs issued BEFORE `revoke_before` for given role are invalid.
            # ══════════════════════════════════════════════════════════════════
            cur.execute("""
                CREATE TABLE IF NOT EXISTS token_revocations (
                    id            INT AUTO_INCREMENT PRIMARY KEY,
                    role          VARCHAR(30)  NOT NULL,
                    revoke_before BIGINT       NOT NULL,
                    revoked_by    INT          DEFAULT NULL,
                    reason        VARCHAR(255) DEFAULT '',
                    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_role (role),
                    INDEX idx_revoke_before (revoke_before)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

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
                    FOREIGN KEY (zone_id) REFERENCES zones(id) ON DELETE CASCADE,
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS sectors (
                    id         INT AUTO_INCREMENT PRIMARY KEY,
                    name       VARCHAR(100) NOT NULL,
                    hq_address TEXT,
                    zone_id    INT NOT NULL,
                    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_zone_id (zone_id),
                    FOREIGN KEY (zone_id) REFERENCES zones(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

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

            cur.execute("""
                CREATE TABLE IF NOT EXISTS matdan_sthal (
                    id                INT AUTO_INCREMENT PRIMARY KEY,
                    name              VARCHAR(250) NOT NULL,
                    address           TEXT,
                    gram_panchayat_id INT          NOT NULL,
                    thana             VARCHAR(150) DEFAULT '',
                    center_type       ENUM('A++','A','B','C') NOT NULL DEFAULT 'C',
                    booth_count INT NOT NULL DEFAULT 1,
                    bus_no            VARCHAR(50)  DEFAULT '',
                    latitude          DECIMAL(10,7),
                    longitude         DECIMAL(10,7),
                    created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_gp_id       (gram_panchayat_id),
                    INDEX idx_thana       (thana),
                    INDEX idx_name        (name),
                    INDEX idx_center_type (center_type),
                    FOREIGN KEY (gram_panchayat_id) REFERENCES gram_panchayats(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

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

            cur.execute("""
                CREATE TABLE IF NOT EXISTS duty_assignments (
                    id          INT AUTO_INCREMENT PRIMARY KEY,
                    staff_id    INT         NOT NULL,
                    sthal_id    INT         NOT NULL,
                    bus_no      VARCHAR(50) DEFAULT '',
                    election_date DATE DEFAULT NULL,
                    attended    TINYINT(1) NOT NULL DEFAULT 0,
                    card_downloaded TINYINT(1) NOT NULL DEFAULT 0,
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
                    UNIQUE KEY uq_token    (token(255)),
                    INDEX      idx_user_id (user_id),
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── booth_rules: per (admin_id, sensitivity, booth_count) ─────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS booth_rules (
                    id                    INT AUTO_INCREMENT PRIMARY KEY,
                    admin_id              INT NOT NULL,
                    sensitivity           ENUM('A++','A','B','C') NOT NULL,
                    booth_count           INT NOT NULL,        -- 1..14, 15 = "15 और उससे अधिक"
            
                    si_armed_count        INT NOT NULL DEFAULT 0,
                    si_unarmed_count      INT NOT NULL DEFAULT 0,
                    hc_armed_count        INT NOT NULL DEFAULT 0,
                    hc_unarmed_count      INT NOT NULL DEFAULT 0,
                    const_armed_count     INT NOT NULL DEFAULT 0,
                    const_unarmed_count   INT NOT NULL DEFAULT 0,
            
                    aux_force_count       INT          NOT NULL DEFAULT 0,
                    pac_count             DECIMAL(4,1) NOT NULL DEFAULT 0,
            
                    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                        ON UPDATE CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_admin_sens_booth (admin_id, sensitivity, booth_count),
                    INDEX idx_admin_sens (admin_id, sensitivity),
                    FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)
            
            # ── district_rules: per (admin_id, duty_type) ──────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS district_rules (
                    id                    INT AUTO_INCREMENT PRIMARY KEY,
                    admin_id              INT          NOT NULL,
                    duty_type             VARCHAR(80)  NOT NULL,
                    duty_label_hi         VARCHAR(150) NOT NULL DEFAULT '',
                    sankhya               INT          NOT NULL DEFAULT 0,
            
                    si_armed_count        INT NOT NULL DEFAULT 0,
                    si_unarmed_count      INT NOT NULL DEFAULT 0,
                    hc_armed_count        INT NOT NULL DEFAULT 0,
                    hc_unarmed_count      INT NOT NULL DEFAULT 0,
                    const_armed_count     INT NOT NULL DEFAULT 0,
                    const_unarmed_count   INT NOT NULL DEFAULT 0,
            
                    aux_force_count       INT          NOT NULL DEFAULT 0,
                    pac_count             DECIMAL(4,1) NOT NULL DEFAULT 0,
                    sort_order            INT          NOT NULL DEFAULT 0,
            
                    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                        ON UPDATE CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_admin_duty (admin_id, duty_type),
                    INDEX idx_admin (admin_id),
                    FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)
            
            

            cur.execute("""
                CREATE TABLE IF NOT EXISTS goswara_nyay_panchayat (
                    id         INT AUTO_INCREMENT PRIMARY KEY,
                    admin_id   INT NOT NULL,
                    block_name VARCHAR(100) NOT NULL,
                    nyay_count INT NOT NULL DEFAULT 0,
                    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                            ON UPDATE CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_admin_block (admin_id, block_name),
                    FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                        CREATE TABLE IF NOT EXISTS sz_duty_locks (
                            id INT AUTO_INCREMENT PRIMARY KEY,
                            super_zone_id INT UNIQUE,
                            is_locked TINYINT(1) DEFAULT 0,
                            status ENUM('locked','unlock_requested','unlocked') DEFAULT 'unlocked',
                            unlock_reason TEXT,
                            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                        )ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                        """)
            
            cur.execute("""
                        CREATE TABLE IF NOT EXISTS sz_assign_jobs (
                            id INT AUTO_INCREMENT PRIMARY KEY,
                            super_zone_id INT,
                            status ENUM('pending','running','done','error') DEFAULT 'pending',
                            total_centers INT DEFAULT 0,
                            done_centers INT DEFAULT 0,
                            error_msg TEXT,
                            created_by INT,
                            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                        )ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                        """)
            
            cur.execute("""
                CREATE TABLE IF NOT EXISTS sz_unlock_requests (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    super_zone_id INT,
                    requested_by INT,
                    reason TEXT,
                    status ENUM('pending','approved','rejected') DEFAULT 'pending',
                    reviewed_by INT,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)
            
           
            # ─────────────────────────────────────────────────────────────────
            #  AUTO-ADD MISSING COLUMNS (safe for existing databases)
            # ─────────────────────────────────────────────────────────────────
            db = Config.DB_NAME

            ensure_column(cur, db, "users", "pno VARCHAR(50) DEFAULT NULL")
            ensure_column(cur, db, "users", "user_rank VARCHAR(100) DEFAULT ''")
            ensure_column(cur, db, "users", "district VARCHAR(100) DEFAULT ''")
            ensure_column(cur, db, "users", "thana VARCHAR(100) DEFAULT ''")
            ensure_column(cur, db, "users", "mobile VARCHAR(15) DEFAULT ''")
            ensure_column(cur, db, "users", "assigned_by INT DEFAULT NULL")
            ensure_column(cur, db, "users", "super_admin_id INT DEFAULT NULL")
            ensure_column(cur, db, "users", "created_by INT DEFAULT NULL")
            ensure_column(cur, db, "users", "is_active TINYINT(1) NOT NULL DEFAULT 1")
            ensure_column(cur, db, "users", "is_armed TINYINT(1) NOT NULL DEFAULT 0")

            ensure_column(cur, db, "duty_assignments", "attended TINYINT(1) NOT NULL DEFAULT 0")
            ensure_column(cur, db, "duty_assignments", "election_date DATE DEFAULT NULL")
            ensure_column(cur, db, "matdan_sthal", "latitude DECIMAL(10,7) DEFAULT NULL")
            ensure_column(cur, db, "matdan_sthal", "longitude DECIMAL(10,7) DEFAULT NULL")
            ensure_column(cur, db, "matdan_sthal", "bus_no VARCHAR(50) DEFAULT ''")
            ensure_column(cur, db, "matdan_sthal", "thana VARCHAR(150) DEFAULT ''")
            ensure_column(cur, db, "matdan_sthal", "center_type ENUM('A++','A','B','C') NOT NULL DEFAULT 'C'")
            ensure_column(cur, db, "matdan_sthal", "booth_count INT NOT NULL DEFAULT 1")
            ensure_column(cur, db, "duty_assignments", "bus_no VARCHAR(50) DEFAULT ''")
            ensure_column(cur, db, "duty_assignments", "card_downloaded TINYINT(1) NOT NULL DEFAULT 0")

            # 🆕 Ensure new columns on election_configs (for existing DBs being upgraded)
            ensure_column(cur, db, "election_configs", "election_type VARCHAR(100) NOT NULL DEFAULT ''")
            ensure_column(cur, db, "election_configs", "election_name VARCHAR(200) NOT NULL DEFAULT ''")
            ensure_column(cur, db, "election_configs", "pratah_samay VARCHAR(20) DEFAULT ''")
            ensure_column(cur, db, "election_configs", "saya_samay VARCHAR(20) DEFAULT ''")
            ensure_column(cur, db, "election_configs", "instructions TEXT")
            ensure_column(cur, db, "election_configs", "is_archived TINYINT(1) NOT NULL DEFAULT 0")
            ensure_column(cur, db, "election_configs", "archived_at DATETIME DEFAULT NULL")

            # ─────────────────────────────────────────────────────────────────
            #  SEED
            # ─────────────────────────────────────────────────────────────────
            cur.execute("SET SESSION foreign_key_checks = 1")
            cur.execute("SET SESSION unique_checks = 1")

            cur.execute("SELECT id FROM users WHERE username='master'")
            if not cur.fetchone():
                cur.execute(
                    "INSERT INTO users (name, username, password, role, is_active) "
                    "VALUES ('Master Admin', 'master', %s, 'master', 1)",
                    (hash_password("master"),)
                )
                print("✅  Seeded master account (username: master / password: master)")
                print("⚠️  IMPORTANT: Change the master password immediately after first login!")

        conn.commit()
        print("✅  Database initialised successfully")

    except Exception as e:
        conn.rollback()
        print(f"❌  init_db error: {e}")
        raise
    finally:
        conn.close()


# ══════════════════════════════════════════════════════════════════════════════
#  MIGRATION HELPER
# ══════════════════════════════════════════════════════════════════════════════

def run_migrations():
    migrations = [
        ("users",            "idx_role_district", "INDEX (role, district)"),
        ("users",            "idx_role_active",   "INDEX (role, is_active)"),
        ("users",            "idx_name",          "INDEX (name)"),
        ("users",            "idx_thana",         "INDEX (thana)"),
        ("super_zones",      "idx_admin_id",      "INDEX (admin_id)"),
        ("kshetra_officers", "idx_super_zone_id", "INDEX (super_zone_id)"),
        ("zones",            "idx_super_zone_id", "INDEX (super_zone_id)"),
        ("zonal_officers",   "idx_zone_id",       "INDEX (zone_id)"),
        ("sectors",          "idx_zone_id",       "INDEX (zone_id)"),
        ("sector_officers",  "idx_sector_id",     "INDEX (sector_id)"),
        ("gram_panchayats",  "idx_sector_id",     "INDEX (sector_id)"),
        ("gram_panchayats",  "idx_name",          "INDEX (name)"),
        ("matdan_sthal",     "idx_gp_id",         "INDEX (gram_panchayat_id)"),
        ("matdan_sthal",     "idx_thana",         "INDEX (thana)"),
        ("matdan_sthal",     "idx_name",          "INDEX (name)"),
        ("matdan_sthal",     "idx_center_type",   "INDEX (center_type)"),
        ("matdan_kendra",    "idx_sthal_id",      "INDEX (matdan_sthal_id)"),
        ("duty_assignments", "idx_sthal_id",      "INDEX (sthal_id)"),
        ("duty_assignments", "idx_assigned_by",   "INDEX (assigned_by)"),
        ("system_logs",      "idx_time",          "INDEX (time)"),
        ("system_logs",      "idx_level",         "INDEX (level)"),
        ("system_logs",      "idx_module",        "INDEX (module)"),
        ("fcm_tokens",       "idx_user_id",       "INDEX (user_id)"),
        # 🆕 new indexes
        ("election_configs",  "idx_district_active", "INDEX (district, is_active)"),
        ("election_configs",  "idx_archived",        "INDEX (is_archived)"),
        ("api_request_logs",  "idx_created_at",      "INDEX (created_at)"),
        ("api_request_logs",  "idx_status_code",     "INDEX (status_code)"),
        ("api_request_logs",  "idx_level",           "INDEX (level)"),
        ("token_revocations", "idx_revoke_before",   "INDEX (revoke_before)"),
        ("booth_rules",     "idx_admin_sens",  "INDEX (admin_id, sensitivity)"),
        ("district_rules",  "idx_admin",       "INDEX (admin_id)"),
    ]

    conn = get_db()
    applied, skipped, failed = [], [], []
    try:
        with conn.cursor() as cur:
            for table, index_name, definition in migrations:
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
                        f"ALTER TABLE `{table}` ADD "
                        f"{definition.replace('INDEX', f'INDEX `{index_name}`', 1)}"
                    )
                    conn.commit()
                    applied.append(f"{table}.{index_name}")
                    print(f"  ✅  Index added: {table}.{index_name}")
                except Exception as e:
                    conn.rollback()
                    failed.append(f"{table}.{index_name}: {e}")
                    print(f"  ❌  Index failed: {table}.{index_name}: {e}")
    finally:
        conn.close()

    print(f"\n✅  Migrations done — applied: {len(applied)}, skipped: {len(skipped)}, failed: {len(failed)}")
    return {"applied": applied, "skipped": skipped, "failed": failed}