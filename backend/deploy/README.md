# Deploy to the Raspberry Pi (homelab)

This project is deployed as a Docker image published to **ghcr.io** and consumed
by the Pi. **It is not compiled on the Pi, and no code is copied to it.**

## Publishing (automatic)

Every push to `main` triggers `.github/workflows/release-and-deploy.yml`: `git-cliff`
computes the next semver from the conventional commits and, if there's anything
releasable, creates the tag, updates `CHANGELOG.md`, builds the **arm64** image,
publishes it to ghcr, and creates the GitHub Release.

| Commit prefix                  | Effect |
|--------------------------------|--------|
| `feat:`                        | minor  |
| `fix:` / `perf:`               | patch  |
| `feat!:` or `BREAKING CHANGE:` | major  |
| `docs:` `chore:` `ci:` `test:` | no release |

## Exposure mode — public gRPC via cloudflared

The backend is a **gRPC server** (HTTP/2), exposed to the internet through the
Cloudflare tunnel so the mobile app reaches it by a stable hostname instead of a
LAN IP that changes. No ports are published on the host: cloudflared reaches the
container by name on the `homelab` network.

In the Cloudflare tunnel, add a public hostname (e.g. `api.your-domain.com`) with
a service of:

```
h2c://pocket-pilot:50051
```

Use `h2c://` — **not** `http://`. The app speaks plaintext gRPC (HTTP/2 cleartext)
inside the LAN; Cloudflare terminates TLS at the edge and proxies gRPC through the
tunnel. If you configure `http://`, gRPC calls fail. Point the Flutter client at
`https://api.your-domain.com` (port 443) with TLS enabled.

> `cloudflared` config lives in your existing tunnel stack, not in this compose
> file. If you prefer the dashboard, add the hostname there; if you use a config
> file, add an `ingress` entry with `service: h2c://pocket-pilot:50051`.

## Deploy on the Pi (manual)

The files in `backend/deploy/` go to `/opt/stacks/pocket-pilot/` on the Pi.

```bash
# Log in to the registry (once; PAT with read:packages)
echo "$GHCR_PAT" | docker login ghcr.io -u AlanIsaacV --password-stdin

# Create the database + role once (see .env.example for the exact psql commands),
# then:
cd /opt/stacks/pocket-pilot
cp .env.example .env && nano .env                  # fill in secrets
docker compose pull
docker compose --profile tools run --rm migrate    # first-time schema setup
docker compose up -d
```

**Update:** `docker compose pull && docker compose up -d`.
**Rollback:** pin an older tag (`:vX.Y.Z`) in `compose.yaml` and repeat pull && up.

## Database migrations

The Pi has no toolchain (no Go, no psql). The migrations ship **inside the image**:
`cmd/migrate` embeds `migrations/*.sql` (see `migrations/embed.go`) and applies any
not yet recorded in a `schema_migrations` table, each in its own transaction. It's
wired as the one-shot `migrate` service under the `tools` profile in `compose.yaml`.

Run it **before** `up` whenever a release changes the schema:

```bash
docker compose pull                                # get the new image first
docker compose --profile tools run --rm migrate    # apply pending migrations
docker compose up -d                               # then start the server
```

Re-running is safe: already-applied versions are skipped, so it's a no-op on an
up-to-date database.

> **Note vs `make migrate`:** the repo's Makefile pipes every `.sql` through psql on
> each run and tolerates "already exists" errors (the files are not idempotent). The
> `migrate` binary is stricter and version-tracked. If you ever point it at a
> database that was migrated the old way (e.g. a dev DB), pre-seed the tracking table
> so it doesn't try to re-run existing files:
> `INSERT INTO schema_migrations (version) SELECT unnest(...)` — on a fresh Pi
> database this is not needed; every migration simply applies in order.

## Scheduled jobs (timers)

If the project shipped systemd timers, map them to **host cron** on the Pi running a
binary/command inside the already-published image:

```cron
# /etc/cron.d/<service>-jobs   (on the Pi)
*/15 * * * *  root  cd /opt/stacks/<service> && docker compose run --rm <service> /usr/local/bin/<job>
```

Alternative without cron: an extra service in `compose.yaml` with its own loop/scheduler
(e.g. a binary using a ticker) and `restart: unless-stopped`. Pick host cron for
spaced-out tasks (less memory) and a resident service if you need second-level precision
or in-memory state between runs.
