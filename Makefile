.PHONY: up down migrate proto tidy run build

## ── Docker ────────────────────────────────────────────────────────────────────
up:
	docker-compose up -d
	@echo "PostgreSQL ready on :5432"

down:
	docker-compose down

## ── Database ──────────────────────────────────────────────────────────────────
# Waits for the healthcheck to pass, then applies the migration.
migrate: up
	@echo "Waiting for PostgreSQL to be healthy..."
	@until [ "$$(docker inspect --format='{{.State.Health.Status}}' pocket-pilot-db 2>/dev/null)" = "healthy" ]; do sleep 1; done
	@for file in backend/migrations/*.sql; do \
		echo "Applying $$file"; \
		docker exec -i pocket-pilot-db psql \
			-U $${POSTGRES_USER:-pocket_pilot} \
			-d $${POSTGRES_DB:-pocket_pilot} \
			< $$file; \
	done
	@echo "Migrations applied."

## ── Code generation ───────────────────────────────────────────────────────────
proto:
	./scripts/gen_proto.sh

## ── Go ────────────────────────────────────────────────────────────────────────
tidy:
	cd backend && go get -u ./cmd/server && go mod tidy

run:
	cd backend && go run ./cmd/server

build:
	cd backend && go build -o bin/server ./cmd/server
