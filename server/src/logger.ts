import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: process.env.NODE_ENV === 'production' ? undefined : { target: 'pino-pretty' },
  redact: ['req.headers.authorization', 'password', 'token', 'privateKey', 'passwordEncrypted'],
});
