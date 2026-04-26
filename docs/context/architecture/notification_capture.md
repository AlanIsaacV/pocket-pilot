# Notification Capture Architecture

Auto-suggestion of transactions from Android bank push notifications. iOS not supported by the OS.

## Scope (v1)

- **Bank coverage:** BBVA México only.
- **Mode:** Suggestions only — every captured notification produces a `PendingTransaction` that the user must approve or edit before it becomes a real `Transaction`.
- **Parsers:** Declarative JSON, embedded as asset in v1; sync from backend in Phase 3.
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
| `pending_transactions` (mig 008) | Suggestions ready for user review/approval. | No (approval becomes a `Transaction` which IS synced) |
| `notification_parsers` (mig 008) | Local cache of parser definitions. Phase 2: seeded from asset. Phase 3: synced from backend. | Yes (pull-only in Phase 3) |
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

- `BankNotificationListenerService.kt` — extends `NotificationListenerService`. Allowlist of `packageName`s in code (`com.bbva.bancomermovil`, `com.bancomer.mbanking`). Writes directly to the sqflite SQLite file (path = `getDatabasePath("pocket_pilot.db")`). Only writes to `captured_notifications` — never reads other tables. Schema is stable.
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

Tested with 7 cases in `test/notification_parser_engine_test.dart` (compra TC, transferencia in, compra online USD, OTP, promo, paquete no-bank, default currency).

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

### Sync handlers and order

| Entity | `syncOrder` | Direction | Notes |
|--------|-------------|-----------|-------|
| `account` | 1 | both | mapping FK depends on it |
| `category` | 2 | both | rule FK depends on it |
| `account_card_mapping` | 5 | both | must arrive before the engine resolves on next refresh |
| `transaction_rule` | 5 | both | same as above |
| `notification_parser` | (TBD Phase 3) | pull-only | server is source of truth |
| `transaction` | 9 | both | unchanged |

`pending_transactions` and `captured_notifications` are NOT synced.

### UI

- `/inbox` (route, link from Settings → "Captura de notificaciones"): lists PendingTransactions + raw unprocessed notifications. RefreshIndicator triggers `processInbox()`.
- `PendingReviewSheet`: bottom sheet pre-filled from the parser match, with editable amount, currency, description, account dropdown, **category dropdown** (filtered by `transaction_type`), and date. Shows a currency-mismatch warning when notification currency ≠ selected account currency. Approve/Dismiss buttons.
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
| 3 | pending | Move parsers from asset to backend table, sync via pull-only handler, seed BBVA MX v1 in migration |
| 4 | pending | Server-side `ParseNotification` RPC, Gemini fallback, `candidate_parsers` table, ReDoS regex validator, privacy toggle in Settings |

## Reference files

**Proto:**
- `proto/pocket_pilot/v1/account_card_mapping_service.proto`
- `proto/pocket_pilot/v1/transaction_rule_service.proto`

**Backend:**
- `backend/internal/cardmapping/cardmapping.go` (model + repo + handler)
- `backend/internal/txrule/txrule.go` (model + repo + handler)
- `backend/internal/sync/entity_type.go` — `EntityAccountCardMapping`, `EntityTransactionRule`
- `backend/migrations/010_account_card_mappings.sql`
- `backend/migrations/011_transaction_rules.sql`

**Frontend Flutter:**
- `lib/src/features/notification_capture/` — entire feature module
- `lib/src/features/accounts/data/account_local_store.dart` — no longer has `findByCardLastDigits` (removed during pivot)
- `lib/main.dart` — `accountCardMappingSyncHandler` and `transactionRuleSyncHandler` registration

**Android native:**
- `frontend/android/app/src/main/kotlin/app/pocketpilot/notifications/` — entire native module
- `frontend/android/app/src/main/AndroidManifest.xml`
- `frontend/android/app/src/main/kotlin/app/pocketpilot/MainActivity.kt`

**Tests:**
- `frontend/test/notification_parser_engine_test.dart` (7 cases)

## Known follow-ups

- **First-word heuristic edge cases:** if generic words like "PAGO" learn a rule, future unrelated transactions may be miscategorized. Watch for this; add a Settings → Reglas screen if it becomes a problem.
- **Same `last_digits` across banks:** mappings are keyed by `(bank_id, last_digits)` so cross-bank collisions don't occur. Mappings are per-user.
- **Rule cleanup:** `account_card_mappings` and `transaction_rules` grow with approvals. No GC yet — add a periodic prune of old soft-deleted rows after ~6 months if tables grow unboundedly in practice.
- **Rate limiting (Phase 4):** decide whether `ParseNotification` shares the existing `aiassistant.RateLimiter` quota or has a dedicated one.
