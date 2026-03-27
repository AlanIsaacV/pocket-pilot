# Module Map

This document outlines the dependencies between internal modules and external libraries for the Pocket Pilot project.

## Core Dependency Graph
- **Protobuf Contracts:** Shared by both Backend and Frontend.
- **Backend (Go):**
    - `Handler` depends on `Repository` and generated Proto code.
    - `Repository` depends on `jackc/pgx/v5` for PostgreSQL access.
    - `Server` depends on all entity `Handlers`.
- **Frontend (Flutter):**
    - `ViewModel` depends on `Repository`.
    - `Repository` depends on `LocalStore` and `SyncOutbox`.
    - `SyncHandler` depends on `LocalStore` and `RemoteService`.
    - `RemoteService` depends on generated gRPC Proto code.
    - App-level controllers (e.g., theme preference) may depend on a feature `Repository` and are provided from app root.

## Key External Libraries
### Backend (Go)
- `google.golang.org/grpc`: Core gRPC library.
- `github.com/jackc/pgx/v5`: PostgreSQL driver and connection pool.
- `github.com/google/uuid`: UUID generation and parsing.

### Frontend (Flutter)
- `grpc`: Dart gRPC implementation.
- `sqflite`: Local SQLite storage.
- `provider`: State management.
- `connectivity_plus`: Monitoring network state.
- `fixnum`: Handling 64-bit integers from gRPC.
