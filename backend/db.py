import pymysql
import pymysql.cursors
from config import Config
from werkzeug.security import generate_password_hash


# ─────────────────────────────────────────────
#  CONNECTION
# ─────────────────────────────────────────────
def get_db():
    return pymysql.connect(
        host        = Config.DB_HOST,
        user        = Config.DB_USER,
        password    = Config.DB_PASS,
        database    = Config.DB_NAME,
        cursorclass = pymysql.cursors.DictCursor,
        autocommit  = False,
    )


# ─────────────────────────────────────────────
#  INIT — creates DB + all tables + seed data
# ─────────────────────────────────────────────
def init_db():
    # Connect without database first so we can CREATE DATABASE
    conn = pymysql.connect(
        host        = Config.DB_HOST,
        user        = Config.DB_USER,
        password    = Config.DB_PASS,
        cursorclass = pymysql.cursors.DictCursor,
        autocommit  = False,
    )

    try:
        with conn.cursor() as cur:

            # ── Database ─────────────────────────────
            cur.execute(f"CREATE DATABASE IF NOT EXISTS `{Config.DB_NAME}`")
            cur.execute(f"USE `{Config.DB_NAME}`")

            # ── Users ────────────────────────────────
            # Central user table — covers master, super_admin, admin, staff
            cur.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                name        VARCHAR(150)  NOT NULL,
                username    VARCHAR(100)  UNIQUE NOT NULL,
                password    VARCHAR(255)  NOT NULL,
                mobile      VARCHAR(15),
                role        ENUM('master','super_admin','admin','staff') NOT NULL DEFAULT 'staff',
                district    VARCHAR(100),
                thana       VARCHAR(100),
                pno         VARCHAR(50)   UNIQUE,
                is_active   TINYINT(1)    NOT NULL DEFAULT 1,
                created_by  INT,
                assigned_by INT,
                created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                            ON UPDATE CURRENT_TIMESTAMP,
                FOREIGN KEY (created_by)  REFERENCES users(id) ON DELETE SET NULL,
                FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            # ── Election Structure ────────────────────

            cur.execute("""
            CREATE TABLE IF NOT EXISTS super_zones (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                name        VARCHAR(100)  NOT NULL,
                district    VARCHAR(100),
                admin_id    INT,
                created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            cur.execute("""
            CREATE TABLE IF NOT EXISTS zones (
                id              INT AUTO_INCREMENT PRIMARY KEY,
                name            VARCHAR(100)  NOT NULL,
                hq_address      TEXT,
                officer_name    VARCHAR(150),
                officer_pno     VARCHAR(50),
                officer_mobile  VARCHAR(15),
                super_zone_id   INT NOT NULL,
                created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (super_zone_id) REFERENCES super_zones(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            cur.execute("""
            CREATE TABLE IF NOT EXISTS sectors (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                name        VARCHAR(100)  NOT NULL,
                zone_id     INT NOT NULL,
                created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (zone_id) REFERENCES zones(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            # Multiple police officers per sector
            cur.execute("""
            CREATE TABLE IF NOT EXISTS sector_officers (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                sector_id   INT NOT NULL,
                name        VARCHAR(150)  NOT NULL,
                pno         VARCHAR(50),
                mobile      VARCHAR(15),
                created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            cur.execute("""
            CREATE TABLE IF NOT EXISTS gram_panchayats (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                name        VARCHAR(200)  NOT NULL,
                address     TEXT,
                sector_id   INT NOT NULL,
                created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            cur.execute("""
            CREATE TABLE IF NOT EXISTS matdan_sthal (
                id                  INT AUTO_INCREMENT PRIMARY KEY,
                name                VARCHAR(250)  NOT NULL,
                address             TEXT,
                gram_panchayat_id   INT NOT NULL,
                thana               VARCHAR(150),
                center_type         ENUM('A','B','C') NOT NULL DEFAULT 'C',
                bus_no              VARCHAR(50),
                latitude            DECIMAL(10,7),
                longitude           DECIMAL(10,7),
                created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (gram_panchayat_id) REFERENCES gram_panchayats(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            cur.execute("""
            CREATE TABLE IF NOT EXISTS matdan_kendra (
                id              INT AUTO_INCREMENT PRIMARY KEY,
                room_number     VARCHAR(50),
                matdan_sthal_id INT NOT NULL,
                created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (matdan_sthal_id) REFERENCES matdan_sthal(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            # ── Duty Assignments ─────────────────────
            cur.execute("""
            CREATE TABLE IF NOT EXISTS duty_assignments (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                staff_id    INT NOT NULL,
                sthal_id    INT NOT NULL,
                bus_no      VARCHAR(50),
                assigned_by INT,
                created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_staff_sthal (staff_id, sthal_id),
                FOREIGN KEY (staff_id)    REFERENCES users(id)         ON DELETE CASCADE,
                FOREIGN KEY (sthal_id)    REFERENCES matdan_sthal(id)  ON DELETE CASCADE,
                FOREIGN KEY (assigned_by) REFERENCES users(id)         ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            # ── System Logs ──────────────────────────
            cur.execute("""
            CREATE TABLE IF NOT EXISTS system_logs (
                id      INT AUTO_INCREMENT PRIMARY KEY,
                level   ENUM('INFO','WARN','ERROR') NOT NULL DEFAULT 'INFO',
                message TEXT NOT NULL,
                module  VARCHAR(80) NOT NULL,
                time    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            # ── App Config ───────────────────────────
            cur.execute("""
            CREATE TABLE IF NOT EXISTS app_config (
                `key`   VARCHAR(100) PRIMARY KEY,
                value   TEXT,
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                           ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)

            # ── Default Config Values ────────────────
            defaults = [
                ("maintenanceMode",   "false"),
                ("allowStaffLogin",   "true"),
                ("forcePasswordReset","false"),
                ("electionYear",      "2026"),
                ("state",             "Uttar Pradesh"),
                ("phase",             "Phase 1"),
                ("electionDate",      "15 Apr 2026"),
            ]
            for k, v in defaults:
                cur.execute("""
                    INSERT INTO app_config (`key`, value)
                    VALUES (%s, %s)
                    ON DUPLICATE KEY UPDATE `key`=`key`
                """, (k, v))

            # ── Seed: Master Admin ───────────────────
            cur.execute("SELECT id FROM users WHERE username = 'master'")
            if not cur.fetchone():
                cur.execute("""
                    INSERT INTO users (name, username, password, role, is_active)
                    VALUES (%s, %s, %s, 'master', 1)
                """, (
                    "Master Admin",
                    "master",
                    generate_password_hash("master"),
                ))
                print("✅  Seeded master admin  (user: master / pass: master)")

            # ── Seed: Super Admin ────────────────────
            cur.execute("SELECT id FROM users WHERE username = 'super'")
            if not cur.fetchone():
                cur.execute("""
                    INSERT INTO users (name, username, password, role, is_active)
                    VALUES (%s, %s, %s, 'super_admin', 1)
                """, (
                    "Super Admin",
                    "super",
                    generate_password_hash("super"),
                ))
                print("✅  Seeded super admin   (user: super  / pass: super)")

        conn.commit()
        print("✅  Database initialised successfully")

    except Exception as e:
        conn.rollback()
        print(f"❌  init_db error: {e}")
        raise

    finally:
        conn.close()