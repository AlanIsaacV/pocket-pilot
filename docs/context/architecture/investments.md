# Investments — Renta Variable (Acciones y ETFs)

Architecture doc for the investments feature: **variable-income assets** (stocks, ETFs) that complement the existing `yield_configs` feature (which covers fixed-income). Tracks holdings with buy/sell lots, computes FIFO and weighted-average cost on the fly, and syncs daily market prices from the backend.

**Status:** Fase 0 (contracts), Fase 1 (persistencia + sync scaffolding) and Fase 2 (UI CRUD + generator) implemented on 2026-04-21. Fases 3–6 pending — see [§Implementation Phases](#implementation-phases).

## Scope

**In scope (whole feature):**
- User-managed holdings (symbol + exchange) inside `investment` accounts.
- Per-holding lots recording individual buys and sells with commissions and optional FX rate.
- Deterministic transaction generation from lots (balance of the investment account reflects cash in/out).
- Daily market price sync from a backend cron (Yahoo Finance + Finnhub).
- On-the-fly FIFO and weighted-average cost calculations.
- Portfolio screen with market value, P&L realized / unrealized, distribution charts.
- Dashboard allocation (liquid / investment_active / investment_passive / debt / revolving).

**Out of scope:**
- Stock splits and corporate actions (deferred to a post-MVP phase).
- Dividend auto-detection — dividends are entered **manually** as income transactions with `holding_id` set and `nature='passive'`.
- Tax/capital-gains reports.
- Options/derivatives.
- Margin / leverage.
- Real-time (intraday) prices. Only end-of-day.

## Key Design Decisions

Anchor these in the doc so future sessions don't relitigate:

| Decision | Choice | Why |
|---|---|---|
| Price source | Backend Go cron hitting a free public API (Yahoo first, Finnhub fallback) | Centralized, daily, covers both US and BMV via `.MX` suffix |
| Cash model | **Implicit**: investment account balance = available cash | Matches broker mental model without a separate `cash_balance` column |
| Dividend capture | Manual income transaction with `holding_id` | Simpler than extending `yield_configs`; auto-detection deferred |
| Currency | Each holding has its own `currency_code`, independent of account | Allows mixed USD + MXN positions in a single account |
| Splits / corporate actions | Not in MVP | Can be applied manually by editing the lot quantities and prices |
| FIFO / weighted avg | Computed on the fly in Flutter from lots | Trivial compute volumes for personal portfolios; avoids materialization drift |
| Transaction generation | Deterministic generator (UUIDv5 from lot id) | Same pattern as `YieldTransactionGenerator`; no cross-entity coordination in outbox |
| market_prices sync | Read-only from client; global table with per-user cursor bump | Server-authoritative; clients never push prices |

## Data Model

### Backend (PostgreSQL)

Migration: `backend/migrations/003_investments.sql`.

**`investment_holdings`** — one row per position the user tracks:
- Identity / ownership: `id uuid`, `user_id uuid`, `account_id uuid` (FK).
- Asset identity: `symbol TEXT`, `exchange TEXT` (`NASDAQ | NYSE | BMV | OTHER`), `display_name TEXT`, `currency_code TEXT`.
- Classification: `asset_type TEXT` (`stock | etf | other`), `status TEXT` (`active | closed`).
- Valuation fallback: `manual_price NUMERIC(18,4) NULL` (escape-hatch when the market feed doesn't cover the symbol).
- Metadata: `notes TEXT NULL`, `created_at`, `updated_at`, `deleted_at`.
- Indexes: `user_id` (active), `user_id, updated_at`, `account_id` (active), `symbol, exchange` (active — used by the cron).

**`investment_lots`** — each buy or sell event:
- `id uuid`, `user_id uuid`, `holding_id uuid` (FK).
- `kind TEXT` (`buy | sell`) + `CHECK` constraint; `quantity NUMERIC(18,8)` + `CHECK (quantity > 0)`.
- `price NUMERIC(18,4)` per unit in the **holding** currency.
- `fee_cents BIGINT` (commission, minor units of the holding currency).
- `fx_rate NUMERIC(18,8) NULL` — **required** when `holding.currency_code != account.currency_code`; converts lot value to account currency for the derived transaction.
- `occurred_at DATE`; `validity TEXT` (`valid | invalid`); `notes TEXT NULL`; timestamps.
- Indexes: `user_id, updated_at`; `holding_id, occurred_at` (active).

**`market_prices`** — server-populated price cache, read-only from client:
- **PK compuesto** `(symbol, exchange)` — no UUID.
- `currency_code TEXT`, `price NUMERIC(18,4)`, `price_date DATE`, `source TEXT` (`yahoo | finnhub | manual`).
- `fetched_at timestamptz`, `updated_at timestamptz`.
- Index: `updated_at` for delta pulls.

**`transactions`** link columns:
- `ALTER TABLE transactions ADD COLUMN holding_id uuid`.
- `ALTER TABLE transactions ADD COLUMN lot_id uuid`.
- Partial indexes on both (`WHERE col IS NOT NULL`).
- `CHECK NOT (yield_id IS NOT NULL AND holding_id IS NOT NULL)` — prevents a transaction from being simultaneously a yield and an investment event.

### Frontend (SQLite)

Migration: `frontend/assets/migrations/002.sql`. DB `_version` bumped `1 → 2` in `frontend/lib/src/core/db/database_helper.dart`.

Mirrors the backend schema without `user_id`. Same `CHECK` constraints on `kind` and `quantity`. Same trigger-based `updated_at` management.

### Precision Rationale

`NUMERIC(18,4)` for `price` (not `*_cents BIGINT`) because BRK.A quotes above $700,000 with 4-decimal precision and overflows int64-in-cents at the corner. `NUMERIC(18,8)` for `quantity` supports fractional ETF shares. In Dart these are mapped to `double`: precision loss is acceptable for personal-finance magnitudes (double provides ~15–17 significant figures, which covers the practical range).

## gRPC Contracts

Three new services in `proto/pocket_pilot/v1/`:

| Service | Proto file | RPCs |
|---|---|---|
| `InvestmentHoldingService` | `investment_holding_service.proto` | List / Upsert / Delete |
| `InvestmentLotService` | `investment_lot_service.proto` | List / Upsert / Delete |
| `MarketPriceService` | `market_price_service.proto` | List **only** (read-only from client) |

`proto/pocket_pilot/v1/transaction_service.proto` extended with:
- `optional string holding_id = 19;`
- `optional string lot_id = 20;`

`scripts/gen_proto.sh` updated to include the three new protos for both Go and Dart output.

## Sync Integration

### New Entity Types

`backend/internal/sync/entity_type.go` gained:
- `EntityInvestmentHolding = "investment_holding"`
- `EntityInvestmentLot = "investment_lot"`
- `EntityMarketPrice = "market_price"`

### Sync Order

Handlers must run in an order that respects FK and generator dependencies. Current order (with new entries bolded):

1. `account`
2. `category`
3. `tag`
4. `transaction_template`
5. `yield_config` / `user_preference` (same order number, safe because independent)
6. **`investment_holding`** (FK to account)
7. **`investment_lot`** (FK to holding; generator runs after its pull)
8. **`market_price`** (pull-only; ordered for stability)
9. `transaction` (generator outputs push here)
10. `goal`
11. `budget`

### MarketPrice Sync Semantics

- Client-side: `MarketPriceSyncHandler.pull()` is the only functional method. `pushUpsert` and `pushDelete` are documented no-ops. No `MarketPriceRepository` exists on the client because there's no local write path.
- Server-side: `MarketPriceRepository.Upsert` (called by the cron in Fase 4) bumps the `market_price` cursor **only** for users who hold the `(symbol, exchange)` pair — via `INSERT ... SELECT DISTINCT user_id FROM investment_holdings WHERE symbol = $1 AND exchange = $2 AND deleted_at IS NULL`. Users without a relevant holding do not see their cursor bumped, so their clients skip the pull.
- Global table, user-scoped cursors: trade-off is a small amount of irrelevant bytes on full-table `List` requests, in exchange for a trivial cron implementation.

## Nature Classification

Transactions derived from lots use these values to avoid polluting by-nature/by-category dashboards:

| Operation | `type` | `nature` | Rationale |
|---|---|---|---|
| Buy | `expense` | `''` (unspecified) | Cash → asset conversion; not consumption |
| Sell | `income` | `windfall` | Matches the canonical "ventas ocasionales" definition |
| Dividend (manual) | `income` | `passive` | Mirrors the yield pattern |

**Critical filter (to implement in Fase 2):** `dashboard_local_store.dart` queries that aggregate spend by nature / by category **must** exclude `lot_id IS NOT NULL` so that portfolio operations don't appear in "monthly spend by category" style views.

## Generator Pattern (pending in Fase 2)

Same shape as `YieldTransactionGenerator`. Adds constant `kDeterministicInvestmentNamespace` in `frontend/lib/src/core/ids/deterministic_namespace.dart`.

For each non-deleted lot, upsert a transaction with:
- `id = uuidv5(kDeterministicInvestmentNamespace, "lot:${lotId}")`
- `type = 'expense'` for buy, `'income'` for sell
- `account_id = holding.account_id`
- `currency_code = account.currency_code` (converted via `fx_rate` if needed)
- `amount_cents`:
  - Buy: `round((quantity * price + fee_cents/1e2) * fx_rate * 100)`
  - Sell: `round((quantity * price - fee_cents/1e2) * fx_rate * 100)`
- `category_id = null`, `nature` per §Nature Classification
- `holding_id`, `lot_id` populated
- `status = 'cleared'`, `date = lot.occurred_at`

For lots with `deleted_at != null`: soft-delete the derived transaction and enqueue a `delete` outbox entry.

Wire into `CompositeScheduledGeneratorRunner` **after** `YieldTransactionGenerator`.

## FIFO + Weighted Average (pending in Fase 3)

Domain math lives in `frontend/lib/src/features/investments/domain/`:
- `position_math.dart`: `computePosition(lots) → { netQuantity, weightedAvgCost, fifoRemainingLots }`.
- `pnl_math.dart`:
  - `computeRealizedPnL(lots)`: walks lots chronologically; each sell consumes the oldest non-consumed buys (FIFO); returns per-sell P&L and total realized.
  - `computeUnrealizedPnL(position, currentPrice)`: uses weighted-average cost.
- Validation: attempting a sell that exceeds available quantity throws with a human-readable message; UI must hard-block the save.

On-the-fly only — no `quantity_cached` / `avg_cost_cached` columns. For >10K lots consider adding a `last_generated_at` skip column; not needed for personal portfolios.

## Backend Cron (pending in Fase 4)

Package `backend/internal/marketprice/`:
- `provider.go`: interface `MarketPriceProvider { Fetch(ctx, []Symbol) ([]Quote, error) }`.
- `yahoo_provider.go`: endpoint `https://query1.finance.yahoo.com/v7/finance/quote?symbols=...`. Batches ≤ 50 symbols, browser user-agent, 5 s per-request timeout, 3 retries with exponential backoff, long backoff on HTTP 429.
- `finnhub_provider.go`: 60 calls/min free tier; US only; requires `FINNHUB_API_KEY`.
- `scheduler.go`: `time.NewTicker(24 * time.Hour)`. Recommended fire time: **22:00 UTC** (covers NYSE close at 21:00 UTC and BMV close at 20:00 UTC). Selects distinct `(symbol, exchange)` across active holdings, fetches, calls `MarketPriceRepository.Upsert` per quote, which already bumps only the relevant users' cursors.
- `admin_handler.go`: RPC `AdminRefreshMarketPrices(symbols[])` gated by `MARKETPRICE_ADMIN_TOKEN` for debugging and post-deploy kick.

Env vars: `MARKETPRICE_ENABLED`, `MARKETPRICE_PROVIDER`, `FINNHUB_API_KEY`, `MARKETPRICE_ADMIN_TOKEN`.

Observability: log per tick — symbols fetched, failures, latency. Optional `market_price_fetch_errors` table for missing-symbol tracing.

## Dashboard Integration (pending in Fase 6)

Extend `DashboardMetrics` with:
- `marketValueOfHoldingsCents` — sum of `quantity * current_price * fx_rate_to_display_currency` across active holdings, where `current_price` prefers `market_prices` row, then `holdings.manual_price`, then last lot price.
- `allocationByBucket: Map<String, int>` with buckets:
  - `liquid` → sum of `bank + cash` balances.
  - `investment_active` → sum of `marketValueOfHoldings`.
  - `investment_passive` → sum of `amount_cents` across active `yield_configs`.
  - `debt` → sum of negative balances on `loan` and `credit_card` accounts.
  - `credit_revolving` → `credit_limit - balance` per credit card.

`netWorth` becomes `accountBalances + marketValueOfHoldings`. The investment-account cash balance is already adjusted by the generator's derived transactions, so market value stacks on top without double counting.

## Cascade Behavior

Archive cascade is orchestrated at the repository layer (no DB-level trigger cascade):
- `InvestmentHoldingRepository.archive(id)` → soft-deletes the holding AND all its active lots. The generator then soft-deletes the derived transactions.
- `AccountRepository.archive(id)` when `account.type == 'investment'` → cascades to all holdings of that account (and transitively to lots and derived transactions). Needs UI confirmation dialog: "esto archivará también N holdings y M operaciones."
- Dividends (`holding_id IS NOT NULL AND lot_id IS NULL`) are **not** auto-deleted when a holding is archived — they survive as historical references.

## Edge Cases

- **Sell > available**: validated at save time in the form. If multi-device edits produce an inconsistency post-sync, the lot is flagged `validity='invalid'` and UI notifies.
- **Symbol absent from market feed**: UI shows "precio no disponible" and falls back to `manual_price` or the last lot price for valuation.
- **Offline for days**: delta pull brings all deltas in one shot once reconnected; UI shows a "Precios actualizados hace N días" banner when the most recent `fetched_at` is stale.
- **Currency mismatch without `fx_rate`**: hard-blocked at the form level. Without `fx_rate` the derived transaction cannot debit the account balance correctly.
- **Multi-device LWW on lots**: standard LWW applies. A secondary device's change to the same lot may silently lose if `updated_at` is older.

## Implementation Phases

Phase-by-phase plan. Each phase is independently deliverable and testable. Update status here as fases advance.

### Fase 0 — Contract freeze ✅ DONE (2026-04-21)

Protos, generated code, entity types, `transactions` link columns. See commit for exact set.

### Fase 1 — Persistencia + Sync scaffolding ✅ DONE (2026-04-21)

- PG migration `003_investments.sql` + SQLite `002.sql`.
- Backend `backend/internal/investment/` package with 3 repos + 3 handlers + validation.
- Frontend `lib/src/features/investments/` with domain models, local stores, remote services, 3 sync handlers, 2 repositories (holding, lot; market_price is pull-only).
- Handlers registered in `backend/cmd/server/main.go` and `frontend/lib/main.dart`.
- `make proto` regenerates Go + Dart. `go build ./...` and `flutter analyze` both clean.

**Not done in Fase 1:** integration tests (project has no testing infrastructure for backend yet); migrations not applied (user runs `make migrate` when ready).

### Fase 2 — UI CRUD holdings / lots + Generator ✅ DONE (2026-04-21)

Implemented:
- `InvestmentAccountDetailScreen` replaces the edit form when tapping an `account.type == 'investment'` in `AccountsScreen._onAccountTap`. Lists holdings with swipe-to-archive and an "Editar cuenta" button back to the account form.
- `HoldingFormScreen` (create/edit) with symbol (uppercase), exchange dropdown (NASDAQ | NYSE | BMV | OTHER), currency picker using `kSuggestedCurrencies`, asset_type (stock | etf | other), display_name, notes, optional manual_price.
- `HoldingDetailScreen` with summary (net quantity + simple weighted-avg cost from buys) and the list of lots ordered `occurred_at DESC`. Overflow menu: edit / archive holding. FAB with bottom sheet "Añadir compra" / "Añadir venta".
- `LotFormScreen` with kind toggle, quantity, price, fee, occurred_at date picker, fx_rate (only visible when currencies differ; **hard-blocked** in save when empty or when sell > net available excluding the edited lot), notes.
- `InvestmentTransactionGenerator` wired in `CompositeScheduledGeneratorRunner` **after** the yield generator. Iterates `queryAllIncludingDeleted()` for full reconciliation: upserts active lots' transactions (idempotent — skips when row matches existing) and soft-deletes transactions whose lot is soft-deleted. `txnId = uuidv5(kDeterministicInvestmentNamespace, "lot:$lotId")`.
- `kDeterministicInvestmentNamespace = '5e7b2f8c-3a4d-4e9b-8c1f-6a2d7e3b4c8f'` added to `frontend/lib/src/core/ids/deterministic_namespace.dart`.
- `dashboard_local_store.dart` excludes `AND t.lot_id IS NULL` from `getMonthlySpendByCategory`, `getMonthlySpendByNature`, and `getMonthlySpendByTag`. `getBalancesPerAccount` is intentionally not filtered — derived transactions SHOULD affect the investment account balance.
- Archive cascade: `InvestmentHoldingRepository.archive(id)` accepts optional `InvestmentLotLocalStore` and soft-deletes lots + enqueues outbox deletes; the generator then soft-deletes derived transactions. `AccountRepository.archiveAccount(id)` accepts optional `InvestmentHoldingLocalStore` / `InvestmentLotLocalStore` and cascades holdings→lots when `type=='investment'`. `AccountsRouteScope` wires both stores.
- `AccountsScreen` archive confirmation dialog uses `AccountsViewModel.countInvestmentHoldings(accountId)` to show "Se archivará la cuenta X y sus N holding(s) con todas sus operaciones." when the account is an investment.

**DoD met:** User creates holding AAPL in an investment account, adds 2 buys + 1 sell via the UI; lots enqueue outbox upserts; the generator derives transactions with `holding_id` + `lot_id` populated; the account balance reflects net cash flow; Dashboard by-category / by-nature / by-tag aggregations exclude those transactions.

**Not done in Fase 2:** FIFO with per-sell realized P&L (simple weighted avg only — pulido in Fase 3); portfolio-wide screen; integration tests (no testing infra for this feature yet).

### Fase 3 — FIFO + weighted + portfolio screen ⏳ PENDING

Acceptance:
- `position_math.dart` and `pnl_math.dart` implemented with unit tests covering FIFO, partial sells, multi-price buys, sell > available.
- `PortfolioScreen` (new route) with a table: symbol / quantity / avg cost / current price (market → manual → last lot) / unrealized P&L / realized P&L / total.
- No charts yet — tabular only.

**DoD:** For a seeded holding with multiple buys and a sell, the UI shows mathematically correct avg cost, realized P&L, unrealized P&L.

### Fase 4 — Backend cron for market_prices ⏳ PENDING

Acceptance:
- `backend/internal/marketprice/` package with provider interface + Yahoo + Finnhub implementations.
- `scheduler.go` wired into `cmd/server/main.go` with graceful shutdown.
- `AdminRefreshMarketPrices` RPC for manual kicks.
- Env var configuration (`MARKETPRICE_ENABLED`, `MARKETPRICE_PROVIDER`, `FINNHUB_API_KEY`, `MARKETPRICE_ADMIN_TOKEN`).
- Observability logs per tick.

**DoD:** Staging deployment ingests prices for seeded US + MX holdings over 24 h; clients receive prices via delta pull; `PortfolioScreen` shows fresh values; a symbol with no feed coverage degrades gracefully.

### Fase 5 — Charts ⏳ PENDING

Acceptance:
- PieChart of portfolio distribution by market value per holding.
- LineChart of 30-day historical performance reconstructed on the fly from `market_prices` cross `lots`-at-date.
- Tab switcher on `PortfolioScreen`: Distribución | Performance | Holdings.

**DoD:** Smooth render with ≥ 50 holdings; widget tests for both charts.

### Fase 6 — Allocation in dashboard ⏳ PENDING

Acceptance:
- `DashboardMetrics` extended with `marketValueOfHoldingsCents` and `allocationByBucket`.
- New widget (horizontal stacked bar) in Dashboard or Estadísticas.
- `netWorth` includes market value; invariant: immediately after a buy, net worth is stable (cash down = market value up).

**DoD:** Dashboard reflects correct net worth post-purchase; fluctuates with subsequent price moves.

### Deferred (post-MVP)

- Splits and corporate actions.
- Auto dividend detection.
- Tax / capital-gains reports.
- Snapshot materialization for performance charts (only if >50 holdings hurts render time).
- Symbol autocomplete on the holding form via a new backend RPC.

## Critical Files

**Backend:**
- `backend/migrations/003_investments.sql`
- `backend/internal/investment/model.go`, `validation.go`, `holding_repository.go`, `lot_repository.go`, `market_price_repository.go`, `handler.go`
- `backend/internal/sync/entity_type.go` (lines 8–21)
- `backend/cmd/server/main.go` (investment handlers wired near the other handlers)

**Frontend:**
- `frontend/assets/migrations/002.sql`
- `frontend/lib/src/core/db/database_helper.dart` (`_version = 2`)
- `frontend/lib/src/features/investments/` (whole directory)
- `frontend/lib/main.dart` (sync handlers registered in `SyncService.handlers`)

**Patterns to mirror when continuing:**
- Generator: `frontend/lib/src/features/yield_configs/data/yield_transaction_generator.dart`.
- Deterministic namespace: `frontend/lib/src/core/ids/deterministic_namespace.dart`.
- Repository with cursor bump: `backend/internal/yieldconfig/repository.go`.
- Dashboard metrics integration: `frontend/lib/src/features/dashboard/data/dashboard_local_store.dart` + `dashboard_repository.dart`.

## Known Risks

- **Yahoo endpoint instability**: it's a non-official API. Mitigation: provider interface with Finnhub fallback, feature flag, fixture-backed tests.
- **Cron cursor bumping at scale**: for N users × M symbols, many `INSERT ... ON CONFLICT` writes. Fine for personal-scale; consider batched writes if it grows.
- **Precision drift on doubles**: for users with extreme quantities or prices, consider a pgtype.Numeric / Decimal path later. Not expected in practice.
- **Multi-device edit races on the same lot**: standard LWW behavior. Banner for "conflict resolved" is already shown by the sync infrastructure.
