import pymysql

def init_db():
    connection = pymysql.connect(
        host="localhost",
        user="root",
        password="Mysql@123",
        cursorclass=pymysql.cursors.DictCursor
    )

    try:
        with connection.cursor() as cursor:

            # =========================
            # CREATE DATABASE
            # =========================
            cursor.execute("CREATE DATABASE IF NOT EXISTS election_db")
            cursor.execute("USE election_db")

            # =========================
            # TABLES
            # =========================

            # =========================
            # SUPER ZONES
            # =========================
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS super_zones (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(100),
                district VARCHAR(100)
            )
            """)

            # =========================
            # ZONES
            # =========================
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS zones (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(100),
                address TEXT,
                officer_name varchar(100),
                officer_mobile VARCHAR(15) UNIQUE,
                super_zone_id INT,
                FOREIGN KEY (super_zone_id) REFERENCES super_zones(id) ON DELETE CASCADE
                
            )
            """)

            # =========================
            # SECTORS
            # =========================
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS sectors (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(100),
                address TEXT,
                officer_name varchar(100),
                officer_mobile VARCHAR(15) UNIQUE,
                zone_id INT,
                FOREIGN KEY (zone_id) REFERENCES zones(id) ON DELETE CASCADE
                
            )
            """)

            # =========================
            # PANCHAYATS
            # =========================
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS gram_panchayats (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(150),
                address TEXT,
                sector_id INT,
                FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE CASCADE
            )
            """)

            # =========================
            # MATDAN STHAL
            # =========================
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS matdan_sthal (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(200),
                address TEXT,
                gram_panchayat_id INT,
                thana VARCHAR(100),
                center_type VARCHAR(100),
                bus_no VARCHAR(50),
                FOREIGN KEY (gram_panchayat_id) REFERENCES gram_panchayats(id) ON DELETE CASCADE
            )
            """)

            # =========================
            # MATDAN KENDRA
            # =========================
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS matdan_kendra (
                id INT AUTO_INCREMENT PRIMARY KEY,
                room_number VARCHAR(50),
                matdan_sthal_id INT,
                FOREIGN KEY (matdan_sthal_id) REFERENCES matdan_sthal(id) ON DELETE CASCADE
            )
            """)

            # =========================
            # USERS (VERY IMPORTANT)
            # =========================
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(150),
                mobile VARCHAR(15) UNIQUE,
                password VARCHAR(255),
                role ENUM('super_admin', 'admin', 'user') DEFAULT 'user',
                kendra_id INT,
                district VARCHAR(100),
                created_by INT,
                assigned_by INT,

                FOREIGN KEY (kendra_id) REFERENCES matdan_kendra(id) ON DELETE SET NULL,
                FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
                FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL
            )
            """)
        connection.commit()
        print("✅ DB Checked/Created")

    finally:
        connection.close()