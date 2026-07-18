# Plan: frictionless-capture

The user stopped registering transactions for weeks despite existing capture features (notification
capture, form prefill, voice assistant). The diagnosis from the planning session: the bottleneck is
not *capture* — it's the *approval step* plus coverage gaps. Suggestions pile up because approving
requires opening the app and answering the same two questions over and over (which account when the
notification carries no card digits; which category for multi-service merchants like Didi/Amazon),
and two accounts (RappiCard, cash) never produce notifications at all.

This plan removes the human from the loop wherever resolution is unambiguous, compresses review to
a single tap where ambiguity is real, and assigns each account the channel that actually fits it:
notifications for BBVA, monthly statement import for RappiCard, withdrawal-capture plus periodic
balance adjustment for cash. The final phase moves processing to the background so the ledger fills
itself without the app ever being opened.

Phases 1–3 attack the approval bottleneck (resolution → fast review → auto-confirm). Phases 4–5
close the coverage gaps (cash, RappiCard). Phase 6 removes the last dependency on opening the app.

## How to use this plan

Each phase is in its own file and is **self-contained**: minimum context, files to create/modify
with absolute paths, ordered steps, "done" criteria. This lets you execute each phase in a separate
Claude Code session without saturating context.

To start a phase, open a new session, read this README for shared context, then read the phase file
and execute it. Live phase/task status is tracked in `plan.json` (run `plan_state.py status
frictionless-capture` to see it) and updated by the `implement` and `update` skills — not by
hand-editing this README.

## Status

- **Status**: planning
- **Created**: 2026-07-18
- **Owner**: Alan Vazquez

## Objective

Make transaction registration require (near) zero discipline: unambiguous bank notifications become
transactions automatically, ambiguous ones need one tap, and the two notification-less accounts
(RappiCard, cash) are covered by monthly reconciliation instead of daily manual entry.

## Scope

### In scope
- Smarter suggestion resolution: pattern-based account fallback for digit-less notifications,
  longest-prefix category rules (fixes the DIDI vs DIDI FOOD flip-flop).
- Fast review UX: batch-approve resolved suggestions, quick-pick category chips.
- Conservative auto-confirm with provenance marker and settings toggle.
- Cash: ATM-withdrawal capture as transfer to a cash account + easy periodic balance adjustment
  (reusing the existing `AdjustBalanceSheet`).
- RappiCard: CSV-import duplicate detection + monthly import reminder.
- Background processing of the capture pipeline + actionable notifications (final phase).

### Out of scope (explicit non-goals)
- New notification parsers for ARQ/DolarApp — few transactions/month, not worth the effort
  (explicit user decision).
- CLI, Telegram bot, or any new *manual* capture channel — evidence shows manual channels don't
  survive busy weeks; the voice assistant (with `transaction_tool`) already covers this niche.
- Aggressive auto-confirm (auto-inserting uncategorized transactions) — revisit only after the
  conservative mode proves accurate.
- iOS notification capture (OS limitation).
- Admin UI to manage rules/mappings — only if the heuristics misbehave in practice.
- Porting the Python statement parsers into the app or backend.

## Phase map

| # | File | Goal |
|---|---|---|
| 1 | [phase-1-smart-resolution.md](phase-1-smart-resolution.md) | Suggestions arrive fully resolved: pattern→account fallback + longest-prefix category rules |
| 2 | [phase-2-fast-review.md](phase-2-fast-review.md) | A backlog of suggestions clears in seconds: batch approve + quick-pick category chips |
| 3 | [phase-3-auto-confirm.md](phase-3-auto-confirm.md) | Unambiguous suggestions become transactions with zero interaction, safely and reversibly |
| 4 | [phase-4-cash-account.md](phase-4-cash-account.md) | Cash covered without per-expense discipline: ATM-withdrawal capture + periodic adjustment |
| 5 | [phase-5-statement-reconciliation.md](phase-5-statement-reconciliation.md) | RappiCard stays current with one monthly action: import dedup + reminder |
| 6 | [phase-6-background-capture.md](phase-6-background-capture.md) | Pipeline runs without opening the app; ambiguous cases resolved from the notification shade |

> Live status (plan / phases / tasks) lives in `plan.json`, not here — run
> `python /Users/alan/.trii-ai/plugins/plan-feature/scripts/plan_state.py status frictionless-capture`
> to see it.

After phase 3 the app already "fills itself" every time it is opened — phases 4–6 extend coverage
and remove the need to open the app at all.

## Cross-service impact

None — isolated to this monorepo. Proto contract changes (phases 1 and 3) affect only the in-repo
Go backend and Flutter client, regenerated together via `make proto`.

## Glossary

| Term | Meaning |
|---|---|
| suggestion | A `PendingTransaction` produced by the capture pipeline, awaiting user review |
| resolution | Filling a suggestion's `suggested_account_id` / `suggested_category_id` from learned mappings/rules |
| pattern mapping | Account mapping keyed by `(bank_id, pattern_id)` — fallback when the notification has no card digits |
| ambiguous merchant | A merchant whose transaction history spans ≥2 distinct categories (e.g. Amazon) — never auto-confirmed |
| auto-confirm | Creating the `Transaction` directly from a fully-resolved, unambiguous suggestion, no user interaction |
| provenance | Marker on a transaction telling how it was created (manual / auto from notification) |

## Open questions

- **Provenance storage** (phase 3): synced `transactions.source` column (proto + dual migration) vs
  local-only marker. Leaning synced column — decide during phase 3.
- **Single-TDC assumption** (phase 1): pattern-level account mapping breaks if the user ever has two
  BBVA credit cards (digit-less notifications couldn't be distinguished). Holds today.
- **ATM withdrawal notification text** (phase 4): no real fixture captured yet — capture via
  `scripts/dump_captured_notifications.sh` before writing the pattern.
- **RappiCard monthly flow sustainability** (phase 5): the PDF→CSV step runs on desktop (`scripts/`,
  uv). Validate after the first monthly cycle; if it also piles up, consider a backend PDF-upload
  endpoint or email forwarding automation as a follow-up plan.
- **Background mechanism** (phase 6): `workmanager` Flutter plugin vs native WorkManager + headless
  Dart entrypoint. Decide during phase 6 after checking plugin health.

## Decisions made during planning

- Root cause is the **approval bottleneck**, not capture: attack approval and coverage instead of
  adding manual capture channels. CLI and Telegram bot explicitly rejected — a manual channel N+1
  depends on the same discipline that already failed, and the existing voice assistant (which can
  create transactions via `transaction_tool`) went unused. → ADR candidate
- **Per-account channel strategy**: notifications for BBVA (high volume, notifies well), monthly
  statement import for RappiCard (rarely notifies, PDF parser already exists), withdrawal-capture +
  balance adjustment for cash (never notifies), nothing for ARQ/DolarApp (too few transactions).
  → ADR candidate
- **Conservative auto-confirm gate**: only local-regex matches (never LLM-extracted) with account
  resolved, category resolved by rule, and merchant not ambiguous. Settings toggle, off by default.
- **Cash granularity is sacrificed by default** (hybrid): withdrawal + periodic adjustment is the
  baseline; per-expense detail stays optional via existing channels (voice, form).
- **First-word rule heuristic replaced by longest-prefix learning/matching** — the first-word rule
  makes "DIDI" and "DIDI FOOD" collide and flip-flop with each approval.
- **`purchase_tdc` notifications carry no card digits** (verified in `bbva_mx.json` v2), so account
  resolution needs a `(bank_id, pattern_id)` fallback learned from approvals.

## References

- `docs/architecture.md`
- `docs/features/notification-capture.md` (pipeline, tables, phase history, gotchas)
- `docs/features/csv-import.md` (Extract→Map→Insert pipeline phase 5 extends)
- `docs/features/bank-statement-parser.md` (RappiCard PDF parser feeding phase 5)
- `docs/features/adjustment-nature.md` (`nature: 'adjustment'` machinery reused in phase 4)
- `docs/features/ai-assistant.md` (LLM quota/model layout — auto-confirm must exclude LLM matches)
- `frontend/assets/parsers/bbva_mx.json` (v2 patterns — source of the digit-less TDC finding)
- `frontend/lib/src/features/accounts/ui/adjust_balance_sheet.dart` (existing reconciliation sheet,
  from `plans/2026-04-08-quick-reconciliation-ui.md`)
- `frontend/lib/src/features/ai_assistant/data/tools/` (existing client-side tools incl.
  `transaction_tool.dart`)
