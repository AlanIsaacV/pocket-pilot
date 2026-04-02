# Deferred TODOs

This file indexes code-level TODOs that are intentionally deferred and must be revisited when their dependency is implemented. Each section groups TODOs by the feature or concept they depend on.

---

## `TODO(liquidity)` — Depends on: Total Liquidity Calculation

**What is liquidity?** The sum of available balances across all user accounts. Once this value is computable, the goals feature can switch from time-based progress to real financial progress.

**When to revisit:** When a `LiquidityService` or equivalent is implemented that can return the user's total liquid balance.

| File | Line | Current behavior | Target behavior |
|------|------|-----------------|-----------------|
| `frontend/lib/src/features/goals/domain/goal.dart` | ~133 | `progressPercentageAt()` uses elapsed months / total months | Use `liquidezAcumulada / targetAmountCents * 100` |
| `frontend/lib/src/features/goals/domain/goal.dart` | ~160 | `monthlyRequiredCentsAt()` uses full `targetAmountCents` | Subtract assigned liquidity: `targetAmountCents - liquidezAsignada` |
| `frontend/lib/src/features/goals/domain/goal.dart` | ~173 | `isOverdueAt()` only checks if target date has passed | Also check: not overdue if liquidity >= targetAmountCents |

**Additional UI changes needed:**
- `goals_list_tab.dart` — restore "Completada" badge when liquidity covers the goal
- `goals_list_tab.dart` — progress bar should reflect liquidity coverage, not just time
