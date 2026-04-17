import crypto from 'crypto';
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { Prisma } from '@prisma/client';
import { prisma } from '../prisma';
import { config } from '../config';
import { loginSchema, signupSchema } from '../validation';
import { rateLimit } from 'express-rate-limit';
import { logger } from '../logger';

const router = Router();

const signToken = (id: string, email: string, emailVerified: boolean, provider: string) =>
  jwt.sign({ email, emailVerified, provider }, config.jwtSecret, { subject: id, expiresIn: '1h' });

/** Cryptographically random 32-byte salt encoded as base64 (unique per user, never changes). */
const generateUserSalt = () => crypto.randomBytes(32).toString('base64');

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
});
router.use(authLimiter);

router.post('/signup', async (req, res) => {
  const parsed = signupSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }
  const { email, password } = parsed.data;

  try {
    const passwordHash = await bcrypt.hash(password, 10);
    const user = await prisma.user.create({
      data: {
        email: email.toLowerCase(),
        passwordHash,
        salt: generateUserSalt(),
        provider: 'password',
      },
      select: {
        id: true,
        email: true,
        salt: true,
        emailVerified: true,
        emailVerifiedAt: true,
        provider: true,
        providerId: true,
      },
    });

    const token = signToken(user.id, user.email, user.emailVerified, user.provider);
    return res.status(201).json({
      token,
      userSalt: user.salt,
      user: {
        id: user.id,
        email: user.email,
        emailVerified: user.emailVerified,
        emailVerifiedAt: user.emailVerifiedAt,
        provider: user.provider,
        providerId: user.providerId,
      },
    });
  } catch (err: any) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
      return res.status(409).json({ error: 'Email already registered' });
    }
    logger.error({ err }, 'Signup error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/login', async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }
  const { email, password } = parsed.data;

  try {
    const user = await prisma.user.findUnique({
      where: { email: email.toLowerCase() },
      select: {
        id: true,
        email: true,
        passwordHash: true,
        salt: true,
        emailVerified: true,
        emailVerifiedAt: true,
        provider: true,
        providerId: true,
      },
    });

    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    if (user.provider !== 'password') {
      return res.status(400).json({ error: `Use ${user.provider} login for this account` });
    }

    const valid = await bcrypt.compare(password, user.passwordHash);
    if (!valid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    if (!user.emailVerified) {
      return res.status(403).json({ error: 'Email not verified' });
    }

    const token = signToken(user.id, user.email, user.emailVerified, user.provider);
    return res.json({
      token,
      userSalt: user.salt,
      user: {
        id: user.id,
        email: user.email,
        emailVerified: user.emailVerified,
        emailVerifiedAt: user.emailVerifiedAt,
        provider: user.provider,
        providerId: user.providerId,
      },
    });
  } catch (err) {
    logger.error({ err }, 'Login error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
