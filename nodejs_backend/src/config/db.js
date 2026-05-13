'use strict';

const mysql = require('mysql2/promise');
const config = require('../config');
const crypto = require('crypto');

// ── Password Helpers ─────────────────────────────────────────────────────────
const SALT = config.passwordSalt;

function hashPassword(plain) {
  return crypto.createHash('sha256').update(plain + SALT).digest('hex');
}

function verifyPassword(plain, hashed) {
  return hashPassword(plain) === hashed;
}

// ── Connection Pool ──────────────────────────────────────────────────────────
let pool = null;

async function createDatabaseIfNotExists() {
  // Connect without specifying a database to create it if needed
  const conn = await mysql.createConnection({
    host: config.db.host,
    port: config.db.port,
    user: config.db.user,
    password: config.db.password,
    charset: 'utf8mb4',
    collation: 'utf8mb4_unicode_ci', // 🔥 ADD THIS
  });
  try {
    await conn.execute(
      `CREATE DATABASE IF NOT EXISTS \`${config.db.database}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`
    );
    console.log(`✅  Database '${config.db.database}' ready`);
  } finally {
    await conn.end();
  }
}

async function getPool() {
  if (pool) return pool;

  // Create DB if it doesn't exist
  await createDatabaseIfNotExists();

  pool = mysql.createPool({
    host: config.db.host,
    port: config.db.port,
    user: config.db.user,
    password: config.db.password,
    database: config.db.database,
    charset: 'utf8mb4',
    // Pool configuration
    connectionLimit: config.db.pool.max,
    queueLimit: config.db.pool.queueLimit,
    acquireTimeout: config.db.pool.acquireTimeout,
    waitForConnections: true,
    // Performance
    enableKeepAlive: true,
    keepAliveInitialDelay: 10000,
    // Return results as objects (like pymysql DictCursor)
    rowsAsArray: false,
    // Timezone
    timezone: '+00:00',
    // Date parsing
    dateStrings: false,
    typeCast: true,
    // Multistatement for migrations only; disabled here for security
    multipleStatements: false,
  });

  // Test connection
  try {
    const conn = await pool.getConnection();
    await conn.ping();
    conn.release();
    console.log(`✅  MySQL pool connected (max: ${config.db.pool.max} connections)`);
  } catch (err) {
    console.error('❌  MySQL pool connection failed:', err.message);
    throw err;
  }

  return pool;
}

// ── Query Helper — wraps pool.execute with error logging ────────────────────
async function query(sql, params = []) {
  const p = await getPool();
  const [rows] = await p.execute(sql, params);
  return rows;
}

// ── Transaction Helper ───────────────────────────────────────────────────────
async function withTransaction(fn) {
  const p = await getPool();
  const conn = await p.getConnection();
  await conn.beginTransaction();
  try {
    const result = await fn(conn);
    await conn.commit();
    return result;
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

// 🔥 ENSURE COLUMN (ADD THIS)
async function ensureColumn(conn, table, columnDef) {
  const colName = columnDef.split(' ')[0].replace(/`/g, '');

  const [rows] = await conn.execute(
    `SELECT COUNT(*) AS cnt
     FROM information_schema.columns
     WHERE table_schema = ? AND table_name = ? AND column_name = ?`,
    [config.db.database, table, colName]
  );

  if (rows[0].cnt === 0) {
    await conn.execute(`ALTER TABLE \`${table}\` ADD COLUMN ${columnDef}`);
    console.log(`✅ Column added: ${table}.${colName}`);
  }
}

// ── Init DB — creates all tables ─────────────────────────────────────────────
async function initDb() {
  // Use a separate connection for multi-statement DDL
  await createDatabaseIfNotExists();

  const conn = await mysql.createConnection({
    host: config.db.host,
    port: config.db.port,
    user: config.db.user,
    password: config.db.password,
    database: config.db.database,
    charset: 'utf8mb4',
    multipleStatements: true,
  });

  try {
    await conn.execute('SET SESSION foreign_key_checks = 0');
    await conn.execute('SET SESSION unique_checks = 0');

    // ── users ─────────────────────────────────────────────────────────────────
    await conn.execute(`
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
        is_active   TINYINT(1)    NOT NULL DEFAULT 1,
        is_armed    TINYINT(1)    NOT NULL DEFAULT 0,
        created_by  INT           DEFAULT NULL,
        assigned_by INT           DEFAULT NULL,
        super_admin_id INT        DEFAULT NULL,
        created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_username  (username),
        UNIQUE KEY uq_pno       (pno),
        INDEX idx_role_district (role, district),
        INDEX idx_role_active   (role, is_active),
        INDEX idx_name          (name),
        INDEX idx_thana         (thana),
        INDEX idx_user_rank     (user_rank),
        INDEX idx_role_rank     (role, user_rank, is_active)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    // ── app_config ────────────────────────────────────────────────────────────
    await conn.execute(`
      CREATE TABLE IF NOT EXISTS app_config (
        \`key\`    VARCHAR(100) PRIMARY KEY,
        value      TEXT,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    // ── super_zones ───────────────────────────────────────────────────────────
    await conn.execute(`
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
    `);

    // ── kshetra_officers ──────────────────────────────────────────────────────
    await conn.execute(`
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
    `);

    // ── zones ─────────────────────────────────────────────────────────────────
    await conn.execute(`
      CREATE TABLE IF NOT EXISTS zones (
        id            INT AUTO_INCREMENT PRIMARY KEY,
        name          VARCHAR(100) NOT NULL,
        hq_address    TEXT,
        super_zone_id INT NOT NULL,
        created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_super_zone_id (super_zone_id),
        FOREIGN KEY (super_zone_id) REFERENCES super_zones(id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    // ── zonal_officers ────────────────────────────────────────────────────────
    await conn.execute(`
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
    `);

    // ── sectors ───────────────────────────────────────────────────────────────
    await conn.execute(`
      CREATE TABLE IF NOT EXISTS sectors (
        id         INT AUTO_INCREMENT PRIMARY KEY,
        name       VARCHAR(100) NOT NULL,
        zone_id    INT NOT NULL,
        created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        hq_address TEXT ,
        INDEX idx_zone_id (zone_id),
        FOREIGN KEY (zone_id) REFERENCES zones(id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    // ── sector_officers ───────────────────────────────────────────────────────
    await conn.execute(`
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
    `);

    // ── gram_panchayats ───────────────────────────────────────────────────────
    await conn.execute(`
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
    `);

    // ── matdan_sthal (election centers) ──────────────────────────────────────
    await conn.execute(`
      CREATE TABLE IF NOT EXISTS matdan_sthal (
        id                INT AUTO_INCREMENT PRIMARY KEY,
        name              VARCHAR(250) NOT NULL,
        address           TEXT,
        gram_panchayat_id INT          NOT NULL,
        thana             VARCHAR(150) DEFAULT '',
        center_type       ENUM('A++','A','B','C') NOT NULL DEFAULT 'C',
        bus_no            VARCHAR(50)  DEFAULT '',
        latitude          DECIMAL(10,7),
        longitude         DECIMAL(10,7),
        created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        booth_count INT NOT NULL DEFAULT 1,
        INDEX idx_gp_id       (gram_panchayat_id),
        INDEX idx_thana       (thana),
        INDEX idx_name        (name),
        INDEX idx_center_type (center_type),
        FOREIGN KEY (gram_panchayat_id) REFERENCES gram_panchayats(id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    // ── matdan_kendra (rooms) ─────────────────────────────────────────────────
    await conn.execute(`
      CREATE TABLE IF NOT EXISTS matdan_kendra (
        id              INT AUTO_INCREMENT PRIMARY KEY,
        room_number     VARCHAR(50) NOT NULL,
        matdan_sthal_id INT         NOT NULL,
        created_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_sthal_id (matdan_sthal_id),
        FOREIGN KEY (matdan_sthal_id) REFERENCES matdan_sthal(id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    // ── duty_assignments ──────────────────────────────────────────────────────
    await conn.execute(`
      CREATE TABLE IF NOT EXISTS duty_assignments (
        id          INT AUTO_INCREMENT PRIMARY KEY,
        staff_id    INT         NOT NULL,
        sthal_id    INT         NOT NULL,
        bus_no      VARCHAR(50) DEFAULT '',
        assigned_by INT         DEFAULT NULL,
        created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        election_date DATE DEFAULT NULL,
        attended    TINYINT(1) NOT NULL DEFAULT 0,
        mode        TEXT NULL, 
        card_downloaded TINYINT(1) NOT NULL DEFAULT 0,
        UNIQUE KEY uq_staff_sthal (staff_id, sthal_id),
        INDEX idx_sthal_id    (sthal_id),
        INDEX idx_assigned_by (assigned_by),
        FOREIGN KEY (staff_id)    REFERENCES users(id)        ON DELETE CASCADE,
        FOREIGN KEY (sthal_id)    REFERENCES matdan_sthal(id) ON DELETE CASCADE,
        FOREIGN KEY (assigned_by) REFERENCES users(id)        ON DELETE SET NULL
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    // ── system_logs ───────────────────────────────────────────────────────────
    await conn.execute(`
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
    `);

    // ── fcm_tokens ────────────────────────────────────────────────────────────
    await conn.execute(`
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
    `);

    // ── goswara_nyay_panchayat ─────────────────────────────────────────────────────
    await conn.execute(`
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
    `);

    // 🔥 ADD THESE TABLES AFTER app_config

    // ── election_configs ─────────────────────────────────────────
    await conn.execute(`
CREATE TABLE IF NOT EXISTS election_configs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  district VARCHAR(100) NOT NULL,
  state VARCHAR(100) NOT NULL DEFAULT '',
  election_type VARCHAR(100) NOT NULL DEFAULT '',
  election_name VARCHAR(200) NOT NULL DEFAULT '',
  phase VARCHAR(50) NOT NULL DEFAULT '',
  election_year VARCHAR(10) NOT NULL DEFAULT '',
  election_date DATE DEFAULT NULL,
  pratah_samay VARCHAR(20) DEFAULT '',
  saya_samay VARCHAR(20) DEFAULT '',
  instructions TEXT,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  is_archived TINYINT(1) NOT NULL DEFAULT 0,
  archived_at DATETIME DEFAULT NULL,
  created_by INT DEFAULT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_district (district),
  INDEX idx_district_active (district, is_active),
  INDEX idx_archived (is_archived),
  INDEX idx_election_date (election_date),
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
`);

    // ── api_request_logs ─────────────────────────────────────────
    await conn.execute(`
CREATE TABLE IF NOT EXISTS api_request_logs (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  method VARCHAR(10) NOT NULL,
  path VARCHAR(500) NOT NULL,
  status_code INT NOT NULL DEFAULT 0,
  duration_ms INT NOT NULL DEFAULT 0,
  user_id INT DEFAULT NULL,
  username VARCHAR(100) DEFAULT NULL,
  role VARCHAR(30) DEFAULT NULL,
  ip_address VARCHAR(45) DEFAULT NULL,
  user_agent VARCHAR(500) DEFAULT NULL,
  request_body TEXT,
  error_message TEXT,
  level ENUM('INFO','WARN','ERROR') NOT NULL DEFAULT 'INFO',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  INDEX idx_created_at (created_at),
  INDEX idx_status_code (status_code),
  INDEX idx_path (path(100)),
  INDEX idx_user_id (user_id),
  INDEX idx_role (role),
  INDEX idx_level (level)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
`);

    // ── token_revocations ─────────────────────────────────────────
    await conn.execute(`
CREATE TABLE IF NOT EXISTS token_revocations (
  id INT AUTO_INCREMENT PRIMARY KEY,
  role VARCHAR(30) NOT NULL,
  revoke_before BIGINT NOT NULL,
  revoked_by INT DEFAULT NULL,
  reason VARCHAR(255) DEFAULT '',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_role (role),
  INDEX idx_revoke_before (revoke_before)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
`);

    // ── booth_rules (IMPORTANT replace booth_staff_rules) ────────
    await conn.execute(`
CREATE TABLE IF NOT EXISTS booth_rules (
  id INT AUTO_INCREMENT PRIMARY KEY,
  admin_id INT NOT NULL,
  sensitivity ENUM('A++','A','B','C') NOT NULL,
  booth_count INT NOT NULL,

  si_armed_count INT NOT NULL DEFAULT 0,
  si_unarmed_count INT NOT NULL DEFAULT 0,
  hc_armed_count INT NOT NULL DEFAULT 0,
  hc_unarmed_count INT NOT NULL DEFAULT 0,
  const_armed_count INT NOT NULL DEFAULT 0,
  const_unarmed_count INT NOT NULL DEFAULT 0,

  aux_armed_count INT NOT NULL DEFAULT 0,
  aux_unarmed_count INT NOT NULL DEFAULT 0,
  pac_count DECIMAL(4,1) NOT NULL DEFAULT 0,

  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_admin_sens_booth (admin_id, sensitivity, booth_count),
  INDEX idx_admin_sens (admin_id, sensitivity),
  FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
`);

    // ── district_rules ─────────────────────────────────────────
    await conn.execute(`
CREATE TABLE IF NOT EXISTS district_rules (
  id INT AUTO_INCREMENT PRIMARY KEY,
  admin_id INT NOT NULL,
  duty_type VARCHAR(80) NOT NULL,
  duty_label_hi VARCHAR(150) DEFAULT '',
  sankhya INT DEFAULT 0,

  si_armed_count INT DEFAULT 0,
  si_unarmed_count INT DEFAULT 0,
  hc_armed_count INT DEFAULT 0,
  hc_unarmed_count INT DEFAULT 0,
  const_armed_count INT DEFAULT 0,
  const_unarmed_count INT DEFAULT 0,

  aux_armed_count INT DEFAULT 0,
  aux_unarmed_count INT DEFAULT 0,
  pac_count DECIMAL(4,1) DEFAULT 0,
  sort_order INT DEFAULT 0,

  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_admin_duty (admin_id, duty_type),
  INDEX idx_admin (admin_id),
  FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
`);

    // ── sz_duty_locks ─────────────────────────────────────────
    await conn.execute(`
CREATE TABLE IF NOT EXISTS sz_duty_locks (
  id INT AUTO_INCREMENT PRIMARY KEY,
  super_zone_id INT UNIQUE,
  is_locked TINYINT(1) DEFAULT 0,
  status ENUM('locked','unlock_requested','unlocked') DEFAULT 'unlocked',
  unlock_reason TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
`);

    // ── sz_assign_jobs ─────────────────────────────────────────
    await conn.execute(`
CREATE TABLE IF NOT EXISTS sz_assign_jobs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  super_zone_id INT,
  status ENUM('pending','running','done','error') DEFAULT 'pending',
  total_centers INT DEFAULT 0,
  done_centers INT DEFAULT 0,
  error_msg TEXT,
  created_by INT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
`);

    // ── sz_unlock_requests ─────────────────────────────────────
    await conn.execute(`
CREATE TABLE IF NOT EXISTS sz_unlock_requests (
  id INT AUTO_INCREMENT PRIMARY KEY,
  super_zone_id INT,
  requested_by INT,
  reason TEXT,
  status ENUM('pending','approved','rejected') DEFAULT 'pending',
  reviewed_by INT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
`);

    // ── district_duty_assignments ─────────────────────────────
    await conn.execute(`
CREATE TABLE IF NOT EXISTS district_duty_assignments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  admin_id INT NOT NULL,
  duty_type VARCHAR(80) NOT NULL,
  batch_no INT DEFAULT 1,
  staff_id INT NOT NULL,
  assigned_by INT DEFAULT NULL,
  bus_no VARCHAR(50) DEFAULT '',
  note TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_staff_duty (staff_id, duty_type),
  INDEX idx_duty_type (duty_type),
  INDEX idx_admin_id (admin_id),
  INDEX idx_batch (admin_id, duty_type, batch_no),
  FOREIGN KEY (staff_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL,
  FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
`);

    // ── district_duty_jobs ────────────────────────────────────
    await conn.execute(`
CREATE TABLE IF NOT EXISTS district_duty_jobs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  admin_id INT NOT NULL,
  status ENUM('pending','running','done','error') DEFAULT 'pending',
  total_types INT DEFAULT 0,
  done_types INT DEFAULT 0,
  assigned INT DEFAULT 0,
  skipped INT DEFAULT 0,
  error_msg TEXT,
  created_by INT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_admin (admin_id),
  FOREIGN KEY (admin_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
`);


    await conn.execute('SET SESSION foreign_key_checks = 1');
    await conn.execute('SET SESSION unique_checks = 1');


    // 🔥 AUTO ADD MISSING COLUMNS (same as Python)
    await ensureColumn(conn, 'users', "pno VARCHAR(50) DEFAULT NULL");
    await ensureColumn(conn, 'users', "user_rank VARCHAR(100) DEFAULT ''");
    await ensureColumn(conn, 'users', "district VARCHAR(100) DEFAULT ''");
    await ensureColumn(conn, 'users', "thana VARCHAR(100) DEFAULT ''");
    await ensureColumn(conn, 'users', "mobile VARCHAR(15) DEFAULT ''");
    await ensureColumn(conn, 'users', "assigned_by INT DEFAULT NULL");
    await ensureColumn(conn, 'users', "super_admin_id INT DEFAULT NULL");
    await ensureColumn(conn, 'users', "created_by INT DEFAULT NULL");
    await ensureColumn(conn, 'users', "is_active TINYINT(1) NOT NULL DEFAULT 1");
    await ensureColumn(conn, 'users', "is_armed TINYINT(1) NOT NULL DEFAULT 0");

    await ensureColumn(conn, 'sectors', "hq_address TEXT");


    await ensureColumn(conn, 'matdan_sthal', "booth_count INT NOT NULL DEFAULT 1");
    await ensureColumn(conn, 'matdan_sthal', "latitude DECIMAL(10,7) DEFAULT NULL");
    await ensureColumn(conn, 'matdan_sthal', "longitude DECIMAL(10,7) DEFAULT NULL");
    await ensureColumn(conn, 'matdan_sthal', "bus_no VARCHAR(50) DEFAULT ''");
    await ensureColumn(conn, 'matdan_sthal', "thana VARCHAR(150) DEFAULT ''");
    await ensureColumn(conn, 'matdan_sthal', "center_type ENUM('A++','A','B','C') NOT NULL DEFAULT 'C'");

    await ensureColumn(conn, 'duty_assignments', "bus_no VARCHAR(50) DEFAULT ''");
    await ensureColumn(conn, 'duty_assignments', "election_date DATE DEFAULT NULL");
    await ensureColumn(conn, 'duty_assignments', "attended    TINYINT(1) NOT NULL DEFAULT 0");
    await ensureColumn(conn, 'duty_assignments', "card_downloaded TINYINT(1) NOT NULL DEFAULT 0");
    await ensureColumn(conn, 'duty_assignments', "mode TEXT NULL");


    await ensureColumn(conn, 'kshetra_officers', "user_rank VARCHAR(100) DEFAULT ''");
    await ensureColumn(conn, 'zonal_officers', "user_rank VARCHAR(100) DEFAULT ''");
    await ensureColumn(conn, 'sector_officers', "user_rank VARCHAR(100) DEFAULT ''");

    // ── Seed: master user ─────────────────────────────────────────────────────
    const [rows] = await conn.execute("SELECT id FROM users WHERE username='master'");
    if (!rows.length) {
      await conn.execute(
        "INSERT INTO users (name, username, password, role, is_active) VALUES ('Master Admin', 'master', ?, 'master', 1)",
        [hashPassword('master')]
      );
      console.log("✅  Seeded master account (username: master / password: master)");
      console.log("⚠️  IMPORTANT: Change the master password immediately after first login!");
    }

    console.log('✅  Database initialised successfully');
  } catch (err) {
    console.error('❌  initDb error:', err.message);
    throw err;
  } finally {
    await conn.end();
  }
}

// 🔥 MIGRATIONS (ADD THIS)
async function runMigrations() {
  const conn = await getPool();

  const migrations = [
    ["users", "idx_role_district", "(role, district)"],
    ["users", "idx_role_active", "(role, is_active)"],
    ["users", "idx_name", "(name)"],
    ["users", "idx_thana", "(thana)"],
    ["matdan_sthal", "idx_gp_id", "(gram_panchayat_id)"],
    ["matdan_sthal", "idx_thana", "(thana)"],
  ];

  for (const [table, indexName, cols] of migrations) {
    const [rows] = await conn.execute(
      `SELECT COUNT(*) AS cnt FROM information_schema.statistics 
       WHERE table_schema=? AND table_name=? AND index_name=?`,
      [config.db.database, table, indexName]
    );

    if (!rows[0].cnt) {
      await conn.execute(
        `ALTER TABLE \`${table}\` ADD INDEX \`${indexName}\` ${cols}`
      );
      console.log(`✅ Index added: ${table}.${indexName}`);
    }
  }
}

// ── Write Log (fire-and-forget) ───────────────────────────────────────────────
async function writeLog(level, message, module) {
  try {
    const p = await getPool();
    await p.execute(
      'INSERT INTO system_logs (level, message, module) VALUES (?, ?, ?)',
      [level, message, module]
    );
  } catch {
    // Never crash the app over logging
  }
}

module.exports = { getPool, query, withTransaction, initDb, runMigrations, writeLog, hashPassword, verifyPassword };
