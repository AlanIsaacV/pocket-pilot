# 0006. No NLS-triggered one-shot background enqueue in v1 (periodic task only)

- **Date**: 2026-07-18
- **Status**: Accepted

## Context

Phase 6 of frictionless-capture (background capture) left open whether
`BankNotificationListenerService` (Kotlin) should enqueue a one-shot WorkManager run when a bank
notification arrives, giving minutes-level capture latency instead of the ~6h periodic window
(see ADR 0005, which deferred this decision to session B).

## Decision

Do not enqueue background work from the NLS in v1. Background capture runs only on the periodic
~6h WorkManager task registered in `main.dart`.

## Rationale

- The `workmanager` plugin exposes no public Kotlin API to enqueue a Dart task: doing it would
  mean replicating the plugin's internal input-Data contract for
  `dev.fluttercommunity.workmanager.BackgroundWorker` — an undocumented internal that can break
  on any plugin upgrade.
- A one-shot could fire on a cold isolate before `main()` ever seeded parsers (fresh install /
  cleared data), producing a run that silently processes nothing.
- The phase's stated goal is eventual capture (hours); the periodic task already meets it.

## Consequences

- Capture latency with the app closed is bounded by the periodic window (~6h), not minutes.
- The seeding gap was closed independently in session B: the shared composition root
  (`capture_repository_factory.dart`) self-seeds parsers from asset, so this decision can be
  revisited later without that blocker.
- Alternatives if revisited: plugin-internal `OneTimeWorkRequest(BackgroundWorker)` (fragile),
  a MethodChannel ping when the app process is alive (partial coverage), or a custom headless
  FlutterEngine invoked from Kotlin (heavy — reimplements what workmanager already does).
