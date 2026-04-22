# Investments — Renta Variable (Acciones y ETFs)

Architecture doc for the investments feature: **variable-income assets** (stocks, ETFs) that complement the existing `yield_configs` feature (which covers fixed-income). Tracks holdings with buy/sell lots, computes FIFO and weighted-average cost on the fly, and syncs daily market prices from the backend.

**Status:** Fases 0–3 done (2026-04-21). Fases 4–6 pending — see [§Implementation Phases](#implementation-phases).

## Scope

**In scope:**
- User-managed holdings (symbol + exchange), globals — not tied to any account.
- Per-holding lots recording buys/sells with commissions and optional FX rate. Each lot settles against its own `account_id` (the cash account).
- Deterministic transaction generation from lots so the settlement account's balance reflects cash in/out.
- Daily market price sync from a backend cron (Yahoo Finance).
- On-the-fly FIFO and weighted-average cost calculations.
- Portfolio view (tabular) with market value, P&L realized/unrealized, dividends.
- Dashboard allocation (liquid / investment_active / investment_passive / debt / revolving).

**Out of scope:**
- Stock splits and corporate actions (post-MVP).
- Dividend auto-detection — dividends are entered **manually** as income transactions with `holding_id` set, `lot_id` NULL, and `nature='passive'`.
- Tax/capital-gains reports.
- Options/derivatives.
- Margin / leverage.
- Real-time (intraday) prices. Only end-of-day.

## Key Design Decisions

| Decision | Choice | Why |
|---|---|---|
| Price source | Backend Go cron hitting Yahoo Finance (free public endpoint) | Centralized, daily, covers US and BMV via `.MX` suffix. Finnhub explicitly rejected: expensive for the value added on top of Yahoo |
| Holdings scope | **Global**, not per-account. Each lot carries its own `account_id` | Lets a single symbol settle against multiple cash accounts |
| Cash model | **Implicit**: settlement account balance = available cash | Matches broker mental model without a separate `cash_balance` column |
| Dividend capture | Manual income transaction with `holding_id`, `lot_id IS NULL`, `nature='passive'` | Simpler than extending `yield_configs`; auto-detection deferred |
| Currency | Each holding has its own `currency_code`, independent of the settlement account | Allows mixed USD + MXN positions |
| FX per lot | `fx_rate` on the lot, required when `holding.currency_code != account.currency_code` | The derived transaction must debit the settlement account in its currency |
| Splits / corporate actions | Not in MVP | Can be applied manually by editing lot quantities and prices |
| FIFO / weighted avg | Computed on the fly in Flutter from lots (pure domain math) | Trivial compute for personal portfolios; avoids materialization drift |
| Transaction generation | Deterministic (UUIDv5 from lot id) | Same pattern as `YieldTransactionGenerator`; no cross-entity coordination in outbox |
| `market_prices` sync | Read-only from client; global table with per-user cursor bump | Server-authoritative; clients never push prices |
| Portfolio UI location | The existing "Holdings" tab of `AccountsScreen` is the portfolio view | Avoids duplicating the global holdings list |

## Data Model

### Backend (PostgreSQL)

Initial migration: `backend/migrations/003_investments.sql`. Related follow-ups: `004` adds `investment_lots.account_id`; `005` drops `investment_holdings.account_id` (holdings are globals).

**`investment_holdings`** — one row per position the user tracks:
- Identity: `id uuid`, `user_id uuid`.
- Asset: `symbol TEXT`, `exchange TEXT` (`NASDAQ | NYSE | BMV | OTHER`), `display_name TEXT`, `currency_code TEXT`.
- Classification: `asset_type TEXT` (`stock | etf | other`), `status TEXT` (`active | closed`).
- Valuation fallback: `manual_price NUMERIC(18,4) NULL` (escape-hatch when the feed doesn't cover the symbol).
- Metadata: `notes TEXT NULL`, timestamps, `deleted_at`.
- Indexes: `user_id` (active), `user_id, updated_at`, `symbol, exchange` (active — used by the cron).

**`investment_lots`** — each buy or sell event:
- `id uuid`, `user_id uuid`, `holding_id uuid` (FK), `account_id uuid` (settlement account, added in migration 004).
- `kind TEXT` (`buy | sell`) + `CHECK`; `quantity NUMERIC(18,8)` + `CHECK (quantity > 0)`.
- `price NUMERIC(18,4)` per unit in the **holding** currency.
- `fee_cents BIGINT` (commission, minor units of the holding currency).
- `fx_rate NUMERIC(18,8) NULL` — required when `holding.currency_code != account.currency_code`.
- `occurred_at DATE`; `validity TEXT` (`valid | invalid`); `notes TEXT NULL`; timestamps.
- Indexes: `user_id, updated_at`; `holding_id, occurred_at` (active).

**`market_prices`** — server-populated price cache, read-only from client:
- **Composite PK** `(symbol, exchange)` — no UUID.
- `currency_code TEXT`, `price NUMERIC(18,4)`, `price_date DATE`, `source TEXT` (`yahoo | manual`).
- `fetched_at timestamptz`, `updated_at timestamptz`.
- Index: `updated_at` for delta pulls.

**`transactions`** link columns:
- `holding_id uuid NULL`, `lot_id uuid NULL`, partial indexes on each.
- `CHECK NOT (yield_id IS NOT NULL AND holding_id IS NOT NULL)`.

### Frontend (SQLite)

Initial migration: `frontend/assets/migrations/002.sql`. Follow-ups: `003.sql` (lot.account_id), `004.sql` (drop holding.account_id). DB `_version` currently `4` in `frontend/lib/src/core/db/database_helper.dart`. Schema mirrors the backend without `user_id`.

### Precision Rationale

`NUMERIC(18,4)` for `price` and `NUMERIC(18,8)` for `quantity` (not `*_cents BIGINT`) — BRK.A quotes above $700,000 with 4 decimals overflow int64-in-cents. In Dart these are mapped to `double`: precision loss is acceptable for personal-finance magnitudes.

## gRPC Contracts

Three services in `proto/pocket_pilot/v1/`:

| Service | Proto file | RPCs |
|---|---|---|
| `InvestmentHoldingService` | `investment_holding_service.proto` | List / Upsert / Delete |
| `InvestmentLotService` | `investment_lot_service.proto` | List / Upsert / Delete |
| `MarketPriceService` | `market_price_service.proto` | List **only** (read-only from client) |

`transaction_service.proto` extended with `optional string holding_id = 19;` and `optional string lot_id = 20;`. `scripts/gen_proto.sh` generates Go + Dart for all three.

## Sync Integration

### Entity Types

`backend/internal/sync/entity_type.go`:
- `EntityInvestmentHolding = "investment_holding"`
- `EntityInvestmentLot = "investment_lot"`
- `EntityMarketPrice = "market_price"`

### Sync Order

1. `account`
2. `category`
3. `tag`
4. `transaction_template`
5. `yield_config` / `user_preference`
6. **`investment_holding`**
7. **`investment_lot`** (generator runs after its pull)
8. **`market_price`** (pull-only)
9. `transaction` (generator outputs push here)
10. `goal`
11. `budget`

### MarketPrice Sync Semantics

- **Client**: `MarketPriceSyncHandler.pull()` is the only functional method; `pushUpsert` / `pushDelete` are no-ops. No `MarketPriceRepository` on the client (no local write path).
- **Server**: `MarketPriceRepository.Upsert` (called by the cron) bumps the `market_price` cursor **only** for users who hold the `(symbol, exchange)` — via `INSERT ... SELECT DISTINCT user_id FROM investment_holdings WHERE symbol = $1 AND exchange = $2 AND deleted_at IS NULL`. Users without a relevant holding skip the pull.

## Nature Classification

Derived transactions use these values so they don't pollute by-nature/by-category dashboards:

| Operation | `type` | `nature` | Rationale |
|---|---|---|---|
| Buy | `expense` | `investment` | Cash → asset conversion; not consumption |
| Sell | `income` | `investment` | Asset → cash; not earned income |
| Dividend (manual) | `income` | `passive` | Mirrors the yield pattern |

`dashboard_local_store.dart` excludes `AND t.lot_id IS NOT NULL` from `getMonthlySpendByCategory`, `getMonthlySpendByNature`, and `getMonthlySpendByTag`. `getBalancesPerAccount` is intentionally **not** filtered — derived transactions should affect the settlement account's balance.

## Generator Pattern

Located at `frontend/lib/src/features/investments/data/investment_transaction_generator.dart`. Namespace constant `kDeterministicInvestmentNamespace` in `frontend/lib/src/core/ids/deterministic_namespace.dart`. Full reconciliation via `queryAllIncludingDeleted()`: upserts active lots idempotently and soft-deletes transactions whose lot is soft-deleted. Wired in `CompositeScheduledGeneratorRunner` **after** `YieldTransactionGenerator`.

Per lot:
- `id = uuidv5(kDeterministicInvestmentNamespace, "lot:${lotId}")`
- `type = 'expense'` for buy, `'income'` for sell
- `account_id = lot.account_id` (the settlement account)
- `currency_code = account.currency_code` (converted via `fx_rate`)
- `amount_cents`:
  - Buy: `round((quantity * price + fee_cents/100) * fx_rate * 100)`
  - Sell: `round((quantity * price - fee_cents/100) * fx_rate * 100)`
- `category_id = null`, `nature` per §Nature Classification, `holding_id` + `lot_id` populated, `status = 'cleared'`, `date = lot.occurred_at`.

## FIFO + Weighted Average (Domain Math)

Pure Dart, testable without Flutter, lives in `frontend/lib/src/features/investments/domain/`:

- `position_math.dart` → `computePosition(lots) → { netQuantity, weightedAvgCost, fifoRemainingLots }`. Filters `deletedAt != null` or `validity != 'valid'`. Sorts `(occurredAt ASC, createdAt ASC)`. Weighted avg is **global** across all valid buys with fees prorated per unit. FIFO queue consumed by sells; `netQuantity` goes negative if a sell exceeds available.
- `pnl_math.dart` → `computeRealizedPnL(lots)` (per-sell breakdown: `proceeds = qty*price - fee/100`, `costBasisConsumed = Σ slices`), `computeUnrealizedPnL({position, currentPrice})` (returns 0 when price null or `netQuantity <= 0`), `InvestmentMathException.sellExceedsAvailable` as defense (UI hard-blocks in `LotFormScreen`).
- `current_price_resolver.dart` → precedence `market_price → holding.manualPrice → last valid lot → null`, returns a `source` tag for the UI pill.

Tests: `frontend/test/position_math_test.dart`, `frontend/test/pnl_math_test.dart`.

No materialized columns — on-the-fly only. For >10K lots consider a skip cache; not expected for personal portfolios.

## Portfolio UI

Lives in the existing "Holdings" tab of `AccountsScreen` (`HoldingsListTab`) — **not** a separate `PortfolioScreen` route. Each row shows symbol / qty / avg / current price (with source pill: Mercado / Manual / Último lote) / market value / P&L chips (Unreal / Real / Div). Footer groups totals by currency; no FX conversion is attempted (no global fx table). Rows with `netQuantity < 0` render a "Datos inconsistentes" pill but don't crash the list.

`HoldingDetailScreen` uses the same domain math for its summary card (qty, avg, price, market value, unrealized, realized, dividends totals + last dividend).

`InvestmentViewModel` (`frontend/lib/src/features/investments/ui/investment_view_model.dart`) holds `_lotsByHolding`, `_priceBySymbolExchange`, `_dividendsByHolding`. `loadPortfolio()` paralelizes per-holding loads with `Future.wait(eagerError: false)`. Dividends read via `TransactionLocalStore.queryDividendsByHolding(holdingId)` (no `TransactionRepository` — it forces a date range; dividends need all-time). Dividend totals group by `tx.currencyCode` (not the holding's) so amounts stay truthful when the user booked them in another currency.

## Backend Cron (pending in Fase 4)

Package `backend/internal/marketprice/`:
- `provider.go`: interface `MarketPriceProvider { Fetch(ctx, []Symbol) ([]Quote, error) }`.
- `yahoo_provider.go`: `https://query1.finance.yahoo.com/v7/finance/quote?symbols=...`. Batches ≤ 50 symbols, browser user-agent, 5 s per-request timeout, 3 retries with exponential backoff, long backoff on HTTP 429.
- `scheduler.go`: `time.NewTicker(24 * time.Hour)`. Fire time **22:00 UTC** (covers NYSE close at 21:00 UTC and BMV close at 20:00 UTC). Selects distinct `(symbol, exchange)` across active holdings, calls `MarketPriceRepository.Upsert` per quote (already bumps only relevant users' cursors).
- `admin_handler.go`: RPC `AdminRefreshMarketPrices(symbols[])` gated by `MARKETPRICE_ADMIN_TOKEN` for debugging and post-deploy kick.

Env vars: `MARKETPRICE_ENABLED`, `MARKETPRICE_ADMIN_TOKEN`.

Observability: log per tick — symbols fetched, failures, latency. Optional `market_price_fetch_errors` table for missing-symbol tracing.

## Dashboard Integration (pending in Fase 6)

Extend `DashboardMetrics` with:
- `marketValueOfHoldingsCents` — `Σ quantity * current_price * fx_to_display` across active holdings, where `current_price` prefers `market_prices`, then `holdings.manual_price`, then last lot price.
- `allocationByBucket: Map<String, int>`:
  - `liquid` → `bank + cash` balances.
  - `investment_active` → `marketValueOfHoldings`.
  - `investment_passive` → Σ `amount_cents` across active `yield_configs`.
  - `debt` → negative balances on `loan` / `credit_card`.
  - `credit_revolving` → `credit_limit - balance` per credit card.

`netWorth` becomes `accountBalances + marketValueOfHoldings`. The settlement-account cash balance is already adjusted by the generator's derived transactions, so market value stacks on top without double counting.

## Cascade Behavior

Archive cascade is orchestrated at the repository layer:
- `InvestmentHoldingRepository.archive(id)` soft-deletes the holding and all its active lots. The generator then soft-deletes the derived transactions.
- `AccountRepository.archive(id)` when `account.type == 'investment'` soft-deletes lots whose `account_id == archived` (holdings survive because they're globals). The UI confirmation dialog shows the impacted-lots count.
- Dividends (`holding_id IS NOT NULL AND lot_id IS NULL`) are **not** auto-deleted — they survive as historical references.

## Edge Cases

- **Sell > available**: validated at save time in the form. Post-sync inconsistency flags the lot `validity='invalid'`; math excludes it.
- **Symbol absent from market feed**: UI falls back to `manual_price` or last lot price; source pill communicates it.
- **Offline for days**: delta pull brings all deltas in one shot on reconnect; UI shows "Precios actualizados hace N días" when `fetched_at` is stale (banner wires in Fase 4 when the cron populates `fetched_at`).
- **Currency mismatch without `fx_rate`**: hard-blocked at the form.
- **Multi-device LWW on lots**: standard LWW; secondary device may silently lose if `updated_at` is older.
- **Corrupt data (`netQuantity < 0`)**: list renders a "Datos inconsistentes" pill per row; the other rows keep rendering.
- **Dividend in a currency ≠ holding.currencyCode**: totals group by `tx.currencyCode`, not holding currency, so footer numbers stay truthful.

## Implementation Phases

Phase-by-phase roadmap. Permanent knowledge lives in the sections above; this table is just the roadmap + acceptance criteria for what's still pending.

### Done

| # | Phase | Completed | Notes |
|---|---|---|---|
| 0 | Contract freeze (protos + entity types + transaction link columns) | 2026-04-21 | See §gRPC Contracts, §Sync Integration |
| 1 | Persistence + sync scaffolding | 2026-04-21 | See §Data Model, §Sync Integration. Migrations applied via `make migrate` |
| 2 | UI CRUD + transaction generator | 2026-04-21 | See §Generator Pattern, §Cascade Behavior |
| 3 | FIFO + weighted avg + P&L in UI | 2026-04-21 | See §FIFO + Weighted Average, §Portfolio UI. 27 unit tests |

### Fase 4 — Backend cron for market_prices ⏳ PENDING

Acceptance:
- `backend/internal/marketprice/` package with `provider.go` + `yahoo_provider.go` + `scheduler.go` + `admin_handler.go`.
- Scheduler wired into `cmd/server/main.go` with graceful shutdown.
- `AdminRefreshMarketPrices` RPC for manual kicks.
- Env var configuration (`MARKETPRICE_ENABLED`, `MARKETPRICE_ADMIN_TOKEN`).
- Observability logs per tick.
- Frontend banner "Precios actualizados hace N días" in `HoldingsListTab` when most recent `fetched_at` > N days.

**DoD:** Staging ingests prices for seeded US + MX holdings over 24 h; clients receive prices via delta pull; `HoldingsListTab` shows fresh values with `source='market'` pill; a symbol with no feed coverage degrades to `manual` / `last_lot` cleanly.

### Fase 5 — Charts ⏳ PENDING

Acceptance:
- PieChart of portfolio distribution by market value per holding.
- LineChart of 30-day historical performance reconstructed on the fly from `market_prices × lots-at-date`.
- Tab switcher inside `HoldingsListTab` (or a sibling screen): Distribución | Performance | Holdings.

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
- `backend/migrations/003_investments.sql`, `004_investment_lots_account.sql`, `005_drop_holding_account.sql`
- `backend/internal/investment/` (model, validation, `holding_repository.go`, `lot_repository.go`, `market_price_repository.go`, `handler.go`)
- `backend/internal/sync/entity_type.go`
- `backend/cmd/server/main.go`

**Frontend:**
- `frontend/assets/migrations/002.sql`, `003.sql`, `004.sql`
- `frontend/lib/src/core/db/database_helper.dart` (`_version`)
- `frontend/lib/src/features/investments/` (whole directory)
- `frontend/lib/src/features/accounts/ui/accounts_route_scope.dart` (DI wiring)
- `frontend/lib/main.dart` (sync handlers registered in `SyncService.handlers`)
- `frontend/test/position_math_test.dart`, `frontend/test/pnl_math_test.dart`

**Patterns to mirror when extending:**
- Generator: `frontend/lib/src/features/yield_configs/data/yield_transaction_generator.dart`.
- Deterministic namespace: `frontend/lib/src/core/ids/deterministic_namespace.dart`.
- Repository with cursor bump: `backend/internal/yieldconfig/repository.go`.
- Dashboard metrics integration: `frontend/lib/src/features/dashboard/data/dashboard_local_store.dart` + `dashboard_repository.dart`.

## Known Risks

- **Yahoo endpoint instability**: it's a non-official API. Mitigation: retry + exponential backoff + long backoff on 429, feature flag (`MARKETPRICE_ENABLED`), fixture-backed tests. If Yahoo breaks for good we pick a different free provider at that moment rather than carrying a paid fallback we don't need today.
- **Cron cursor bumping at scale**: for N users × M symbols, many `INSERT ... ON CONFLICT`. Fine for personal-scale; batch writes if it grows.
- **Precision drift on doubles**: for extreme quantities/prices, consider a `pgtype.Numeric` / Decimal path later. Not expected in practice.
- **Multi-device edit races on the same lot**: standard LWW; existing "conflict resolved" banner in the sync infra already surfaces it.
