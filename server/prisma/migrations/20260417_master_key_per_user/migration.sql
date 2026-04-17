-- Migration: master_key_per_user
-- Switches from per-item Argon2id salts to a single salt per user.
--
-- Data impact: all existing Host and Key rows are wiped (they were encrypted
-- with per-item salts that will no longer be used). Users must re-add their
-- hosts and keys after this migration.

-- 1. Wipe all encrypted rows (they cannot be decrypted under the new scheme)
DELETE FROM "keys";
DELETE FROM "hosts";

-- 2. Add salt column to users (cryptographically random, generated per user at signup)
ALTER TABLE "users" ADD COLUMN "salt" TEXT NOT NULL DEFAULT '';

-- 3. Assign a random salt to any existing users (uses gen_random_uuid as entropy source)
UPDATE "users" SET "salt" = encode(sha256((gen_random_uuid()::text || id::text)::bytea), 'hex')
WHERE "salt" = '';

-- 4. Remove the default now that all rows are populated
ALTER TABLE "users" ALTER COLUMN "salt" DROP DEFAULT;

-- 5. Drop per-item salt columns from hosts and keys
ALTER TABLE "hosts" DROP COLUMN "salt";
ALTER TABLE "keys" DROP COLUMN "salt";
