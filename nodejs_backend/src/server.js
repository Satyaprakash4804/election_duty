'use strict';

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const cookieParser = require('cookie-parser');
const rateLimit = require('express-rate-limit');
const config = require('./config');
const { initDb, runMigrations } = require('./config/db');
const { notFound, errorHandler } = require('./middleware/errorHandler');

// ── Route modules ─────────────────────────────────────────────────────────────
const authRoutes = require('./routes/auth');
const masterRoutes = require('./routes/master');
const superAdminRoutes = require('./routes/superAdmin');
const adminRoutes = require('./routes/admin');
const staffRoutes = require('./routes/staff');
const hierarchyRoutes = require('./routes/hierarchy');
const fcmRoutes = require('./routes/fcm');

const app = express();

// ── Trust proxy (for correct IP behind nginx/load balancer) ───────────────────
app.set('trust proxy', 1);

// ── Security headers ──────────────────────────────────────────────────────────
app.use(helmet({
  crossOriginResourcePolicy: { policy: 'cross-origin' },
  contentSecurityPolicy: false, // Disable CSP for API server
}));

// ── CORS ──────────────────────────────────────────────────────────────────────
app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, curl, etc.)
    if (!origin) return callback(null, true);
    if (config.cors.origins.includes(origin) || config.cors.origins.includes('*')) {
      return callback(null, true);
    }
    callback(new Error(`CORS: origin '${origin}' not allowed`));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: '*',
  exposedHeaders: ['Content-Length', 'X-Request-Id'],
  maxAge: 86400, // 24h preflight cache
}));

// ── Compression (gzip) ────────────────────────────────────────────────────────
app.use(compression({ level: 6, threshold: 1024 }));

// ── Request logging ───────────────────────────────────────────────────────────
if (config.app.isProd) {
  app.use(morgan('dev'));
} else {
  app.use(morgan('combined', {
    skip: (req) => req.path === '/ping' || req.path === '/health',
  }));
}

// ── Body parsing ──────────────────────────────────────────────────────────────
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(cookieParser());

// ── Global rate limiter ───────────────────────────────────────────────────────
const globalLimiter = rateLimit({
  windowMs: config.rateLimit.windowMs,
  max: config.rateLimit.max,
  standardHeaders: true,
  legacyHeaders: false,
  message: { status: 'error', message: 'Too many requests, please try again later.' },
  skip: (req) => req.path === '/ping' || req.path === '/health',
});
app.use(globalLimiter);

// ── Login rate limiter (tighter) ─────────────────────────────────────────────
const loginLimiter = rateLimit({
  windowMs: config.rateLimit.loginWindowMs,
  max: config.rateLimit.loginMax,
  standardHeaders: true,
  legacyHeaders: false,
  message: { status: 'error', message: 'Too many login attempts. Please wait a minute.' },
});

// ── Health check (no auth, no rate limit) ─────────────────────────────────────
app.get('/ping', (req, res) => res.json({ status: 'ok', message: 'Election API running', ts: new Date().toISOString() }));
app.get('/health', (req, res) => res.json({ status: 'ok', uptime: process.uptime(), memory: process.memoryUsage() }));

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/api/auth', loginLimiter, authRoutes);          // /api/login, /api/logout, /api/me
app.use('/api/master', masterRoutes);                       // /api/master/…
app.use('/api/super', superAdminRoutes);                   // /api/super/…
app.use('/api/admin', adminRoutes);                        // /api/admin/…
app.use('/api/admin/hierarchy', hierarchyRoutes);                // /api/admin/hierarchy/…
app.use('/api/staff', staffRoutes);                        // /api/staff/…
app.use('/', fcmRoutes);                          // /save-token, /send-notification

// ── 404 & error handlers ──────────────────────────────────────────────────────
app.use(notFound);
app.use(errorHandler);

// ── Start server ──────────────────────────────────────────────────────────────
async function start() {
  try {
    console.log('🚀 Election API — Node.js/Express');
    console.log(`   Environment: ${config.app.env}`);

    // Initialise database (create tables, seed master account)
    await initDb();
    await runMigrations();

    const server = app.listen(config.app.port, config.app.host, () => {
      console.log(`✅ Server listening on http://${config.app.host}:${config.app.port}`);
    });

    // Graceful shutdown
    const shutdown = async (signal) => {
      console.log(`\n${signal} received — shutting down gracefully...`);
      server.close(async () => {
        try {
          const { getPool } = require('./config/db');
          const pool = await getPool();
          await pool.end();
          console.log('✅ MySQL pool closed');
        } catch { }
        console.log('✅ Server closed');
        process.exit(0);
      });
      // Force exit after 10s
      setTimeout(() => { console.error('⚠️  Forced exit'); process.exit(1); }, 10000);
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));

    // Unhandled rejection safety net
    process.on('unhandledRejection', (reason, promise) => {
      console.error('Unhandled Rejection at:', promise, 'reason:', reason);
    });
    process.on('uncaughtException', (err) => {
      console.error('Uncaught Exception:', err);
      shutdown('uncaughtException');
    });

  } catch (err) {
    console.error('❌ Failed to start server:', err);
    process.exit(1);
  }
}

start();

module.exports = app; // for testing
