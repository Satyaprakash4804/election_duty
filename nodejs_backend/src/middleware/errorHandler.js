'use strict';

const config = require('../config');

// ── 404 handler ──────────────────────────────────────────────────────────────
function notFound(req, res) {
  res.status(404).json({ status: 'error', message: `Route ${req.method} ${req.path} not found` });
}

// ── Global error handler ─────────────────────────────────────────────────────
function errorHandler(err, req, res, next) { // eslint-disable-line no-unused-vars
  const status = err.status || err.statusCode || 500;
  const message = config.app.isProd && status === 500
    ? 'Internal server error'
    : err.message || 'Internal server error';

  if (status >= 500) {
    console.error(`[${new Date().toISOString()}] ERROR ${status} ${req.method} ${req.path}:`, err);
  }

  res.status(status).json({
    status: 'error',
    message,
    ...(config.app.isDev && status >= 500 && { stack: err.stack }),
  });
}

module.exports = { notFound, errorHandler };
