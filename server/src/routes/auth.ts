import crypto from 'crypto';
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { Prisma } from '@prisma/client';
import { prisma } from '../prisma';
import { config } from '../config';
import {
  loginSchema,
  signupSchema,
  uploadKeypairSchema,
  uploadWorkspaceKeySchema,
} from '../validation';
import { rateLimit } from 'express-rate-limit';
import { logger } from '../logger';
import { AuthenticatedRequest, requireAuth } from '../middleware/auth';

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

/** Fetch the membership rows for a user to include in auth responses. */
async function getUserWorkspaces(userId: string) {
  const memberships = await prisma.workspaceMember.findMany({
    where: { userId, inviteStatus: 'accepted' },
    include: { workspace: { select: { id: true, name: true, isDefault: true } } },
    orderBy: { invitedAt: 'asc' },
  });
  return memberships.map((m) => ({
    id: m.workspace.id,
    name: m.workspace.name,
    isDefault: m.workspace.isDefault,
    role: m.role,
    encryptedWorkspaceKey: m.encryptedWorkspaceKey,
    inviteStatus: m.inviteStatus,
  }));
}

router.post('/signup', async (req, res) => {
  const parsed = signupSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }
  const { email, password } = parsed.data;

  try {
    const passwordHash = await bcrypt.hash(password, 10);

    // Create user + default workspace + owner membership in one transaction
    const { user, workspace } = await prisma.$transaction(async (tx) => {
      const newUser = await tx.user.create({
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
          publicKey: true,
          encryptedPrivateKey: true,
          plan: true,
          emailVerified: true,
          emailVerifiedAt: true,
          provider: true,
          providerId: true,
        },
      });

      const newWorkspace = await tx.workspace.create({
        data: { name: 'Personal', ownerId: newUser.id, isDefault: true },
      });

      await tx.workspaceMember.create({
        data: {
          workspaceId: newWorkspace.id,
          userId: newUser.id,
          role: 'owner',
          inviteStatus: 'accepted',
          joinedAt: new Date(),
        },
      });

      return { user: newUser, workspace: newWorkspace };
    });

    const token = signToken(user.id, user.email, user.emailVerified, user.provider);

    // Default workspace membership (encryptedWorkspaceKey is null until passphrase page uploads it)
    const workspaces = [
      {
        id: workspace.id,
        name: workspace.name,
        isDefault: true,
        role: 'owner',
        encryptedWorkspaceKey: null,
        inviteStatus: 'accepted',
      },
    ];

    return res.status(201).json({
      token,
      userSalt: user.salt,
      publicKey: user.publicKey,
      encryptedPrivateKey: user.encryptedPrivateKey,
      plan: user.plan,
      workspaces,
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
        publicKey: true,
        encryptedPrivateKey: true,
        plan: true,
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
    const workspaces = await getUserWorkspaces(user.id);

    return res.json({
      token,
      userSalt: user.salt,
      publicKey: user.publicKey,
      encryptedPrivateKey: user.encryptedPrivateKey,
      plan: user.plan,
      workspaces,
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

// PUT /auth/keypair — upload or update the user's X25519 keypair after passphrase entry
router.put('/keypair', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = uploadKeypairSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }
  const { publicKey, encryptedPrivateKey } = parsed.data;

  try {
    await prisma.user.update({
      where: { id: req.user!.id },
      data: { publicKey, encryptedPrivateKey },
    });
    return res.json({ ok: true });
  } catch (err) {
    logger.error({ err }, 'Upload keypair error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /auth/workspaces/:id/key — set the caller's encryptedWorkspaceKey on their membership
router.put('/workspaces/:id/key', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = uploadWorkspaceKeySchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }
  const { encryptedWorkspaceKey } = parsed.data;

  try {
    const membership = await prisma.workspaceMember.findUnique({
      where: { workspace_member_unique: { workspaceId: req.params.id, userId: req.user!.id } },
    });
    if (!membership) {
      return res.status(404).json({ error: 'Workspace membership not found' });
    }

    await prisma.workspaceMember.update({
      where: { workspace_member_unique: { workspaceId: req.params.id, userId: req.user!.id } },
      data: { encryptedWorkspaceKey },
    });
    return res.json({ ok: true });
  } catch (err) {
    logger.error({ err }, 'Upload workspace key error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
