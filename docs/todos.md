# Deferred TODOs

This file indexes code-level TODOs that are intentionally deferred and must be revisited when their dependency is implemented. Each section groups TODOs by the feature or concept they depend on.

---

## Test suite

- **Pre-existing failure in `frontend/test/statistics_category_list_row_test.dart`** ("renders name,
  current month amount, avg, and up arrow for Trend.up"): expects text containing `"prom"` that
  `category_list_row.dart` no longer renders after the stats refactor (commits `be4af04`/`e602009`).
  Verified unrelated to frictionless-capture phase 1 via `git stash` (fails identically on `ea40ba0`).
  Fix the test — or restore the avg label if it was removed by mistake — so the suite signal stays
  trustworthy. Recorded 2026-07-18.
