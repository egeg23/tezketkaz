const pino = require('pino');
const env = require('../config/env');

const transport = env.isDev
  ? { target: 'pino-pretty', options: { colorize: true, translateTime: 'SYS:HH:MM:ss' } }
  : undefined;

const logger = pino({
  level: env.LOG_LEVEL,
  base: { service: 'tezketkaz-api' },
  serializers: {
    err: pino.stdSerializers.err,
    req: pino.stdSerializers.req,
    res: pino.stdSerializers.res,
  },
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      '*.password',
      '*.token',
      '*.JWT_SECRET',
      '*.SECRET_KEY',
      '*.PAYME_KEY',
    ],
    remove: true,
  },
  transport,
});

// Convenience: build a child logger bound to a request. Routes can do
//   const log = logger.forRequest(req); log.info({ extra }, 'event');
// or rely on req.log (set by pino-http) which already carries req.id.
logger.forRequest = function forRequest(req) {
  return logger.child({
    requestId: req?.id || req?.headers?.['x-request-id'] || undefined,
    userId: req?.user?.id || undefined,
  });
};

module.exports = logger;
