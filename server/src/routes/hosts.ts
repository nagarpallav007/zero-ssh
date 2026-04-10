import { Router } from 'express';
import { prisma } from '../prisma';
import { AuthenticatedRequest, requireAuth } from '../middleware/auth';
import { hostCreateSchema, hostUpdateSchema } from '../validation';
import { logger } from '../logger';

const router = Router();

// GET /hosts — return all encrypted host blobs for the authenticated user
router.get('/', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const hosts = await prisma.host.findMany({
      where: { userId: req.user!.id },
      orderBy: { updatedAt: 'desc' },
      select: {
        id: true,
        encryptedData: true,
        salt: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    return res.json({ hosts });
  } catch (err) {
    logger.error({ err }, 'Fetch hosts error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /hosts — store a client-encrypted host blob
router.post('/', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = hostCreateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }
  const { encryptedData, salt } = parsed.data;

  try {
    const row = await prisma.host.create({
      data: {
        userId: req.user!.id,
        encryptedData,
        salt,
      },
      select: {
        id: true,
        encryptedData: true,
        salt: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    return res.status(201).json({ host: row });
  } catch (err) {
    logger.error({ err }, 'Create host error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /hosts/:id — replace a client-encrypted host blob
router.put('/:id', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = hostUpdateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }

  try {
    const existing = await prisma.host.findFirst({
      where: { id: req.params.id, userId: req.user!.id },
    });
    if (!existing) {
      return res.status(404).json({ error: 'Host not found' });
    }

    const { encryptedData, salt } = parsed.data;
    const row = await prisma.host.update({
      where: { id: req.params.id },
      data: {
        encryptedData: encryptedData ?? undefined,
        salt: salt ?? undefined,
      },
      select: {
        id: true,
        encryptedData: true,
        salt: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    return res.json({ host: row });
  } catch (err) {
    logger.error({ err }, 'Update host error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /hosts/:id
router.delete('/:id', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const deleted = await prisma.host.deleteMany({
      where: { id: req.params.id, userId: req.user!.id },
    });
    if (deleted.count === 0) {
      return res.status(404).json({ error: 'Host not found' });
    }
    return res.status(204).send();
  } catch (err) {
    logger.error({ err }, 'Delete host error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
