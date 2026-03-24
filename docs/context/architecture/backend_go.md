# Backend (Go) Architecture

The backend is a gRPC server implemented in Go, using PostgreSQL as the persistent storage.

## Package Structure
- `cmd/server/`: The entry point for the gRPC server.
- `internal/`: Contains all business logic and service implementations.
    - `gen/proto/`: Generated code from `.proto` files. **Do not modify manually.**
    - `<entity>/`: Domain-specific packages (e.g., `account`, `transaction`).
        - `handler.go`: Implements the gRPC service interface. Converts to/from proto and calls the repository.
        - `repository.go`: Contains all database access logic using `pgxpool`.
    - `middleware/`: Common gRPC interceptors (e.g., Auth, Logging, Error Handling).
    - `database/`: Database connection and pool management.

## Key Patterns
### Repository Pattern
Each domain entity has a `Repository` struct responsible for SQL queries.
- **Methods:** `GetByID`, `List` (supports delta pull), `Upsert` (implements LWW), `SoftDelete`.
- **Naming:** Repository methods should mirror the domain's needs, while `scan` functions are used to map DB rows to Go structs.

### Handler Pattern
The `Handler` struct implements the gRPC server interface generated from Protobuf.
- **Responsibility:** Request validation, auth context extraction, data transformation (Proto <-> Go Domain), and calling the Repository.
- **Conversion:** Conversion functions (`toProto`, `fromProto`) should be kept as private helpers within the handler's file.

## Data Persistence (PostgreSQL)
- **Migrations:** All schema changes must be added to `backend/migrations/` as numbered SQL files.
- **Constraints:** Every table **MUST** have:
    - `id UUID PRIMARY KEY`
    - `user_id UUID NOT NULL`
    - `created_at TIMESTAMP WITH TIME ZONE NOT NULL`
    - `updated_at TIMESTAMP WITH TIME ZONE NOT NULL`
    - `deleted_at TIMESTAMP WITH TIME ZONE` (for soft deletes)
- **LWW:** Updates must use `ON CONFLICT (id) DO UPDATE SET ... WHERE table.updated_at < EXCLUDED.updated_at`.
