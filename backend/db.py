import pymysql
import pymysql.cursors
from config import Config
from werkzeug.security import generate_password_hash


def get_db():
    return pymysql.connect(
        host=Config.DB_HOST, user=Config.DB_USER,
        password=Config.DB_PASS, database=Config.DB_NAME,
        cursorclass=pymysql.cursors.DictCursor, autocommit=False,
    )


def init_db():
    conn = pymysql.connect(
        host=Config.DB_HOST, user=Config.DB_USER, password=Config.DB_PASS,
        cursorclass=pymysql.cursors.DictCursor, autocommit=False,
    )
    try:
        with conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS `{Config.DB_NAME}`")
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

            # super_zones — no inline officer cols; uses kshetra_officers table
            cur.execute("""CREATE TABLE IF NOT EXISTS super_zones (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                district VARCHAR(100) DEFAULT '',
                block VARCHAR(100) DEFAULT '',
                admin_id INT,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # kshetra_officers — multiple per super zone
            # user_id links to users table so existing staff can be picked
            cur.execute("""CREATE TABLE IF NOT EXISTS kshetra_officers (
                id INT AUTO_INCREMENT PRIMARY KEY,
                super_zone_id INT NOT NULL,
                user_id INT DEFAULT NULL,
                name VARCHAR(150) NOT NULL DEFAULT '',
                pno VARCHAR(50) DEFAULT '',
                mobile VARCHAR(15) DEFAULT '',
                user_rank VARCHAR(100) DEFAULT  '',
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (super_zone_id) REFERENCES super_zones(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # zones — no inline officer cols; uses zonal_officers table
            cur.execute("""CREATE TABLE IF NOT EXISTS zones (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                hq_address TEXT,
                super_zone_id INT NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (super_zone_id) REFERENCES super_zones(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # zonal_officers — multiple per zone
            cur.execute("""CREATE TABLE IF NOT EXISTS zonal_officers (
                id INT AUTO_INCREMENT PRIMARY KEY,
                zone_id INT NOT NULL,
                user_id INT DEFAULT NULL,
                name VARCHAR(150) NOT NULL DEFAULT '',
                pno VARCHAR(50) DEFAULT '',
                mobile VARCHAR(15) DEFAULT '',
                user_rank VARCHAR(100) DEFAULT '',
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (zone_id)  REFERENCES zones(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id)  REFERENCES users(id) ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # sectors
            cur.execute("""CREATE TABLE IF NOT EXISTS sectors (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                zone_id INT NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (zone_id) REFERENCES zones(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # sector_officers — multiple per sector
            cur.execute("""CREATE TABLE IF NOT EXISTS sector_officers (
                id INT AUTO_INCREMENT PRIMARY KEY,
                sector_id INT NOT NULL,
                user_id INT DEFAULT NULL,
                name VARCHAR(150) NOT NULL DEFAULT '',
                pno VARCHAR(50) DEFAULT '',
                mobile VARCHAR(15) DEFAULT '',
                user_rank VARCHAR(100) DEFAULT  '',
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id)   REFERENCES users(id)   ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # gram_panchayats
            cur.execute("""CREATE TABLE IF NOT EXISTS gram_panchayats (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(200) NOT NULL,
                address TEXT,
                sector_id INT NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # matdan_sthal
            cur.execute("""CREATE TABLE IF NOT EXISTS matdan_sthal (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(250) NOT NULL,
                address TEXT,
                gram_panchayat_id INT NOT NULL,
                thana VARCHAR(150) DEFAULT '',
                center_type ENUM('A','B','C') NOT NULL DEFAULT 'C',
                bus_no VARCHAR(50) DEFAULT '',
                latitude DECIMAL(10,7),
                longitude DECIMAL(10,7),
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (gram_panchayat_id) REFERENCES gram_panchayats(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # matdan_kendra
            cur.execute("""CREATE TABLE IF NOT EXISTS matdan_kendra (
                id INT AUTO_INCREMENT PRIMARY KEY,
                room_number VARCHAR(50) NOT NULL,
                matdan_sthal_id INT NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (matdan_sthal_id) REFERENCES matdan_sthal(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # duty_assignments
            cur.execute("""CREATE TABLE IF NOT EXISTS duty_assignments (
                id INT AUTO_INCREMENT PRIMARY KEY,
                staff_id INT NOT NULL,
                sthal_id INT NOT NULL,
                bus_no VARCHAR(50) DEFAULT '',
                assigned_by INT,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_staff_sthal (staff_id, sthal_id),
                FOREIGN KEY (staff_id)    REFERENCES users(id)        ON DELETE CASCADE,
                FOREIGN KEY (sthal_id)    REFERENCES matdan_sthal(id) ON DELETE CASCADE,
                FOREIGN KEY (assigned_by) REFERENCES users(id)        ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # system_logs
            cur.execute("""CREATE TABLE IF NOT EXISTS system_logs (
                id INT AUTO_INCREMENT PRIMARY KEY,
                level ENUM('INFO','WARN','ERROR') NOT NULL DEFAULT 'INFO',
                message TEXT NOT NULL,
                module VARCHAR(80) NOT NULL,
                time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            # app_config
            cur.execute("""CREATE TABLE IF NOT EXISTS app_config (
                `key` VARCHAR(100) PRIMARY KEY,
                value TEXT,
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")
            
            # FCM tocken Table
            cur.execute("""CREATE TABLE IF NOT EXISTS fcm_tokens (
                id INT AUTO_INCREMENT PRIMARY KEY,

                user_id INT NOT NULL,
                token TEXT NOT NULL,

                device_name VARCHAR(255) DEFAULT NULL,
                browser VARCHAR(100) DEFAULT NULL,
                os VARCHAR(100) DEFAULT NULL,

                user_agent TEXT,
                ip_address VARCHAR(45),

                is_active TINYINT(1) DEFAULT 1,

                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

                UNIQUE KEY unique_token (token(255)),

                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4""")

            for k, v in [
                ("maintenanceMode","false"),("allowStaffLogin","true"),
                ("forcePasswordReset","false"),("electionYear","2026"),
                ("state","Uttar Pradesh"),("phase","Phase 1"),
                ("electionDate","15 Apr 2026"),
            ]:
                cur.execute("INSERT INTO app_config (`key`,value) VALUES (%s,%s) ON DUPLICATE KEY UPDATE `key`=`key`", (k,v))

            # seed master
            cur.execute("SELECT id FROM users WHERE username='master'")
            if not cur.fetchone():
                cur.execute("INSERT INTO users (name,username,password,role,is_active) VALUES ('Master Admin','master',%s,'master',1)", (generate_password_hash("master"),))
                print("✅  Seeded master  (user:master / pass:master)")

            # seed super
            cur.execute("SELECT id FROM users WHERE username='super'")
            if not cur.fetchone():
                cur.execute("INSERT INTO users (name,username,password,role,is_active) VALUES ('Super Admin','super',%s,'super_admin',1)", (generate_password_hash("super"),))
                print("✅  Seeded super   (user:super  / pass:super)")

        conn.commit()
        print("✅  Database initialised")
    except Exception as e:
        conn.rollback(); print(f"❌  init_db error: {e}"); raise
    finally:
        conn.close()