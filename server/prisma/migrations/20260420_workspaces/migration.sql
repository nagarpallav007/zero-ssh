-- Migration: workspace-based architecture
-- Wipes all host and key data (no production data to preserve).
-- Adds Workspace and WorkspaceMember tables.
-- Moves hosts and keys from user-scoped to workspace-scoped.
-- Adds X25519 keypair fields and plan to users.

-- 1. Wipe existing host and key data
DELETE FROM "keys";
DELETE FROM "hosts";

-- 2. Add keypair and plan fields to users
ALTER TABLE "users"
  ADD COLUMN "public_key" TEXT,
  ADD COLUMN "encrypted_private_key" TEXT,
  ADD COLUMN "plan" VARCHAR(32) NOT NULL DEFAULT 'free';

-- 3. Create workspaces table
CREATE TABLE "workspaces" (
  "id"          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  "name"        VARCHAR(128) NOT NULL,
  "owner_id"    UUID        NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "is_default"  BOOLEAN     NOT NULL DEFAULT false,
  "created_at"  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "workspaces_owner_id_idx" ON "workspaces"("owner_id");

-- 4. Create workspace_members table
CREATE TABLE "workspace_members" (
  "id"                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  "workspace_id"            UUID        NOT NULL REFERENCES "workspaces"("id") ON DELETE CASCADE,
  "user_id"                 UUID        NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "role"                    VARCHAR(16) NOT NULL,
  "encrypted_workspace_key" TEXT,
  "invite_status"           VARCHAR(16) NOT NULL DEFAULT 'accepted',
  "invite_token"            TEXT        UNIQUE,
  "invite_email"            TEXT,
  "invited_at"              TIMESTAMPTZ NOT NULL DEFAULT now(),
  "joined_at"               TIMESTAMPTZ,
  UNIQUE("workspace_id", "user_id")
);
CREATE INDEX "workspace_members_user_id_idx" ON "workspace_members"("user_id");

-- 5. Swap hosts from user_id to workspace_id
ALTER TABLE "hosts" DROP COLUMN "user_id";
DROP INDEX IF EXISTS "hosts_user_id_idx";
ALTER TABLE "hosts" ADD COLUMN "workspace_id" UUID NOT NULL REFERENCES "workspaces"("id") ON DELETE CASCADE;
CREATE INDEX "hosts_workspace_id_idx" ON "hosts"("workspace_id");

-- 6. Swap keys from user_id to workspace_id
ALTER TABLE "keys" DROP COLUMN "user_id";
DROP INDEX IF EXISTS "keys_user_id_idx";
ALTER TABLE "keys" ADD COLUMN "workspace_id" UUID NOT NULL REFERENCES "workspaces"("id") ON DELETE CASCADE;
CREATE INDEX "keys_workspace_id_idx" ON "keys"("workspace_id");
