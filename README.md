# ZeroSSH

A lightweight, cross-platform SSH client with **zero-knowledge encrypted key sync**.  
Connect to your servers from any device. Your private keys never leave your device unencrypted — not even the server can read them.

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
- **Cross-platform** — one Flutter codebase runs on macOS, iOS, Android, Windows, and Linux
- **SSH key management** — import PEM keys, label them, reuse across hosts
- **Customisable terminal themes** — multiple built-in colour schemes
- **Guest mode** — use the app without an account (local terminal + manual hosts)
- **Native macOS feel** — unified toolbar, traffic-light alignment, native window chrome

---

## Architecture

```
┌─────────────────────────────┐        ┌──────────────────────────────┐
│  Flutter Client             │        │  Node.js Server              │
│                             │  HTTPS │                              │
│  • xterm terminal emulator  │◄──────►│  • Express REST API          │
│  • dartssh2 SSH client      │        │  • JWT authentication        │
│  • Client-side AES-256-GCM  │        │  • PostgreSQL via Prisma     │
│    encryption               │        │  • Stores ciphertext only    │
└─────────────────────────────┘        └──────────────────────────────┘
```

**Zero-knowledge flow**: Passphrase → Argon2id → encryption key (in-memory only) → encrypts all secrets before they leave the device.

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| Client | Flutter 3, Dart 3, Riverpod, xterm, dartssh2 |
| Encryption | AES-256-GCM + Argon2id (client-side) |
| Server | Node.js 20 LTS, TypeScript, Express 5 |
| Database | PostgreSQL 15 + Prisma ORM |
| Auth | bcrypt + JWT (1-hour access tokens) |
| Security | Helmet, CORS allowlist, rate limiting |

---

## Getting started

### Prerequisites

| Tool | Version |
|------|---------|
| Flutter | 3.x (`flutter --version`) |
| Node.js | 20 LTS (`node --version`) |
| PostgreSQL | 15+ (or Docker) |

---

### 1 — Start the server

```bash
cd server
cp .env.example .env          # fill in the values below
npm install
npm run prisma:migrate        # creates tables
npm run dev                   # http://localhost:4000
```

**Required `.env` values:**

```env
DATABASE_URL="postgresql://user:password@localhost:5432/zerossh"
JWT_SECRET="<random 32+ char string>"
SERVER_KEY_SECRET="<random 32+ char string>"
PORT=4000
ALLOWED_ORIGINS="http://localhost:3000"   # comma-separated browser origins
```

**Quick Postgres via Docker:**

```bash
docker run -d --name zerossh-db \
  -e POSTGRES_USER=zerossh \
  -e POSTGRES_PASSWORD=devpass \
  -e POSTGRES_DB=zerossh \
  -p 5432:5432 postgres:15
```

---

### 2 — Run the client

```bash
cd client
flutter pub get
flutter run -d macos          # or: ios | android | windows | linux
```

By default the client points to `http://localhost:4000`.  
To change it, set the `API_BASE_URL` environment variable at build time:

```bash
flutter run --dart-define=API_BASE_URL=https://your-server.com -d macos
```

---

## Project structure

```
zerossh/
├── client/                   # Flutter application
│   ├── lib/
│   │   ├── main.dart         # App entry, auth gate
│   │   ├── screens/          # UI pages
│   │   ├── services/         # API, crypto, SSH, storage
│   │   ├── models/           # SSHHost, SSHKey
│   │   ├── theme/            # Design system (colors, spacing, typography)
│   │   └── utils/            # Platform detection
│   └── macos/Runner/         # macOS-specific window chrome (Swift)
│
└── server/                   # Node.js API
    ├── src/
    │   ├── index.ts          # Express REST API
    │   ├── routes/           # auth, hosts, keys
    │   └── middleware/       # JWT auth
    └── prisma/
        └── schema.prisma     # Database schema
```

---

## Security model

- **Client-side encryption only** — the server never sees plaintext private keys or host metadata
- **Argon2id key derivation** — passphrase stretched before use as an AES key
- **AES-256-GCM** — authenticated encryption for all secrets
- **In-memory passphrase** — never written to disk; cleared on logout
- **JWT sessions** — 1-hour expiry, bcrypt password hashing
- **Rate limiting** — 300 req/15 min globally, 20 req/15 min on auth routes

---

## Contributing

Contributions are welcome. A few guidelines:

1. **Security-sensitive changes** (crypto, auth, key handling) require extra care and a clear explanation of the threat model impact in the PR.
2. **Zero-knowledge invariant** — the server must never receive or store plaintext secrets. Do not break this.
3. **Cross-platform** — test on at least two platforms (e.g. macOS + Android) before submitting.
4. **Code style** — Dart: `flutter analyze` must pass clean. TypeScript: `npm run build` must pass.
5. **Commits** — conventional commits (`feat:`, `fix:`, `refactor:`, etc.), short subject line.

### Development tips

```bash
# Watch server with hot reload
cd server && npm run dev

# Flutter hot reload
cd client && flutter run -d macos
# then press 'r' to reload, 'R' for full restart

# Database schema change
cd server && npx prisma migrate dev --name your_change_name

# Check for issues
cd client && flutter analyze
cd server && npm run build
```

---

## Roadmap

- [ ] TOTP / passkey second factor
- [ ] Port forwarding / tunnels
- [ ] Host groups and tagging
- [ ] Jump host / bastion support
- [ ] Offline mode (local-only, no account required)
- [ ] Self-hosted Docker image

---

## License

MIT — see [LICENSE](LICENSE).
