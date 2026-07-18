# Pocket Pilot

Pocket Pilot is an offline-first personal finance application built with Flutter and Go. It uses gRPC for synchronization and follows a Last Write Wins (LWW) conflict resolution strategy.

## Documentation for Developers and Agents
To maintain consistency across different AI agents and development environments, all architectural and technical documentation is centralized in the `docs/` directory.

- **[docs/architecture.md](docs/architecture.md):** The starting point for understanding the system, its layout, and data flow.
- **[docs/features/_index.md](docs/features/_index.md):** Index of documented features.
- **[CLAUDE.md](CLAUDE.md) / [AGENTS.md](AGENTS.md):** Context routers for AI agents (GEMINI.md → AGENTS.md).

## Project Structure
- `backend/`: Go gRPC server and PostgreSQL repository.
- `frontend/`: Flutter mobile application and SQLite local store.
- `proto/`: Protobuf definitions for gRPC services.
- `scripts/`: Utility scripts for code generation and maintenance.

## Quick Start
Refer to [docs/architecture.md](docs/architecture.md) for a detailed view of the system's architecture, and [docs/runbook.md](docs/runbook.md) for local setup (Docker + make targets).
