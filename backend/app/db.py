import pymysql
from config import Config


def get_db():
    connection = pymysql.connect(
        host       = Config.DB_HOST,
        user       = Config.DB_USER,
        password   = Config.DB_PASS,
        cursorclass= pymysql.cursors.DictCursor,
    )

    try:
        with connection.cursor() as cursor:

            cursor.execute(f"CREATE DATABASE IF NOT EXISTS {Config.DB_NAME}")
            cursor.execute(f"USE {Config.DB_NAME}")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS super_zones (
                id       INT AUTO_INCREMENT PRIMARY KEY,
                name     VARCHAR(100) NOT NULL,
                district VARCHAR(100) NOT NULL
            )""")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS zones (
                id             INT AUTO_INCREMENT PRIMARY KEY,
                name           VARCHAR(100) NOT NULL,
                address        TEXT,
                officer_name   VARCHAR(100),
                officer_mobile VARCHAR(15) UNIQUE,
                super_zone_id  INT,
                FOREIGN KEY (super_zone_id) REFERENCES super_zones(id) ON DELETE CASCADE
            )""")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS sectors (
                id             INT AUTO_INCREMENT PRIMARY KEY,
                name           VARCHAR(100) NOT NULL,
                address        TEXT,
                officer_name   VARCHAR(100),
                officer_mobile VARCHAR(15) UNIQUE,
                zone_id        INT,
                FOREIGN KEY (zone_id) REFERENCES zones(id) ON DELETE CASCADE
            )""")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS gram_panchayats (
                id        INT AUTO_INCREMENT PRIMARY KEY,
                name      VARCHAR(150) NOT NULL,
                address   TEXT,
                sector_id INT,
                FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE CASCADE
            )""")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS matdan_sthal (
                id                INT AUTO_INCREMENT PRIMARY KEY,
                name              VARCHAR(200) NOT NULL,
                address           TEXT,
                gram_panchayat_id INT,
                thana             VARCHAR(100),
                center_type       VARCHAR(100),
                bus_no            VARCHAR(50),
                FOREIGN KEY (gram_panchayat_id) REFERENCES gram_panchayats(id) ON DELETE CASCADE
            )""")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS matdan_kendra (
                id              INT AUTO_INCREMENT PRIMARY KEY,
                room_number     VARCHAR(50),
                matdan_sthal_id INT,
                FOREIGN KEY (matdan_sthal_id) REFERENCES matdan_sthal(id) ON DELETE CASCADE
            )""")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                name        VARCHAR(150) NOT NULL,
                username    VARCHAR(100) UNIQUE,
                mobile      VARCHAR(15)  UNIQUE,
                password    VARCHAR(255) NOT NULL,
                role        ENUM('master','super_admin','admin','user') DEFAULT 'user',
                is_active   TINYINT(1)   DEFAULT 1,
                district    VARCHAR(100),
                kendra_id   INT,
                created_by  INT,
                assigned_by INT,
                created_at  DATETIME     DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (kendra_id)   REFERENCES matdan_kendra(id) ON DELETE SET NULL,
                FOREIGN KEY (created_by)  REFERENCES users(id)         ON DELETE SET NULL,
                FOREIGN KEY (assigned_by) REFERENCES users(id)         ON DELETE SET NULL
            )""")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS staff (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                pno         VARCHAR(20)  UNIQUE NOT NULL,
                name        VARCHAR(150) NOT NULL,
                mobile      VARCHAR(15)  UNIQUE,
                designation VARCHAR(100),
                department  VARCHAR(150),
                district    VARCHAR(100),
                is_assigned TINYINT(1)   DEFAULT 0,
                created_by  INT,
                created_at  DATETIME     DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
            )""")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS duties (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                staff_id    INT  NOT NULL,
                kendra_id   INT  NOT NULL,
                duty_type   VARCHAR(100),
                shift       VARCHAR(50),
                duty_date   DATE,
                remarks     TEXT,
                assigned_by INT,
                assigned_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (staff_id)    REFERENCES staff(id)         ON DELETE CASCADE,
                FOREIGN KEY (kendra_id)   REFERENCES matdan_kendra(id) ON DELETE CASCADE,
                FOREIGN KEY (assigned_by) REFERENCES users(id)         ON DELETE SET NULL,
                UNIQUE KEY uq_staff_duty (staff_id, duty_date)
            )""")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS system_logs (
                id      INT AUTO_INCREMENT PRIMARY KEY,
                level   ENUM('INFO','WARN','ERROR') NOT NULL DEFAULT 'INFO',
                message VARCHAR(500) NOT NULL,
                module  VARCHAR(50)  NOT NULL,
                time    DATETIME     DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_level (level),
                INDEX idx_time  (time)
            )""")

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS app_config (
                id    INT AUTO_INCREMENT PRIMARY KEY,
                `key` VARCHAR(100) UNIQUE NOT NULL,
                value VARCHAR(500) NOT NULL
            )""")

            # Seed default config
            cursor.execute("SELECT COUNT(*) AS cnt FROM app_config")
            if cursor.fetchone()["cnt"] == 0:
                cursor.executemany(
                    "INSERT INTO app_config (`key`, value) VALUES (%s, %s)",
                    [
                        ("maintenanceMode",    "false"),
                        ("allowStaffLogin",    "true"),
                        ("forcePasswordReset", "false"),
                        ("electionYear",       "2026"),
                        ("state",              "Uttar Pradesh"),
                        ("phase",              "Phase 1"),
                        ("electionDate",       "15 Apr 2026"),
                    ]
                )

            # Seed default master admin
            cursor.execute("SELECT COUNT(*) AS cnt FROM users WHERE role = 'master'")
            if cursor.fetchone()["cnt"] == 0:
                from werkzeug.security import generate_password_hash
                cursor.execute("""
                    INSERT INTO users (name, username, password, role, is_active)
                    VALUES (%s, %s, %s, 'master', 1)
                """, ("Master Admin", "master", generate_password_hash("Master@123")))
                print("🔑  Default master created  →  username: master  |  password: Master@123")
                print("    ⚠️  Change this password immediately after first login!")

        connection.commit()
        print("✅  Database initialised successfully")

    except Exception as e:
        connection.rollback()
        print(f"❌  DB init failed: {e}")
        raise

    finally:
        connection.close()


if __name__ == "__main__":
    get_db()