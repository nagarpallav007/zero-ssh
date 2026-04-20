import { Router } from 'express';
import { prisma } from '../prisma';
import { AuthenticatedRequest, requireAuth } from '../middleware/auth';
import { logger } from '../logger';

const router = Router();

// GET /users/lookup?email= — find a user by email for workspace invite
// Returns only id and publicKey (no other user data exposed)
router.get('/lookup', requireAuth, async (req: AuthenticatedRequest, res) => {
  const email = (req.query.email as string | undefined)?.toLowerCase().trim();
  if (!email) {
    return res.status(400).json({ error: 'email query parameter required' });
  }

  try {
    const user = await prisma.user.findUnique({
      where: { email },
      select: { id: true, publicKey: true },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (!user.publicKey) {
      return res.status(400).json({
        error: 'User has not set up their encryption keys yet. Ask them to log in once.',
      });
    }

    return res.json({ id: user.id, publicKey: user.publicKey });
  } catch (err) {
    logger.error({ err }, 'User lookup error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
