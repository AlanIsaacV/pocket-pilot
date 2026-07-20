# syntax=docker/dockerfile:1
# ── Go multi-stage build ────────────────────────────────────────────────────
# Cross-compiles to the target platform (arm64 for the Pi) using buildx's build
# args. The compile runs NATIVELY on the amd64 runner (fast, no emulation); only
# the final binary(ies) land in a minimal arm64 image.
# (scaffold.py fills in the Go version and the entrypoints from go.mod.)

FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
# Builds both entrypoints into /out/: `server` (the gRPC daemon, the default
# CMD) and `migrate` (one-shot schema migrator, run via the compose "tools"
# profile). The migrate binary embeds migrations/*.sql — see migrations/embed.go.
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w" -o /out/ ./cmd/server ./cmd/migrate

# Minimal final image: no shell, non-root user.
FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /out/ /usr/local/bin/
USER nonroot:nonroot
CMD ["/usr/local/bin/server"]
