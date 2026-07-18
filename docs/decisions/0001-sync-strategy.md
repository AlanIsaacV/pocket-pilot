# ADR 0001: Sync Strategy (LWW + Delta Pull)

## Status
Accepted

## Context
The Pocket Pilot application needs to work offline-first. This requires a strategy for synchronizing data between the client (Flutter/SQLite) and the server (Go/PostgreSQL) and resolving conflicts that arise when the same record is modified on multiple devices or when the client has been offline for a long period.

## Decision
We chose a combination of **Last Write Wins (LWW)** for conflict resolution and **Delta Pull** for data synchronization.

### Why LWW?
- **Simplicity:** Easier to implement than CRDTs or operational transforms.
- **Timestamp-Based:** Uses `updated_at` (UTC) to determine the "winning" version.
- **Server Authority:** The server is the final arbiter of which version is newest.

### Why Delta Pull?
- **Efficiency:** Only sends changed records since the client's last successful sync.
- **Offline-Friendly:** Allows the client to catch up quickly after being offline.

## Consequences
- All records **MUST** have an `updated_at` timestamp in UTC.
- Clients must handle the `conflict_resolved` flag from the server and overwrite local data when a conflict is resolved in favor of the server's version.
- Soft deletes are required to sync deletions across devices via the Delta Pull process.
