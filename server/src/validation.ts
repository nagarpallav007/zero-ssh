import { z } from 'zod';

export const emailSchema = z.string().trim().toLowerCase().email().max(254);
export const passwordSchema = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .max(128, 'Password too long');

// Keys: server stores opaque client-encrypted blobs + Argon2id salt
export const keyCreateSchema = z.object({
  label: z.string().trim().max(128).optional().nullable(),
  publicKey: z.string().trim().max(8192).optional().nullable(),
  encryptedData: z.string().min(1),
  salt: z.string().min(1),
});

export const keyUpdateSchema = z.object({
  label: z.string().trim().max(128).optional(),
  publicKey: z.string().trim().max(8192).optional(),
  encryptedData: z.string().min(1).optional(),
  salt: z.string().min(1).optional(),
});

// Hosts: all metadata is client-encrypted; server sees only blob + salt
export const hostCreateSchema = z.object({
  encryptedData: z.string().min(1),
  salt: z.string().min(1),
});

export const hostUpdateSchema = hostCreateSchema.partial();

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().max(256),
});

export const signupSchema = z.object({
  email: emailSchema,
  password: passwordSchema,
});

export type SignupInput = z.infer<typeof signupSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
