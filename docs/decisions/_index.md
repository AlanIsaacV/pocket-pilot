# Architectural decisions (ADRs)

One decision per file. Dates are the file's first-commit date.

| # | Title | Status | Date |
| - | ----- | ------ | ---- |
| [0001](0001-sync-strategy.md) | Sync strategy (LWW + Delta Pull) | Accepted | 2026-03-23 |
| [0002](0002-sync-coalescing-and-user-preferences.md) | Sync coalescing and user-preferences flush timing | Accepted | 2026-03-27 |
| [0003](0003-sync-preflight-cursors.md) | Sync preflight cursors | Accepted | 2026-04-16 |
| [0004](0004-transaction-source-provenance.md) | Transaction provenance as synced `source` column | Accepted | 2026-07-18 |
| [0005](0005-background-capture-workmanager-wal.md) | Background capture via workmanager + SQLite WAL/busy_timeout contract | Accepted | 2026-07-18 |
| [0006](0006-no-nls-oneshot-enqueue.md) | No NLS-triggered one-shot background enqueue in v1 (periodic task only) | Accepted | 2026-07-18 |
| [0007](0007-local-scheduled-notifications-over-fcm.md) | Local scheduled notifications over FCM push | Accepted | 2026-07-19 |
| [0008](0008-canonical-widget-library-location.md) | Single canonical shared-widget library in `frontend/lib/src/ui/` | Accepted | 2026-07-19 |
