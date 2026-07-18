# Investments — Renta Variable (Acciones y ETFs)

Architecture doc for the investments feature: **variable-income assets** (stocks, ETFs) that complement the existing `yield_configs` feature (which covers fixed-income). Tracks holdings with buy/sell lots, computes FIFO and weighted-average cost on the fly, and syncs daily market prices from the backend.

**Status:** Fases 0–4 done (2026-04-21). Fase 5 parcial (PieChart de distribución, 2026-04-21). Fase 6 done (Allocation card en Dashboard, 2026-04-25). Fases 7 y 8 done (Splits — persistencia + sync + math + UI + dashboard, 2026-04-25). Fase 5.1 (LineChart 30 días) pendiente — see [§Implementation Phases](#implementation-phases).

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
- Corporate actions other than splits (spinoffs, mergers, rights issues — out for MVP).
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
| Splits | First-class entity `investment_split` (Fases 7–8) | Math walks `(lots ∪ splits)` chronologically and adjusts FIFO state in-flight (qty *= ratio, price /= ratio). Lots remain immutable |
| Corporate actions ≠ splits | Not in MVP | Spinoffs, mergers, rights issues mutate cost basis differently; deferred |
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
- `EntityInvestmentSplit = "investment_split"`
- `EntityMarketPrice = "market_price"`

### Sync Order

1. `account`
2. `category`
3. `tag`
4. `transaction_template`
5. `yield_config` / `user_preference`
6. **`investment_holding`**
7. **`investment_lot`** (generator runs after its pull)
8. **`investment_split`** (no generator — splits do not produce transactions)
9. **`market_price`** (pull-only)
10. `transaction` (generator outputs push here)
11. `goal`
12. `budget`

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

## Splits

Forward and reverse stock splits are first-class events. Lots remain immutable; the math walks the union `(lots ∪ splits)` chronologically and adjusts the FIFO state in flight.

### Schema

**Backend** (`backend/migrations/007_investment_splits.sql`): table `investment_splits` with `id, user_id, holding_id (FK), ratio_num NUMERIC(18,8), ratio_den NUMERIC(18,8), occurred_at DATE, notes, created_at, updated_at, deleted_at`. Indexes `(user_id, updated_at)` (sync cursor) and `(holding_id, occurred_at) WHERE deleted_at IS NULL` (math). CHECKs `ratio_num > 0` and `ratio_den > 0`. `set_updated_at_investment_splits` trigger.

**Frontend** (`frontend/assets/migrations/005.sql`): mirror without `user_id`. DB `_version` 4 → 5.

### Sync

- `EntityInvestmentSplit = "investment_split"`. Sync order **8**, between `investment_lot` (7) and `market_price` (which moved 8 → 9). Splits depend on holdings/lots already being local; they are themselves prerequisites for math reading current state.
- Server: `SplitRepository.Upsert/SoftDelete` bumpea cursor `investment_split` para el `user_id` afectado dentro de la misma transacción (mismo patrón que lots).
- Client: `InvestmentSplitSyncHandler` con pull/pushUpsert/pushDelete completos (writable). LWW resolution server-side via `conflict_resolved` flag, igual que lots.
- **No transaction generator for splits** — splits do not produce cash flow.

### Math walk

`computePosition(lots, {splits = const []})` and `computeRealizedPnL(lots, {splits = const []})` build a unified event timeline sorted `(occurredAt ASC, createdAt ASC)`:

- **Buy**: enqueue FIFO slice `(qty, effectivePrice = (qty*price + fee/100)/qty)`; accumulate global `totalBuyQty` and `totalBuyCost`.
- **Sell**: consume FIFO from the head; accumulate `totalSellQty`. In `pnl_math`, also accumulates `costBasisConsumed` and emits a `RealizedSellEntry`.
- **Split**: `ratio = num/den`. Every queued FIFO slice has `qty *= ratio` and `effectivePrice /= ratio`. Global `totalBuyQty *= ratio` and `totalSellQty *= ratio`. `totalBuyCost` stays — the avg cost (`cost/qty`) naturally divides by `ratio`.

Soft-deleted splits (`deletedAt != null`) are filtered out before the walk. The result `Position.netQuantity` and `weightedAvgCost` are reported in the **post-split share count**, so consumers can multiply directly by today's market price.

**Algoritmo elegido: walk vs effective-ratio-per-lot.** El walk cronológico se prefirió sobre el approach alternativo (calcular Π de ratios posteriores a cada lot y aplicarlo solo a la cola FIFO consumible al momento del sell) porque generaliza naturalmente a multi-split y al sell-entre-splits sin manejar acumuladores externos.

### Current price fallback

`resolveCurrentPrice(..., {splits = const []})` preserva la precedencia `market → manual → último lote → null`. Cuando llega al fallback de último lote, ahora computa `cumulativeRatio = Π(s.ratioNum/s.ratioDen) for s in splits where s.occurredAt > lot.occurredAt && deletedAt == null` y retorna `lot.price / cumulativeRatio`. Splits anteriores o con misma fecha que el lot no aplican (la fecha del lot ya es post-split). El fallback de `manualPrice` se toma face-value: el usuario se asume que lo registró ya en post-split share count.

### UI

- **`HoldingDetailScreen`**: el FAB bottom sheet gana 3ra acción "Registrar split" (`Icons.call_split`). La lista cambia de `ListView.builder` sobre lots a un timeline mixto sealed `_HoldingEvent = _LotEvent | _SplitEvent`, sorted `(occurredAt DESC, createdAt DESC)`. La card de split usa `Icons.call_split`, fondo `surfaceContainerHighest`, label "Split N a D (forward)" o "(reverso)" según `ratioNum > ratioDen`. `_HoldingSummaryCard` ahora pasa `splits` a `computePosition`/`computeRealizedPnL`/`resolveCurrentPrice`.
- **`SplitFormScreen`** (nuevo): form con `ratio_num`, `ratio_den`, `occurred_at` (date picker) y `notes` opcional. Validación: ambos > 0, num != den (no-op bloqueado), occurred_at requerido. Hint inline "2 a 1 = forward; 1 a 10 = reverso" + preview en vivo. Bloquea save sobre holdings archivados. Rutas anidadas bajo `AccountsRouteScope`: `/accounts/holdings/:holdingId/splits/new` y `:splitId/edit`.
- **`HoldingsListTab`**: `_buildStats` y `_buildDistribution` pasan `vm.splitsFor` a la math. Sin cambios estructurales — los números nuevos los emite la math.

### ViewModel + DI

- `InvestmentViewModel` recibe `InvestmentSplitRepository`. Cachea `_splitsByHolding`. `loadPortfolio()` paraleliza splits junto con lots/price/dividends por holding (4to future en `Future.wait(eagerError: false)`). Métodos `saveSplit/deleteSplit` recargan via `loadHoldingFull` y disparan `_syncInBackground` (no orchestrator — splits no generan transactions).
- `AccountsRouteScope` provee `InvestmentSplitLocalStore` y `InvestmentSplitRepository`, e inyecta el repo al VM.
- `DashboardRouteScope` instancia `InvestmentSplitLocalStore` y se lo pasa a `DashboardRepository(splitStore: ...)`.
- `DashboardRepository._loadMarketValueByCurrency` carga splits por holding y los pasa via callback `splitsFor` a `computePortfolioDistribution`. Si `splitStore == null` (legacy) el callback retorna `[]` y la math se comporta como pre-Fase-8.

### Edge cases

- **Sell > available post-split**: cubierto por `InvestmentMathException.sellExceedsAvailable` — el walk lo detecta naturalmente.
- **Split con fecha futura**: se aplica igual (los anuncios son anteriores al effective date).
- **Holdings archivados**: el form bloquea registrar splits cuando `holding.deletedAt != null`.
- **Soft-deleted splits**: math y resolver los filtran.
- **Multi-device LWW**: estándar (mismo patrón que lots).
- **Fractional shares post-reverso**: permitidas (NUMERIC(18,8)). Si el broker pagó cash por la fractional, se registra como sell aparte.

## Portfolio UI

Lives in the existing "Holdings" tab of `AccountsScreen` (`HoldingsListTab`) — **not** a separate `PortfolioScreen` route. Each row shows symbol / qty / avg / current price (with source pill: Mercado / Manual / Último lote) / market value / P&L chips (Unreal / Real / Div). Footer groups totals by currency; no FX conversion is attempted (no global fx table). Rows with `netQuantity < 0` render a "Datos inconsistentes" pill but don't crash the list.

`HoldingDetailScreen` uses the same domain math for its summary card (qty, avg, price, market value, unrealized, realized, dividends totals + last dividend).

`InvestmentViewModel` (`frontend/lib/src/features/investments/ui/investment_view_model.dart`) holds `_lotsByHolding`, `_priceBySymbolExchange`, `_dividendsByHolding`. `loadPortfolio()` paralelizes per-holding loads with `Future.wait(eagerError: false)`. Dividends read via `TransactionLocalStore.queryDividendsByHolding(holdingId)` (no `TransactionRepository` — it forces a date range; dividends need all-time). Dividend totals group by `tx.currencyCode` (not the holding's) so amounts stay truthful when the user booked them in another currency.

### Distribution chart (Fase 5)

`HoldingsListTab` hosts a `SegmentedButton` (`Distribución | Holdings`) above the list; state is local to the tab (`enum _HoldingsView`). No nested `TabBar` — `AccountsScreen` already owns the outer 4-tab bar, and the cashflow feature sets the precedent of using `SegmentedButton` for view toggles.

The distribution view renders `PortfolioPieChart` (`features/investments/ui/widgets/portfolio_pie_chart.dart`), which consumes a `Map<String currencyCode, List<PortfolioSlice>>` built by the pure function `computePortfolioDistribution` (`features/investments/domain/portfolio_distribution.dart`). The function mirrors the list's exclusion rules — deleted, non-active, `netQuantity <= 0`, and `currentPrice == null` holdings are dropped — groups the rest by currency (same pattern as `_TotalsFooter`, no FX), orders slices desc by market value, and computes per-currency percentages. One `PieChart` is rendered per currency, stacked vertically with a header and a `Wrap` legend of chips `[dot] SYMBOL · XX.X%`. Slice colors are picked deterministically from `AppColors.categoryPresets` (14 Catpuccin Latte colors) via `holdingId.hashCode % 14`, so the color of a given holding is stable frame to frame. The `_TotalsFooter` stays visible in both views — it anchors the absolute numbers (market value, P&L, dividends) that the pie intentionally does not surface.

## Backend Cron

Package `backend/internal/marketprice/`:
- `provider.go`: interface `MarketPriceProvider { Fetch(ctx, []investment.SymbolExchange) ([]Quote, []SymbolError, error); Name() string }`.
- `yahoo_provider.go`: `https://query1.finance.yahoo.com/v8/finance/chart/{SYMBOL}`. **One HTTP GET per symbol, no auth**. The older `v7/finance/quote` batch endpoint now gates anonymous traffic behind a crumb+cookie flow (returns HTTP 401), so batching was traded for a stateless per-symbol call — cheap enough at MVP holding counts on a 24h cadence. Browser user-agent, 5 s per-request timeout, 3 retries with exponential backoff (`{500ms, 2s, 8s}`), long backoff (60 s) on HTTP 429. `doWithRetries` **short-circuits on 4xx-non-429** (a 404/401 is deterministic — retrying won't change it). HTTP 404 or a 200 with `chart.error != nil`/empty `chart.result` → `SymbolError{Reason:"not_found"}`. Options: `WithBaseURL`, `WithUserAgent`, `WithBackoffs`, `WithRateLimitSleep`.
- `scheduler.go`: `time.NewTimer` aligned to **22:00 UTC** (covers NYSE close at 21:00 UTC and BMV close at 20:00 UTC), recomputed each cycle to avoid drift. Selects distinct `(symbol, exchange)` across active holdings via `HoldingRepository.ListActiveSymbolExchanges`, calls `MarketPriceRepository.Upsert` per quote (bumps only relevant users' cursors). `runOnBoot=true` triggers one `Tick` before the first timer.
- `admin_handler.go`: RPC `AdminRefreshMarketPrices(symbols[])` gated by `MARKETPRICE_ADMIN_TOKEN` for debugging and post-deploy kick (empty `symbols` ⇒ refresh all active holdings).

Env vars: `MARKETPRICE_ENABLED`, `MARKETPRICE_ADMIN_TOKEN`.

Observability: log per tick — symbols fetched, failures, latency. Optional `market_price_fetch_errors` table for missing-symbol tracing.

## Dashboard Integration (Fase 6)

`DashboardMetrics` (per-currency, en `features/dashboard/domain/dashboard_metrics.dart`) gana cuatro campos sobre los cuatro originales:

- `marketValueOfHoldingsCents` — `Σ quantity * current_price` sobre holdings activos cuyo `currencyCode` coincide con la entrada del map. `current_price` por precedencia `market_price → manual_price → último lote válido` (mismo `current_price_resolver` que la lista de holdings y el PieChart).
- `yieldsValueCents` — `Σ amount_cents` de yield_configs activos cuya `account.currency_code` coincide. JOIN nuevo `yield_configs ⨝ accounts` en `DashboardLocalStore.getYieldsValueByCurrency`.
- `debtCents` — `|Σ balance|` para cuentas `credit_card` o `loan` con balance < 0.
- `revolvingCreditCents` — `Σ (credit_limit + balance)` cuando > 0 sobre tarjetas. (Antes era una variable local dentro de `calculateAllMetrics`; ahora se expone para que el AllocationCard la lea.)

`netWorthCents` se redefine: `Σ todos los balances + marketValueOfHoldings`. Los yields **no** se suman aparte porque su principal **ya está dentro del balance bancario** (modelo cuenta digital MX, e.g. pagaré BBVA Libretón). Esta suposición ancla todo el resto del diseño.

`liquidAssetsCents` (gross bank+cash) se conserva sin cambios; `safeToSpend`/`buyingPower` siguen leyéndolo y no se ajustan. La diferencia entre "liquid total" y "free liquid" se materializa **solo en el render del AllocationCard**, donde el segmento "Líquido" del bar = `liquidAssetsCents - yieldsValueCents` (clamped a 0).

**`AllocationCard`** (`features/dashboard/ui/widgets/allocation_card.dart`, archivo dedicado mirror del patrón de `portfolio_pie_chart.dart`) renderiza una barra horizontal apilada de **3 segmentos** que suman 100% del activo positivo: free liquid (`cs.primary`), stocks (`AppColors.catSapphire`), yields (`AppColors.income`). Implementación: `Row` de `Expanded(flex: ((cents/total)*1000).round())` dentro de un `ClipRRect` — sin `fl_chart` (no se necesita para 3 segmentos). Debajo del bar: legend de chips por segmento `[dot] Label · XX% · $amount`. Auxiliares `Wrap` (no `Row`, evita overflow horizontal): "Deuda actual: -$X" en `cs.error` y "Crédito disp.: +$Y" en `onSurfaceVariant`. Renderiza `SizedBox.shrink()` cuando los 3 buckets son 0; oculta cada chip auxiliar cuando su valor es 0; con un solo bucket > 0, ocupa el bar completo.

Posicionado en `DashboardSummaryTab` entre `_NetWorthCard` y `_MetricsGrid`.

**Filtro de cuentas** (`accountIds` del `DashboardFilterViewModel`): liquid / yields / debt / revolving lo respetan via SQL. **Holdings lo ignoran** — son globales (mismo principio que `HoldingsListTab` en `/accounts`); `_loadMarketValueByCurrency` siempre lee todos los holdings activos. Cuando el usuario filtra cuentas, ve "en mis N cuentas seleccionadas $X liquid, mi portfolio global tiene $Y stocks". Asimetría intencional, consistente con la decisión de holdings-globales del feature.

**DI**: `DashboardRepository` recibe ahora `InvestmentHoldingLocalStore`, `InvestmentLotLocalStore`, `MarketPriceLocalStore` como dependencias **opcionales**. Si null (legacy / tests), el bucket de stocks contribuye 0. `DashboardRouteScope` los instancia inline desde el `DatabaseHelper` (mismo patrón que `DashboardLocalStore`). `_loadMarketValueByCurrency` reusa `computePortfolioDistribution` y suma `slice.marketValue` por currency convirtiendo a cents (`(value * 100).round()`).

**Invariante post-buy** (cubierta por test): cuenta USD con $1000, compra 5 × $100 + $5 fee → balance $495 + market value $500 = net worth $995. Diferencia vs pre-buy = $5 (los fees). Después de un cambio de precio el net worth fluctúa por `Σ qty × Δprice`.

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
| 4 | Backend cron for `market_prices` + frontend staleness banner | 2026-04-21 | See §Backend Cron. Yahoo `v8/finance/chart/{SYMBOL}` per-symbol; `_StalePricesBanner` when `maxFetchedAt > 2 días` |
| 5 (parcial) | Charts — PieChart de distribución | 2026-04-21 | See §Distribution chart (Fase 5). LineChart movido a Fase 5.1 — no hay historia diaria en `market_prices` |
| 6 | Allocation in dashboard | 2026-04-25 | See §Dashboard Integration (Fase 6). 3-bucket bar (free liquid / stocks / yields) + chips de deuda / crédito disp. Yields restados de liquid en render para evitar doble conteo |
| 7 | Splits — persistencia + sync (infraestructura silenciada hasta Fase 8) | 2026-04-25 | See §Splits. Migración 007 backend / 005 frontend (`_version` 4→5). Proto `InvestmentSplitService`. Sync order 8 (market_price bumpeado a 9). DI wireado en `AccountsRouteScope`; math y UI todavía no consumen |
| 8 | Splits — math + UI + dashboard | 2026-04-25 | See §Splits. Walk cronológico de `(lots ∪ splits)` en `position_math`/`pnl_math`; fallback ajustado en `current_price_resolver`; callback `splitsFor` en `portfolio_distribution`. `SplitFormScreen` nueva, FAB sheet con 3ra acción, timeline mixto (sealed `_HoldingEvent`). `DashboardRepository` consume splits para market value correcto |

### Fase 5.1 — Performance LineChart (30 días) ⏳ PENDING

Bloqueado hoy por el schema de `market_prices` (PK `(symbol, exchange)` → una sola fila por símbolo, sin historia diaria). Requiere su propio diseño antes de implementarse.

Acceptance (plan tentativo):
- Nueva tabla `market_price_history(symbol, exchange, price_date)` con PK compuesta — o rediseño de `market_prices` para soportar historia.
- Backend cron extendido: el endpoint Yahoo `v8/finance/chart/{SYMBOL}` ya devuelve serie diaria si se pide `range=1mo&interval=1d`; el parser actual sólo lee `meta.regularMarketPrice`, hay que extender para persistir la serie. Backfill en el primer tick tras migrar.
- Nuevo sync handler `market_price_history` pull-only con cursor por usuario (mirror del pattern de `market_price`).
- Frontend migration v4→v5, nuevo `MarketPriceHistoryLocalStore`.
- LineChart 30 días reconstruido on-the-fly: `Σ over holdings of (lotQtyAtDate(t) × priceAt(t))` por día, sobre la ventana.
- Extender el `SegmentedButton` de `HoldingsListTab` a 3 segments (`Holdings | Distribución | Performance`).

**DoD:** LineChart renderiza con ≥ 30 días de historia + ≥ 50 holdings; widget test del chart; la curva refleja performance real (no la curva cantidad-valorada-a-precio-de-hoy, que es un anti-patrón considerado y rechazado durante la brainstorm de Fase 5).

### Deferred (post-MVP)

- Corporate actions other than splits (spinoffs, mergers, rights issues).
- Auto dividend detection.
- Tax / capital-gains reports.
- Snapshot materialization for performance charts (only if >50 holdings hurts render time).
- Symbol autocomplete on the holding form via a new backend RPC.

## Critical Files

**Backend:**
- `backend/migrations/003_investments.sql`, `004_investment_lots_account.sql`, `005_drop_holding_account.sql`, `007_investment_splits.sql`
- `backend/internal/investment/` (model, validation, `holding_repository.go`, `lot_repository.go`, `split_repository.go`, `market_price_repository.go`, `handler.go`)
- `backend/internal/sync/entity_type.go`
- `backend/cmd/server/main.go`

**Frontend:**
- `frontend/assets/migrations/002.sql`, `003.sql`, `004.sql`, `005.sql`
- `frontend/lib/src/core/db/database_helper.dart` (`_version`)
- `frontend/lib/src/features/investments/` (whole directory, incluye `domain/portfolio_distribution.dart`, `domain/investment_split.dart`, `data/investment_split_*.dart`, `ui/widgets/portfolio_pie_chart.dart`, `ui/split_form_screen.dart`)
- `frontend/lib/src/features/accounts/ui/accounts_route_scope.dart` (DI wiring)
- `frontend/lib/main.dart` (sync handlers registered in `SyncService.handlers`)
- `frontend/lib/src/features/dashboard/domain/dashboard_metrics.dart` (Fase 6 — 4 campos nuevos)
- `frontend/lib/src/features/dashboard/data/dashboard_local_store.dart` (Fase 6 — `getYieldsValueByCurrency`)
- `frontend/lib/src/features/dashboard/data/dashboard_repository.dart` (Fase 6 — investment stores opcionales, `_loadMarketValueByCurrency`)
- `frontend/lib/src/features/dashboard/ui/dashboard_route_scope.dart` (Fase 6 — DI de holding/lot/market_price stores)
- `frontend/lib/src/features/dashboard/ui/widgets/allocation_card.dart` (Fase 6 — widget público)
- `frontend/lib/src/ui/screens/dashboard/dashboard_summary_tab.dart` (Fase 6 — uso de AllocationCard)
- `frontend/test/position_math_test.dart`, `frontend/test/pnl_math_test.dart`, `frontend/test/current_price_resolver_test.dart`, `frontend/test/portfolio_distribution_test.dart`, `frontend/test/portfolio_pie_chart_test.dart`, `frontend/test/dashboard_repository_allocation_test.dart`, `frontend/test/allocation_card_test.dart`, `frontend/test/investment_split_test.dart`

**Patterns to mirror when extending:**
- Generator: `frontend/lib/src/features/yield_configs/data/yield_transaction_generator.dart`.
- Deterministic namespace: `frontend/lib/src/core/ids/deterministic_namespace.dart`.
- Repository with cursor bump: `backend/internal/yieldconfig/repository.go`.
- Dashboard metrics integration: `frontend/lib/src/features/dashboard/data/dashboard_local_store.dart` + `dashboard_repository.dart`.

## Known Risks

- **Yahoo endpoint instability**: it's a non-official API. Precedent: `v7/finance/quote` went behind crumb+cookie auth (401) and we migrated to `v8/finance/chart` per-symbol. Mitigation: retry + exponential backoff + long backoff on 429, **short-circuit on 4xx-non-429 so a future auth flip bails on the first 401 instead of exhausting the ladder**, feature flag (`MARKETPRICE_ENABLED`), fixture-backed tests. If Yahoo breaks for good we pick a different free provider at that moment rather than reimplementing crumb+cookie state (fragile) or carrying a paid fallback we don't need today.
- **Cron cursor bumping at scale**: for N users × M symbols, many `INSERT ... ON CONFLICT`. Fine for personal-scale; batch writes if it grows.
- **Precision drift on doubles**: for extreme quantities/prices, consider a `pgtype.Numeric` / Decimal path later. Not expected in practice.
- **Multi-device edit races on the same lot**: standard LWW; existing "conflict resolved" banner in the sync infra already surfaces it.
