-- Initial Prisma migration for keyvault-server
-- Mirrors previous initDb bootstrap, now managed via Prisma Migrate.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE "User" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "email" TEXT NOT NULL UNIQUE,
  "password_hash" TEXT NOT NULL,
  "email_verified" BOOLEAN NOT NULL DEFAULT false,
  "email_verified_at" TIMESTAMPTZ,
  "provider" TEXT NOT NULL DEFAULT 'password',
  "provider_id" TEXT,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE "Key" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "user_id" UUID NOT NULL,
  "label" TEXT,
  "public_key" TEXT NOT NULL,
  "private_key_encrypted" TEXT NOT NULL,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE "Host" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "user_id" UUID NOT NULL,
  "name" TEXT NOT NULL,
  "hostname" TEXT NOT NULL,
  "username" TEXT NOT NULL,
  "port" INTEGER NOT NULL DEFAULT 22,
  "key_id" UUID,
  "password_encrypted" TEXT,
  "private_key_encrypted" TEXT,
  "public_key" TEXT,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE "Key"
  ADD CONSTRAINT "Key_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Host"
  ADD CONSTRAINT "Host_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Host"
  ADD CONSTRAINT "Host_key_id_fkey"
  FOREIGN KEY ("key_id") REFERENCES "Key"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "keys_user_id_idx" ON "Key"("user_id");
CREATE INDEX "hosts_user_id_idx" ON "Host"("user_id");
CREATE INDEX "hosts_key_id_idx" ON "Host"("key_id");
