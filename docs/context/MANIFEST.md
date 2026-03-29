# Project Context Manifest

This manifest serves as a map for all AI agents and developers working on the Pocket Pilot project. It categorizes technical documentation and conventions to ensure consistency across the codebase.

## How to use this Context
Before starting any task, identify the relevant domain (Backend, Frontend, or Proto) and read the corresponding files. If you make architectural decisions or change conventions during a session, log them in `.journal.md` and update the permanent documents at the end of the session.

## Document Index

### Core Architecture
- [architecture/system_overview.md](architecture/system_overview.md) - High-level system design (Client-Server-DB) and data flow.
- [architecture/sync_protocol.md](architecture/sync_protocol.md) - Detailed Offline-First protocol (Delta Pull, Outbox, LWW).
- [architecture/backend_go.md](architecture/backend_go.md) - Go gRPC server structure, Repository patterns, and PostgreSQL rules.
- [architecture/frontend_flutter.md](architecture/frontend_flutter.md) - Flutter app structure, State Management (Provider), and SQLite patterns.
- [architecture/transaction_templates_and_scheduled_generation.md](architecture/transaction_templates_and_scheduled_generation.md) - Transaction templates, scheduled generator (`sync -> generate -> sync`), deterministic UUIDv5 occurrences, transfer-pair reconciliation, and tags/template linkage behavior.

### Development Conventions
- [conventions/coding_standards.md](conventions/coding_standards.md) - Naming conventions, error handling, and style guides for Go and Dart.
- [conventions/proto_guidelines.md](conventions/proto_guidelines.md) - Rules for defining gRPC services and messages.
- [conventions/database_schema.md](conventions/database_schema.md) - Migration rules and schema design for PostgreSQL and SQLite.

### Decision Records & Dependencies
- [decisions/0001-sync-strategy.md](decisions/0001-sync-strategy.md) - Initial ADR: Why we chose Last Write Wins (LWW) and Delta Pull.
- [decisions/0002-sync-coalescing-and-user-preferences.md](decisions/0002-sync-coalescing-and-user-preferences.md) - Ensures concurrent sync requests are coalesced and preference saves flush to server immediately.
- [dependencies/module_map.md](dependencies/module_map.md) - Dependency graph between internal modules and external libraries.

### Session Logs
- [.journal.md](.journal.md) - Temporary log for technical decisions made during the current session.
