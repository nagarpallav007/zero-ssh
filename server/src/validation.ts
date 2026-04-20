import { z } from 'zod';

export const emailSchema = z.string().trim().toLowerCase().email().max(254);
export const passwordSchema = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .max(128, 'Password too long');

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().max(256),
});

export const signupSchema = z.object({
  email: emailSchema,
  password: passwordSchema,
});

// User X25519 keypair upload (after passphrase entry)
export const uploadKeypairSchema = z.object({
  publicKey: z.string().min(1).max(4096),
  encryptedPrivateKey: z.string().min(1).max(4096),
});

// Workspace key upload (ECIES-wrapped workspace key for the calling user's membership)
export const uploadWorkspaceKeySchema = z.object({
  encryptedWorkspaceKey: z.string().min(1),
});

// Workspace creation — client also provides their own ECIES-encrypted workspace key
export const workspaceCreateSchema = z.object({
  name: z.string().trim().min(1).max(128),
  encryptedWorkspaceKey: z.string().min(1),
});

// Workspace invite — includes the workspace key ECIES-encrypted for the invitee
export const workspaceInviteSchema = z.object({
  email: emailSchema,
  encryptedWorkspaceKey: z.string().min(1),
  role: z.enum(['admin', 'member']),
});

// Atomic member removal — includes re-encrypted hosts, keys, and new member key envelopes
const rotatedHostSchema = z.object({ id: z.string().uuid(), encryptedData: z.string().min(1) });
const rotatedKeySchema  = z.object({ id: z.string().uuid(), encryptedData: z.string().min(1) });
const newMemberKeySchema = z.object({ userId: z.string().uuid(), encryptedWorkspaceKey: z.string().min(1) });

export const workspaceMemberRemoveSchema = z.object({
  rotatedHosts: z.array(rotatedHostSchema),
  rotatedKeys:  z.array(rotatedKeySchema),
  newMemberKeys: z.array(newMemberKeySchema),
});

// Workspace host CRUD
export const workspaceHostCreateSchema = z.object({
  encryptedData: z.string().min(1),
});
export const workspaceHostUpdateSchema = workspaceHostCreateSchema.partial();

// Workspace key CRUD
export const workspaceKeyCreateSchema = z.object({
  encryptedData: z.string().min(1),
  label: z.string().trim().max(128).optional().nullable(),
  publicKey: z.string().trim().max(8192).optional().nullable(),
});
export const workspaceKeyUpdateSchema = z.object({
  encryptedData: z.string().min(1).optional(),
  label: z.string().trim().max(128).optional(),
  publicKey: z.string().trim().max(8192).optional(),
});

// Role update
export const workspaceMemberRoleSchema = z.object({
  role: z.enum(['admin', 'member']),
});

export type SignupInput = z.infer<typeof signupSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
