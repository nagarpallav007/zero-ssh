import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const EnvSchema = z.object({
  PORT: z.coerce.number().int().positive().default(4000),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 chars'),
  ALLOWED_ORIGINS: z.string().optional(), // comma-separated
  RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().optional(),
  RATE_LIMIT_MAX: z.coerce.number().int().positive().optional(),
});

const parsed = EnvSchema.safeParse(process.env);
if (!parsed.success) {
  console.error('Environment validation failed', parsed.error.format());
  process.exit(1);
}

const env = parsed.data;

export const config = {
  port: env.PORT,
  databaseUrl: env.DATABASE_URL,
  jwtSecret: env.JWT_SECRET,
  allowedOrigins: env.ALLOWED_ORIGINS
    ? env.ALLOWED_ORIGINS.split(',').map((o) => o.trim()).filter(Boolean)
    : [],
  rateLimit: {
    windowMs: env.RATE_LIMIT_WINDOW_MS ?? 15 * 60 * 1000,
    max: env.RATE_LIMIT_MAX ?? 300,
  },
};
