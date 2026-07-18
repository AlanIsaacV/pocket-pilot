# Investment Splits — Design

**Date:** 2026-04-25
**Status:** Drafted, pending implementation
**Owner:** Alan

## Context

Algunos holdings del usuario tuvieron stock splits (forward y/o reversos). Hoy la math del feature (`position_math`, `pnl_math`, `current_price_resolver`, `portfolio_distribution`) opera sobre lots inmutables; los precios de Yahoo (`market_prices`) ya vienen split-adjusted, por lo que el market value se calcula sobre `original_qty × adjusted_price` y queda incorrecto. El costo promedio también se distorsiona.

La arquitectura del feature ([investments.md](../../context/architecture/investments.md)) explícitamente listaba splits como out-of-scope post-MVP con un workaround manual ("editar lots a mano"). Este spec elimina ese workaround agregando splits como first-class events.

## Decisiones de diseño

Confirmadas en brainstorming con el usuario:

1. **Modelo de datos: events sincronizados.** Nueva entity `investment_split` mirror del patrón de `investment_lot` (proto + sync handler + local store + remote service + repository). Lots permanecen inmutables; los splits modifican qty/price en el read-path de la math.
2. **UX entrada:** FAB bottom sheet en `HoldingDetailScreen` gana 3ra acción "Registrar split" → nuevo `SplitFormScreen`.
3. **UX display:** Lista del HoldingDetailScreen pasa de "lista de lots" a "timeline mixto" — lots y splits ordenados por `occurred_at` desc, con tratamiento visual distinto (icono `call_split`, fondo tenue para splits).
4. **Reverse splits:** sí, soportados (`ratio_num` y `ratio_den` ambos > 0, sin restricción num >= den).
5. **Math:** walk cronológico — events (lots + splits) sorted by `(occurred_at ASC, created_at ASC)`. Cuando aparece un split, el FIFO state pendiente se ajusta in-flight.

## Schema

### Backend (PostgreSQL — `006_investment_splits.sql`)

```sql
CREATE TABLE investment_splits (
  id            uuid PRIMARY KEY,
  user_id       uuid NOT NULL,
  holding_id    uuid NOT NULL REFERENCES investment_holdings(id),
  ratio_num     NUMERIC(18,8) NOT NULL CHECK (ratio_num > 0),
  ratio_den     NUMERIC(18,8) NOT NULL CHECK (ratio_den > 0),
  occurred_at   DATE NOT NULL,
  notes         TEXT,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

CREATE INDEX idx_investment_splits_user_updated_at
  ON investment_splits(user_id, updated_at);
CREATE INDEX idx_investment_splits_holding_active
  ON investment_splits(holding_id, occurred_at) WHERE deleted_at IS NULL;
```

`NUMERIC(18,8)` en ratio fields permite splits exóticos (e.g. 7-for-3) sin pérdida de precisión. En Dart los manejamos como `double`.

### Frontend (SQLite — `005.sql`)

Mirror del backend sin `user_id`. `_version` bump 4 → 5 en `database_helper.dart`.

### Proto

`proto/pocket_pilot/v1/investment_split_service.proto` con `InvestmentSplitService { List, Upsert, Delete }`. Mensaje `InvestmentSplit` con los mismos fields.

Generado vía `scripts/gen_proto.sh` (Go + Dart).

## Sync Integration

- `EntityInvestmentSplit = "investment_split"` en `backend/internal/sync/entity_type.go`.
- Sync order: insertar entre `investment_lot` y `market_price`.
  - Nuevo orden: `account → category → tag → transaction_template → yield_config/user_preference → investment_holding → investment_lot → **investment_split** → market_price → transaction → goal → budget`.
- Server: `SplitRepository.Upsert/SoftDelete` bumpea cursor `investment_split` para el `user_id` afectado (mismo patrón que lots).
- Client: `InvestmentSplitSyncHandler` con pull/pushUpsert/pushDelete completo (writable).

## Math

### `position_math.dart` (extendido)

```dart
PositionResult computePosition(
  List<InvestmentLotModel> lots, {
  List<InvestmentSplitModel> splits = const [],
}) { ... }
```

Algoritmo: build event timeline `(lots ∪ splits)` sorted `(occurredAt ASC, createdAt ASC)`. Walk events:
- **Buy:** enqueue FIFO `(qty, price, fee)`; acumula al weighted avg.
- **Sell:** consume FIFO; resta del weighted avg en proporción a la qty consumida.
- **Split:** ratio = `num / den`. Para cada lot en FIFO: `qty *= ratio, price /= ratio`. Para weighted avg state: `totalQty *= ratio, totalCostQty *= ratio` (avg cost = totalCost/totalQty queda dividido por ratio, que es lo correcto).

Después del walk, return `(netQuantity, weightedAvgCost, fifoRemainingLots)`. **API de retorno preservada** — los `fifoRemainingLots` ahora reportan post-split values (qty y price ajustados al "ahora").

### `pnl_math.dart` (extendido)

`computeRealizedPnL(lots, splits)` walk idéntico, pero acumula realized en cada sell event:
- `proceeds = sell.qty * sell.price - sell.fee/100`
- `costBasisConsumed` se computa de la cola FIFO en estado actualizado (post-splits previos al sell).
- `realized = proceeds - costBasisConsumed`.

`computeUnrealizedPnL` no necesita firma nueva — recibe `position` ya ajustada.

### `current_price_resolver.dart` (extendido)

Precedencia preservada `market → manual → último lote → null`, pero el fallback al último lote ahora aplica el ratio acumulado de splits posteriores al lote: `lot.price / Π(splits.ratio after lot.occurredAt)`. Sin esto, el fallback devuelve el precio pre-split y la math se rompe en holdings sin market_price ni manual_price.

Firma extendida: `resolveCurrentPrice({holding, marketPrice, lots, splits})`.

### `portfolio_distribution.dart` (extendido)

`computePortfolioDistribution` recibe un nuevo callback `splitsFor(String holdingId)`. Lo pasa a `computePosition` y `resolveCurrentPrice`. El consumer (`InvestmentViewModel`) cachea splits per holding igual que lots.

## UI

### `SplitFormScreen` (nuevo)

Form fields: `ratio_num` (int input, default 2), `ratio_den` (int input, default 1), `occurred_at` (date picker), `notes` (optional text). Validación: ambos ratios > 0, num != den (no-ops bloqueados), occurred_at requerido. Hint inline "2 a 1 = forward; 1 a 10 = reverso".

Rutas: `/accounts/holdings/:holdingId/splits/new`, `/accounts/holdings/:holdingId/splits/:splitId/edit` bajo `AccountsRouteScope`.

### `HoldingDetailScreen` (modificado)

- **FAB bottom sheet:** se agrega 3ra acción "Registrar split" entre Comprar/Vender. Ícono `call_split`.
- **Lista de operaciones:** hoy es `ListView.builder` sobre lots descendente. Cambia a lista de eventos mixtos `List<_HoldingEvent>` donde `_HoldingEvent` es un sealed type `LotEvent | SplitEvent`. Sort `occurred_at DESC, createdAt DESC`. Card de split: icono, label "Split 2:1 (forward)" o "Split 1:10 (reverso)", fecha, notes opcional. Swipe-to-delete habilitado para splits.

### `InvestmentViewModel`

Extender con `Map<String, List<InvestmentSplitModel>> _splitsByHolding`, getter `splitsFor(id)`, métodos `saveSplit/deleteSplit`. `loadPortfolio` paraleliza lots + price + dividends + **splits** por holding.

### `HoldingsListTab` y `_TotalsFooter`

Sin cambios en su código — leen del VM. La math que ahora respeta splits hace que los números sean automáticamente correctos.

### Dashboard `AllocationCard`

Sin cambios. `DashboardRepository._loadMarketValueByCurrency` ya pasa los lots vía `lotsFor`; sólo necesita pasar también `splitsFor` cargando del nuevo `InvestmentSplitLocalStore` (DI extendida en `DashboardRouteScope`).

## DI Wiring

- `AccountsRouteScope`: provee `InvestmentSplitLocalStore`, `InvestmentSplitRemoteService`, `InvestmentSplitRepository`. `InvestmentViewModel` recibe el repo.
- `DashboardRouteScope`: instancia `InvestmentSplitLocalStore` (mismo patrón que el holding/lot/price stores agregados en Fase 6).
- `DashboardRepository`: nuevo parámetro opcional `InvestmentSplitLocalStore? splitStore`. `_loadMarketValueByCurrency` lee splits por holding y los pasa a `computePortfolioDistribution`.
- `main.dart`: registrar `InvestmentSplitSyncHandler` en `SyncService.handlers` en posición correcta.

## Edge cases

- **Sell > available post-split:** ya cubierto por `InvestmentMathException.sellExceedsAvailable` — el walk cronológico hace que se detecte naturalmente.
- **Split con fecha futura:** se aplica igualmente (los anuncios suceden antes del effective date; el usuario puede registrar de antemano). Sin filtro por `occurred_at <= now`.
- **Holdings archivados:** form bloquea registrar splits sobre `holding.deletedAt != null`.
- **Soft-deleted splits:** math filtra `deletedAt == null` (mismo patrón que lots).
- **Multi-device LWW:** estándar, mismo patrón que lots.
- **Fractional shares post-reverso:** se permiten (NUMERIC(18,8)). Si el broker pagó cash por la fractional, el usuario lo registra como un sell aparte.

## Out of scope

- **Auto-detect splits desde Yahoo:** la API `chart?range=1mo&interval=1d` retorna `events.splits` — futuro nice-to-have, manual primero.
- **Spinoffs / mergers / rights issues:** mecánica diferente (genera nuevo holding con cost basis transferida); no en este spec.

## Tests

**Domain math (puro Dart):**
- `position_math_test.dart` — extender:
  - Forward 2:1 antes de un buy: el split no afecta nada (qty pre-split=0).
  - Forward 2:1 entre dos buys: lot1 ajustado, lot2 no.
  - Reverso 1:10 entre dos buys.
  - Múltiples splits acumulan (2:1 luego 3:1 → ratio total 6:1 sobre lots iniciales).
  - Sell entre splits: FIFO consume con ratio aplicado al momento del sell.
  - Determinismo sobre orden de input mezclado.
- `pnl_math_test.dart` — sell post-split consume lot pre-split, realized PnL correcto.
- `current_price_resolver_test.dart` — last-lot fallback ajustado por ratio acumulado.
- `portfolio_distribution_test.dart` — split aumenta market value cuando price es post-split.
- `dashboard_repository_allocation_test.dart` — split en un holding ajusta `marketValueOfHoldingsCents`.

**Backend (Go):**
- `split_repository_test.go` — Upsert / SoftDelete / List con cursor bump.
- Integración handler test mínimo.

**Mapping:**
- `investment_split_test.dart` — fromMap/toMap/fromProto/toProto/normalized.

## Critical files

**New:**
- `backend/migrations/006_investment_splits.sql`
- `backend/internal/investment/split_repository.go` (mirror de lot_repository)
- `proto/pocket_pilot/v1/investment_split_service.proto`
- `frontend/assets/migrations/005.sql`
- `frontend/lib/src/features/investments/domain/investment_split.dart`
- `frontend/lib/src/features/investments/data/investment_split_local_store.dart`
- `frontend/lib/src/features/investments/data/investment_split_remote_service.dart`
- `frontend/lib/src/features/investments/data/investment_split_sync_handler.dart`
- `frontend/lib/src/features/investments/data/investment_split_repository.dart`
- `frontend/lib/src/features/investments/ui/split_form_screen.dart`
- Tests: `frontend/test/investment_split_test.dart` + nuevos cases en los tests existentes citados arriba.

**Modified:**
- `backend/internal/investment/handler.go` (extender con SplitHandler)
- `backend/internal/sync/entity_type.go` (`EntityInvestmentSplit`)
- `backend/cmd/server/main.go` (wire del nuevo handler)
- `scripts/gen_proto.sh`
- `frontend/lib/src/core/db/database_helper.dart` (`_version` 4 → 5)
- `frontend/lib/src/features/investments/domain/position_math.dart` (walk cronológico con splits)
- `frontend/lib/src/features/investments/domain/pnl_math.dart` (sell post-split consume FIFO ajustado)
- `frontend/lib/src/features/investments/domain/current_price_resolver.dart` (fallback ajustado)
- `frontend/lib/src/features/investments/domain/portfolio_distribution.dart` (callback `splitsFor`)
- `frontend/lib/src/features/investments/ui/investment_view_model.dart` (cache splits, paraleliza load, save/delete)
- `frontend/lib/src/features/investments/ui/holding_detail_screen.dart` (FAB bottom sheet + timeline mixto)
- `frontend/lib/src/features/investments/ui/holdings_list_tab.dart` (sin cambios estructurales — la math actualizada se refleja vía VM)
- `frontend/lib/src/features/accounts/ui/accounts_route_scope.dart` (DI splits)
- `frontend/lib/src/features/dashboard/ui/dashboard_route_scope.dart` (DI splits)
- `frontend/lib/src/features/dashboard/data/dashboard_repository.dart` (pasar splits a `_loadMarketValueByCurrency`)
- `frontend/lib/main.dart` (registrar sync handler)
- `frontend/lib/src/ui/router.dart` (rutas `/holdings/:id/splits/new` y `:splitId/edit`)
- Tests existentes citados.

## Verificación

1. **Unit tests:** `flutter test` — todos pasan, incluido el nuevo `investment_split_test.dart` y las extensiones de los tests de math.
2. **Backend:** `go test ./internal/investment/...` con TEST_DATABASE_URL.
3. **Análisis estático:** `flutter analyze` y `go vet ./...` limpios.
4. **Smoke en device:**
   - Crear holding "AAPL", buy 10 @ $100. avg=$100, qty=10.
   - Registrar split 2:1 fecha posterior al buy. Lista muestra el split arriba del buy. avg=$50, qty=20.
   - Registrar otro buy 5 @ $40 post-split. avg ponderado = (20×50 + 5×40)/(25) = 1200/25 = $48.
   - Sell 5 @ $60 post-split: realized = 5×60 - 5×50 (FIFO de los primeros 20 a $50) = $50.
   - Eliminar el split: avg vuelve a $100, qty 10 (asumiendo solo el lot original).
   - Dashboard `AllocationCard`: market value refleja qty post-split × price post-split (Yahoo ya viene adjusted).
