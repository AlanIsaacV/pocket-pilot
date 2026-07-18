# Phase 6 — background-capture: the ledger fills itself with the app closed

## Goal

Remove the last dependency on opening the app: run the capture pipeline (parse → resolve →
auto-confirm) in the background, and surface what needs a human as actionable OS notifications —
"N transactions registered automatically" summaries, and 1-tap category questions for ambiguous
suggestions, answerable from the notification shade.

## Prerequisites

Phases 1–3 (the pipeline being run in background must already be trustworthy). Phase 4 recommended
(withdrawals then also flow unattended).

## Scope

### In scope
- Background execution of `processInbox()` + the auto-confirm gate: periodic (e.g. every 4–6 h)
  and/or NLS-triggered one-shot work; mechanism decided in 6.1.
- Summary notification after a background run that auto-confirmed ≥1 transaction.
- **Actionable suggestion notifications**: for a suggestion with a single ambiguity (category),
  post a notification with 2–3 category action buttons; tapping creates the transaction without
  opening the UI. "Open review" fallback action for everything else.
- SQLite concurrency audit: NLS Kotlin writer + background Dart isolate + foreground app.
- Battery sanity: batching, no wakelocks, respect Doze.

### Out of scope for this phase
- iOS (no notification capture there at all).
- Real-time per-notification processing guarantees — eventual (hours) is the target.
- Sync in background (transactions created in background sync on next app open, as today —
  evaluate only if it proves confusing).
- Rich notification UI beyond action buttons.

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| _TBD during implementation_ (background dispatcher: `workmanager` plugin registration or native WorkManager + headless Dart entrypoint) | create | periodic/one-shot background runs |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/lib/main.dart` | modify | background entrypoint registration |
| _TBD during implementation_ (`frontend/android/app/src/main/kotlin/app/pocketpilot/notifications/`) | modify | optional: enqueue one-shot work from `BankNotificationListenerService` |
| _TBD during implementation_ (local notifications: plugin setup + channel + action handling) | create | summary + actionable notifications |
| _TBD during implementation_ (`frontend/lib/src/features/notification_capture/` — headless pipeline runner) | create | app-independent `processInbox` + auto-confirm invocation with minimal DI |
| `/Volumes/rusty-drive/projects/pocket-pilot/frontend/test/` | create | pipeline-runner unit tests |

## Steps

### 6.1 — Mechanism spike

Evaluate `workmanager` plugin health vs native WorkManager + `FlutterEngine` headless execution;
verify SQLite open-from-isolate against the NLS's live connection (WAL mode? busy timeouts?).

> Expand during implementation: this decides the rest of the phase. The notification-capture doc's
> DB-handle gotchas (`docs/features/notification-capture.md` § Operational tooling) are required
> reading.

### 6.2 — Headless pipeline runner

Extract a minimal composition root (DB + stores + repository, no UI providers) callable from the
background entrypoint. LLM fallback in background: skip or keep? (leaning skip — retry on next
foreground open — to avoid quota burn and network in background).

### 6.3 — Summary + actionable notifications

Local notification channel; category action buttons resolve via background handler → create
transaction → cancel notification.

### 6.4 — Trigger wiring + battery pass

Periodic schedule + optional NLS one-shot enqueue; verify Doze behavior on a real device.

### 6.5 — Tests + device validation

## Success criteria

- With the app not opened: a bank notification arrives → within the scheduled window a suggestion
  exists (or a transaction, if unambiguous and auto-confirm ON) — validated on a real device with
  the app swiped away.
- Tapping a category action on the suggestion notification creates the transaction with that
  category; the notification dismisses; no app UI opens.
- Unit tests cover the headless runner's decision logic (auto vs notify vs leave pending).
- No new ANRs/crashes from concurrent DB access (device soak: NLS active + background run +
  foreground open simultaneously).
- `flutter test` green.

## Context budget

Likely **2 sessions**: (a) mechanism spike + headless runner, (b) actionable notifications +
device validation. Split when starting if the spike eats the session.

## Notes for the implementing session

- The NLS keeps its own SQLite handle alive independent of the Flutter process (documented
  negative result: pushed DB files get overwritten). Any background isolate must tolerate
  concurrent writes — prefer short transactions and retry on `SQLITE_BUSY`.
- Auto-confirmed-in-background transactions won't sync until the app opens (SyncService runs in
  foreground) — acceptable for v1; note it in the summary notification copy if confusing.
