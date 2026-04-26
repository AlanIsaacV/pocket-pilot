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
                              .createTransaction()       (if card_last_digits present     (if categoryId chosen and
                                                          and chosen account differs)      first-word match_text new)
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
| `account_card_mappings` (mig 010) | (`bank_id`, `last_digits`) → `account_id`. Auto-populated on approval. | Yes |
| `transaction_rules` (mig 011) | `match_text` (substring) → `category_id`. Auto-populated on approval. | Yes |

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

- `BankNotificationListenerService.kt` — extends `NotificationListenerService`. Allowlist of `packageName`s in code (`com.bbva.bancomermovil`, `com.bancomer.mbanking`). Writes directly to the sqflite SQLite file (path = `getDatabasePath("pocket_pilot.db")`). Only writes to `captured_notifications` — never reads other tables. Schema is stable. Two callbacks share a private `captureIfBank(sbn)` helper:
  - `onNotificationPosted(sbn)` — every new notification while the listener is bound.
  - `onListenerConnected()` — backfill from `activeNotifications` whenever the OS rebinds the service. Covers "user granted permission after notifications already arrived" and "OS restarted the listener". Idempotent thanks to `NotificationDb` dedupe; notifications dismissed from the shade cannot be recovered (no API).
- `NotificationDb.kt` — minimal DB writer. Dedupes via `(package_name, posted_at ± 1 minute, text+title)` query before INSERT. Generates deterministic UUIDs from SHA-256 of the payload as a second-line idempotency defense.
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
2. On match: looks up `account_card_mappings` (latest active by `updated_at` for `bank_id` + `last_digits`) → `suggested_account_id`.
3. On match: looks up `transaction_rules` (substring of merchant description in `match_text`, ordered by `priority` DESC, `updated_at` DESC) → `suggested_category_id`.
4. Inserts `PendingTransaction` and marks the notification `matched_local`.

`approve()` — user confirmed the suggestion:
1. Calls `TransactionRepository.createTransaction()` (which handles the outbox enqueue for the new `Transaction`).
2. Marks the `PendingTransaction` `approved` and the source `CapturedNotification` `consumed`.
3. **Implicit learning:** if the notification carried `card_last_digits` and the chosen account differs from the existing mapping (or none existed), inserts a new row in `account_card_mappings` + outbox.
4. **Implicit learning:** if a category was chosen, derives `match_text` as the **first word** of the merchant description (e.g. "STARBUCKS REFORMA 222" → `"STARBUCKS"`) and upserts a `transaction_rule` if no active rule with that exact `match_text` exists for the same category.

**Why first word?** Substring matching against the full merchant string would only match identical strings. Taking the first word makes "STARBUCKS REFORMA 222" learn a rule that also catches "STARBUCKS POLANCO". Trade-off: generic first words ("PAGO", "COMPRA") could over-match. Acceptable for v1 — we'll add a manual rule editor only if the heuristic causes problems in practice.

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

- `/inbox` (route, link from Settings → "Captura de notificaciones"): lists PendingTransactions + raw unprocessed notifications. RefreshIndicator triggers `processInbox()`. AppBar action **"Reintentar no parseables"** (icon `replay_rounded`) appears only when `vm.hasUnparseable` is true; tap calls `repository.reprocessUnparseable()` and shows a SnackBar with `Reintentadas N, parseadas M`. The "Sin procesar" section filters to `status IN ('received', 'unparseable')` only — notifications that already produced a `PendingTransaction` (`matched_local`/`matched_server`/`llm_used`) live exclusively in the "Sugerencias" section to avoid duplication.
- `PendingReviewSheet`: bottom sheet pre-filled from the parser match, with editable amount, currency, description, account dropdown, **category dropdown** (filtered by `transaction_type`), and date. Shows a currency-mismatch warning when notification currency ≠ selected account currency. Approve/Dismiss buttons. **Provider scoping note:** `showModalBottomSheet` mounts the sheet under the root navigator, outside the `NotificationCaptureRouteScope` subtree. The sheet's `initState` reads `AccountLocalStore` and `CategoryLocalStore`, so the caller in `pending_inbox_screen.dart` MUST re-provide them via `Provider<X>.value` inside a `MultiProvider` in the modal `builder` (along with the `NotificationInboxViewModel`). Same pattern applies to any future modal that needs scoped providers.
- `OnboardingPermissionScreen` (`/onboarding/notifications`): explains the feature and links out to OS settings.

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
| 4 | pending | Server-side `ParseNotification` RPC, Gemini fallback, `candidate_parsers` + `parser_match_failures` tables (BE mig 014), ReDoS regex validator (`(?P<...>)` rejected, backref/nested quantifier/>200ch rejected, 50ms exec timeout), `aiassistant.RateLimiter` extended with `feature_key` column on `ai_usage` (BE mig 013), 90-day retention on raw_notification, privacy toggle `share_with_llm_for_parser` in Settings, disclosure in OnboardingPermissionScreen |

## Operational tooling

- **`scripts/dump_captured_notifications.sh`** — extracts the device's `pocket_pilot.db` via `adb run-as <debugApp> cat`, then `sqlite3 json_group_array(...)` filtered by `package_name LIKE '%bancomer%'` (default; first arg overrides). Output: `frontend/test_data/captured_raw.json` (gitignored — may contain PII). Requires the debug build (`app.pocketpilot.debug`); release builds are not `run-as`-able. Source these dumps into `bbva_mx_real_notifications.json` by hand-curating and adding `expected.{pattern_id, transaction_type, fields}`.
- **DB push limitation (negative result):** Modifying the device's SQLite locally and pushing it back via `adb exec-in shell run-as cat > databases/pocket_pilot.db` does **not** work reliably even after `am force-stop`. Cause: the `BankNotificationListenerService` is an OS-managed component independent of the Flutter process; it survives `force-stop` (Android keeps NLS bound while the permission is active), holds the DB file handle, and either overwrites the pushed file on its next flush or causes the kernel to silently reject the write. Verify with `shasum -a 256` of local vs `adb run-as cat ... | shasum`. Use the in-app "Reintentar no parseables" button or add a debug-only Dart helper instead of pushing files.
- **Re-export DB for inspection:** `adb exec-out run-as app.pocketpilot.debug cat databases/pocket_pilot.db > <local-path>`. `exec-out` (not `shell`) preserves binary integrity (no CRLF translation).

## Reference files

**Proto:**
- `proto/pocket_pilot/v1/account_card_mapping_service.proto`
- `proto/pocket_pilot/v1/transaction_rule_service.proto`
- `proto/pocket_pilot/v1/notification_parser_service.proto`

**Backend:**
- `backend/internal/cardmapping/cardmapping.go` (model + repo + handler)
- `backend/internal/txrule/txrule.go` (model + repo + handler)
- `backend/internal/notificationparser/notificationparser.go` (model + repo + handler — global table, pull-only client API)
- `backend/internal/sync/entity_type.go` — `EntityAccountCardMapping`, `EntityTransactionRule`, `EntityNotificationParser`
- `backend/migrations/010_account_card_mappings.sql`
- `backend/migrations/011_transaction_rules.sql`
- `backend/migrations/012_notification_parsers.sql` (table + BBVA MX seed v1; current row in DB is v2 via UPDATE SQL)
- `backend/cmd/server/main.go` — `notificationParserHandler` DI

**Frontend Flutter:**
- `lib/src/features/notification_capture/` — entire feature module, including `data/parser_remote_service.dart`, `data/parser_sync_handler.dart`, and `data/parser_local_store.dart` (`upsertFromSync`)
- `lib/src/features/accounts/data/account_local_store.dart` — no longer has `findByCardLastDigits` (removed during pivot)
- `lib/main.dart` — `parserSyncHandler` (syncOrder=4), `accountCardMappingSyncHandler`, `transactionRuleSyncHandler` registration
- `assets/parsers/bbva_mx.json` — v2 (4 patterns), single source of truth shared with the BE seed
- `assets/migrations/008.sql` — original schema (no `suggested_category_id`)
- `assets/migrations/012.sql` — `ALTER TABLE pending_transactions ADD COLUMN suggested_category_id TEXT`

**Android native:**
- `frontend/android/app/src/main/kotlin/app/pocketpilot/notifications/` — entire native module
- `frontend/android/app/src/main/AndroidManifest.xml`
- `frontend/android/app/src/main/kotlin/app/pocketpilot/MainActivity.kt`

**Tests + fixtures:**
- `frontend/test/notification_parser_engine_test.dart` — fixture-driven positives + inline negatives
- `frontend/test_data/bbva_mx_real_notifications.json` — 8 real BBVA MX notifications with `expected` blocks (curated from `captured_raw.json`)

**Scripts:**
- `scripts/dump_captured_notifications.sh` — adb + sqlite3 extractor

## Known follow-ups

- **First-word heuristic edge cases:** if generic words like "PAGO" learn a rule, future unrelated transactions may be miscategorized. Watch for this; add a Settings → Reglas screen if it becomes a problem.
- **Same `last_digits` across banks:** mappings are keyed by `(bank_id, last_digits)` so cross-bank collisions don't occur. Mappings are per-user.
- **Rule cleanup:** `account_card_mappings` and `transaction_rules` grow with approvals. No GC yet — add a periodic prune of old soft-deleted rows after ~6 months if tables grow unboundedly in practice.
- **Rate limiting (Phase 4) — decided:** extend `aiassistant.RateLimiter` with a `feature_key` (new column `feature TEXT NOT NULL DEFAULT 'chat'` on `ai_usage` via mig 013) so `notification_parser` quota is isolated from `chat`. Two `RateLimiter` instances share the `Repository` but track usage separately. Defaults: `NOTIFICATION_PARSER_DAILY_LIMIT=50`, `NOTIFICATION_PARSER_MONTHLY_TOKEN_LIMIT=200_000` (lower than chat because each notification is short).
- **Modal sheets need explicit provider re-provision:** any future bottom sheet/dialog opened with `showModalBottomSheet` from this feature must follow the `MultiProvider` pattern in `pending_inbox_screen.dart::_openReviewSheet`. The root navigator scoping bug is silent at compile time; only fails at runtime when the sheet's `initState` calls `context.read<X>()`.
- **In-place migration drift (mig 008 + 012):** the original `pending_transactions` schema was modified after release to add `suggested_category_id`, leaving early devices without the column. The fix (restore 008 + add 012 ALTER) followed the rule "never modify a published .sql"; remember this when iterating on future migrations during development. `database_helper.dart` documents the rule in its leading comment.
