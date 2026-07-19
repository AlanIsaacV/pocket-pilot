# 0009 — Widget unification intentionally converges divergent UI behavior

- **Status**: Accepted
- **Date**: 2026-07-19

## Context

Selection/input UI was re-implemented feature by feature: confirmation dialogs existed ~23 times,
swipe backgrounds 11 times, section labels 5 times, plus 5 raw `showDatePicker` calls and a private
copy of the expense/income toggle — with small behavioral divergences (labels in different
languages, different margins, button styles, toggle padding) that broke UX uniformity. A strictly
behavior-preserving refactor would have had to parameterize every divergence, preserving the
inconsistencies it set out to remove.

## Decision

The widget-unification plan (`plans/widget-unification/`) deliberately relaxes the "refactor
preserves behavior" golden rule, per the owner's request:

> Where duplicated widgets diverge, all call sites converge on one canonical variant. A screen that
> genuinely needs special behavior gets it via explicit parameters — never via a private copy.

Companion rules: **Spanish is the canonical UI label language**, and canonical variants are chosen
from the strongest existing implementation (e.g. transactions' swipe background with explicit
margins; the shared `TransactionTypeToggle`'s 10px padding).

First enacted by phase 1 (2026-07-19): `showConfirmDialog` replaced 23 inline confirms (dialog
chrome/button styles converged), `DismissibleBackground` replaced 11 swipe backgrounds (margins
converged; an `edit` variant was added for categories' edit swipe), `FormSectionLabel` replaced 5
labels, `pickDate()` (extended with optional `firstDate`/`lastDate`) replaced all raw
`showDatePicker` calls, and `category_form_screen`'s private toggle copy was deleted.

Phase 2 (2026-07-19): `showCurrencyPicker` (`ui/widgets/currency_picker.dart`) replaced the ~9
per-form `_showCurrencySheet()` implementations across all 8 currency-selecting forms — the
templates form's flow was the canonical donor — and the private
`_ScrollableBottomSheet`/`_SheetItem` copies in accounts/budgets/goals were deleted (net −429 LOC).

Phase 3 (2026-07-19): `showAccountPicker` (`ui/widgets/account_picker.dart`) replaced the ~8
per-form account sheets (transaction, transfer, template ×2, debt, yield-config, lot, CSV-mapping).
Converged intentionally: `accountIconForType` row icons everywhere (debt's and lot's hardcoded
icons removed), a new uniform trailing check on the selected account, a contact-excluding default
filter (fixes CSV-mapping's oversight of listing contacts), the transfer form now excludes the
counterpart account per leg, and `advanced_filters`' EN labels converged to ES ("Cuenta"/"Todas").
Two dropdown sites stay dropdowns as documented exceptions (`advanced_filters` needs an "all"
option; `pending_review_sheet` is a dense sheet-within-sheet with a `FormField` validator).

## Alternatives considered

- **Behavior-preserving refactor** (parameterize every existing divergence) — rejected: the
  divergences are accidents, not requirements; preserving them defeats the goal of UX uniformity
  and bloats the shared widgets' APIs.
- **Leave duplicates in place** — rejected: ~30 scattered copies meant every UX change had to be
  applied N times and drifted immediately.

## Consequences

- Micro behavior changes shipped intentionally (margins, text sizes, dialog wording/button styles,
  toggle padding, EN→ES labels) — visual QA should expect them after each unification phase.
- New grep-enforced invariants (see `docs/conventions.md` § Frontend UI conventions): no inline
  `showDialog<bool>` confirms, no inline swipe backgrounds, no raw `showDatePicker` outside
  `form_date_utils.dart`.
- Phases 2–5 (currency/account pickers, `TemporalPageView`, list/tab dedup) follow the same
  convergence contract.
