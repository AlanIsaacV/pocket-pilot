# Phase 4 — temporal-page-view: one date-range filter widget over a shared filter-state interface

## Goal

Collapse the two wholesale copies of `temporal_page_view.dart` (~340 LOC each, transactions vs
dashboard) into one shared widget parameterized by a small filter-state interface that both
`TransactionFilterViewModel` and `DashboardFilterViewModel` implement. Labels converge on Spanish
(the dashboard variant) — a visible, intended behavior change for the transactions filter.

## Prerequisites

Phase 0. Independent of phases 1–3.

## Scope

### In scope
- NEW shared `TemporalPageView` in `lib/src/ui/widgets/` (quick ranges, period pager, granularity
  sheet, custom start/end dates, chips, dots — the survey found the two copies structurally
  identical).
- A minimal abstraction (`TemporalFilterState` or similar) exposing the fields/callbacks the
  widget needs; both view models implement it.
- Deletion of both feature-local copies; Spanish labels everywhere.
- Decide the final home of `dashboard_filter_sheet.dart`/`DashboardFilterViewModel` (already
  consumed cross-feature by statistics + cashflow): move to `lib/src/ui/` or stay put — decide
  during implementation and record it.

### Out of scope for this phase
- Changing filter semantics (quick-range definitions, granularity options, persistence).
- Merging `TransactionFilterViewModel` and `DashboardFilterViewModel` into one class — only the
  interface unifies.
- `FilterSheet`/`AdvancedFilters` composition in transactions (they just consume the new widget).

## Files to create / modify

| Path | Action | Responsibility |
|---|---|---|
| `frontend/lib/src/ui/widgets/temporal_page_view.dart` | create | the unified widget + `TemporalFilterState` interface |
| `frontend/lib/src/features/transactions/ui/widgets/temporal_page_view.dart` (10–351) | delete | replaced by shared widget |
| `frontend/lib/src/features/dashboard/ui/widgets/temporal_page_view.dart` (8–348) | delete | replaced by shared widget (canonical Spanish labels donor) |
| `frontend/lib/src/features/transactions/ui/widgets/filter_sheet.dart` | modify | consume shared widget; `TransactionFilterViewModel` implements the interface |
| `frontend/lib/src/features/dashboard/ui/widgets/dashboard_filter_sheet.dart` | modify | consume shared widget; `DashboardFilterViewModel` implements the interface |
| `frontend/lib/src/features/transactions/ui/transaction_filter_view_model.dart` (_TBD exact path_) | modify | implement the interface |
| `frontend/lib/src/features/dashboard/ui/dashboard_filter_view_model.dart` (_TBD exact path_) | modify | implement the interface |

## Steps

### 4.1 — Diff the two copies precisely

Confirm the survey's claim (identical except labels + view-model type) with an actual `diff`; any
real divergence found becomes an explicit interface member or parameter.

### 4.2 — Extract the interface and the shared widget

> Expand during implementation: interface surface — which getters/setters/callbacks the widget
> actually touches on each view model.

### 4.3 — Wire both consumers, delete both copies

### 4.4 — Verification pass

Both filter surfaces (transactions filter sheet, dashboard/statistics/cashflow filter) behave as
before, now with Spanish labels in transactions.

## Success criteria

- Exactly one `temporal_page_view.dart` exists, under `lib/src/ui/widgets/`.
- `grep -rn "Week\b\|'Month'\|'Year'" frontend/lib/src/` shows no English granularity labels in
  the filter UI.
- Transactions and dashboard filters both drive their existing view models correctly (manual
  check of quick ranges, pager, granularity, custom range).
- Widget test for the shared widget passes; `flutter analyze` clean; `flutter test` passes.
- Net LOC reduction ≥ ~300.

## Context budget

Single session.
