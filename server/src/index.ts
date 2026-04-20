import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { rateLimit } from 'express-rate-limit';
import { config } from './config';
import authRoutes from './routes/auth';
import userRoutes from './routes/users';
import workspaceRoutes from './routes/workspaces';
import { logger } from './logger';

const app = express();

app.use(helmet());
app.use(
  cors({
    origin: (origin, callback) => {
      if (!origin) return callback(null, true); // allow curl/CLI
      if (config.allowedOrigins.length === 0) {
        return callback(new Error('CORS not allowed'), false);
      }
      if (config.allowedOrigins.includes(origin)) {
        return callback(null, true);
      }
      return callback(new Error('CORS origin denied'), false);
    },
    credentials: false,
  })
);
app.use(express.json({ limit: '256kb' }));

const globalLimiter = rateLimit({
  windowMs: config.rateLimit.windowMs,
  max: config.rateLimit.max,
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(globalLimiter);

app.get('/health', (_req, res) => res.json({ status: 'ok' }));
app.use('/auth', authRoutes);
app.use('/users', userRoutes);
app.use('/workspaces', workspaceRoutes);

const start = async () => {
  try {
    app.listen(config.port, () => {
      logger.info({ port: config.port }, 'ZeroSSH server listening');
    });
  } catch (err) {
    logger.error({ err }, 'Failed to start server');
    process.exit(1);
  }
};

start();
