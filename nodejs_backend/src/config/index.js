'use strict';

require('dotenv').config();

const config = {
  app: {
    env: process.env.NODE_ENV || 'development',
    port: parseInt(process.env.PORT, 10) || 5000,
    host: process.env.HOST || '0.0.0.0',
    baseUrl: process.env.BASE_URL || 'http://localhost:5000',
    isDev: (process.env.NODE_ENV || 'development') === 'development',
    isProd: process.env.NODE_ENV === 'production',
  },

  db: {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT, 10) || 3306,
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASS || '',
    database: process.env.DB_NAME || 'election_db',
    pool: {
      min: parseInt(process.env.DB_POOL_MIN, 10) || 5,
      max: parseInt(process.env.DB_POOL_MAX, 10) || 50,
      queueLimit: parseInt(process.env.DB_QUEUE_LIMIT, 10) || 0,
      acquireTimeout: parseInt(process.env.DB_ACQUIRE_TIMEOUT, 10) || 30000,
    },
  },

  jwt: {
    secret: process.env.JWT_SECRET || 'fallback_secret_change_in_production',
    expiry: parseInt(process.env.JWT_EXPIRY, 10) || 36000, // seconds
  },

  rateLimit: {
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS, 10) || 15 * 60 * 1000,
    max: parseInt(process.env.RATE_LIMIT_MAX, 10) || 500,
    loginWindowMs: parseInt(process.env.LOGIN_RATE_LIMIT_WINDOW_MS, 10) || 60 * 1000,
    loginMax: parseInt(process.env.LOGIN_RATE_LIMIT_MAX, 10) || 20,
  },

  cors: {
    origins: (process.env.CORS_ORIGINS || 'http://localhost:5173')
      .split(',')
      .map(o => o.trim())
      .filter(Boolean),
  },

  firebase: {
    serviceAccountPath: process.env.FIREBASE_SERVICE_ACCOUNT_PATH || './serviceAccountKey.json',
  },

  backup: {
    mysqldumpPath: process.env.MYSQLDUMP_PATH || 'mysqldump',
    backupDir: process.env.BACKUP_DIR || './backups',
  },

  // Password hashing
  passwordSalt: 'election_2026_secure_key',
};

// Warn on insecure defaults in production
if (config.app.isProd) {
  if (config.jwt.secret === 'fallback_secret_change_in_production') {
    console.warn('⚠️  WARNING: Using default JWT secret in production! Set JWT_SECRET env var.');
  }
}

module.exports = config;
