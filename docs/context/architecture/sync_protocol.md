# Synchronization Protocol

Pocket Pilot uses an offline-first strategy based on an Outbox pattern for writes and a Delta Pull pattern for reads.

## Core Concepts

### 1. Delta Pull (Pull)
- **Mechanism:** The client maintains a `last_synced_at` timestamp for each entity type.
- **Request:** The client calls `List<Entity>(updated_since=last_synced_at, page=PageRequest(page_size, page_token))`.
- **Response:** The server returns all records (including soft-deleted ones) modified after that time, capped by `page_size`, plus a `PageResponse.next_page_token` when more records remain.
- **Pagination:** ALL list endpoints are paginated on the backend (default `page_size=20`, max `100`). Both full sync (`updated_since=nil`) and delta sync must loop through pages until `next_page_token` is empty — otherwise only the first page is persisted and the remaining records are silently lost. Sync handlers accumulate `SyncItem`s across pages and commit a single `last_synced_at` derived from the server's `synced_at` timestamp of the final response.

### 2. Sync Outbox (Push)
- **Mechanism:** Every local write (insert/update/delete) is enqueued in a `sync_outbox` table in SQLite.
- **Deduplication:** The outbox only keeps the latest operation per `(entity_type, entity_id)` to avoid redundant network calls.
- **Retry Logic:** Each entry has a `retry_count` (max 3 retries per cycle). At the start of every sync cycle, `resetAllRetries()` resets all retry counts to 0, making previously failed entries eligible again. The max-retries limit only prevents infinite loops within a single cycle — entries are never permanently abandoned.
- **Push Order:** Handlers are sorted by `syncOrder` to respect FK dependencies: accounts (1) → categories (2) → tags (3) → transaction_templates (4) → transactions (5) → user_preferences (6). This prevents FK errors when pushing entities that reference other entities.
- **Concurrent Sync Calls:** If `sync()` is requested while another sync cycle is running, the request is coalesced and an additional pass runs immediately after the current one finishes (no request is dropped).

### 2.1 Scheduled Generation Cycle
- **Orchestration:** App-level scheduled generation runs as `sync -> generate -> sync`.
- **Why:** First sync pulls latest templates/references, generation creates deterministic local occurrences, second sync pushes generated transactions and template cursor updates.
- **Coalescing:** Overlapping generation-cycle requests are coalesced to one queued extra pass.

### 3. Last Write Wins (LWW)
- **Rule:** The version with the most recent `updated_at` timestamp (UTC) is the source of truth.
- **Server Implementation:** `INSERT ... ON CONFLICT (id) DO UPDATE SET ... WHERE accounts.updated_at < EXCLUDED.updated_at`.
- **Conflict Handling:**
    - If `conflict_resolved=false`: The client's version was accepted by the server.
    - If `conflict_resolved=true`: The server has a newer version. The server returns its current version, and the client **MUST** overwrite its local data with this server version.

### 4. Soft Deletes
- **Flag:** Records are never physically deleted from the server. They use a `deleted_at` timestamp.
- **LWW for Deletions:** Deleting a record is just another LWW update where the `deleted_at` timestamp is set.
