# 0008 — Single canonical shared-widget library in `frontend/lib/src/ui/`

- **Status**: Accepted
- **Date**: 2026-07-19

## Context

Cross-feature widgets were de-facto homed in `features/transactions/ui/` (form widgets, date
utils, transfer/transaction form widgets, the shared category pickers) plus icon helpers in
`features/accounts/ui/` and `features/categories/ui/`. They were imported by ~10 other features,
creating an accidental dependency of nearly every feature on `transactions`, while the declared
shared home `lib/src/ui/` held only three generic widgets.

## Decision

Relocate the de-facto shared widgets to `lib/src/ui/` — `ui/widgets/` for widget/helper files and
`ui/screens/category_picker/` for the shared picker screens — and adopt the layering rule:

> A widget used by 2+ features lives in `lib/src/ui/`; a feature's `ui/` never imports another
> feature's `ui/`.

Enacted by phase 0 of `plans/widget-unification/` (2026-07-19) as a pure relocation — zero
behavior change; only file paths and import lines moved.

## Alternatives considered

- **Leave the widgets in `features/transactions/ui/`** — rejected: perpetuates the cross-feature
  dependency on `transactions` and gives new shared widgets (phases 1–4) no natural home.
- **Move `category_icon_data.dart` to `core/`** (it has one non-UI consumer,
  `categories/data/category_seeder.dart`) — rejected to keep phase 0 a pure relocation; the seeder
  already imported a `ui/` path before the move, so layering is not worsened.

## Consequences

- Later widget-unification phases (shared confirm dialog, currency/account pickers,
  `TemporalPageView`) are born in `lib/src/ui/` next to their building blocks.
- `categories/data/category_seeder.dart` now imports `ui/widgets/category_icon_data.dart` — a
  data→ui import kept deliberately (pre-existing shape, single consumer).
- Exception resolved by phase 4 (2026-07-19): `dashboard_filter_sheet.dart` and
  `dashboard_filter_view_model.dart` moved (`git mv`) to `ui/widgets/` — they were imported
  cross-feature by 11 files in statistics/cashflow/dashboard-summary, violating the layering rule;
  16 import sites updated, class names unchanged.
