# Pocket Pilot

Pocket Pilot is an offline-first personal finance application built with Flutter and Go. It uses gRPC for synchronization and follows a Last Write Wins (LWW) conflict resolution strategy.

## Documentation for Developers and Agents
To maintain consistency across different AI agents and development environments, all architectural and technical documentation is centralized in the `docs/context/` directory.

- **[docs/context/MANIFEST.md](docs/context/MANIFEST.md):** The starting point for understanding the system and its conventions.
- **[GEMINI.md](GEMINI.md) / [CLAUDE.md](CLAUDE.md):** Context pointers for AI agents.

## Project Structure
- `backend/`: Go gRPC server and PostgreSQL repository.
- `frontend/`: Flutter mobile application and SQLite local store.
- `proto/`: Protobuf definitions for gRPC services.
- `scripts/`: Utility scripts for code generation and maintenance.

## Quick Start
Refer to [docs/context/architecture/system_overview.md](docs/context/architecture/system_overview.md) for a detailed view of the system's architecture.
