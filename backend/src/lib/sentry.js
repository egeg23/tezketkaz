// Lazy Sentry initialiser. Importing this module never throws — if @sentry/node
// is not installed or SENTRY_DSN is not set, we return a fully-shaped shim so
// callers can `app.use(sentry.requestHandler)` etc. unconditionally.
//
// Usage:
//   const sentry = require('./lib/sentry')(app, server);
//   app.use(sentry.requestHandler);
//   ... routes ...
//   app.use(sentry.errorHandler);

const env = require('../config/env');
const logger = require('./logger');

function noopMiddleware(req, res, next) { next(); }
// eslint-disable-next-line no-unused-vars
function noopErrorMiddleware(err, req, res, next) { next(err); }

function shim() {
  return {
    requestHandler: noopMiddleware,
    tracingHandler: noopMiddleware,
    errorHandler: noopErrorMiddleware,
    captureException: () => {},
    captureMessage: () => {},
    enabled: false,
  };
}

function init(app /* , server */) {
  if (!env.SENTRY_DSN) return shim();

  let Sentry;
  try {
    // eslint-disable-next-line global-require
    Sentry = require('@sentry/node');
  } catch (err) {
    logger.warn({ err: err.message }, 'SENTRY_DSN set but @sentry/node not installed; using shim');
    return shim();
  }

  try {
    Sentry.init({
      dsn: env.SENTRY_DSN,
      environment: env.NODE_ENV || 'development',
      release: process.env.GIT_COMMIT || 'dev',
      tracesSampleRate: 0.1,
      profilesSampleRate: 0,
    });
  } catch (err) {
    logger.error({ err }, 'Sentry.init failed; falling back to shim');
    return shim();
  }

  // Sentry v8 dropped Handlers.* in favour of expressIntegration() + automatic
  // request scoping. Provide a small adapter so call sites stay stable.
  let requestHandler = noopMiddleware;
  let tracingHandler = noopMiddleware;
  let errorHandler = noopErrorMiddleware;

  try {
    if (Sentry.Handlers && typeof Sentry.Handlers.requestHandler === 'function') {
      // v7 style (still works if user pins older version)
      requestHandler = Sentry.Handlers.requestHandler();
      tracingHandler = Sentry.Handlers.tracingHandler ? Sentry.Handlers.tracingHandler() : noopMiddleware;
      errorHandler = Sentry.Handlers.errorHandler();
    } else if (typeof Sentry.expressErrorHandler === 'function') {
      // v8 style
      errorHandler = Sentry.expressErrorHandler();
      if (typeof Sentry.setupExpressErrorHandler === 'function' && app) {
        // setupExpressErrorHandler attaches the error middleware itself; we
        // still expose a no-op so caller's app.use(sentry.errorHandler) is safe.
        try { Sentry.setupExpressErrorHandler(app); errorHandler = noopErrorMiddleware; } catch { /* ignore */ }
      }
    }
  } catch (err) {
    logger.warn({ err: err.message }, 'Sentry middleware adapter failed');
  }

  return {
    requestHandler,
    tracingHandler,
    errorHandler,
    captureException: (e, ctx) => {
      try { Sentry.captureException(e, ctx); } catch { /* noop */ }
    },
    captureMessage: (m, ctx) => {
      try { Sentry.captureMessage(m, ctx); } catch { /* noop */ }
    },
    enabled: true,
  };
}

module.exports = init;
module.exports.shim = shim;
