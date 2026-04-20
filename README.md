# ZeroSSH

A lightweight, cross-platform SSH client with **zero-knowledge encrypted sync and team sharing**.  
Connect to your servers from any device. Your private keys and host metadata never leave your device unencrypted — not even the server can read them.

![Node](https://img.shields.io/badge/Node.js-20%20LTS-339933?logo=node.js)
![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-3.x-54C5F8?logo=flutter)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20Android%20%7C%20Windows%20%7C%20Linux-blue)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **Multi-tab terminal** — open multiple SSH sessions side by side
- **Local terminal** — built-in local shell on desktop (no SSH needed)
- **Zero-knowledge encryption** — SSH keys and host metadata are AES-256-GCM encrypted on your device before sync; the server stores only ciphertext
- **Team workspaces** — share hosts securely with teammates; workspace encryption keys are distributed per-member via ECIES so the server never sees the plaintext key
- **Workspace selector** — switch between Personal and team workspaces directly from the host list bar
- **Cross-platform** — one Flutter codebase runs on macOS, iOS, Android, Windows, and Linux
- **SSH key management** — import PEM keys, label them, reuse across hosts
- **Pinch-to-zoom terminal** — adjust font size with a gesture (8–24 sp)
- **Customisable terminal themes** — multiple built-in colour schemes
- **Guest mode** — use the app without an account (local terminal only)
- **Native macOS feel** — unified toolbar, traffic-light alignment, native window chrome

---

## Architecture

```
┌─────────────────────────────────┐        ┌──────────────────────────────┐
│  Flutter Client                 │        │  Node.js Server              │
│                                 │  HTTPS │                              │
│  • xterm terminal emulator      │◄──────►│  • Express REST API          │
│  • dartssh2 SSH client          │        │  • JWT authentication        │
│  • Argon2id key derivation      │        │  • PostgreSQL via Prisma     │
│  • AES-256-GCM encryption       │        │  • Stores ciphertext only    │
│  • ECIES workspace key sharing  │        │  • Workspace + member mgmt   │
└─────────────────────────────────┘        └──────────────────────────────┘
```

---

## Security model

### Personal encryption (per-user)

```
Passphrase
    │
    ▼  Argon2id (memory=64 MB, iterations=3, parallelism=4)
Master Key (32 bytes, in-memory only)
    │
    ├──► encrypts X25519 private key → stored on server (ciphertext)
    └──► (workspace keys are encrypted via ECIES, not master key directly)
```

### Workspace key distribution (ECIES)

Each workspace has a random 32-byte AES key. It is never stored in plaintext — instead, it is ECIES-encrypted once per member:

```
Workspace Key (random 32 bytes)
    │
    ▼  ECIES: X25519 ECDH + HKDF-SHA256 + AES-256-GCM
encryptedWorkspaceKey  ← stored per member row on the server
    │
    ▼  (recipient decrypts with their X25519 private key)
Workspace Key (in-memory only, used to encrypt/decrypt hosts & keys)
```

**Key rotation on member removal:** when a member is removed, a new workspace key is generated, all hosts and SSH keys are re-encrypted atomically, and the new key is ECIES-encrypted for each remaining member in a single database transaction.

### What the server stores

| Data | What the server has |
|------|---------------------|
| SSH private keys | AES-256-GCM ciphertext |
| Host metadata (hostname, user, port) | AES-256-GCM ciphertext |
| Workspace encryption key | ECIES ciphertext (one envelope per member) |
| User X25519 private key | AES-256-GCM ciphertext (encrypted with master key) |
| User X25519 public key | Plaintext (public by design) |
| Passphrase / master key | **Never stored or transmitted** |

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| Client | Flutter 3, Dart 3, Riverpod, xterm, dartssh2 |
| Symmetric encryption | AES-256-GCM (hosts, keys, workspace key envelope) |
| Key derivation | Argon2id — passphrase → master key |
| Asymmetric encryption | X25519 ECDH + HKDF-SHA256 + AES-256-GCM (ECIES) |
| Server | Node.js 20 LTS, TypeScript, Express 5 |
| Database | PostgreSQL 15 + Prisma ORM |
| Auth | bcrypt + JWT (1-hour access tokens) |
| Security | Helmet, CORS allowlist, rate limiting |

---

## Workspaces

Every user gets a **Personal** workspace on signup. Team sharing is done by creating additional workspaces and inviting members by email.

- **Roles**: Owner, Admin (can manage hosts and members), Member (read-only)
- **Invite flow**: invitee's public key is fetched, the workspace key is ECIES-encrypted for them, and an email invite is sent
- **Key rotation**: removing a member triggers an atomic re-encryption of all workspace hosts and SSH keys with a fresh workspace key
- **Plan gating**: creating team workspaces requires a paid plan; Personal workspace is always free

The workspace selector lives in the host list banner bar — for users who only use Personal, it is a single tap away but otherwise invisible.

---

## Getting started

### Prerequisites

| Tool | Version |
|------|---------|
| Flutter | 3.x (`flutter --version`) |
| Node.js | 20 LTS (`node --version`) |
| PostgreSQL | 15+ (or Docker) |

### 1 — Start the server

```bash
cd server
cp .env.example .env          # fill in the values below
npm install
npm run dev                   # http://localhost:4000
```

**Required `.env` values:**

```env
DATABASE_URL="postgresql://user:password@localhost:5432/zerossh"
JWT_SECRET="<random 32+ char string>"
PORT=4000
```

**Optional `.env` values (email invites):**

```env
APP_BASE_URL="https://your-app.com"
SMTP_HOST="smtp.example.com"
SMTP_PORT=587
SMTP_USER="user@example.com"
SMTP_PASS="password"
SMTP_FROM="ZeroSSH <noreply@example.com>"
```

If SMTP is not configured, invite tokens are printed to the server console instead.

**Run the migration** (first time or after upgrading):

```bash
npx prisma db execute --file prisma/migrations/20260420_workspaces/migration.sql --schema prisma/schema.prisma
```

**Quick Postgres via Docker:**

```bash
docker run -d --name zerossh-db \
  -e POSTGRES_USER=zerossh \
  -e POSTGRES_PASSWORD=devpass \
  -e POSTGRES_DB=zerossh \
  -p 5432:5432 postgres:15
```

### 2 — Run the client

```bash
cd client
flutter pub get
flutter run -d macos          # or: ios | android | windows | linux
```

By default the client points to `http://localhost:4000`. To change it:

```bash
flutter run --dart-define=API_BASE_URL=https://your-server.com -d macos
```

---

## Project structure

```
zerossh/
├── client/                        # Flutter application
│   ├── lib/
│   │   ├── main.dart              # App entry, auth + passphrase gate
│   │   ├── screens/
│   │   │   ├── host_management_page.dart   # Host list + workspace selector
│   │   │   ├── workspace_detail_page.dart  # Member management
│   │   │   ├── terminal_tabs_page.dart     # Tab bar
│   │   │   ├── terminal_page.dart          # xterm + dartssh2 session
│   │   │   ├── passphrase_page.dart        # Key derivation + bootstrap
│   │   │   └── host_form_page.dart         # Add/edit host form
│   │   ├── services/
│   │   │   ├── crypto_service.dart         # AES-GCM + ECIES
│   │   │   ├── workspace_repository.dart   # Workspace CRUD + key ops
│   │   │   ├── host_repository.dart        # Host CRUD (workspace-scoped)
│   │   │   ├── key_repository.dart         # SSH key CRUD (workspace-scoped)
│   │   │   ├── auth_service.dart           # Login, session, SharedPreferences
│   │   │   └── passphrase_manager.dart     # In-memory master key + X25519 keypair
│   │   ├── models/
│   │   │   ├── workspace.dart              # WorkspaceSession, WorkspaceMember, etc.
│   │   │   ├── ssh_host.dart
│   │   │   └── ssh_key.dart
│   │   ├── theme/                          # AppColors, AppSpacing, AppTypography
│   │   └── utils/                          # PlatformUtils
│   └── macos/Runner/                       # macOS window chrome (Swift)
│
└── server/                        # Node.js API
    ├── src/
    │   ├── index.ts               # Express + WebSocket SSH bridge
    │   ├── routes/
    │   │   ├── auth.ts            # Login, signup, keypair + workspace key upload
    │   │   ├── workspaces.ts      # Workspace + member + host + key endpoints
    │   │   └── users.ts           # Public key lookup (for invite flow)
    │   ├── email_service.ts       # Invite email (nodemailer or console fallback)
    │   └── middleware/            # JWT auth
    └── prisma/
        └── schema.prisma          # User, Workspace, WorkspaceMember, Host, Key
```

---

## Contributing

Contributions are welcome. A few guidelines:

1. **Security-sensitive changes** (crypto, auth, key handling) require extra care and a clear explanation of the threat model impact in the PR.
2. **Zero-knowledge invariant** — the server must never receive or store plaintext secrets. Do not break this.
3. **ECIES correctness** — workspace key envelopes use X25519 + HKDF-SHA256 + AES-256-GCM with `info = 'zerossh-workspace-key'`. Do not change the KDF parameters without updating all clients simultaneously.
4. **Cross-platform** — test on at least two platforms before submitting.
5. **Code style** — `flutter analyze` and `npm run build` must pass clean.
6. **Commits** — conventional commits (`feat:`, `fix:`, `refactor:`, etc.), short subject line.

---

## Roadmap

- [ ] Accept workspace invites in-app (currently via email link only)
- [ ] TOTP / passkey second factor
- [ ] Port forwarding / tunnels
- [ ] Host groups and tagging
- [ ] Jump host / bastion support
- [ ] Self-hosted Docker image

---

## License

MIT — see [LICENSE](LICENSE).
