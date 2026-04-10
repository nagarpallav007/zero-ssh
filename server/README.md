# Keyvault Server

Backend service for syncing and brokering SSH access for cross‑platform clients (Flutter/web/native). Provides JWT auth, SSH key storage, host inventory, and a WebSocket SSH bridge.

## Features
- User auth with bcrypt + JWT (1h access tokens).
- Email verification enforced on login (field available).
- SSH key vault: encrypted at rest (AES-256-GCM), per-user keys; private keys are **not returned** in API responses.
- Host inventory: optional password or key linkage; automatic key creation when you supply a private key.
- WebSocket SSH bridge (`/ws/ssh`) for browsers: multiplexed shell with input/resize, per-user connection limits, idle timeouts.
- Security defaults: helmet, strict CORS allowlist, request validation (zod), global & auth rate limits, structured logging with redaction.

## Stack
- Node 18+, TypeScript, Express 5
- Prisma ORM (Postgres)
- ssh2 for SSH bridging
- pino for logging

## Prerequisites
- Node 18+ and npm
- Postgres 15+ (Docker recipe below)

### Postgres via Docker
```bash
docker run -d --name keyvault-db \
  -e POSTGRES_PASSWORD=devpass \
  -e POSTGRES_USER=keyvault \
  -e POSTGRES_DB=keyvault \
  -p 5432:5432 \
  -v keyvault_data:/var/lib/postgresql/data \
  postgres:15
```

## Environment
Copy `.env.example` to `.env` and fill:

| var | required | example | notes |
| --- | --- | --- | --- |
| DATABASE_URL | yes | postgres://keyvault:devpass@localhost:5432/keyvault | Postgres connection |
| JWT_SECRET | yes | 64-char hex | ≥32 chars |
| SERVER_KEY_SECRET | yes | 64-char hex | ≥32 chars; used for AES-256-GCM KEK |
| PORT | no | 4000 | Server port |
| ALLOWED_ORIGINS | no | https://app.example.com,https://localhost:5173 | Comma-separated allowlist; empty = block browser origins (CLI allowed) |
| RATE_LIMIT_WINDOW_MS | no | 900000 | Global window |
| RATE_LIMIT_MAX | no | 300 | Global max per window |

## Install & Database
```bash
npm install
npm run prisma:generate        # build Prisma client
npm run prisma:migrate         # apply migrations locally
```
First migration: `prisma/migrations/20260306_init`.

## Run
- Dev (watch): `npm run dev`
- Build: `npm run build`
- Prod: `npm run build && npm start`

## Security Defaults (server)
- Helmet, strict CORS allowlist (browsers must be listed).
- JSON body limit 256kb; zod validation on auth/keys/hosts.
- Password policy: ≥12 chars with upper/lower/number/symbol; email must be verified to log in.
- JWT access tokens expire in 1 hour.
- Rate limits: global (default 300/15m) and auth routes (20/15m).
- WebSocket: JWT only via `Sec-WebSocket-Protocol`, rejects query tokens; max 3 concurrent connections/user; 10m idle timeout.
- Private key/password values are encrypted at rest and never returned in responses.

## API Reference
All JSON unless noted. Auth: Bearer access token unless “public”.

### Auth
- **POST /auth/signup**  
  Body: `{ "email": "user@example.com", "password": "Str0ng!Passw0rd" }`  
  Res: `{ "token": "<jwt>", "user": { id, email, emailVerified, emailVerifiedAt, provider, providerId } }`  
  Errors: 409 email exists; 400 validation.

- **POST /auth/login**  
  Body: `{ "email": "user@example.com", "password": "Str0ng!Passw0rd" }`  
  Res: same shape as signup.  
  Errors: 401 invalid creds; 403 email not verified; 400 wrong provider.

### Keys (Bearer)
- **GET /keys** → `{ "keys": [ { id, label, publicKey, createdAt, updatedAt } ] }`
- **POST /keys**  
  Body: `{ "label":"laptop", "publicKey":"ssh-ed25519 AAA...", "privateKey":"-----BEGIN..." }`  
  Res: `{ "key": { id, label, publicKey, createdAt, updatedAt } }`
- **PUT /keys/:id**  
  Body: any of `{ label?, publicKey?, privateKey? }` → same response shape as POST.
- **DELETE /keys/:id** → 204

Notes: Private keys are stored encrypted but not returned.

### Hosts (Bearer)
- **GET /hosts** → `{ "hosts": [ { id, name, hostname, username, port, keyId, publicKey, key, createdAt, updatedAt } ] }`  
  Embedded `key` includes `{ id, label, publicKey }` when linked.
- **POST /hosts**  
  Body example:  
  ```json
  {
    "name": "prod-box",
    "hostname": "10.0.0.5",
    "username": "ubuntu",
    "port": 22,
    "keyId": "existing-key-uuid",
    "publicKey": "ssh-ed25519 AAA..."   // required if providing privateKey
  }
  ```  
  You may instead provide `privateKey` (+ optional `publicKey`) to auto-create a key record and link it. Password auth: use `password` field.
- **PUT /hosts/:id**  
  Any subset of host fields; if `privateKey` provided without `publicKey` → 400.
- **DELETE /hosts/:id** → 204

### WebSocket SSH Bridge
- URL: `ws://<host>:<port>/ws/ssh`
- Auth: set header `Sec-WebSocket-Protocol: Bearer <access_jwt>` (query tokens are rejected).
- Messages (JSON):
  - Connect: `{ "type":"connect", "hostId":"<uuid>", "cols":120, "rows":30 }`  
    or ad-hoc: `{ "type":"connect", "hostname":"example.com", "username":"ubuntu", "port":22, "privateKey":"...", "password":null }`
  - Input: `{ "type":"input", "data":"ls -la\\n" }`
  - Resize: `{ "type":"resize", "cols":120, "rows":30 }`
  - Disconnect: `{ "type":"disconnect" }`
- Server events: `{ "type":"ready" }`, `{ "type":"data", "data":"..." }`, `{ "type":"error", "message":"..." }`, `{ "type":"exit" }`
- Limits: max 3 concurrent connections/user; idle timeout 10 minutes.

## Development Notes
- Prisma schema is the source of truth; do not use the old `initDb`.
- Keep `ALLOWED_ORIGINS` empty during CLI-only dev; set it for browser clients.
- Logging uses pino; adjust `LOG_LEVEL` as needed.

## Roadmap ideas
- KMS-backed envelope encryption for per-user data keys.
- Refresh-token flow with rotation and revocation.
- Optional 2FA/WebAuthn, audit log sink, captcha on auth abuse.
