# Plan: widget-unification

The Flutter frontend grew feature by feature, and selection/input UI was re-implemented along the
way: currency selection exists ~9 times, account selection ~8 times, confirmation dialogs ~15
times, and a 340-line date-range filter widget is duplicated wholesale between two features — with
small behavioral divergences (labels in different languages, different post-selection side effects,
different margins) that break UX uniformity. Meanwhile the de-facto shared widget library lives
inside `features/transactions/ui/`, imported cross-feature by ~10 other features, while the
declared shared home `lib/src/ui/` holds only three generic widgets.

This plan consolidates one canonical shared widget library under `frontend/lib/src/ui/` and
unifies each duplicated pattern behind a single widget with one canonical behavior. **This is
deliberately not a behavior-preserving refactor**: where occurrences diverge today, they converge
on the chosen canonical behavior, and any screen that genuinely needs special behavior gets it via
explicit parameters. Expected outcome: a smaller codebase (rough estimate: 1,500–2,000 net LOC
removed) and one place to change each pattern in the future.

## How to use this plan

Each phase is in its own file and is **self-contained**: minimum context, files to create/modify
with absolute paths, ordered steps, "done" criteria. This lets you execute each phase in a separate
Claude Code session without saturating context.

To start a phase, open a new session, read this README for shared context, then read the phase
file and execute it. Live phase/task status is tracked in `plan.json` (run `plan_state.py status
widget-unification` to see it) and updated by the `implement` and `update` skills — not by
hand-editing this README.

## Status

- **Status**: planning
- **Created**: 2026-07-19
- **Owner**: Alan Vazquez

## Objective

Unify duplicated frontend widgets (currency/account pickers, temporal range filter, confirmation
dialogs, swipe backgrounds, form labels, type toggles) into one canonical library under
`frontend/lib/src/ui/`, converging divergent behaviors on a single explicit contract per pattern.

## Scope

### In scope
- Relocating the de-facto shared widgets from `features/transactions/ui/` (and `accounts`/
  `categories` icon helpers) into `frontend/lib/src/ui/`.
- Shared `CurrencyPicker` and `AccountPicker` adopted by every form that selects those entities.
- One shared `TemporalPageView` replacing the two wholesale copies (dashboard + transactions).
- Shared small primitives: confirmation dialog, dismissible (swipe) background, form section
  label, `pickDate()` adoption where it is bypassed, single `TransactionTypeToggle`.
- Collapsing the near-duplicate screen/list_tab pairs in `yield_configs` and
  `transaction_templates`.
- Intentional behavior convergence: unified labels (Spanish), margins, sheet chrome, and
  post-selection side effects made explicit per call site.

### Out of scope (explicit non-goals)
- **Amount input unification** (calculator `NumPad` vs plain `TextFormField`) — a product/UX
  decision, deferred to its own effort.
- **Category picker** — `CategoryPickerScreen` is already the shared single-select picker;
  `CategoryMultiPicker` is intentionally distinct (multi-select filter). Only their *location*
  moves (phase 0); no behavior work.
- Category *selected-value rows* per form (chips vs `InputDecorator` vs `DetailRow`) — the
  exploration confirmed these diverge intentionally per screen density/UX.
- Icon/color pickers in `category_form_screen.dart` — single-use today, nothing to unify.
- Any backend, proto, or sync changes. Any visual redesign beyond converging existing variants.

## Phase map

| # | File | Goal |
|---|---|---|
| 0 | [phase-0-ui-library-home.md](phase-0-ui-library-home.md) | Move de-facto shared widgets into `lib/src/ui/` (pure relocation, no behavior change) |
| 1 | [phase-1-shared-primitives.md](phase-1-shared-primitives.md) | Shared confirm dialog, swipe background, section label, `pickDate` adoption, single type toggle |
| 2 | [phase-2-currency-picker.md](phase-2-currency-picker.md) | One `CurrencyPicker` flow adopted by all ~9 currency-selecting forms |
| 3 | [phase-3-account-picker.md](phase-3-account-picker.md) | One `AccountPicker` sheet adopted by all ~8 account-selecting forms |
| 4 | [phase-4-temporal-page-view.md](phase-4-temporal-page-view.md) | Single `TemporalPageView` widget over a shared filter-state interface |
| 5 | [phase-5-list-tab-screen-dedup.md](phase-5-list-tab-screen-dedup.md) | Collapse yield_configs + transaction_templates screen/list_tab near-duplicate pairs |

> Live status (plan / phases / tasks) lives in `plan.json`, not here — run
> `python /Users/alan/.trii-ai/plugins/plan-feature/scripts/plan_state.py status widget-unification`
> to see it.

After phase 1 the app already has uniform dialogs/swipe affordances everywhere; phases 2–5 are
independent of each other and can be reordered if needed (all depend only on phase 0).

## Cross-service impact

None — isolated to this repo, and within it to `frontend/` only. No proto, backend, SQLite, or
sync changes.

## Target architecture

```
frontend/lib/src/ui/
├── app.dart, router.dart                    # unchanged
├── screens/…                                # unchanged (+ category picker screens move here)
│   └── category_picker/
│       ├── category_picker_screen.dart      # moved from features/transactions/ui/
│       └── category_multi_picker.dart       # moved from features/transactions/ui/widgets/
└── widgets/
    ├── pp_screen_state.dart                 # existing
    ├── form_app_bar_actions.dart            # existing
    ├── notification_bell.dart               # existing
    ├── form_widgets.dart                    # moved (ScrollableBottomSheet, SheetItem, NumPad, TagsSection…)
    ├── form_date_utils.dart                 # moved (pickDate, formatDateDisplay)
    ├── transaction_form_widgets.dart        # moved (TransactionTypeToggle, TransactionCategorySection)
    ├── transfer_form_widgets.dart           # moved (TransferCard, TransferModeToggle…)
    ├── account_icon.dart                    # moved (accountIconForType)
    ├── category_icon_data.dart              # moved (icon hex helpers)
    ├── confirm_dialog.dart                  # NEW (phase 1)
    ├── dismissible_background.dart          # NEW (phase 1)
    ├── form_section_label.dart              # NEW (phase 1)
    ├── currency_picker.dart                 # NEW (phase 2)
    ├── account_picker.dart                  # NEW (phase 3)
    └── temporal_page_view.dart              # NEW (phase 4, replaces 2 copies)
```

Rule going forward: a widget used by 2+ features lives in `lib/src/ui/`; `features/<f>/ui/` never
imports another feature's `ui/`.

## Conventions

- Test command: `cd frontend && flutter test`; static check: `cd frontend && flutter analyze`.
- Format with `dart format` before committing (repo convention).
- Category icons/colors must keep using the hex helpers (`CategoryIconData.iconFromHex`, sanitized
  color parsing) — see `docs/conventions.md` § Frontend UI conventions.
- `showModalBottomSheet` does not inherit providers — re-provide via `MultiProvider(.value)` when a
  new shared sheet needs view models (see `docs/architecture.md` critical notes).

## Open questions

- Phase 3: should the `DropdownButton`-based account fields in
  `features/transactions/ui/widgets/advanced_filters.dart` and
  `features/notification_capture/ui/pending_review_sheet.dart` adopt the shared `AccountPicker`
  sheet, or is a dropdown the right fit for filter/dense-review contexts? Decide during
  implementation with the user.
- Phase 0: whether `category_icon_data.dart` consumers outside UI (the category seeder) justify a
  different destination (e.g. `core/`) — verify import graph during implementation.
- Widget tests: the repo has few widget tests today. Each phase's success criteria ask for basic
  widget tests on the NEW shared components only; expanding coverage to call sites is not required.

## Decisions made during planning

- **Single canonical widget library in `lib/src/ui/`**, including relocating the de-facto shared
  widgets out of `features/transactions/ui/` — chosen over "leave them in place" to remove the
  cross-feature dependency on transactions. → ADR candidate
- **This plan intentionally changes behavior** where duplicates diverge: occurrences converge on
  one canonical behavior; special cases must become explicit parameters. The `refactor` golden rule
  ("preserve behavior") is knowingly relaxed, per the owner's request. → ADR candidate
- **Spanish is the canonical UI label language** (the transactions `temporal_page_view` copy uses
  English labels today; the dashboard copy's Spanish labels win).
- Canonical variants chosen from the survey: `transaction_templates`' currency flow (typed
  selection state, account-currency retention), transactions' `SheetItem` (supports trailing
  widget), transactions' swipe background (explicit margins, parameterized label/icon/color).
- Amount-input unification (NumPad vs TextFormField) explicitly deferred — product decision.
- No security or performance review gates: frontend-only UI refactor, no new endpoints, no hot
  paths, no data-shape changes.

## References

- `docs/architecture.md` § Frontend patterns, § Critical notes for collaborators
- `docs/conventions.md` § Frontend UI conventions, § Testing
- `docs/features/_index.md` (feature inventory)
- Exploration surveys (this planning session): Codex duplicated-widget survey + screen×selector
  inventory; their consolidated findings are embedded in the phase files' file tables.
