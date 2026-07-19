# Operational runbook

## Deployment

> `> TODO: fill in` — no production deployment target is committed to this repo (no Dockerfile for
> the server, no Cloud Run/Cloud Build config). The steps below cover **local development**; add the
> production deploy pipeline here once it exists.

### Local development

```bash
make up        # start PostgreSQL (docker-compose, container: pocket-pilot-db, :5432)
make migrate   # wait for DB healthcheck, then apply backend/migrations/*.sql in order
make proto     # regenerate Go + Dart code from proto/ (run after any .proto change)
make run       # go run ./cmd/server  (gRPC server on GRPC_PORT, default 50051)
make build     # go build -o backend/bin/server ./cmd/server
make down      # stop PostgreSQL
make tidy      # cd backend && go get -u ./cmd/server && go mod tidy
```

Frontend: standard Flutter tooling from `frontend/` (`flutter pub get`, `flutter run`,
`flutter test`). SQLite migrations ship as assets (`frontend/assets/migrations/`) and apply on
`DatabaseHelper` version bump.

### Detected targets

| Target | Source | Notes |
| ------ | ------ | ----- |
| PostgreSQL (local) | `docker-compose.yml` | `postgres:18-alpine`, volume `postgres_data`, healthcheck via `pg_isready` |
| gRPC server (local) | `Makefile` → `run`/`build` | `backend/cmd/server`, port from `GRPC_PORT` |
| Proto codegen | `scripts/gen_proto.sh` | generates `backend/internal/gen/` + `frontend/lib/src/generated/` |

## Env vars / configuration

Backend config is read from environment (see `.env.example`; real values live in `.env`, which is
git-ignored — never commit secrets).

| Variable | Description | Required |
| -------- | ----------- | -------- |
| `POSTGRES_USER` | PostgreSQL user (docker-compose + migrate) | Yes (dev) |
| `POSTGRES_PASSWORD` | PostgreSQL password | Yes (dev) |
| `POSTGRES_DB` | PostgreSQL database name | Yes (dev) |
| `DATABASE_URL` | Full Postgres DSN used by the server | Yes |
| `GRPC_PORT` | gRPC listen port (default `50051`) | No (defaults) |
| `MARKETPRICE_ENABLED` | Register the investments price cron (`true` to enable) | No (default `false`) |
| `MARKETPRICE_RUN_ON_BOOT` | Force one price tick at server start | No (default `false`) |
| `MARKETPRICE_PROVIDER` | Upstream price source; only `yahoo` implemented | No (default `yahoo`) |
| `MARKETPRICE_ADMIN_TOKEN` | Gates the admin RPC used to manually kick the price job | No (empty = admin kick disabled) |

> The market-price cron normally fires its first tick at 22:00 UTC unless `MARKETPRICE_RUN_ON_BOOT`
> forces one earlier. See [features/investments.md](features/investments.md).

## Monitoring & alerts

- **Dashboards**: `> TODO: fill in`
- **Alerts**: `> TODO: fill in`
- **Logs**: gRPC server logs to stdout (via the logging middleware); no aggregation configured yet.

## Common operational issues

- **Symptom**: `make migrate` hangs → **Diagnosis**: waiting on the DB healthcheck → **Resolution**:
  confirm the `pocket-pilot-db` container is up (`docker ps`) and healthy.
- **Symptom**: generated code out of sync after editing a `.proto` → **Diagnosis**: codegen not run
  → **Resolution**: `make proto` and rebuild.
- **Symptom**: pushing a modified SQLite DB to an Android device fails → **Diagnosis**: the
  notification-listener service keeps a file handle (survives `am force-stop`) → **Resolution**: see
  [features/notification-capture.md](features/notification-capture.md).
- **Symptom**: reinstalling the debug APK wipes app data → **Diagnosis**: `flutter install`
  uninstalls on signature change → **Resolution**: always `adb install -r`; see
  [postmortems/0001](postmortems/0001-flutter-install-data-loss.md).
- **Symptom**: NLS approved in Settings but captures nothing after a reinstall → **Diagnosis**:
  zombie binding (listed but never called) → **Resolution**: toggle notification access OFF→ON;
  see [features/notification-capture.md](features/notification-capture.md) § Operational tooling.
- **Symptom**: pulled `pocket_pilot.db` looks stale or empty → **Diagnosis**: WAL — recent commits
  live in the `-wal` sidecar → **Resolution**: pull `.db`, `.db-wal` and `.db-shm` together.
- **Symptom**: `cmd jobscheduler run` cannot find the WorkManager job → **Diagnosis**: Android 14+
  puts WorkManager jobs in a namespace → **Resolution**: add `-n androidx.work.systemjobscheduler`.

## External dependencies

- **3rd-party APIs**: Yahoo Finance (market prices), Google Gemini (AI chat + notification parsing),
  Google / Apple identity providers (social login, JWKS verification).
- **Internal services**: none (single backend service).
- **Infra**: PostgreSQL (server source of truth), on-device SQLite (client), Android Notification
  Listener Service (notification capture).
