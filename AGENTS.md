# Pocket Pilot — Agent Context Index

Entry point for AI agents other than Claude Code (Gemini CLI, OpenCode, …). `GEMINI.md` symlinks
here; Claude Code uses its own `CLAUDE.md`. All routers point to the **same** `docs/` knowledge base,
so there is one source of truth.

Pocket Pilot is an offline-first personal finance app: Flutter + SQLite client, Go/gRPC + PostgreSQL
backend, synced with Last Write Wins over Protobuf contracts. Monorepo: `backend/` (Go),
`frontend/` (Flutter), `proto/` (contracts), `scripts/` (Python parsers).

## Read before starting a task

- **Architecture / layout / data flow** → [docs/architecture.md](docs/architecture.md)
- **Conventions** (Go/Dart, proto, DB/migrations, UI) → [docs/conventions.md](docs/conventions.md)
- **Local dev / env / make targets** → [docs/runbook.md](docs/runbook.md)
- **Features** → [docs/features/_index.md](docs/features/_index.md)
- **Decisions (ADRs)** → [docs/decisions/_index.md](docs/decisions/_index.md)
- **Historical plans & specs** (reference) → `plans/`, `docs/specs/`

## Critical rules

1. **Never hand-edit generated code** (`backend/internal/gen/`, `frontend/lib/src/generated/`);
   after any `proto/` change run `make proto`.
2. **Dual migrations** (PostgreSQL + SQLite) and **LWW** on every syncable table — see
   `docs/conventions.md`.
3. Never commit secrets; real config lives in `.env` (git-ignored).

---
*Pointer file — the source of truth is `docs/`.*
