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


# ══════════════════════════════════════════════════════════════════════════════
#  BOOTSTRAP — create database if missing
# ══════════════════════════════════════════════════════════════════════════════

def create_database_if_not_exists():
    conn = pymysql.connect(
        host=Config.DB_HOST,
        user=Config.DB_USER,
        password=Config.DB_PASS,
        cursorclass=pymysql.cursors.DictCursor,
    )
    try:
        with conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS `{Config.DB_NAME}` "
                        "CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
        conn.commit()
    finally:
        conn.close()

create_database_if_not_exists()


# ══════════════════════════════════════════════════════════════════════════════
#  CONNECTION POOL (preferred) or per-request connections
# ══════════════════════════════════════════════════════════════════════════════

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
        except Exception:
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
        except Exception:
            pass
        return conn


# ══════════════════════════════════════════════════════════════════════════════
#  CONVENIENCE HELPER
# ══════════════════════════════════════════════════════════════════════════════

def get_user_districts(user_id: int) -> list[str]:
    """Return the list of districts assigned to a multi_super_admin (or [] otherwise)."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT district FROM user_districts WHERE user_id=%s ORDER BY district",
                (user_id,)
            )
            return [r["district"] for r in cur.fetchall()]
    finally:
        conn.close()


# ══════════════════════════════════════════════════════════════════════════════
#  SCHEMA HELPERS — idempotent, safe to re-run
# ══════════════════════════════════════════════════════════════════════════════

def ensure_column(cur, db_name: str, table: str, column_def: str):
    col_name = column_def.strip().split()[0].strip("`")
    cur.execute("""
        SELECT COUNT(*) AS cnt
        FROM information_schema.columns
        WHERE table_schema=%s AND table_name=%s AND column_name=%s
    """, (db_name, table, col_name))
    if cur.fetchone()["cnt"] == 0:
        cur.execute(f"ALTER TABLE `{table}` ADD COLUMN {column_def}")
        print(f"  ✅  Column added: {table}.{col_name}")


def ensure_index(cur, db_name: str, table: str, index_name: str, columns: str):
    cur.execute("""
        SELECT COUNT(*) AS cnt
        FROM information_schema.statistics
        WHERE table_schema=%s AND table_name=%s AND index_name=%s
    """, (db_name, table, index_name))
    if cur.fetchone()["cnt"] == 0:
        try:
            cur.execute(f"ALTER TABLE `{table}` ADD INDEX `{index_name}` ({columns})")
            print(f"  ✅  Index added: {table}.{index_name}")
        except Exception as e:
            print(f"  ⚠️  Index {table}.{index_name} skipped: {e}")


def has_foreign_key(cur, db_name: str, table: str, fk_name: str) -> bool:
    cur.execute("""
        SELECT COUNT(*) AS cnt
        FROM information_schema.table_constraints
        WHERE table_schema=%s AND table_name=%s
          AND constraint_name=%s AND constraint_type='FOREIGN KEY'
    """, (db_name, table, fk_name))
    return cur.fetchone()["cnt"] > 0


def ensure_foreign_key(cur, db_name: str, table: str, fk_name: str, fk_def: str):
    if has_foreign_key(cur, db_name, table, fk_name):
        return
    try:
        cur.execute(f"ALTER TABLE `{table}` ADD CONSTRAINT `{fk_name}` {fk_def}")
        print(f"  ✅  FK added: {table}.{fk_name}")
    except Exception as e:
        print(f"  ⚠️  FK {table}.{fk_name} skipped: {e}")


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
            cur.execute(f"USE `{Config.DB_NAME}`")
            cur.execute("SET SESSION foreign_key_checks = 0")
            cur.execute("SET SESSION unique_checks = 0")

            # ── users ────────────────────────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id             INT AUTO_INCREMENT PRIMARY KEY,
                    name           VARCHAR(150)  NOT NULL,
                    username       VARCHAR(100)  NOT NULL,
                    password       VARCHAR(255)  NOT NULL,
                    mobile         VARCHAR(15)   DEFAULT '',
                    role           ENUM('master','super_admin','multi_super_admin','admin','staff') NOT NULL DEFAULT 'staff',
                    district       VARCHAR(100)  DEFAULT '',
                    thana          VARCHAR(100)  DEFAULT '',
                    pno            VARCHAR(50)   DEFAULT NULL,
                    user_rank      VARCHAR(100)  DEFAULT '',
                    is_armed       TINYINT(1)    NOT NULL DEFAULT 0,
                    is_active      TINYINT(1)    NOT NULL DEFAULT 1,
                    created_by     INT           DEFAULT NULL,
                    assigned_by    INT           DEFAULT NULL,
                    super_admin_id INT           DEFAULT NULL,
                    created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
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

            # ── user_districts (many-to-many for multi_super_admin) ──────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS user_districts (
                    id          INT AUTO_INCREMENT PRIMARY KEY,
                    user_id     INT          NOT NULL,
                    district    VARCHAR(100) NOT NULL,
                    assigned_by INT          DEFAULT NULL,
                    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_user_district (user_id, district),
                    INDEX idx_user_id  (user_id),
                    INDEX idx_district (district),
                    FOREIGN KEY (user_id)     REFERENCES users(id) ON DELETE CASCADE,
                    FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── election_configs ─────────────────────────────────────────────
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
                    is_finalized    TINYINT(1)   NOT NULL DEFAULT 0,
                    auto_finalized  TINYINT(1)   NOT NULL DEFAULT 0,
                    finalized_at    DATETIME     DEFAULT NULL,
                    finalized_by    INT          DEFAULT NULL,
                    created_by      INT          DEFAULT NULL,
                    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                 ON UPDATE CURRENT_TIMESTAMP,
                    INDEX idx_district        (district),
                    INDEX idx_district_active (district, is_active),
                    INDEX idx_archived        (is_archived),
                    INDEX idx_finalized       (is_finalized),
                    INDEX idx_election_date   (election_date),
                    INDEX idx_lookup_active   (district, is_active, is_archived, is_finalized),
                    FOREIGN KEY (created_by)   REFERENCES users(id) ON DELETE SET NULL,
                    FOREIGN KEY (finalized_by) REFERENCES users(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── app_config (key/value store) ─────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS app_config (
                    `key`      VARCHAR(100) NOT NULL PRIMARY KEY,
                    value      TEXT         NOT NULL,
                    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                              ON UPDATE CURRENT_TIMESTAMP
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── api_request_logs / token_revocations ─────────────────────────
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

            # ── hierarchy: super_zones ───────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS super_zones (
                    id         INT AUTO_INCREMENT PRIMARY KEY,
                    name       VARCHAR(100) NOT NULL,
                    district   VARCHAR(100) DEFAULT '',
                    block      VARCHAR(100) DEFAULT '',
                    admin_id   INT          DEFAULT NULL,
                    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_admin_id (admin_id),
                    INDEX idx_district (district),
                    FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── 🔐 OFFICER TABLES with election_id (NEW) ─────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS kshetra_officers (
                    id            INT AUTO_INCREMENT PRIMARY KEY,
                    super_zone_id INT NOT NULL,
                    user_id       INT DEFAULT NULL,
                    name          VARCHAR(150) NOT NULL DEFAULT '',
                    pno           VARCHAR(50)  DEFAULT '',
                    mobile        VARCHAR(15)  DEFAULT '',
                    user_rank     VARCHAR(100) DEFAULT '',
                    election_id   INT          DEFAULT NULL,
                    assigned_by   INT          DEFAULT NULL,
                    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_super_zone_id (super_zone_id),
                    INDEX idx_election_id   (election_id),
                    INDEX idx_user_id       (user_id),
                    FOREIGN KEY (super_zone_id) REFERENCES super_zones(id)      ON DELETE CASCADE,
                    FOREIGN KEY (user_id)       REFERENCES users(id)            ON DELETE SET NULL,
                    FOREIGN KEY (election_id)   REFERENCES election_configs(id) ON DELETE SET NULL,
                    FOREIGN KEY (assigned_by)   REFERENCES users(id)            ON DELETE SET NULL
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
                    id          INT AUTO_INCREMENT PRIMARY KEY,
                    zone_id     INT NOT NULL,
                    user_id     INT DEFAULT NULL,
                    name        VARCHAR(150) NOT NULL DEFAULT '',
                    pno         VARCHAR(50)  DEFAULT '',
                    mobile      VARCHAR(15)  DEFAULT '',
                    user_rank   VARCHAR(100) DEFAULT '',
                    election_id INT          DEFAULT NULL,
                    assigned_by INT          DEFAULT NULL,
                    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_zone_id     (zone_id),
                    INDEX idx_election_id (election_id),
                    INDEX idx_user_id     (user_id),
                    FOREIGN KEY (zone_id)     REFERENCES zones(id)            ON DELETE CASCADE,
                    FOREIGN KEY (user_id)     REFERENCES users(id)            ON DELETE SET NULL,
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE SET NULL,
                    FOREIGN KEY (assigned_by) REFERENCES users(id)            ON DELETE SET NULL
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
                    id          INT AUTO_INCREMENT PRIMARY KEY,
                    sector_id   INT NOT NULL,
                    user_id     INT DEFAULT NULL,
                    name        VARCHAR(150) NOT NULL DEFAULT '',
                    pno         VARCHAR(50)  DEFAULT '',
                    mobile      VARCHAR(15)  DEFAULT '',
                    user_rank   VARCHAR(100) DEFAULT '',
                    election_id INT          DEFAULT NULL,
                    assigned_by INT          DEFAULT NULL,
                    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_sector_id   (sector_id),
                    INDEX idx_election_id (election_id),
                    INDEX idx_user_id     (user_id),
                    FOREIGN KEY (sector_id)   REFERENCES sectors(id)          ON DELETE CASCADE,
                    FOREIGN KEY (user_id)     REFERENCES users(id)            ON DELETE SET NULL,
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE SET NULL,
                    FOREIGN KEY (assigned_by) REFERENCES users(id)            ON DELETE SET NULL
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
                    booth_count       INT          NOT NULL DEFAULT 1,
                    bus_no            VARCHAR(50)  DEFAULT '',
                    latitude          DECIMAL(10,7),
                    longitude         DECIMAL(10,7),
                    custom_rule_id    INT          DEFAULT NULL,
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

            # ── duty_assignments — election_id REQUIRED for new rows ──────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS duty_assignments (
                    id              INT AUTO_INCREMENT PRIMARY KEY,
                    staff_id        INT         NOT NULL,
                    sthal_id        INT         NOT NULL,
                    election_id     INT         DEFAULT NULL,
                    bus_no          VARCHAR(50) DEFAULT '',
                    mode            VARCHAR(50) DEFAULT NULL,
                    election_date   DATE        DEFAULT NULL,
                    attended        TINYINT(1)  NOT NULL DEFAULT 0,
                    card_downloaded TINYINT(1)  NOT NULL DEFAULT 0,
                    assigned_by     INT         DEFAULT NULL,
                    created_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_staff_sthal (staff_id, sthal_id),
                    INDEX idx_sthal_id    (sthal_id),
                    INDEX idx_assigned_by (assigned_by),
                    INDEX idx_election_id (election_id),
                    INDEX idx_election_sthal (election_id, sthal_id),
                    FOREIGN KEY (staff_id)    REFERENCES users(id)             ON DELETE CASCADE,
                    FOREIGN KEY (sthal_id)    REFERENCES matdan_sthal(id)      ON DELETE CASCADE,
                    FOREIGN KEY (assigned_by) REFERENCES users(id)             ON DELETE SET NULL,
                    FOREIGN KEY (election_id) REFERENCES election_configs(id)  ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── district_duty_assignments ─────────────────────────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS district_duty_assignments (
                    id          INT AUTO_INCREMENT PRIMARY KEY,
                    admin_id    INT         NOT NULL,
                    duty_type   VARCHAR(80) NOT NULL,
                    batch_no    INT         NOT NULL DEFAULT 1,
                    staff_id    INT         NOT NULL,
                    election_id INT         DEFAULT NULL,
                    assigned_by INT         DEFAULT NULL,
                    bus_no      VARCHAR(50) DEFAULT '',
                    note        TEXT,
                    created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_staff_duty (staff_id, duty_type),
                    INDEX idx_duty_type     (duty_type),
                    INDEX idx_admin_id      (admin_id),
                    INDEX idx_batch         (admin_id, duty_type, batch_no),
                    INDEX idx_election_id   (election_id),
                    INDEX idx_election_duty (election_id, duty_type),
                    FOREIGN KEY (staff_id)    REFERENCES users(id)            ON DELETE CASCADE,
                    FOREIGN KEY (assigned_by) REFERENCES users(id)            ON DELETE SET NULL,
                    FOREIGN KEY (admin_id)    REFERENCES users(id)            ON DELETE CASCADE,
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── booth_rules / district_rules with election_id ─────────────────
            cur.execute("""
                CREATE TABLE IF NOT EXISTS booth_rules (
                    id                  INT AUTO_INCREMENT PRIMARY KEY,
                    admin_id            INT NOT NULL,
                    election_id         INT DEFAULT NULL,
                    sensitivity         ENUM('A++','A','B','C') NOT NULL,
                    booth_count         INT NOT NULL,
                    si_armed_count      INT NOT NULL DEFAULT 0,
                    si_unarmed_count    INT NOT NULL DEFAULT 0,
                    hc_armed_count      INT NOT NULL DEFAULT 0,
                    hc_unarmed_count    INT NOT NULL DEFAULT 0,
                    const_armed_count   INT NOT NULL DEFAULT 0,
                    const_unarmed_count INT NOT NULL DEFAULT 0,
                    aux_armed_count     INT NOT NULL DEFAULT 0,
                    aux_unarmed_count   INT NOT NULL DEFAULT 0,
                    pac_count           DECIMAL(4,1) NOT NULL DEFAULT 0,
                    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                 ON UPDATE CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_admin_sens_booth (admin_id, sensitivity, booth_count),
                    INDEX idx_admin_sens  (admin_id, sensitivity),
                    INDEX idx_election_id (election_id),
                    FOREIGN KEY (admin_id)    REFERENCES users(id)            ON DELETE CASCADE,
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS district_rules (
                    id                  INT AUTO_INCREMENT PRIMARY KEY,
                    admin_id            INT         NOT NULL,
                    election_id         INT         DEFAULT NULL,
                    duty_type           VARCHAR(80) NOT NULL,
                    duty_label_hi       VARCHAR(150) NOT NULL DEFAULT '',
                    sankhya             INT          NOT NULL DEFAULT 0,
                    si_armed_count      INT NOT NULL DEFAULT 0,
                    si_unarmed_count    INT NOT NULL DEFAULT 0,
                    hc_armed_count      INT NOT NULL DEFAULT 0,
                    hc_unarmed_count    INT NOT NULL DEFAULT 0,
                    const_armed_count   INT NOT NULL DEFAULT 0,
                    const_unarmed_count INT NOT NULL DEFAULT 0,
                    aux_armed_count     INT NOT NULL DEFAULT 0,
                    aux_unarmed_count   INT NOT NULL DEFAULT 0,
                    pac_count           DECIMAL(4,1) NOT NULL DEFAULT 0,
                    sort_order          INT          NOT NULL DEFAULT 0,
                    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                 ON UPDATE CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_admin_duty (admin_id, duty_type),
                    INDEX idx_admin       (admin_id),
                    INDEX idx_election_id (election_id),
                    FOREIGN KEY (admin_id)    REFERENCES users(id)            ON DELETE CASCADE,
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ── system_logs / fcm_tokens ──────────────────────────────────────
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

            # ── goswara / locks / unlock_requests / jobs ──────────────────────
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
                    id            INT AUTO_INCREMENT PRIMARY KEY,
                    super_zone_id INT UNIQUE,
                    is_locked     TINYINT(1) DEFAULT 0,
                    status        ENUM('locked','unlock_requested','unlocked') DEFAULT 'unlocked',
                    unlock_reason TEXT,
                    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS sz_assign_jobs (
                    id            INT AUTO_INCREMENT PRIMARY KEY,
                    super_zone_id INT,
                    status        ENUM('pending','running','done','error') DEFAULT 'pending',
                    total_centers INT DEFAULT 0,
                    done_centers  INT DEFAULT 0,
                    error_msg     TEXT,
                    shortage_report LONGTEXT,
                    created_by    INT,
                    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_sz   (super_zone_id),
                    INDEX idx_stat (status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS sz_unlock_requests (
                    id            INT AUTO_INCREMENT PRIMARY KEY,
                    super_zone_id INT,
                    requested_by  INT,
                    reason        TEXT,
                    status        ENUM('pending','approved','rejected') DEFAULT 'pending',
                    reviewed_by   INT,
                    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS district_duty_jobs (
                    id          INT AUTO_INCREMENT PRIMARY KEY,
                    admin_id    INT  NOT NULL,
                    status      ENUM('pending','running','done','error') DEFAULT 'pending',
                    total_types INT  NOT NULL DEFAULT 0,
                    done_types  INT  NOT NULL DEFAULT 0,
                    assigned    INT  NOT NULL DEFAULT 0,
                    skipped     INT  NOT NULL DEFAULT 0,
                    error_msg   TEXT,
                    created_by  INT  DEFAULT NULL,
                    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                         ON UPDATE CURRENT_TIMESTAMP,
                    INDEX idx_admin (admin_id),
                    FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ══════════════════════════════════════════════════════════════════
            #  HISTORY TABLES
            # ══════════════════════════════════════════════════════════════════
            cur.execute("""
                CREATE TABLE IF NOT EXISTS duty_assignments_history (
                    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
                    election_id         INT         NOT NULL,
                    original_id         INT         NOT NULL,
                    admin_id            INT         NOT NULL,
                    district            VARCHAR(100) DEFAULT '',
                    election_name       VARCHAR(200) DEFAULT '',
                    staff_id            INT         NOT NULL,
                    sthal_id            INT         NOT NULL,
                    staff_name          VARCHAR(150) DEFAULT '',
                    staff_pno           VARCHAR(50)  DEFAULT '',
                    staff_mobile        VARCHAR(15)  DEFAULT '',
                    staff_rank          VARCHAR(100) DEFAULT '',
                    staff_district      VARCHAR(100) DEFAULT '',
                    staff_thana         VARCHAR(100) DEFAULT '',
                    is_armed            TINYINT(1)   NOT NULL DEFAULT 0,
                    center_name         VARCHAR(250) DEFAULT '',
                    center_type         VARCHAR(10)  DEFAULT '',
                    bus_no              VARCHAR(50)  DEFAULT '',
                    election_date       DATE         DEFAULT NULL,
                    attended            TINYINT(1)   NOT NULL DEFAULT 0,
                    card_downloaded     TINYINT(1)   NOT NULL DEFAULT 0,
                    assigned_by         INT          DEFAULT NULL,
                    original_created_at DATETIME     DEFAULT NULL,
                    archived_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_election_id    (election_id),
                    INDEX idx_admin_id       (admin_id),
                    INDEX idx_district       (district),
                    INDEX idx_district_elect (district, election_id),
                    INDEX idx_sthal_id       (sthal_id),
                    INDEX idx_staff_id       (staff_id),
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS district_duty_history (
                    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
                    election_id         INT         NOT NULL,
                    original_id         INT         NOT NULL,
                    admin_id            INT         NOT NULL,
                    district            VARCHAR(100) DEFAULT '',
                    election_name       VARCHAR(200) DEFAULT '',
                    duty_type           VARCHAR(80) NOT NULL,
                    duty_label_hi       VARCHAR(150) DEFAULT '',
                    batch_no            INT         NOT NULL DEFAULT 1,
                    staff_id            INT         NOT NULL,
                    staff_name          VARCHAR(150) DEFAULT '',
                    staff_pno           VARCHAR(50)  DEFAULT '',
                    staff_mobile        VARCHAR(15)  DEFAULT '',
                    staff_rank          VARCHAR(100) DEFAULT '',
                    staff_district      VARCHAR(100) DEFAULT '',
                    staff_thana         VARCHAR(100) DEFAULT '',
                    is_armed            TINYINT(1)   NOT NULL DEFAULT 0,
                    assigned_by         INT          DEFAULT NULL,
                    bus_no              VARCHAR(50)  DEFAULT '',
                    note                TEXT,
                    original_created_at DATETIME     DEFAULT NULL,
                    archived_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_election_id    (election_id),
                    INDEX idx_admin_id       (admin_id),
                    INDEX idx_district       (district),
                    INDEX idx_district_elect (district, election_id),
                    INDEX idx_duty_type      (duty_type),
                    INDEX idx_staff_id       (staff_id),
                    INDEX idx_batch          (election_id, duty_type, batch_no),
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS district_rules_history (
                    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
                    election_id         INT         NOT NULL,
                    original_id         INT         NOT NULL,
                    admin_id            INT         NOT NULL,
                    district            VARCHAR(100) DEFAULT '',
                    election_name       VARCHAR(200) DEFAULT '',
                    duty_type           VARCHAR(80) NOT NULL,
                    duty_label_hi       VARCHAR(150) NOT NULL DEFAULT '',
                    sankhya             INT         NOT NULL DEFAULT 0,
                    si_armed_count      INT         NOT NULL DEFAULT 0,
                    si_unarmed_count    INT         NOT NULL DEFAULT 0,
                    hc_armed_count      INT         NOT NULL DEFAULT 0,
                    hc_unarmed_count    INT         NOT NULL DEFAULT 0,
                    const_armed_count   INT         NOT NULL DEFAULT 0,
                    const_unarmed_count INT         NOT NULL DEFAULT 0,
                    aux_armed_count     INT         NOT NULL DEFAULT 0,
                    aux_unarmed_count   INT         NOT NULL DEFAULT 0,
                    pac_count           DECIMAL(4,1) NOT NULL DEFAULT 0,
                    sort_order          INT         NOT NULL DEFAULT 0,
                    original_created_at DATETIME    DEFAULT NULL,
                    archived_at         DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_election_id (election_id),
                    INDEX idx_admin_id    (admin_id),
                    INDEX idx_district    (district),
                    INDEX idx_duty_type   (duty_type),
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS booth_rules_history (
                    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
                    election_id         INT             NOT NULL,
                    original_id         INT             NOT NULL,
                    admin_id            INT             NOT NULL,
                    district            VARCHAR(100)    DEFAULT '',
                    election_name       VARCHAR(200)    DEFAULT '',
                    sensitivity         ENUM('A++','A','B','C') NOT NULL,
                    booth_count         INT             NOT NULL,
                    si_armed_count      INT             NOT NULL DEFAULT 0,
                    si_unarmed_count    INT             NOT NULL DEFAULT 0,
                    hc_armed_count      INT             NOT NULL DEFAULT 0,
                    hc_unarmed_count    INT             NOT NULL DEFAULT 0,
                    const_armed_count   INT             NOT NULL DEFAULT 0,
                    const_unarmed_count INT             NOT NULL DEFAULT 0,
                    aux_armed_count     INT             NOT NULL DEFAULT 0,
                    aux_unarmed_count   INT             NOT NULL DEFAULT 0,
                    pac_count           DECIMAL(4,1)    NOT NULL DEFAULT 0,
                    original_created_at DATETIME        DEFAULT NULL,
                    archived_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_election_id (election_id),
                    INDEX idx_admin_id    (admin_id),
                    INDEX idx_district    (district),
                    INDEX idx_sensitivity (election_id, sensitivity),
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS kshetra_officers_history (
                    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
                    election_id         INT          NOT NULL,
                    original_id         INT          NOT NULL,
                    admin_id            INT          NOT NULL,
                    district            VARCHAR(100) DEFAULT '',
                    election_name       VARCHAR(200) DEFAULT '',
                    super_zone_id       INT          NOT NULL,
                    super_zone_name     VARCHAR(100) DEFAULT '',
                    super_zone_block    VARCHAR(100) DEFAULT '',
                    user_id             INT          DEFAULT NULL,
                    name                VARCHAR(150) NOT NULL DEFAULT '',
                    pno                 VARCHAR(50)  DEFAULT '',
                    mobile              VARCHAR(15)  DEFAULT '',
                    user_rank           VARCHAR(100) DEFAULT '',
                    assigned_by         INT          DEFAULT NULL,
                    original_created_at DATETIME     DEFAULT NULL,
                    archived_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_election_id   (election_id),
                    INDEX idx_admin_id      (admin_id),
                    INDEX idx_district      (district),
                    INDEX idx_super_zone_id (super_zone_id),
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS zonal_officers_history (
                    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
                    election_id         INT          NOT NULL,
                    original_id         INT          NOT NULL,
                    admin_id            INT          NOT NULL,
                    district            VARCHAR(100) DEFAULT '',
                    election_name       VARCHAR(200) DEFAULT '',
                    zone_id             INT          NOT NULL,
                    zone_name           VARCHAR(100) DEFAULT '',
                    super_zone_id       INT          DEFAULT NULL,
                    super_zone_name     VARCHAR(100) DEFAULT '',
                    user_id             INT          DEFAULT NULL,
                    name                VARCHAR(150) NOT NULL DEFAULT '',
                    pno                 VARCHAR(50)  DEFAULT '',
                    mobile              VARCHAR(15)  DEFAULT '',
                    user_rank           VARCHAR(100) DEFAULT '',
                    assigned_by         INT          DEFAULT NULL,
                    original_created_at DATETIME     DEFAULT NULL,
                    archived_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_election_id (election_id),
                    INDEX idx_admin_id    (admin_id),
                    INDEX idx_district    (district),
                    INDEX idx_zone_id     (zone_id),
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            cur.execute("""
                CREATE TABLE IF NOT EXISTS sector_officers_history (
                    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
                    election_id         INT          NOT NULL,
                    original_id         INT          NOT NULL,
                    admin_id            INT          NOT NULL,
                    district            VARCHAR(100) DEFAULT '',
                    election_name       VARCHAR(200) DEFAULT '',
                    sector_id           INT          NOT NULL,
                    sector_name         VARCHAR(100) DEFAULT '',
                    zone_id             INT          DEFAULT NULL,
                    zone_name           VARCHAR(100) DEFAULT '',
                    super_zone_id       INT          DEFAULT NULL,
                    super_zone_name     VARCHAR(100) DEFAULT '',
                    user_id             INT          DEFAULT NULL,
                    name                VARCHAR(150) NOT NULL DEFAULT '',
                    pno                 VARCHAR(50)  DEFAULT '',
                    mobile              VARCHAR(15)  DEFAULT '',
                    user_rank           VARCHAR(100) DEFAULT '',
                    assigned_by         INT          DEFAULT NULL,
                    original_created_at DATETIME     DEFAULT NULL,
                    archived_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_election_id (election_id),
                    INDEX idx_admin_id    (admin_id),
                    INDEX idx_district    (district),
                    INDEX idx_sector_id   (sector_id),
                    FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """)

            # ─────────────────────────────────────────────────────────────────
            #  AUTO-ADD MISSING COLUMNS / FK for existing databases
            # ─────────────────────────────────────────────────────────────────
            cur.execute("SET SESSION foreign_key_checks = 0")
            db = Config.DB_NAME

            # Widen `users.role` enum to include 'multi_super_admin' (idempotent)
            try:
                cur.execute("""
                    SELECT COLUMN_TYPE
                    FROM information_schema.columns
                    WHERE table_schema = %s AND table_name = 'users' AND column_name = 'role'
                """, (db,))
                row = cur.fetchone()
                if row and "multi_super_admin" not in (row["COLUMN_TYPE"] or ""):
                    cur.execute("""
                        ALTER TABLE users
                        MODIFY COLUMN role
                        ENUM('master','super_admin','multi_super_admin','admin','staff')
                        NOT NULL DEFAULT 'staff'
                    """)
                    print("  ✅  users.role enum widened (multi_super_admin)")
            except Exception as e:
                print(f"  ⚠️  users.role enum migration skipped: {e}")

            # users
            for col in [
                "pno VARCHAR(50) DEFAULT NULL",
                "user_rank VARCHAR(100) DEFAULT ''",
                "district VARCHAR(100) DEFAULT ''",
                "thana VARCHAR(100) DEFAULT ''",
                "mobile VARCHAR(15) DEFAULT ''",
                "assigned_by INT DEFAULT NULL",
                "super_admin_id INT DEFAULT NULL",
                "created_by INT DEFAULT NULL",
                "is_active TINYINT(1) NOT NULL DEFAULT 1",
                "is_armed TINYINT(1) NOT NULL DEFAULT 0",
            ]:
                ensure_column(cur, db, "users", col)

            # election_configs
            for col in [
                "election_type VARCHAR(100) NOT NULL DEFAULT ''",
                "election_name VARCHAR(200) NOT NULL DEFAULT ''",
                "pratah_samay VARCHAR(20) DEFAULT ''",
                "saya_samay VARCHAR(20) DEFAULT ''",
                "instructions TEXT",
                "is_archived TINYINT(1) NOT NULL DEFAULT 0",
                "archived_at DATETIME DEFAULT NULL",
                "is_finalized TINYINT(1) NOT NULL DEFAULT 0",
                "auto_finalized TINYINT(1) NOT NULL DEFAULT 0",
                "finalized_at DATETIME DEFAULT NULL",
                "finalized_by INT DEFAULT NULL",
            ]:
                ensure_column(cur, db, "election_configs", col)
            ensure_index(cur, db, "election_configs", "idx_lookup_active",
                         "district, is_active, is_archived, is_finalized")

            # ⚡ duty_assignments
            for col in [
                "election_id INT DEFAULT NULL",
                "attended TINYINT(1) NOT NULL DEFAULT 0",
                "election_date DATE DEFAULT NULL",
                "bus_no VARCHAR(50) DEFAULT ''",
                "card_downloaded TINYINT(1) NOT NULL DEFAULT 0",
                "mode VARCHAR(50) DEFAULT NULL",
            ]:
                ensure_column(cur, db, "duty_assignments", col)
            ensure_index(cur, db, "duty_assignments", "idx_election_id", "election_id")
            ensure_index(cur, db, "duty_assignments", "idx_election_sthal", "election_id, sthal_id")
            ensure_foreign_key(cur, db, "duty_assignments", "fk_da_election",
                "FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE SET NULL")

            # ⚡ district_duty_assignments
            for col in [
                "election_id INT DEFAULT NULL",
                "bus_no VARCHAR(50) DEFAULT ''",
                "note TEXT",
            ]:
                ensure_column(cur, db, "district_duty_assignments", col)
            ensure_index(cur, db, "district_duty_assignments", "idx_election_id", "election_id")
            ensure_index(cur, db, "district_duty_assignments", "idx_election_duty",
                         "election_id, duty_type")
            ensure_foreign_key(cur, db, "district_duty_assignments", "fk_dda_election",
                "FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE SET NULL")

            # ⚡ booth_rules / district_rules
            for tbl in ("booth_rules", "district_rules"):
                ensure_column(cur, db, tbl, "election_id INT DEFAULT NULL")
                ensure_index(cur, db, tbl, "idx_election_id", "election_id")
                short = "br" if tbl == "booth_rules" else "dr"
                ensure_foreign_key(cur, db, tbl, f"fk_{short}_election",
                    "FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE SET NULL")

            # ⚡ 🔐 OFFICER tables — election_id + assigned_by
            officer_fk_map = {
                "kshetra_officers": "ko",
                "zonal_officers":   "zo",
                "sector_officers":  "so",
            }
            for tbl, alias in officer_fk_map.items():
                ensure_column(cur, db, tbl, "election_id INT DEFAULT NULL")
                ensure_column(cur, db, tbl, "assigned_by INT DEFAULT NULL")
                ensure_index(cur, db, tbl, "idx_election_id", "election_id")
                ensure_foreign_key(cur, db, tbl, f"fk_{alias}_election",
                    "FOREIGN KEY (election_id) REFERENCES election_configs(id) ON DELETE SET NULL")
                ensure_foreign_key(cur, db, tbl, f"fk_{alias}_assignedby",
                    "FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL")

            # matdan_sthal
            for col in [
                "latitude DECIMAL(10,7) DEFAULT NULL",
                "longitude DECIMAL(10,7) DEFAULT NULL",
                "bus_no VARCHAR(50) DEFAULT ''",
                "thana VARCHAR(150) DEFAULT ''",
                "center_type ENUM('A++','A','B','C') NOT NULL DEFAULT 'C'",
                "booth_count INT NOT NULL DEFAULT 1",
                "custom_rule_id INT DEFAULT NULL",
            ]:
                ensure_column(cur, db, "matdan_sthal", col)

            # district_duty_jobs
            for col in [
                "updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP "
                "ON UPDATE CURRENT_TIMESTAMP",
                "total_types INT NOT NULL DEFAULT 0",
                "done_types INT NOT NULL DEFAULT 0",
                "assigned INT NOT NULL DEFAULT 0",
                "skipped INT NOT NULL DEFAULT 0",
                "error_msg TEXT",
            ]:
                ensure_column(cur, db, "district_duty_jobs", col)

            # history denormalized columns
            for tbl in (
                "duty_assignments_history",
                "district_duty_history",
                "district_rules_history",
                "booth_rules_history",
                "kshetra_officers_history",
                "zonal_officers_history",
                "sector_officers_history",
            ):
                ensure_column(cur, db, tbl, "district VARCHAR(100) DEFAULT ''")
                ensure_column(cur, db, tbl, "election_name VARCHAR(200) DEFAULT ''")
                ensure_index(cur, db, tbl, "idx_district", "district")
                ensure_index(cur, db, tbl, "idx_district_elect", "district, election_id")

            # Officer history tables — assigned_by column for archival
            for tbl in (
                "kshetra_officers_history",
                "zonal_officers_history",
                "sector_officers_history",
            ):
                ensure_column(cur, db, tbl, "assigned_by INT DEFAULT NULL")

            cur.execute("SET SESSION foreign_key_checks = 1")
            cur.execute("SET SESSION unique_checks = 1")

            # ─────────────────────────────────────────────────────────────────
            #  SEED master account
            # ─────────────────────────────────────────────────────────────────
            cur.execute("SELECT id FROM users WHERE username='master'")
            if not cur.fetchone():
                cur.execute(
                    "INSERT INTO users (name, username, password, role, is_active) "
                    "VALUES ('Master Admin', 'master', %s, 'master', 1)",
                    (hash_password("master"),)
                )
                print("✅  Seeded master account (master / master)")
                print("⚠️  IMPORTANT: change master password immediately!")

        conn.commit()
        print("✅  Database initialised successfully")

    except Exception as e:
        conn.rollback()
        print(f"❌  init_db error: {e}")
        raise
    finally:
        conn.close()


def run_migrations():
    """No-op kept for backward compatibility."""
    print("ℹ️  run_migrations(): all schema work now handled by init_db()")
    return {"applied": [], "skipped": [], "failed": []}