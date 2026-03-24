# Synchronization Protocol

Pocket Pilot uses an offline-first strategy based on an Outbox pattern for writes and a Delta Pull pattern for reads.

## Core Concepts

### 1. Delta Pull (Pull)
- **Mechanism:** The client maintains a `last_synced_at` timestamp for each entity type.
- **Request:** The client calls `List<Entity>(updated_since=last_synced_at)`.
- **Response:** The server returns all records (including soft-deleted ones) modified after that time.
- **Pagination:** Delta requests are not paginated to ensure all changes are captured in one sync cycle. Full sync requests (where `updated_since` is nil) are paginated.

### 2. Sync Outbox (Push)
- **Mechanism:** Every local write (insert/update/delete) is enqueued in a `sync_outbox` table in SQLite.
- **Deduplication:** The outbox only keeps the latest operation per `(entity_type, entity_id)` to avoid redundant network calls.
- **Retry Logic:** Each entry has a `retry_count` (max 3 retries). If all retries fail, the entry is marked as permanently failed for manual intervention or full re-sync.

### 3. Last Write Wins (LWW)
- **Rule:** The version with the most recent `updated_at` timestamp (UTC) is the source of truth.
- **Server Implementation:** `INSERT ... ON CONFLICT (id) DO UPDATE SET ... WHERE accounts.updated_at < EXCLUDED.updated_at`.
- **Conflict Handling:**
    - If `conflict_resolved=false`: The client's version was accepted by the server.
    - If `conflict_resolved=true`: The server has a newer version. The server returns its current version, and the client **MUST** overwrite its local data with this server version.

### 4. Soft Deletes
- **Flag:** Records are never physically deleted from the server. They use a `deleted_at` timestamp.
- **LWW for Deletions:** Deleting a record is just another LWW update where the `deleted_at` timestamp is set.
