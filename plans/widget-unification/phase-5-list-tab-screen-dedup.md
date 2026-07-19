# Phase 5 — list-tab-screen-dedup: collapse the yield_configs and transaction_templates screen/tab pairs

## Goal

Each of `yield_configs` and `transaction_templates` maintains two near-identical files — a
standalone `*_screen.dart` (with `Scaffold`) and a bare `*_list_tab.dart` (for tab embedding) —
duplicating list, card, swipe, and confirm logic (~600 LOC total). Extract one embeddable list
body per feature, consumed by both wrappers, so future changes land once.

## Prerequisites

Phase 0. Phase 1 strongly recommended first (the duplicated swipe backgrounds and confirm dialogs
inside these files will already be shared primitives, shrinking what's left to dedup).

## Scope

### In scope
- `features/yield_configs/ui/`: extract a shared list-body widget; `yield_configs_screen.dart` and
  `yield_configs_list_tab.dart` become thin wrappers (or one file with an `embedded` flag —
  decide during implementation).
- Same for `features/transaction_templates/ui/`.
- These extracted bodies stay **feature-local** — this is intra-feature dedup, not a shared-library
  addition.

### Out of scope for this phase
- Deduplicating across the two features (their list bodies are similar in shape but render
  different entities — do NOT force a generic abstraction).
- Routing changes beyond what the wrapper split requires.
- Any other feature's screen/tab pairs (none were flagged by the survey).

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `frontend/lib/src/features/yield_configs/ui/yield_configs_list_body.dart` (_name TBD_) | create | single list/card/swipe/confirm implementation |
| `frontend/lib/src/features/yield_configs/ui/yield_configs_screen.dart` | modify | thin `Scaffold` wrapper around the body |
| `frontend/lib/src/features/yield_configs/ui/yield_configs_list_tab.dart` | modify | thin embedded wrapper (or deleted if the flag approach wins) |
| `frontend/lib/src/features/transaction_templates/ui/transaction_templates_list_body.dart` (_name TBD_) | create | single implementation |
| `frontend/lib/src/features/transaction_templates/ui/transaction_templates_screen.dart` | modify | thin wrapper |
| `frontend/lib/src/features/transaction_templates/ui/transaction_templates_list_tab.dart` | modify | thin wrapper (or deleted) |

## Steps

### 5.1 — Diff each pair to catalogue real divergences

> Expand during implementation: the survey says the pairs are "line-for-line equivalent" for swipe
> backgrounds and largely equivalent elsewhere — verify with `diff` and list any real differences
> (AppBar actions, FAB, route pushes) that become wrapper responsibilities.

### 5.2 — Extract the yield_configs body, wire both wrappers

### 5.3 — Extract the transaction_templates body, wire both wrappers

### 5.4 — Verification pass

Both entry points per feature (standalone route and embedded tab) render and behave identically to
before.

## Success criteria

- No duplicated list/card/confirm logic between each screen/tab pair (diff-verified: wrappers hold
  only scaffolding).
- Both navigation entry points still work for both features (manual check via router routes).
- `flutter analyze` clean; `flutter test` passes.
- Net LOC reduction ≥ ~400 across the two features.

## Context budget

Single session.
