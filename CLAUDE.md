# Pocket Pilot

Offline-first personal finance app: Flutter + SQLite client, Go/gRPC + PostgreSQL backend, synced
with Last Write Wins over Protobuf contracts.

> Monorepo: `backend/` (Go), `frontend/` (Flutter), `proto/` (contracts), `scripts/` (Python parsers).
> Other agents (Gemini, etc.) read `AGENTS.md`, which points to this same `docs/` knowledge base.

## For this session, consider reading

- Architecture, layout, modules, data flow → `docs/architecture.md`
- Conventions (Go/Dart style, proto, DB/migrations, UI) → `docs/conventions.md`
- Local dev, env vars, make targets → `docs/runbook.md`
- Documented features → `docs/features/_index.md`
- Architectural decisions (ADRs) → `docs/decisions/_index.md`
- Postmortems / security / performance gotchas → `docs/postmortems|security|performance/_index.md`
- Historical plans & design specs (reference) → `plans/`, `docs/specs/`

## Critical rules

- **Never hand-edit generated code** (`backend/internal/gen/`, `frontend/lib/src/generated/`). After
  any change under `proto/`, run `make proto`.
- **Migrations are dual**: a PostgreSQL migration (`backend/migrations/NNN_*.sql`) AND a SQLite one
  (`frontend/assets/migrations/NNN.sql`) + bump `DatabaseHelper._version`. See `docs/conventions.md`.
- **LWW everywhere**: syncable tables carry `id/user_id/created_at/updated_at/deleted_at`; upserts use
  `ON CONFLICT … WHERE table.updated_at < EXCLUDED.updated_at`. Soft-delete only.
- **Deterministic generators** (scheduled txns, interest, investment txns) use fixed UUIDv5
  namespaces in `frontend/lib/src/core/ids/` — don't change them.
- Never commit secrets; real config lives in `.env` (git-ignored). `.env.example` is the template.

## Local commands

```bash
make up && make migrate   # start PostgreSQL + apply backend migrations
make proto                # regenerate Go + Dart from proto/
make run                  # run gRPC server (backend/cmd/server)
cd backend && go test ./...          # backend tests
cd frontend && flutter test          # frontend tests
```
