# Notification Capture Architecture

Auto-suggestion of transactions from Android bank push notifications. iOS not supported by the OS.

## Scope (v1)

- **Bank coverage:** BBVA México only.
- **Mode:** Suggestions only — every captured notification produces a `PendingTransaction` that the user must approve or edit before it becomes a real `Transaction`.
- **Parsers:** Declarative JSON. Asset embedded in the app (`assets/parsers/bbva_mx.json`) acts as a fallback before the first sync; the source of truth is the backend `notification_parsers` global table, distributed pull-only (Phase 3+). Bumping `version` server-side ships new regex without a redeploy.
- **Account/category mapping:** Implicit — populated automatically from the user's approval decisions ("learn from approval"). No user-facing UI to manage mappings or rules.
- **Out of scope (v1):** auto-confirm mode, additional banks, admin UI to promote candidate parsers.

## Pipeline

```
[Android NLS]                                                      [Flutter isolate]
  StatusBarNotification (BBVA pkg)                                   on app open / refresh
       │                                                                   │
       ▼                                                                   ▼
  package allowlist filter ────► captured_notifications ─────► ParserEngine.tryMatch
                                       (status=received)               │       │
                                                                       │       └─ no match → status=unparseable
                                                                       │          (Phase 4: send to server LLM)
                                                                       ▼
                                                       resolve account_id from account_card_mappings
                                                       resolve category_id from transaction_rules
                                                                       │
                                                                       ▼
                                                          PendingTransaction (status=pending)
                                                                       │
                                                                       ▼   (PendingReviewSheet — user edits & approves)
                                                                       │
                                       ┌───────────────────────────────┼───────────────────────────────┐
                                       ▼                               ▼                               ▼
                              TransactionRepository      account_card_mappings UPSERT     transaction_rules UPSERT
                              .createTransaction()       (digits mapping when digits      (if categoryId chosen; longest-
                                                          present; else (bank_id,          prefix escalation when the
                                                          pattern_id) mapping)             first word is already taken)
                                       │                               │                               │
                                       └───────────────► sync_outbox ◄─┴───────────────────────────────┘
```

## Data model

### Tables (frontend SQLite — local-only unless noted)

| Table | Purpose | Synced |
|-------|---------|--------|
| `captured_notifications` (mig 007) | Raw push notifications captured by NLS Kotlin. Schema FROZEN — Kotlin writes to it directly. | No (PII potentially sensitive) |
| `pending_transactions` (mig 008 + mig 012 repair) | Suggestions ready for user review/approval. `suggested_category_id` was originally added in-place to mig 008 after some devices already ran it; mig 012 (`ALTER TABLE ADD COLUMN`) repairs schema drift on existing installs. Mig 008 was later restored to its original state — the column is exclusively added by 012. | No (approval becomes a `Transaction` which IS synced) |
| `notification_parsers` (mig 008) | Local cache of parser definitions. Phase 2: seeded from asset. Phase 3: replaced by sync delta-pull from backend; asset stays as fallback. | Yes (pull-only) |
| `account_card_mappings` (mig 010 + mig 017) | (`bank_id`, `last_digits`) → `account_id`; since FE mig 017 / BE mig 019 also (`bank_id`, `pattern_id`) → `account_id` for digit-less notifications (`last_digits` nullable, CHECK at least one of `last_digits`/`pattern_id`; proto field `pattern_id` = 8). Auto-populated on approval. | Yes |
| `transaction_rules` (mig 011) | `match_text` (substring) → `category_id`. Auto-populated on approval. | Yes |
| `package_observations` (mig 016) | Log liviano sin PII: `(package_name, first_seen_at, last_seen_at, noti_count)`. NLS UPSERT por cada noti del SO. Pobla el picker "Mis bancos". Retención 90d (sweeper Fase 6 extendido). | No (local-only) |
| `watched_packages` (mig 016) | Per-device toggle: qué packages procesa el NLS aquí. NLS lee `WHERE enabled=1` en `onListenerConnected()`. | No (per-device intencionalmente) |
| `bank_aliases` (mig 016) | Per-user alias: `(package_name, bank_id?, display_label)`. Sincroniza para que la decisión "Mi BBVA" llegue como hint a otros devices del mismo usuario. | Yes |
| `bank_packages` (mig 016) | Cache local del catálogo global pull-only `(package_name → bank_id, default_label)`. Admin promueve sugerencias server-side. | Yes (pull-only) |

### `captured_notifications` lifecycle (`status` column)

```
received ─┬─► matched_local   (parser matched in client, PendingTransaction created)
          ├─► matched_server  (Phase 4: server parser matched after client miss)
          ├─► llm_used        (Phase 4: server LLM extracted fields)
          ├─► ignored         (matched ignore_pattern, OTP, promo, or user dismissed)
          ├─► unparseable     (no match anywhere — drop or surface to user for manual)
          └─► consumed        (PendingTransaction approved → real Transaction created)
```

## Components

### Android native (`frontend/android/app/src/main/kotlin/app/pocketpilot/notifications/`)

- `BankNotificationListenerService.kt` — extends `NotificationListenerService`. **Fase 8**: la allowlist hardcoded de strings se reemplazó por un cache en memoria `@Volatile var watchedPackages: Set<String>` que se rellena desde `watched_packages WHERE enabled=1` en `onListenerConnected()` (rebind = refresh). Cada noti que llega pasa por `handleNotification(sbn)`:
  1. **Siempre**: `db.upsertPackageObservation(sbn.packageName, sbn.postTime)` — log liviano sin PII para alimentar el picker "Mis bancos".
  2. **Solo si** `sbn.packageName in watchedPackages`: el path original que escribe a `captured_notifications` con title/text/big_text.
  - `onNotificationPosted(sbn)` — every new notification while the listener is bound.
  - `onListenerConnected()` — refresh del cache + backfill from `activeNotifications`. Cubre "user granted permission after notifications already arrived" y "OS restarted the listener". Idempotente thanks to `NotificationDb` dedupe.
- `NotificationDb.kt` — minimal DB writer. Dedupes via `(package_name, posted_at ± 1 minute, text+title)` query before INSERT. Generates deterministic UUIDs from SHA-256 of the payload as a second-line idempotency defense. **Fase 8** añade dos métodos: `upsertPackageObservation(packageName, postedAtMillis)` (INSERT … ON CONFLICT(package_name) DO UPDATE SET last_seen_at=MAX(...), noti_count+=1) y `getEnabledWatchedPackages(): Set<String>` (SELECT package_name FROM watched_packages WHERE enabled=1). Ambos manejan el caso DB-no-existe / mig-no-corrida devolviendo no-op / set vacío respectivamente.
- `BootReceiver.kt` — re-enables the NLS component after `BOOT_COMPLETED` (defense for OEMs that disable it).

`AndroidManifest.xml` declares the `<service>` with `BIND_NOTIFICATION_LISTENER_SERVICE` and the `<receiver>` for boot. Permission flow: user must manually toggle the listener in *Settings → Notification access*. The OS does not allow a runtime permission prompt.

### Permission bridge (`MainActivity.kt`)

MethodChannel `com.pocketpilot/notification_capture` exposes:
- `isPermissionGranted` — reads `Settings.Secure.enabled_notification_listeners` directly to verify the listener is enabled.
- `openSettings` — opens `Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS`.

Frontend wrapper: `NotificationPermissionService` (`features/notification_capture/data/`).

### Parser definitions

Schema (`assets/parsers/bbva_mx.json` for v1):

```json
{
  "schema_version": 1,
  "bank_id": "bbva_mx",
  "package_names": ["com.bbva.bancomermovil", "com.bancomer.mbanking"],
  "version": 1,
  "default_currency": "MXN",
  "ignore_patterns": [
    {"field": "title|text|big_text", "regex": "...", "flags": "i"}
  ],
  "patterns": [
    {
      "id": "purchase_card",
      "transaction_type": "expense",
      "match": {"field": "text", "regex": "(?<amount>...)...", "flags": "is"},
      "captures": {
        "amount_cents":         {"from": "amount", "transform": "money_to_cents"},
        "currency_code":        {"from": "currency", "transform": "upper", "default": "MXN"},
        "merchant_description": {"from": "merchant", "transform": "trim"},
        "card_last_digits":     {"from": "digits"}
      }
    }
  ]
}
```

**Important:** Dart `RegExp` uses ECMAScript named groups `(?<name>...)`, not Python's `(?P<name>...)`. Backend regex validator (Phase 4) must enforce the same when accepting LLM-proposed patterns.

`transform` is a closed whitelist enforced in the engine: `upper`, `lower`, `trim` (string→string). `money_to_cents` is special-cased in the engine because its output is `int`. Adding a new transform requires code in `parser_engine.dart`, NOT a JSON change — prevents injection from server-distributed parsers.

### Parser engine (`features/notification_capture/engine/parser_engine.dart`)

- Per parser: `package_names` filter first → `ignore_patterns` (any match → drop) → `patterns` in order (first match wins).
- Per `RegExp.firstMatch`: 50 ms timeout via `Stopwatch` as a ReDoS guard. Backend will validate complexity before persisting candidate parsers in Phase 4.
- Returns `ParserMatch` with extracted `amount_cents`, `currency_code`, `merchant_description`, `card_last_digits`, `transaction_type`.

Tests live in `test/notification_parser_engine_test.dart`. The positive cases come from a real-data fixture file (`frontend/test_data/bbva_mx_real_notifications.json`) loaded via `dart:io` `File`, validated with `expected.{pattern_id, transaction_type, fields}`. Negative cases are inline (OTP, promo, non-bank package, unrecognized text). Bumping the parser to v3 means: capture new fixtures, add expected blocks, run test, then bump server-side via UPDATE SQL.

### Repository (`NotificationCaptureRepository`)

`processInbox()` — drains `received` notifications:
1. Tries each active parser in order until one matches.
2. On match: looks up `account_card_mappings` (latest active by `updated_at` for `bank_id` + `last_digits`) → `suggested_account_id`. When the notification carries no card digits (BBVA `purchase_tdc` is the only such pattern today), falls back to the `(bank_id, pattern_id)` mapping via `findByBankAndPattern` (same latest-active semantics). See `_resolveAccount` in `notification_capture_repository.dart`.
3. On match: looks up `transaction_rules` (substring of merchant description in `match_text`, ordered by `LENGTH(match_text)` DESC, `priority` DESC, `updated_at` DESC — longest prefix wins) → `suggested_category_id`.
4. Inserts `PendingTransaction` and marks the notification `matched_local`.

`approve()` — user confirmed the suggestion:
1. Calls `TransactionRepository.createTransaction()` (which handles the outbox enqueue for the new `Transaction`).
2. Marks the `PendingTransaction` `approved` and the source `CapturedNotification` `consumed`.
3. **Implicit learning:** if the notification carried `card_last_digits` and the chosen account differs from the existing mapping (or none existed), inserts a new row in `account_card_mappings` + outbox (`_learnDigitsMapping`). When it carried **no digits**, learns a (`bank_id`, `pattern_id`) mapping instead under the same differs-or-none condition (`_learnPatternMapping`), so the next digit-less notification from that pattern resolves.
4. **Implicit learning:** if a category was chosen, derives `match_text` as the **first word** of the merchant description (e.g. "STARBUCKS REFORMA 222" → `"STARBUCKS"`); if an active rule with that text already points at a **different** category, escalates to the **first two words** instead of overwriting (e.g. `DIDI` → Transporte stays; approving "DIDI FOOD MX" → Comida learns `DIDI FOOD`). Upserts if no active rule with the derived `match_text` exists for the same category.

**Why first word + longest prefix?** Substring matching against the full merchant string would only match identical strings. Taking the first word makes "STARBUCKS REFORMA 222" learn a rule that also catches "STARBUCKS POLANCO". When two merchants share a first word with different categories (`DIDI` vs `DIDI FOOD`), the two-word escalation plus `LENGTH(match_text)` DESC matching lets both rules coexist instead of flip-flopping on every approval. Known gap: if the two-word rule already exists for yet another category, its category is overwritten (no third-level escalation) — relevant to the auto-confirm confidence gate. Generic first words ("PAGO", "COMPRA") could still over-match. Acceptable for v1.

`approveAllResolved()` — fast-review batch path (frictionless-capture f2):
1. Iterates pending suggestions and approves those with BOTH `suggested_account_id` and
   `suggested_category_id` set, each through the normal `approve()` path — learning, outbox
   writes, and `parser_feedback` rows (`was_helpful` null) stay identical to a manual approval.
2. Continue-on-error: a failed item stays `pending` (logged; already-approved items are never
   rolled back) so the next batch retries only the failures. Returns `({approved, failed})`
   for UI feedback.

`candidateCategoriesFor(pending)` — quick-pick candidates (frictionless-capture f2): up to 3
category IDs for a suggestion whose account is resolved but category is missing. Learned rules
win by specificity: `TransactionRuleLocalStore.findRulesForDescriptionPrefix(description)`
returns active rules whose `match_text` prefixes the merchant description (`LENGTH(match_text)`
DESC); remaining slots fill with `TransactionRepository.getTopCategoryIdsForAccount(accountId)`
(most-used categories for the suggested account), deduplicated.

`reprocessUnparseable()` — re-runs the engine against everything currently in `status='unparseable'`. Resets those rows to `received` (clearing any stale `pending_tx_id`) and calls `processInbox()`. Returns `({reopened, matched})` for UI feedback. Used by the "Reintentar no parseables" action button on the bandeja AppBar (see UI section). Necessary because parser bumps (v1→v2 in Phase 3.5, future LLM fallback in Phase 4) need to reach notifications that the previous engine had already given up on.

### Backend parser table (Phase 3+)

**Migration `012_notification_parsers.sql`** creates the global table:

```sql
CREATE TABLE notification_parsers (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bank_id     TEXT NOT NULL UNIQUE,
    version     INT  NOT NULL CHECK (version > 0),
    definition  JSONB NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  timestamptz NOT NULL DEFAULT NOW(),
    updated_at  timestamptz NOT NULL DEFAULT NOW(),
    deleted_at  timestamptz
);
```

Seeded inline with the BBVA MX definition using PostgreSQL dollar-quoted strings (`$bbva$ ... $bbva$::jsonb`) to avoid escaping the regex backslashes in the JSON. The seed mirrors `frontend/assets/parsers/bbva_mx.json` byte-for-byte at the time of the migration; future bumps happen via UPDATE SQL (or, post-Phase 4, an admin-only RPC), never by editing the migration.

**Module `internal/notificationparser/notificationparser.go`** follows the cardmapping single-file template (Repository + Handler in one package), with two structural differences from user-scoped modules:

- No `user_id` filtering anywhere — the table is global; every authenticated user gets the same parsers.
- `Upsert` and `SoftDelete` call a private `bumpAllUsers(tx, at)` that iterates `SELECT id FROM users` and calls `cursor.Bump(tx, uid, EntityNotificationParser, at)` for each. This guarantees `GetSyncStatus` reports the change to every client. Acceptable for v1 (< ~10k users); replace with a virtual global cursor if it becomes a hotspot.

`GetByBankID(bankID)` is exposed for internal Phase 4 usage (server-side engine retry before invoking the LLM).

**Proto `notification_parser_service.proto`** exposes only `ListNotificationParsers(updated_since, page)` returning `repeated NotificationParser { bank_id, version, definition (string), updated_at, deleted_at }`. `definition` is transported as a string (the JSON-serialized parser) rather than `google.protobuf.Struct` so pattern order is preserved and the message stays small. Clients deserialize on the way into local SQLite. There are no client-facing Upsert/Delete RPCs in Phase 3.

**Update flow without redeploy:**

```sql
UPDATE notification_parsers
SET version    = 2,
    definition = $bbva$ {...new JSON...} $bbva$::jsonb,
    updated_at = NOW()
WHERE bank_id = 'bbva_mx';
```

The trigger-set `updated_at` advances; on the next user request to the gRPC server, the manual cursor.Bump path doesn't run (we used raw SQL), so `GetSyncStatus` won't fast-track this user — but the next time the client pulls `notification_parsers` with its delta cursor, the new row arrives. For an immediate push, do the update via a Go path that calls `repo.Upsert` (which runs `bumpAllUsers`), or run a `UPDATE user_sync_cursors SET cursor_at = NOW() WHERE entity_type = 'notification_parser';` after the SQL bump.

### Frontend: `ParserSyncHandler` and store helpers

- `parser_remote_service.dart` — pull-only gRPC client. Single method `listParsers({updatedSince, pageToken})`.
- `parser_sync_handler.dart` — `entityType = 'notification_parser'`, `syncOrder = 4` (before account_card_mapping/transaction_rule and transactions). `pushUpsert` and `pushDelete` are no-ops because the parser repository has no outbox. `pull()` paginates and emits `SyncItem(id=bankId, updatedAt, data={bank_id, version, definition (json string), updated_at, deleted_at})`. `saveLocally` calls `ParserLocalStore.upsertFromSync(...)` which `INSERT OR REPLACE`s by `bank_id`, persisting `deleted_at` so soft-deleted parsers disappear from `listActive()`.
- `ParserLocalStore.seedFromAssetIfMissing(...)` (Phase 2) is preserved as a first-launch fallback before the first sync; once the sync brings a higher `version`, the asset value is replaced.

### Sync handlers and order

| Entity | `syncOrder` | Direction | Notes |
|--------|-------------|-----------|-------|
| `account` | 1 | both | mapping FK depends on it |
| `category` | 2 | both | rule FK depends on it |
| `notification_parser` | 4 | pull-only | global table, server is source of truth — must arrive before the engine processes inbox |
| `account_card_mapping` | 5 | both | must arrive before the engine resolves on next refresh |
| `transaction_rule` | 5 | both | same as above |
| `transaction` | 9 | both | unchanged |

`pending_transactions` and `captured_notifications` are NOT synced.

### UI

Fase 9 (2026-05-09) reorganizó la presentación: las raw notifications dejaron de mostrarse en pantalla (siguen guardándose en SQLite y purgándose a 90d), la "bandeja" se eliminó como ruta dedicada y las sugerencias se integraron al listado de transacciones. La superficie del feature hoy:

- **`/transactions` — sección "Por confirmar"** (`features/transactions/ui/transactions_screen.dart`): bloque fijo arriba del listado mensual que **unifica** dos fuentes: `PendingTransactionModel` (sugerencias de notis, chip "Notificación bancaria", icon `notifications_active_outlined`) y `TransactionModel.status='pending'` (occurrences pendientes de templates, chip "Pendiente"). Header `POR CONFIRMAR (N)`; cuando `N==0`, no se renderiza. Las pending salen del listado mensual (`vm.transactions.where(status != 'pending')`) para evitar duplicación. Cada fila tiene `Dismissible` endToStart con dialog de confirmación. **Tap fila o "Confirmar" en una sugerencia**: abre `PendingReviewSheet`. Since frictionless-capture f2 the sheet is no longer the only approval path: an **"Aprobar N resueltas"** header action (visible when N>0 suggestions carry both `suggested_account_id` and `suggested_category_id`; N counts `PendingTransactionModel` only, never template occurrences) batch-approves via `approveAllResolved()` after a confirmation dialog with the count and reports via snackbar ("N aprobadas" / "N aprobadas, M con error" — failed items stay listed for retry); and suggestions with account resolved but category missing render a `ChoiceChip` row (≤3 candidates from `candidateCategoriesFor()`) — tapping a chip approves directly with that category and learns the rule through the normal `approve()` path. **Tap fila o "Confirmar" en una occurrence**: comportamiento previo (`vm.confirmTransaction`). Pull-to-refresh dispara `Future.wait([vm.refresh(), pendingVM.refresh()])`; `pendingVM.refresh()` ya invoca `processInbox()`. Sin dedup automático cuando una sugerencia coincide con una occurrence — ambos coexisten visualmente y el usuario descarta uno manualmente (known follow-up).
- **`PendingReviewSheet`** (`features/notification_capture/ui/pending_review_sheet.dart`): bottom sheet pre-llenado desde el parser match. Campos editables: monto, moneda, descripción, cuenta (dropdown), **categoría (tile jerárquica)** y fecha. **Categoría:** desde Fase 9 reusa `CategoryPickerScreen` (drill-down con breadcrumb) en vez de un `DropdownButtonFormField` plano — los nombres duplicados con padres distintos ahora se distinguen visualmente. Se invoca con `Navigator.of(context).push<CategoryModel>(MaterialPageRoute(...))` envolviendo la pantalla en `Provider<CategoryLocalStore>.value` (no `context.push` de go_router porque cerraría el modal). El campo expone una `IconButton(Icons.close)` para limpiar la selección y volver a "Sin categoría" (la pantalla compartida no se modificó). Estado interno migrado de `String? _selectedCategoryId` a `CategoryModel? _selectedCategory`. Currency-mismatch warning, thumbs up/down opcional para `parser_feedback` (Fase 5). **Provider scoping:** `showModalBottomSheet` usa el rootNavigator y no hereda providers de scopes intermedios. El caller (`transactions_screen.dart::_openReviewSheet`) re-provee `PendingSuggestionsViewModel`, `AccountLocalStore`, `CategoryLocalStore` con `.value` en el `builder` del modal. Como esos providers viven a nivel app desde Fase 9, en la práctica funcionaría sin re-provisión, pero el patrón explícito sigue siendo defensa robusta para cualquier modal del feature.
- **`/settings/notification-capture`** (`features/notification_capture/ui/notification_capture_settings_screen.dart`): pantalla de configuración. Sección PERMISOS: link "Permiso del sistema" → Ajustes Android, link "Mis bancos" → `/settings/notification-capture/banks`, ListTile **"Reintentar parseo"** (icon `replay_rounded`, siempre habilitado; si no hay unparseables, snack `"No hay notificaciones para reintentar"`). Sección PRIVACIDAD E IA: toggles `share_with_llm_for_parser` y `help_improve_app` (Fase 4). El antiguo link "Bandeja de sugerencias" se eliminó.
- **`OnboardingPermissionScreen`** (`/onboarding/notifications`): explica el feature y enlaza a Ajustes del SO. Observa el flip `false→true` del permiso al volver de Ajustes y redirige al picker "Mis bancos" con `?firstTime=1`. Lee `PendingSuggestionsViewModel` para `permissionGranted` y `refresh()`.

**DI scope (Fase 9):** stores compartidos del feature (`CapturedNotificationLocalStore`, `PendingTransactionLocalStore`, `ParserLocalStore`, `AccountLocalStore`, `CategoryLocalStore`, `AccountCardMappingLocalStore`, `TransactionRuleLocalStore`, `ParserFeedbackLocalStore`, `BankAliasLocalStore`, `BankPackageLocalStore`, `NotificationCapturePreferences`, `ParserRemoteService`, `NotificationPermissionService`), `NotificationCaptureRepository` y `PendingSuggestionsViewModel` (renombrado desde `NotificationInboxViewModel`) viven en `main.dart` como providers globales — la sección "Por confirmar" en `/transactions` y la pantalla de settings comparten el mismo VM sin duplicación. `NotificationCaptureRouteScope` queda reducido al sub-árbol del banks picker (`PackageObservationLocalStore`, `WatchedPackageLocalStore`, `BankPackageRemoteService`, `BanksPickerViewModel`). El `processInbox` se dispara via `loadOnAppear()` en el constructor del VM (fire-and-forget en cold start) y al pull-to-refresh de `/transactions`.

## Multi-currency

The notification's currency is preserved in the resulting `Transaction` (per user decision). When the chosen account's `currency_code` differs from the notification's, the review sheet shows a non-blocking warning. No automatic FX conversion.

## Phase status

| Phase | Status | What it ships |
|-------|--------|---------------|
| 0 | done, then **reverted** | `accounts.card_last_digits` removed in favor of `account_card_mappings` (the user-facing field added complexity for a model that only fits 1 card per account; many real cases — physical+digital, ephemeral cards — needed N:1) |
| 1 | done | NLS Android, `captured_notifications` table, permission onboarding, raw inbox view |
| 2 | done | `ParserEngine`, BBVA MX parser asset, `PendingTransaction` flow, review sheet, account+category dropdowns, learn-from-approval upserts |
| 0.5/0.6 | done | `account_card_mappings` and `transaction_rules` entities (proto + BE module + sync handlers + FE feature) |
| 3 | done | `notification_parsers` global table (BE mig 012), `internal/notificationparser/` module, `ListNotificationParsers` RPC, FE `ParserSyncHandler` pull-only at syncOrder=4, NLS `onListenerConnected` backfill |
| 3.5 | done | Real BBVA MX fixtures (8 captured notifications), parser bumped to v2 (4 patterns: `purchase_tdc`, `account_charge`, `card_payment_credit`, `account_credit`), test rewritten to load fixtures, "Reintentar no parseables" UX, repair mig FE 012 for `pending_transactions.suggested_category_id` schema drift |
| 4 | done | `ParseNotification` RPC + `internal/notificationparser/llm_fallback.go` (Gemini reused) + `prompt.go` (few-shot ECMAScript constraint) + `regex_validator.go` (rejects `(?P<...>)`/backref/nested quantifier/>200ch + Go RE2 compile probe) + `candidate_repo.go` (anonymous, no user_id). `aiassistant.RateLimiter` extended with `feature` on `ai_usage` (BE mig 013, separate `chat` and `notification_parser` instances). FE: trazabilidad en `captured_notifications` (FE mig 013: `matched_parser_version`, `matched_pattern_id`, `extraction_method`); `processInbox()` intenta LLM tras fallo local (errores no-bloqueantes); device-local toggles `share_with_llm_for_parser` (opt-in) y `help_improve_app` (opt-out, gates persistencia de samples) en `NotificationCapturePreferences`; pantalla `/settings/notification-capture` con dos `SwitchListTile`; `OnboardingPermissionScreen` actualizada. **No implementado en MVP (queda como roadmap):** cross-validation con segundo LLM, retención 90-day, `parser_match_failures`. |
| 5 | done | `parser_feedback` push-only (BE mig 015 + módulo `internal/parserfeedback/` + proto `parser_feedback_service.proto` con `Upsert`/`List`, sin `Delete`). FE mig 014 + `domain/parser_feedback.dart` + `data/parser_feedback_*.dart` (local store, remote service, sync handler push-only `syncOrder=7`). Cada decisión final en `PendingReviewSheet` (Aprobar O Descartar) inserta una fila con: thumb opcional `was_helpful` tri-estado (`google.protobuf.BoolValue` en wire, `INTEGER 0\|1\|NULL` en SQLite), 4 flags derivados (`account_changed`, `category_changed`, `amount_changed`, `description_changed`) calculados al aprobar comparando `suggested_*` vs final, `was_dismissed`, y trazabilidad completa (bank_id, pattern_id, parser_version, extraction_method). UI: dos `IconButton.filledTonal` (thumb_up/thumb_down) inmediatamente después del header del sheet — opcional, tap segundo vuelve a none. Helper `PendingTransactionModel.splitParserId` extraído del view model. `_descriptionChanged` con normalización conservadora (trim + lowercase + colapso de whitespace) — un usuario que solo limpia trailing spaces NO dispara el flag. UNIQUE server-side `(user_id, pending_transaction_id)` como salvaguarda; LWW resuelto por `id` (mismo patrón que cardmapping). 13 tests unitarios en `frontend/test/parser_feedback_helpers_test.dart`; 3 tests de cursor en `backend/internal/parserfeedback/cursor_integration_test.go`. Sin toggle (feedback no incluye texto crudo, solo IDs/flags). |
| 7 | done (2026-04-26) | Modelo LLM configurable por feature (chat vs parser). `GeminiProvider` toma `model` en construcción; `LLMProvider` interface expone `Model()`. Env vars `AI_CHAT_MODEL` y `NOTIFICATION_PARSER_MODEL` (default `gemini-3.1-flash-lite-preview` en ambos: cero cambio de comportamiento). BE mig 017 añade `ai_usage.model TEXT NOT NULL DEFAULT 'gemini-3.1-flash-lite-preview'` + índice por modelo. `LLMFallback.modelVersion` eliminado: tanto `RecordUsage` como `candidate_parsers.llm_model_version` ahora leen de `provider.Model()` (single source of truth). Detalle completo en `architecture/ai_assistant.md`. |
| 6 | done | Retención 90-day simétrica FE+BE. **FE** (mig 015): `captured_notifications` añade `purged_at TEXT` + índice parcial; sweeper Dart (`captured_notifications_retention_sweeper.dart`) NULLea `title`/`text`/`big_text` y marca `purged_at` cuando `posted_at < now-90d`, gated por `lastPurgeAt` (clave device-local en `NotificationCapturePreferences`) con cadencia ≥24h; trigger `unawaited(sweeper.sweepIfDue())` en `main.dart` post-init. Filtro `WHERE purged_at IS NULL` en `listInbox`/`listPendingProcessing`/`resetUnparseableToReceived` (al nivel del local store). El status del lifecycle se preserva → trazabilidad y `parser_feedback` agregado intactos. **BE** (mig 016): extiende CHECK con `'purged'` y añade `purged_at TIMESTAMPTZ`; `candidate_repo.go::PurgeOldSamples` NULLea `sample_title`/`sample_text`/`sample_big_text`, marca `status='purged'`. Goroutine en `cmd/server/main.go` (`startCandidateRetentionSweeper`) corre al startup y luego con `time.NewTicker(24h)`. Preserva `proposed_regex`/`extracted_fields` (no son PII). Tests: 5 unit FE en `test/notification_capture/captured_notifications_retention_sweeper_test.dart` (gating + cutoff + sweepNow); 2 integration BE en `internal/notificationparser/candidate_repo_test.go` (skippean sin `TEST_DATABASE_URL`). |
| 9 | done (2026-05-09) | UX refactor: las raw notifications dejan de mostrarse en pantalla (la sección "Sin procesar" daba sensación de inseguridad), `/inbox` se elimina, las sugerencias migran a una sección **"Por confirmar"** arriba de `/transactions` que unifica `PendingTransactionModel` + `TransactionModel.status='pending'` (occurrences de templates), y el picker de categoría del review sheet se reemplaza por la pantalla jerárquica `CategoryPickerScreen` ya usada en el form de transacciones. **Renombre:** `NotificationInboxViewModel` → `PendingSuggestionsViewModel` (limpia campos `rawNotifications`, `hasUnparseable`, `dismissRaw`). **Scope:** stores del feature + `NotificationCaptureRepository` + el VM se suben a providers globales en `main.dart` (vida = app); `NotificationCaptureRouteScope` queda con solo lo del banks picker. **Reintentar parseo:** botón se mueve a `/settings/notification-capture` como ListTile siempre habilitado (snack distingue "0 reintentadas" cuando no hay nada). **`processInbox` triggers:** cold start via `loadOnAppear()` del VM + pull-to-refresh de `/transactions` (`Future.wait([vm.refresh(), pendingVM.refresh()])`). **Picker de categoría desde modal:** se invoca con `Navigator.push(MaterialPageRoute(...))` en lugar de `context.push` de go_router porque el sheet vive sobre el rootNavigator y go_router cerraría el modal — la pantalla compartida no se modificó; el caso "Sin categoría" (null) se gestiona localmente en el sheet con un `IconButton(close)` que limpia la selección. **Sin dedup pending+template** en este alcance (known follow-up): si una notificación coincide con una occurrence, ambas aparecen en la sección y el usuario descarta una. **Tooling:** `scripts/gen_proto.sh` ahora incluye `bank_alias_service.proto` y `bank_package_service.proto` (faltaban desde Fase 8 y bloqueaban la compilación). |
| 8 | done (2026-04-26) | Package selection dinámica + loop comunitario. Reemplaza la allowlist hardcoded del NLS Kotlin (BANK_PACKAGES) por una decisión per-device en `watched_packages` (FE local-only). El NLS lee la tabla en `onListenerConnected()` y la cachea como `Volatile Set<String>`; refresh por rebind (sin MethodChannel ping aún). Discovery vía `package_observations` (FE local-only, sin PII): el NLS hace UPSERT (package_name, last_seen_at, noti_count) por TODA noti recibida — no requiere `QUERY_ALL_PACKAGES`. **Tres tablas BE nuevas (mig 018):** `bank_packages` (catálogo global pull-only, mismo patrón que `notification_parsers` con `bumpAllUsers`); `bank_aliases` (per-user push+pull, mismo patrón que `account_card_mappings` con LWW por id, UNIQUE `(user_id, package_name)`); `package_suggestions` (anónimo, sin user_id, gated por `help_improve_app=ON`). **Cuatro tablas FE nuevas (mig 016):** `package_observations`, `watched_packages`, `bank_aliases`, `bank_packages`. Mig 016 seed BBVA en `watched_packages` + `bank_packages` (cero fricción para existing users) y backfill de `package_observations` desde `captured_notifications` (UI accionable desde primer abrir). **Sync entities:** `EntityBankPackage` (syncOrder=4 igual que parser) + `EntityBankAlias` (syncOrder=5 igual que cardmapping). **UI nueva:** `BanksPickerScreen` en `/settings/notification-capture/banks?firstTime=1` (con banner explicativo cuando se llega post-permission). `OnboardingPermissionScreen` redirige al picker cuando el observer detecta el flip false→true al volver de Ajustes. `NotificationCaptureSettingsScreen` añade ListTile "Mis bancos". **Repository refactor:** `_bankIdForPackage` ahora async, consulta bank_aliases → bank_packages → 'unknown' (era switch hardcoded BBVA). **Retention sweeper extendido:** acepta `List<PurgeRunner>`; en producción incluye `package_observations.purgeOlderThan` además del existente para `captured_notifications`. **Tie-in Fase 4:** sin cambios al pipeline — packages habilitados sin parser local caen al LLM fallback existente; si `help_improve_app=ON`, alimenta `candidate_parsers` y se sigue el mismo loop admin para promover regex. **Loop comunitario:** cliente envía sugerencias anónimas a `package_suggestions`; admin revisa y promueve a `bank_packages` vía SQL directo (o `repo.Upsert` que `bumpAllUsers`). |

| 10 (frictionless-capture f1) | done (2026-07-18) | Smart resolution: `pattern_id` on `account_card_mappings` (proto field 8, BE mig 019 / FE mig 017 `_version=17`; `last_digits` nullable + CHECK at-least-one via SQLite table rebuild), (`bank_id`, `pattern_id`) account fallback for digit-less notifications + approval-time pattern learning, longest-prefix rule learning/matching (`LENGTH(match_text)` DESC). No uniqueness guard: insert-new-row + latest-active LWW, same as digits mappings. Also fixed latent bug: `account_card_mapping_remote_service.upsertMapping` never forwarded `pattern_id` outbound. |
| 11 (frictionless-capture f2) | done (2026-07-18) | Fast review: "Aprobar N resueltas" header action (`approveAllResolved()`, continue-on-error, confirm dialog + result snackbar) + quick-pick `ChoiceChip` category row on `_SuggestionTile` for category-only gaps (`candidateCategoriesFor()`: longest-prefix rules then account most-used, cap 3). `parser_feedback` rows still written on batch approvals (`was_helpful` null — quality signal feeds f3's confidence gate). |

## Operational tooling

- **Retention sweepers (Fase 6)** — `CapturedNotificationsRetentionSweeper` (FE) corre al app launch con gating diario; `startCandidateRetentionSweeper` (BE) corre al startup + cada 24h vía `time.NewTicker`. Ambos NULLean texto crudo después de 90 días; los metadatos no-PII (status, parser_version, regex propuesto) se preservan. Para forzar manualmente: setear `notification_capture.last_purge_at = NULL` en `user_preferences` (FE) o llamar `repo.PurgeOldSamples(ctx)` desde un debug RPC (BE).
- **`scripts/dump_captured_notifications.sh`** — extracts the device's `pocket_pilot.db` via `adb run-as <debugApp> cat`, then `sqlite3 json_group_array(...)` filtered by `package_name LIKE '%bancomer%'` (default; first arg overrides). Output: `frontend/test_data/captured_raw.json` (gitignored — may contain PII). Requires the debug build (`app.pocketpilot.debug`); release builds are not `run-as`-able. Source these dumps into `bbva_mx_real_notifications.json` by hand-curating and adding `expected.{pattern_id, transaction_type, fields}`.
- **DB push limitation (negative result):** Modifying the device's SQLite locally and pushing it back via `adb exec-in shell run-as cat > databases/pocket_pilot.db` does **not** work reliably even after `am force-stop`. Cause: the `BankNotificationListenerService` is an OS-managed component independent of the Flutter process; it survives `force-stop` (Android keeps NLS bound while the permission is active), holds the DB file handle, and either overwrites the pushed file on its next flush or causes the kernel to silently reject the write. Verify with `shasum -a 256` of local vs `adb run-as cat ... | shasum`. Use the in-app "Reintentar no parseables" button or add a debug-only Dart helper instead of pushing files.
- **Re-export DB for inspection:** `adb exec-out run-as app.pocketpilot.debug cat databases/pocket_pilot.db > <local-path>`. `exec-out` (not `shell`) preserves binary integrity (no CRLF translation).

## Reference files

**Proto:**
- `proto/pocket_pilot/v1/account_card_mapping_service.proto`
- `proto/pocket_pilot/v1/transaction_rule_service.proto`
- `proto/pocket_pilot/v1/notification_parser_service.proto`
- `proto/pocket_pilot/v1/parser_feedback_service.proto` (Fase 5)
- `proto/pocket_pilot/v1/bank_package_service.proto` (Fase 8: ListBankPackages pull-only + SubmitPackageSuggestion anónima)
- `proto/pocket_pilot/v1/bank_alias_service.proto` (Fase 8: List/Upsert/Delete user-scoped, mirror cardmapping)

**Backend:**
- `backend/internal/cardmapping/cardmapping.go` (model + repo + handler)
- `backend/internal/txrule/txrule.go` (model + repo + handler)
- `backend/internal/notificationparser/notificationparser.go` (model + repo + handler — global table, pull-only client API)
- `backend/internal/notificationparser/llm_fallback.go` (Fase 4: handler `ParseNotification`)
- `backend/internal/notificationparser/prompt.go` (few-shot prompt + `ParseLLMResponse`)
- `backend/internal/notificationparser/regex_validator.go` (ReDoS guard + sintaxis Dart-compatible)
- `backend/internal/notificationparser/candidate_repo.go` (Insert-only para `candidate_parsers`)
- `backend/internal/aiassistant/repository.go` (acepta `feature` en RecordUsage/GetUsageStats)
- `backend/internal/aiassistant/rate_limiter.go` (constructor recibe `feature`; instancias separadas para `chat` y `notification_parser`)
- `backend/internal/sync/entity_type.go` — `EntityAccountCardMapping`, `EntityTransactionRule`, `EntityNotificationParser`
- `backend/migrations/010_account_card_mappings.sql`
- `backend/migrations/011_transaction_rules.sql`
- `backend/migrations/012_notification_parsers.sql` (table + BBVA MX seed v1; current row in DB is v2 via UPDATE SQL)
- `backend/migrations/013_ai_usage_feature.sql` (Fase 4: `ai_usage.feature` column + index)
- `backend/migrations/014_candidate_parsers.sql` (Fase 4: tabla anónima de propuestas LLM)
- `backend/migrations/015_parser_feedback.sql` (Fase 5: señal de calidad por sugerencia)
- `backend/migrations/016_candidate_parsers_retention.sql` (Fase 6: status `purged` + `purged_at`)
- `backend/migrations/017_ai_usage_model.sql` (Fase 7: `ai_usage.model` + índice por modelo)
- `backend/migrations/018_bank_packages.sql` (Fase 8: bank_packages global + bank_aliases user-scoped + package_suggestions anónimo)
- `backend/migrations/019_account_card_mappings_pattern.sql` (frictionless-capture f1: `pattern_id` + índice no-único + `last_digits` DROP NOT NULL + CHECK at-least-one)
- `backend/internal/bankpackage/bankpackage.go` (Fase 8: Repository + Handler global pull-only + bumpAllUsers)
- `backend/internal/bankpackage/suggestion_repo.go` (Fase 8: Insert anónimo en package_suggestions)
- `backend/internal/bankalias/bankalias.go` (Fase 8: Repository + Handler user-scoped, LWW, mirror cardmapping)
- `backend/internal/parserfeedback/parserfeedback.go` (Fase 5: módulo Modelo + Repository + Handler)
- `backend/internal/parserfeedback/cursor_integration_test.go` (Fase 5: tests cursor + LWW)
- `backend/cmd/server/main.go` — DI: `notificationParserLimiter` con feature_key, `candidateRepo`, `notificationparser.NewHandlerWithLLM(...)`. Fase 6: helper `startCandidateRetentionSweeper(ctx, candidateRepo)` (goroutine 24h ticker)
- `backend/internal/notificationparser/candidate_repo.go` — Fase 6: const `RetentionWindow = 90*24h` + método `PurgeOldSamples(ctx)`
- `backend/internal/notificationparser/candidate_repo_test.go` — Fase 6: tests integration (cutoff, idempotencia)

**Frontend Flutter:**
- `lib/src/features/notification_capture/` — entire feature module, including `data/parser_remote_service.dart` (Fase 4: agrega `parseNotification` + `ParserQuotaExceededException`), `data/parser_sync_handler.dart`, `data/parser_local_store.dart` (`upsertFromSync`), `data/notification_capture_preferences.dart` (Fase 4: toggles device-local), `ui/notification_capture_settings_screen.dart` (Fase 4 + Fase 9: ListTile "Reintentar parseo")
- `lib/src/features/notification_capture/ui/pending_suggestions_view_model.dart` — Fase 9: rename de `notification_inbox_view_model.dart`. Sin `rawNotifications`/`hasUnparseable`/`dismissRaw`. Provee `pendingTransactions`, `permissionGranted`, `refresh`, `reprocessUnparseable`, `dismissPending`, `approvePending`, `loadOnAppear`; frictionless-capture f2 adds `approveAllResolved` and `candidateCategoriesFor` (delegate to the repository; the batch path refreshes the list afterwards).
- `lib/src/features/notification_capture/ui/notification_capture_route_scope.dart` — Fase 9: reducido al sub-árbol del banks picker (`PackageObservationLocalStore`, `WatchedPackageLocalStore`, `BankPackageRemoteService`, `BanksPickerViewModel`). Los stores compartidos del feature, el repo y el VM ahora viven en `main.dart`.
- `lib/src/features/notification_capture/ui/pending_review_sheet.dart` — Fase 9: `_selectedCategoryId` (String?) → `_selectedCategory` (CategoryModel?); dropdown plano de categoría reemplazado por `_CategoryTile` que abre `CategoryPickerScreen` via `Navigator.push(MaterialPageRoute)` envolviendo en `Provider<CategoryLocalStore>.value`. `IconButton(close)` clearable para volver a "Sin categoría".
- `lib/src/features/notification_capture/ui/onboarding_permission_screen.dart` — Fase 9: usa `PendingSuggestionsViewModel` (rename).
- `lib/src/features/transactions/ui/transactions_screen.dart` — Fase 9: sección "Por confirmar" (`_PendingConfirmHeader` + `_SuggestionTile` con chip "Notificación bancaria") arriba del listado mensual, `_TransactionList` filtra `status != 'pending'` para evitar duplicación, `RefreshIndicator.onRefresh` corre `Future.wait([vm.refresh(), pendingVM.refresh()])`, `_openReviewSheet` re-provee `PendingSuggestionsViewModel`/`AccountLocalStore`/`CategoryLocalStore` con `.value`, `_confirmDismissSuggestion` agrega dialog específico para sugerencias.
- `lib/src/features/accounts/data/account_local_store.dart` — no longer has `findByCardLastDigits` (removed during pivot)
- `lib/main.dart` — Fase 9: stores del feature + `NotificationCaptureRepository` + `PendingSuggestionsViewModel(..loadOnAppear())` se proveen como providers globales (vida = app); `parserSyncHandler` (syncOrder=4), `accountCardMappingSyncHandler`, `transactionRuleSyncHandler` registration siguen como Fase 3+.
- `lib/src/ui/router.dart` — Fase 4: route `/settings/notification-capture`. Fase 9: ruta `/inbox` y su import de `pending_inbox_screen.dart` eliminados.
- `lib/src/ui/screens/settings/settings_screen.dart` — Fase 4: el item "Captura de notificaciones" va a `/settings/notification-capture`. (Fase 9 elimina el sub-link "Bandeja de sugerencias" dentro de esa pantalla; el resto de la nav no cambia.)
- `assets/parsers/bbva_mx.json` — v2 (4 patterns), single source of truth shared with the BE seed
- `assets/migrations/008.sql` — original schema (no `suggested_category_id`)
- `assets/migrations/012.sql` — `ALTER TABLE pending_transactions ADD COLUMN suggested_category_id TEXT`
- `assets/migrations/013.sql` — Fase 4: trazabilidad `matched_parser_version`/`matched_pattern_id`/`extraction_method` en `captured_notifications`. `database_helper.dart::_version = 13`.
- `assets/migrations/014.sql` — Fase 5: tabla local `parser_feedback` mirror del schema BE. `database_helper.dart::_version = 14`.
- `assets/migrations/015.sql` — Fase 6: `captured_notifications.purged_at TEXT` + índice parcial. `database_helper.dart::_version = 15`.
- `assets/migrations/016.sql` — Fase 8: 4 tablas nuevas (`package_observations`, `watched_packages`, `bank_aliases`, `bank_packages`) + seed BBVA en watched/bank_packages + backfill de package_observations desde captured_notifications. `database_helper.dart::_version = 16`.
- `assets/migrations/017.sql` — frictionless-capture f1: table rebuild de `account_card_mappings` (`pattern_id`, `last_digits` nullable + CHECK, índices/trigger recreados — SQLite no puede dropear NOT NULL con ALTER). `database_helper.dart::_version = 17`.
- `lib/src/features/notification_capture/domain/{package_observation,watched_package,bank_alias,bank_package}.dart` — Fase 8: 4 modelos de dominio.
- `lib/src/features/notification_capture/data/{package_observation,watched_package,bank_alias,bank_package}_local_store.dart` — Fase 8: 4 DAOs.
- `lib/src/features/notification_capture/data/bank_package_sync_handler.dart` — Fase 8: pull-only `syncOrder=4`, mismo orden que parser.
- `lib/src/features/notification_capture/data/bank_alias_sync_handler.dart` — Fase 8: push+pull `syncOrder=5`, mismo orden que cardmapping/txrule.
- `lib/src/features/notification_capture/data/{bank_package,bank_alias}_remote_service.dart` — Fase 8: clientes gRPC.
- `lib/src/features/notification_capture/ui/banks_picker_screen.dart` — Fase 8: pantalla "Mis bancos" en `/settings/notification-capture/banks`.
- `lib/src/features/notification_capture/ui/banks_picker_view_model.dart` — Fase 8: `BanksPickerEntry` agregando observation+watched+alias+catalogEntry; `markAsBank`/`unmarkAsBank` orquestan watched + alias + outbox + suggestion.
- `lib/src/features/notification_capture/data/captured_notifications_retention_sweeper.dart` — Fase 8 extension: `_runners: List<PurgeRunner>` para encadenar la purga de `package_observations`.
- `lib/src/features/notification_capture/domain/parser_feedback.dart` — Fase 5: `ParserFeedbackModel` con conversión `BoolValue`↔`bool?` y `INTEGER`↔`bool` para SQLite.
- `lib/src/features/notification_capture/data/parser_feedback_local_store.dart` — Fase 5: `upsert`, `upsertRow`, `findByPendingTransactionId`.
- `lib/src/features/notification_capture/data/parser_feedback_remote_service.dart` — Fase 5: `upsertFeedback(map)` (push-only, no `list`).
- `lib/src/features/notification_capture/data/parser_feedback_sync_handler.dart` — Fase 5: push-only, `syncOrder=7`, `pull` retorna lista vacía.
- `lib/src/features/notification_capture/data/captured_notifications_retention_sweeper.dart` — Fase 6: sweeper Dart con gating diario + factory `forTesting`.
- `lib/src/features/notification_capture/data/captured_notification_local_store.dart` — Fase 6: método `purgeOlderThan(...)` y filtros `purged_at IS NULL` en queries de bandeja.

**Android native:**
- `frontend/android/app/src/main/kotlin/app/pocketpilot/notifications/` — entire native module. **Fase 8**: `BankNotificationListenerService.kt` perdió `BANK_PACKAGES`; ahora cachea el set desde `watched_packages` en `onListenerConnected()` y observa todos los packages a `package_observations`. `NotificationDb.kt` añadió `upsertPackageObservation` y `getEnabledWatchedPackages`.
- `frontend/android/app/src/main/AndroidManifest.xml`
- `frontend/android/app/src/main/kotlin/app/pocketpilot/MainActivity.kt`

**Tests + fixtures:**
- `frontend/test/notification_parser_engine_test.dart` — fixture-driven positives + inline negatives
- `frontend/test_data/bbva_mx_real_notifications.json` — 8 real BBVA MX notifications with `expected` blocks (curated from `captured_raw.json`)
- `backend/internal/notificationparser/regex_validator_test.go` — Fase 4: tabla con 10 casos (Python named group, backref, nested quantifier, longitud, sintaxis) + sanity check con regex BBVA reales
- `backend/internal/notificationparser/prompt_test.go` — Fase 4: `ParseLLMResponse` (matched, no-match, markdown fences, JSON inválido, validación amount+type, clamp confidence) + `BuildMessages` (system/user roles, ECMAScript constraint en system prompt)
- `backend/internal/aiassistant/rate_limiter_test.go` — Fase 4: integration (skip sin `TEST_DATABASE_URL`) que verifica que cuotas `chat` y `notification_parser` son aisladas — agotar una no afecta la otra
- `frontend/test/notification_capture/captured_notifications_retention_sweeper_test.dart` — Fase 6: 5 casos unit con `PurgeRunner`/`LastPurgeAtStore` fakes (gating + cutoff + sweepNow)
- `backend/internal/cardmapping/cardmapping_test.go` — frictionless-capture f1: pattern-only permitido, ambos-ausentes rechazado, round-trip proto de `pattern_id`
- `frontend/test/account_card_mapping_model_test.dart` — frictionless-capture f1: round-trip del modelo incl. mapping pattern-only (sin dígitos)
- `frontend/test/notification_capture/notification_capture_repository_learn_test.dart` — frictionless-capture f1+f2: end-to-end con fixtures BBVA reales — TDC sin dígitos resuelve tras una aprobación; DIDI/DIDI FOOD coexisten por longest-prefix; f2 adds batch-approval filtering (resolved-only, continue-on-error), candidate-category ranking (prefix rules then account usage, no duplicates), and quick-pick approval (uses suggested account + tapped category, learns the rule)

**Scripts:**
- `scripts/dump_captured_notifications.sh` — adb + sqlite3 extractor
- `scripts/gen_proto.sh` — Fase 9: ahora incluye `bank_alias_service.proto` y `bank_package_service.proto` en la lista de archivos a regenerar (faltaban desde Fase 8 y bloqueaban `flutter analyze`/`flutter test`).

## Known follow-ups

- **First-word heuristic edge cases (partially resolved, frictionless-capture f1):** the DIDI/DIDI FOOD flip-flop is fixed by two-word escalation + longest-prefix matching. Remaining gaps: generic first words ("PAGO") can still over-match, and an existing two-word rule's category is overwritten when re-learned (no third-level escalation) — feeds phase 3's auto-confirm confidence gate. Add a Settings → Reglas screen if it becomes a problem.
- **Same `last_digits` across banks:** mappings are keyed by `(bank_id, last_digits)` so cross-bank collisions don't occur. Mappings are per-user.
- **Pattern mapping can't distinguish two credit cards at the same bank:** digit-less notifications resolve per (`bank_id`, `pattern_id`), so a second BBVA TDC would be indistinguishable. Accepted caveat — the user has one BBVA TDC today (frictionless-capture f1).
- **Rule cleanup:** `account_card_mappings` and `transaction_rules` grow with approvals. No GC yet — add a periodic prune of old soft-deleted rows after ~6 months if tables grow unboundedly in practice.
- **~~Retention 90-day en raw notifications~~** (Fase 6, done 2026-04-26): sweepers FE (`captured_notifications.purged_at`) + BE (`candidate_parsers.status='purged'`) anonimizan texto crudo a los 90 días. Status/parser_version/regex propuestos se preservan.
- **Rate limiting (Phase 4) — decided:** extend `aiassistant.RateLimiter` with a `feature_key` (new column `feature TEXT NOT NULL DEFAULT 'chat'` on `ai_usage` via mig 013) so `notification_parser` quota is isolated from `chat`. Two `RateLimiter` instances share the `Repository` but track usage separately. Defaults: `NOTIFICATION_PARSER_DAILY_LIMIT=50`, `NOTIFICATION_PARSER_MONTHLY_TOKEN_LIMIT=200_000` (lower than chat because each notification is short).
- **Modelo independiente del chat (Fase 7) — decided:** cada feature tiene su propio `GeminiProvider` con modelo configurable. Para parser: `NOTIFICATION_PARSER_MODEL` (default `gemini-3.1-flash-lite-preview`). El modelo efectivo se persiste en `ai_usage.model` (mig 017) y en `candidate_parsers.llm_model_version`. Detalles de cuotas, modelos y persistencia → ver `architecture/ai_assistant.md`.
- **Modal sheets need explicit provider re-provision:** any future bottom sheet/dialog opened with `showModalBottomSheet` from this feature must follow the `MultiProvider` pattern in `transactions_screen.dart::_openReviewSheet` (la referencia anterior `pending_inbox_screen.dart` se eliminó en Fase 9). The root navigator scoping bug is silent at compile time; only fails at runtime when the sheet's `initState` calls `context.read<X>()`. Incluso con stores globales en `main.dart`, mantener el `MultiProvider` con `.value` es defensa explícita y barata.
- **Dedup `PendingTransaction` + `TransactionModel.status='pending'` (Fase 9):** una notificación bancaria puede generar una sugerencia mientras un template recurrente programa la misma transacción (ej. domiciliación de servicios). Hoy ambos coexisten en la sección "Por confirmar" y el usuario descarta uno. Pendiente de iteración: detección heurística (misma cuenta + monto cercano + fecha cercana → chip "Posible duplicado") o auto-link al template. Sin urgencia; primero observar cuántos casos reales lo gatillan.
- **Picker desde modales (Fase 9):** `CategoryPickerScreen` se invoca desde el `PendingReviewSheet` con `Navigator.of(context).push<CategoryModel>(MaterialPageRoute(...))`, NO con `context.push` de go_router. Razón: el sheet vive sobre `Navigator.of(context, rootNavigator: true)` y go_router opera ahí — cerraría el modal al navegar. La pantalla compartida no se modificó (sigue retornando `CategoryModel` no-null vía `Navigator.pop`); el caso "Sin categoría" se gestiona localmente con un `IconButton(close)` en la tile. Patrón replicable para cualquier futuro selector que se necesite invocar desde un modal.
- **In-place migration drift (mig 008 + 012):** the original `pending_transactions` schema was modified after release to add `suggested_category_id`, leaving early devices without the column. The fix (restore 008 + add 012 ALTER) followed the rule "never modify a published .sql"; remember this when iterating on future migrations during development. `database_helper.dart` documents the rule in its leading comment.
