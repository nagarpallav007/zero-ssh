import crypto from 'crypto';
import { Router } from 'express';
import { prisma } from '../prisma';
import { AuthenticatedRequest, requireAuth } from '../middleware/auth';
import {
  workspaceCreateSchema,
  workspaceInviteSchema,
  workspaceMemberRemoveSchema,
  workspaceMemberRoleSchema,
  workspaceHostCreateSchema,
  workspaceHostUpdateSchema,
  workspaceKeyCreateSchema,
  workspaceKeyUpdateSchema,
} from '../validation';
import { logger } from '../logger';
import { sendWorkspaceInvite } from '../email_service';

const router = Router();

// ── Role helpers ──────────────────────────────────────────────────────────────

const ROLE_ORDER: Record<string, number> = { owner: 3, admin: 2, member: 1 };

/** Returns the membership or throws with an HTTP 403 response via the returned null. */
async function getMembership(workspaceId: string, userId: string) {
  return prisma.workspaceMember.findUnique({
    where: { workspace_member_unique: { workspaceId, userId } },
  });
}

function roleAtLeast(actual: string, required: string) {
  return (ROLE_ORDER[actual] ?? 0) >= (ROLE_ORDER[required] ?? 999);
}

// ── Workspace CRUD ────────────────────────────────────────────────────────────

// GET /workspaces — list workspaces the caller is an accepted member of
router.get('/', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const memberships = await prisma.workspaceMember.findMany({
      where: { userId: req.user!.id, inviteStatus: 'accepted' },
      include: { workspace: { select: { id: true, name: true, isDefault: true, ownerId: true } } },
      orderBy: { invitedAt: 'asc' },
    });
    return res.json({
      workspaces: memberships.map((m) => ({
        id: m.workspace.id,
        name: m.workspace.name,
        isDefault: m.workspace.isDefault,
        ownerId: m.workspace.ownerId,
        role: m.role,
        encryptedWorkspaceKey: m.encryptedWorkspaceKey,
        inviteStatus: m.inviteStatus,
      })),
    });
  } catch (err) {
    logger.error({ err }, 'List workspaces error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /workspaces — create a team workspace (plan-gated)
router.post('/', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = workspaceCreateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }

  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user!.id },
      select: { plan: true },
    });
    if (!user || user.plan === 'free') {
      return res.status(403).json({ error: 'Team workspaces require a paid plan' });
    }

    const { name, encryptedWorkspaceKey } = parsed.data;
    const { workspace, member } = await prisma.$transaction(async (tx) => {
      const ws = await tx.workspace.create({
        data: { name, ownerId: req.user!.id, isDefault: false },
      });
      const mem = await tx.workspaceMember.create({
        data: {
          workspaceId: ws.id,
          userId: req.user!.id,
          role: 'owner',
          encryptedWorkspaceKey,
          inviteStatus: 'accepted',
          joinedAt: new Date(),
        },
      });
      return { workspace: ws, member: mem };
    });

    return res.status(201).json({
      workspace: {
        id: workspace.id,
        name: workspace.name,
        isDefault: workspace.isDefault,
        ownerId: workspace.ownerId,
        createdAt: workspace.createdAt,
      },
      role: member.role,
      encryptedWorkspaceKey: member.encryptedWorkspaceKey,
    });
  } catch (err) {
    logger.error({ err }, 'Create workspace error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /workspaces/:id — workspace detail + members list (for the caller)
router.get('/:id', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const membership = await getMembership(req.params.id, req.user!.id);
    if (!membership || membership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Not a member of this workspace' });
    }

    const workspace = await prisma.workspace.findUnique({
      where: { id: req.params.id },
      select: { id: true, name: true, isDefault: true, ownerId: true, createdAt: true },
    });
    if (!workspace) return res.status(404).json({ error: 'Workspace not found' });

    const members = await prisma.workspaceMember.findMany({
      where: { workspaceId: req.params.id },
      include: { user: { select: { email: true, publicKey: true } } },
      orderBy: { invitedAt: 'asc' },
    });

    return res.json({
      workspace,
      encryptedWorkspaceKey: membership.encryptedWorkspaceKey,
      members: members.map((m) => ({
        id: m.id,
        userId: m.userId,
        email: m.user.email,
        publicKey: m.user.publicKey,
        role: m.role,
        inviteStatus: m.inviteStatus,
        joinedAt: m.joinedAt,
      })),
    });
  } catch (err) {
    logger.error({ err }, 'Get workspace error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /workspaces/:id — delete a workspace (owner only, cannot delete default)
router.delete('/:id', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const membership = await getMembership(req.params.id, req.user!.id);
    if (!membership || membership.role !== 'owner') {
      return res.status(403).json({ error: 'Only the owner can delete a workspace' });
    }

    const workspace = await prisma.workspace.findUnique({
      where: { id: req.params.id },
      select: { isDefault: true },
    });
    if (!workspace) return res.status(404).json({ error: 'Workspace not found' });
    if (workspace.isDefault) {
      return res.status(400).json({ error: 'Cannot delete the default personal workspace' });
    }

    await prisma.workspace.delete({ where: { id: req.params.id } });
    return res.status(204).send();
  } catch (err) {
    logger.error({ err }, 'Delete workspace error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Members ───────────────────────────────────────────────────────────────────

// POST /workspaces/:id/invites — invite a user by email
router.post('/:id/invites', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = workspaceInviteSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }

  try {
    const callerMembership = await getMembership(req.params.id, req.user!.id);
    if (!callerMembership || !roleAtLeast(callerMembership.role, 'admin') || callerMembership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Owner or admin required' });
    }

    const { email, encryptedWorkspaceKey, role } = parsed.data;

    const invitee = await prisma.user.findUnique({
      where: { email },
      select: { id: true, publicKey: true },
    });
    if (!invitee) {
      return res.status(404).json({ error: 'User not found. They need to sign up first.' });
    }
    if (!invitee.publicKey) {
      return res.status(400).json({ error: 'User has not set up their encryption keys yet. Ask them to log in once.' });
    }

    // Check not already a member
    const existing = await getMembership(req.params.id, invitee.id);
    if (existing) {
      return res.status(409).json({ error: 'User is already a member of this workspace' });
    }

    const workspace = await prisma.workspace.findUnique({
      where: { id: req.params.id },
      select: { name: true },
    });

    const token = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days

    const member = await prisma.workspaceMember.create({
      data: {
        workspaceId: req.params.id,
        userId: invitee.id,
        role,
        encryptedWorkspaceKey,
        inviteStatus: 'pending',
        inviteToken: token,
        inviteEmail: email,
        invitedAt: new Date(),
      },
    });

    // Fire and forget — email failure does not fail the request
    sendWorkspaceInvite({
      toEmail: email,
      workspaceName: workspace?.name ?? 'workspace',
      inviterEmail: req.user!.email,
      token,
    });

    return res.status(201).json({
      member: {
        id: member.id,
        userId: invitee.id,
        email,
        role: member.role,
        inviteStatus: member.inviteStatus,
      },
    });
  } catch (err) {
    logger.error({ err }, 'Invite member error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /workspaces/:id/invites/accept — accept an invite via token
router.post('/:id/invites/accept', async (req, res) => {
  const token = req.body?.token as string | undefined;
  if (!token) {
    return res.status(400).json({ error: 'token required' });
  }

  try {
    const member = await prisma.workspaceMember.findFirst({
      where: { workspaceId: req.params.id, inviteToken: token, inviteStatus: 'pending' },
    });
    if (!member) {
      return res.status(410).json({ error: 'Invite not found or already accepted' });
    }

    await prisma.workspaceMember.update({
      where: { id: member.id },
      data: { inviteStatus: 'accepted', joinedAt: new Date(), inviteToken: null },
    });

    return res.json({ ok: true });
  } catch (err) {
    logger.error({ err }, 'Accept invite error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /workspaces/:id/members/:userId — remove a member (atomic key rotation)
router.delete('/:id/members/:userId', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = workspaceMemberRemoveSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }

  try {
    const callerMembership = await getMembership(req.params.id, req.user!.id);
    if (!callerMembership || !roleAtLeast(callerMembership.role, 'admin') || callerMembership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Owner or admin required' });
    }

    const targetMembership = await getMembership(req.params.id, req.params.userId);
    if (!targetMembership) {
      return res.status(404).json({ error: 'Member not found' });
    }
    if (targetMembership.role === 'owner') {
      return res.status(400).json({ error: 'Cannot remove the workspace owner' });
    }

    const { rotatedHosts, rotatedKeys, newMemberKeys } = parsed.data;

    await prisma.$transaction([
      // Delete the removed member
      prisma.workspaceMember.delete({ where: { id: targetMembership.id } }),
      // Re-encrypt all hosts
      ...rotatedHosts.map((h) =>
        prisma.host.update({
          where: { id: h.id },
          data: { encryptedData: h.encryptedData },
        })
      ),
      // Re-encrypt all keys
      ...rotatedKeys.map((k) =>
        prisma.key.update({
          where: { id: k.id },
          data: { encryptedData: k.encryptedData },
        })
      ),
      // Update remaining member key envelopes
      ...newMemberKeys.map((mk) =>
        prisma.workspaceMember.update({
          where: { workspace_member_unique: { workspaceId: req.params.id, userId: mk.userId } },
          data: { encryptedWorkspaceKey: mk.encryptedWorkspaceKey },
        })
      ),
    ]);

    return res.status(204).send();
  } catch (err) {
    logger.error({ err }, 'Remove member error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// PATCH /workspaces/:id/members/:userId — update a member's role
router.patch('/:id/members/:userId', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = workspaceMemberRoleSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }

  try {
    const callerMembership = await getMembership(req.params.id, req.user!.id);
    if (!callerMembership || !roleAtLeast(callerMembership.role, 'admin') || callerMembership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Owner or admin required' });
    }

    const target = await getMembership(req.params.id, req.params.userId);
    if (!target) return res.status(404).json({ error: 'Member not found' });
    if (target.role === 'owner') return res.status(400).json({ error: 'Cannot change the owner role' });

    await prisma.workspaceMember.update({
      where: { id: target.id },
      data: { role: parsed.data.role },
    });
    return res.json({ ok: true });
  } catch (err) {
    logger.error({ err }, 'Update role error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Hosts ─────────────────────────────────────────────────────────────────────

router.get('/:id/hosts', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const membership = await getMembership(req.params.id, req.user!.id);
    if (!membership || membership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Not a member of this workspace' });
    }

    const hosts = await prisma.host.findMany({
      where: { workspaceId: req.params.id },
      orderBy: { updatedAt: 'desc' },
      select: { id: true, encryptedData: true, createdAt: true, updatedAt: true },
    });
    return res.json({ hosts });
  } catch (err) {
    logger.error({ err }, 'List workspace hosts error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/hosts', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = workspaceHostCreateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }

  try {
    const membership = await getMembership(req.params.id, req.user!.id);
    if (!membership || !roleAtLeast(membership.role, 'admin') || membership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Admin or owner required' });
    }

    const host = await prisma.host.create({
      data: { workspaceId: req.params.id, encryptedData: parsed.data.encryptedData },
      select: { id: true, encryptedData: true, createdAt: true, updatedAt: true },
    });
    return res.status(201).json({ host });
  } catch (err) {
    logger.error({ err }, 'Create workspace host error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/:id/hosts/:hostId', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = workspaceHostUpdateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }

  try {
    const membership = await getMembership(req.params.id, req.user!.id);
    if (!membership || !roleAtLeast(membership.role, 'admin') || membership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Admin or owner required' });
    }

    const existing = await prisma.host.findFirst({
      where: { id: req.params.hostId, workspaceId: req.params.id },
    });
    if (!existing) return res.status(404).json({ error: 'Host not found' });

    const host = await prisma.host.update({
      where: { id: req.params.hostId },
      data: { encryptedData: parsed.data.encryptedData ?? undefined },
      select: { id: true, encryptedData: true, createdAt: true, updatedAt: true },
    });
    return res.json({ host });
  } catch (err) {
    logger.error({ err }, 'Update workspace host error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/:id/hosts/:hostId', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const membership = await getMembership(req.params.id, req.user!.id);
    if (!membership || !roleAtLeast(membership.role, 'admin') || membership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Admin or owner required' });
    }

    const deleted = await prisma.host.deleteMany({
      where: { id: req.params.hostId, workspaceId: req.params.id },
    });
    if (deleted.count === 0) return res.status(404).json({ error: 'Host not found' });
    return res.status(204).send();
  } catch (err) {
    logger.error({ err }, 'Delete workspace host error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Keys ──────────────────────────────────────────────────────────────────────

router.get('/:id/keys', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const membership = await getMembership(req.params.id, req.user!.id);
    if (!membership || membership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Not a member of this workspace' });
    }

    const keys = await prisma.key.findMany({
      where: { workspaceId: req.params.id },
      orderBy: { updatedAt: 'desc' },
      select: { id: true, label: true, publicKey: true, encryptedData: true, createdAt: true, updatedAt: true },
    });
    return res.json({ keys });
  } catch (err) {
    logger.error({ err }, 'List workspace keys error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/:id/keys', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = workspaceKeyCreateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }

  try {
    const membership = await getMembership(req.params.id, req.user!.id);
    if (!membership || !roleAtLeast(membership.role, 'admin') || membership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Admin or owner required' });
    }

    const key = await prisma.key.create({
      data: {
        workspaceId: req.params.id,
        label: parsed.data.label ?? null,
        publicKey: parsed.data.publicKey ?? null,
        encryptedData: parsed.data.encryptedData,
      },
      select: { id: true, label: true, publicKey: true, encryptedData: true, createdAt: true, updatedAt: true },
    });
    return res.status(201).json({ key });
  } catch (err) {
    logger.error({ err }, 'Create workspace key error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/:id/keys/:keyId', requireAuth, async (req: AuthenticatedRequest, res) => {
  const parsed = workspaceKeyUpdateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten().fieldErrors });
  }

  try {
    const membership = await getMembership(req.params.id, req.user!.id);
    if (!membership || !roleAtLeast(membership.role, 'admin') || membership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Admin or owner required' });
    }

    const existing = await prisma.key.findFirst({
      where: { id: req.params.keyId, workspaceId: req.params.id },
    });
    if (!existing) return res.status(404).json({ error: 'Key not found' });

    const key = await prisma.key.update({
      where: { id: req.params.keyId },
      data: {
        label: parsed.data.label ?? undefined,
        publicKey: parsed.data.publicKey ?? undefined,
        encryptedData: parsed.data.encryptedData ?? undefined,
      },
      select: { id: true, label: true, publicKey: true, encryptedData: true, createdAt: true, updatedAt: true },
    });
    return res.json({ key });
  } catch (err) {
    logger.error({ err }, 'Update workspace key error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/:id/keys/:keyId', requireAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const membership = await getMembership(req.params.id, req.user!.id);
    if (!membership || !roleAtLeast(membership.role, 'admin') || membership.inviteStatus !== 'accepted') {
      return res.status(403).json({ error: 'Admin or owner required' });
    }

    const deleted = await prisma.key.deleteMany({
      where: { id: req.params.keyId, workspaceId: req.params.id },
    });
    if (deleted.count === 0) return res.status(404).json({ error: 'Key not found' });
    return res.status(204).send();
  } catch (err) {
    logger.error({ err }, 'Delete workspace key error');
    return res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
