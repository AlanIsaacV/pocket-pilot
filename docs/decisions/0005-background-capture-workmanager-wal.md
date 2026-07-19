# 0005 — Background capture via workmanager + SQLite WAL/busy_timeout contract

- **Status**: accepted
- **Date**: 2026-07-18

## Context

Frictionless-capture phase 6 moves the notification-capture pipeline (parse → resolve →
auto-confirm) to background execution on Android, so the ledger fills itself without the app
being opened. Two mechanism candidates: the `workmanager` Flutter plugin vs a hand-rolled
native WorkManager `Worker` + headless `FlutterEngine` + `DartEntrypoint`. Additionally, a
background Dart isolate becomes a **third** concurrent accessor of `pocket_pilot.db`, alongside
the Kotlin `NotificationListenerService` (which opens a raw short-lived `SQLiteDatabase` handle
per write) and the foreground app — and neither side configured WAL or busy timeouts.

## Decision

1. **Mechanism: the `workmanager` plugin** (fluttercommunity, v0.9.x federated). It already
   implements exactly the native-WorkManager-plus-headless-engine pattern; rolling our own buys
   nothing for a periodic (~6h) DB batch job. Known narrow issues (Flutter 3.29 embedding
   breakage #588, Android 15 background networking #649) are workaroundable — and #649 is moot
   because of (3).
2. **Mandatory SQLite concurrency contract** (regardless of mechanism):
   `PRAGMA journal_mode=WAL` — persisted in the DB file, so the Kotlin NLS handle benefits too —
   plus per-connection `PRAGMA busy_timeout=5000` on **both** the Dart (`DatabaseHelper.onConfigure`,
   busy_timeout first, both via `rawQuery`) and Kotlin (`NotificationDb.kt`) sides, with short
   transactions in the background pipeline.
3. **No LLM fallback in background**: `BackgroundCaptureRunner`'s composition root omits
   `ParserRemoteService` — avoids LLM quota burn and network-in-background; unmatched
   notifications retry on the next foreground `processInbox()`.

## Alternatives considered

- **Native WorkManager + own headless engine**: full control, no third-party dependency with an
  irregular maintenance history — but ~200 lines of delicate engine/channel/lifecycle plumbing
  the plugin already solves. Reserve for when the plugin can't express a need.
- **`android_alarm_manager_plus`**: lower-level than WorkManager (no constraints/backoff), worse
  Doze behavior for spaced batch work.
- **`flutter_background_service`**: persistent foreground service — oversized for a 6-hourly
  batch job.
- **Keeping the LLM fallback in background**: more unattended coverage, but burns quota on a
  path with no user watching and hits workmanager #649 on Android 15.

## Consequences

- Existing installs convert to WAL on next open (one-time, file-persisted); every future
  connection — Dart or Kotlin — must set its own `busy_timeout` (see conventions.md).
- Background-created transactions sync on next foreground open (`SyncService` is
  foreground-only) — accepted for v1.
- Registration is guarded: a workmanager failure degrades to foreground-only capture instead of
  crashing cold start.
- Session B completed 2026-07-18: actionable notifications + real-device validation (the
  empirical WAL check with the NLS live came back positive). The NLS one-shot enqueue question
  this ADR deferred was resolved in [ADR 0006](0006-no-nls-oneshot-enqueue.md) — not doing it
  in v1. Device validation also caught that the Kotlin `busy_timeout` had shipped via `execSQL`
  (row-returning PRAGMA → throw → null connection): the WAL contract was inert on the NLS side
  until fixed to `rawQuery` (see postmortem-adjacent note in
  features/notification-capture.md § Components).
