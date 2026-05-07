const pino = require('pino');
const env = require('../config/env');

const transport = env.isDev
  ? { target: 'pino-pretty', options: { colorize: true, translateTime: 'SYS:HH:MM:ss' } }
  : undefined;

const logger = pino({
  level: env.LOG_LEVEL,
  base: { service: 'tezketkaz-api' },
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

module.exports = logger;
