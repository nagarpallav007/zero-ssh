import { Router } from 'express';
import { prisma } from '../prisma';
import { AuthenticatedRequest, requireAuth } from '../middleware/auth';
import { keyCreateSchema, keyUpdateSchema } from '../validation';
import { logger } from '../logger';

const router = Router();

// GET /keys — return all encrypted key blobs for the authenticated user
router.get('/', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const keys = await prisma.key.findMany({
      where: { userId: req.user!.id },
      orderBy: { updatedAt: 'desc' },
      select: {
        id: true,
        label: true,
        publicKey: true,
        encryptedData: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    return res.json({ keys });
  } catch (err) {
    logger.error({ err }, 'Fetch keys error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /keys — store a client-encrypted key blob
router.post('/', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = keyCreateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }
  const { label, publicKey, encryptedData } = parsed.data;

  try {
    const row = await prisma.key.create({
      data: {
        userId: req.user!.id,
        label: label ?? null,
        publicKey: publicKey ?? null,
        encryptedData,
      },
      select: {
        id: true,
        label: true,
        publicKey: true,
        encryptedData: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    return res.status(201).json({ key: row });
  } catch (err) {
    logger.error({ err }, 'Create key error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /keys/:id — replace a client-encrypted key blob
router.put('/:id', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = keyUpdateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }

  try {
    const existing = await prisma.key.findFirst({
      where: { id: req.params.id, userId: req.user!.id },
    });
    if (!existing) {
      return res.status(404).json({ error: 'Key not found' });
    }

    const { label, publicKey, encryptedData } = parsed.data;
    const row = await prisma.key.update({
      where: { id: req.params.id },
      data: {
        label: label ?? undefined,
        publicKey: publicKey ?? undefined,
        encryptedData: encryptedData ?? undefined,
      },
      select: {
        id: true,
        label: true,
        publicKey: true,
        encryptedData: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    return res.json({ key: row });
  } catch (err) {
    logger.error({ err }, 'Update key error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /keys/:id
router.delete('/:id', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const deleted = await prisma.key.deleteMany({
      where: { id: req.params.id, userId: req.user!.id },
    });
    if (deleted.count === 0) {
      return res.status(404).json({ error: 'Key not found' });
    }
    return res.status(204).send();
  } catch (err) {
    logger.error({ err }, 'Delete key error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
