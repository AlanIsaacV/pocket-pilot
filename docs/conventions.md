# Conventions

## General principles

- **Clarity over cleverness.** Write code that reads easily.
- **Surgical changes.** Make the minimum change needed to fulfill a requirement.

## Code style

### Go (backend)

- **Language**: Go (see `backend/go.mod`). Format with `gofmt`; tidy deps with `make tidy`.
- **Error handling**: always check errors; wrap with `fmt.Errorf("context: %w", err)` for traceability.
- **Context**: always pass `context.Context` to DB and gRPC calls.
- **Naming**: standard Go — `camelCase` (unexported), `PascalCase` (exported).
- **Logging**: prefer structured logging; remove ad-hoc `log`/`fmt` debug output before merging.
- **Comments**: idiomatic Go doc comments (e.g. `// Handler implements pb.AccountServiceServer`).
- **Conversions**: keep proto↔domain helpers (`toProto`/`fromProto`) private within the handler file.

### Dart (frontend)

- **Formatting**: format *new* files with `dart format`; do **not** run it on existing files — the
  current formatter (Dart 3.12+) reformats the repo's checked-in style wholesale, drowning the
  logical diff. Match the surrounding style by hand when editing (found in widget-unification
  phase 4; revisit if the repo is ever reformatted wholesale as its own commit).
- **Typing**: avoid `dynamic`; prefer strong typing and generics.
- **Naming**: `camelCase` for variables/methods, `PascalCase` for classes.
- **Models**: every syncable model MUST implement `toMap()`, `fromMap()`, `fromProto()`, and
  `toServerMap()` to cover local persistence, gRPC, and outbox payload transforms.
- **Async**: use `async`/`await`; handle errors with `try`/`catch` in UI/ViewModels.

## Error handling

- Backend returns gRPC status errors from handlers after validation; repositories return wrapped
  errors up the stack. Frontend surfaces failures via ViewModel `errorMessage` fields; sync failures
  are retried per cycle (see [architecture.md](architecture.md) → Sync).

## Testing

- **Backend**: Go tests (`go test ./...`); DB-touching tests use `internal/testdb`.
- **Frontend**: Flutter/Dart unit tests under `frontend/test/` (e.g. `position_math`, `pnl_math`,
  ViewModel tests). Pure-Dart domain math is unit-tested without a device.
- **Location/conventions**: co-locate tests with the layer they exercise; keep domain math pure and
  fully unit-tested (investments ships 27 such tests).

## Protobuf / API design

- **Backwards compatibility**: never remove or rename fields — use `reserved` when deprecating.
- **Package**: `pocket_pilot.v1`; one `*_service.proto` per entity; shared types in `common.proto`.
- **Sync-oriented services MUST expose**: `List<Entity>` (`updated_since`, `page`; `user_id` inferred
  from auth context), `Upsert<Entity>` (returns `conflict_resolved`), `Delete<Entity>` (identity +
  `deleted_at` for LWW soft delete).
- **Types**: `string` UUIDs; `google.protobuf.Timestamp` for time; `Money` for money;
  enum values prefixed by the enum name (`ACCOUNT_TYPE_BANK`); proto3 `optional` for
  subtype-conditional fields (`optional string category_id` → `*string` in Go, `hasField()` in Dart).
- **Codegen**: after any `.proto` change run `make proto` (`./scripts/gen_proto.sh`).

## Database & migrations

- **Naming**: plural `snake_case` tables; `snake_case` columns.
- **LWW columns**: syncable tables carry `created_at`, `updated_at`, `deleted_at`; identity may vary
  (single `id` UUID, or composite like `user_preferences(user_id, pref_key)`).
- **PostgreSQL**: `UUID` ids, `TIMESTAMP WITH TIME ZONE`, money as cents (`BIGINT` preferred over
  `NUMERIC`). LWW via `ON CONFLICT … DO UPDATE … WHERE table.updated_at < EXCLUDED.updated_at`.
  Soft-delete via `deleted_at`, never physical delete.
- **SQLite**: `TEXT` UUIDs, ISO-8601 UTC `TEXT` timestamps, `INTEGER` cents; may omit `user_id`.
  Enable foreign keys. Tags arrays persisted as JSON `TEXT`.
- **Nullable/self FKs**: `transactions.category_id` is nullable (transfers have none);
  `transactions.linked_transaction_id` self-references to pair transfer legs (use a partial index
  `WHERE column IS NOT NULL`).
- **Migration process**: (1) update `.proto` if needed → (2) add `backend/migrations/NNN_*.sql`
  → (3) add `frontend/assets/migrations/NNN.sql` + bump `DatabaseHelper._version` → (4) update the
  `Handler` and `LocalStore` for the new fields.
- **Dropping constraints in SQLite**: SQLite cannot `ALTER` away a `NOT NULL`/`CHECK`; rebuild the
  table instead — CREATE the new table → `INSERT … SELECT` → DROP old → RENAME → recreate
  indexes/triggers. First use: `frontend/assets/migrations/017.sql` (the PostgreSQL side is a plain
  `ALTER COLUMN … DROP NOT NULL`).
- **SQLite PRAGMAs on Android**: issue pragmas that return a row (`journal_mode`, `busy_timeout`)
  via `rawQuery`, **never** `execute`/`execSQL` — Android's `execSQL` rejects row-returning
  statements at runtime (device-only failure; `sqflite_common_ffi` unit tests accept `execute`
  and won't catch it). Set `busy_timeout` **before** `journal_mode=WAL` so the one-time WAL
  conversion already has the busy wait. `journal_mode=WAL` persists in the DB file;
  `busy_timeout` is per-connection — every new connection (Dart or Kotlin) must set its own.
  Canonical implementation: `configureDatabaseForConcurrentAccess` in
  `frontend/lib/src/core/db/database_helper.dart` (Dart) and `NotificationDb.openDatabase`
  (Kotlin).
- **Unpublished-migration exception**: a migration created in the current, not-yet-shipped session
  may be edited in place instead of adding a repair migration — "never modify a published .sql"
  applies from the moment it ships to a device.
- **MVP baseline exception**: while no production data exists, editing baseline `001_*.sql` directly
  to add required columns is acceptable.

## Frontend UI conventions

- **Category icons**: stored as Material codepoint hex (e.g. `"ef52"`). Render with
  `Icon(CategoryIconData.iconFromHex(model.icon))` — **never** `Text(model.icon)`. Convert back with
  `iconToHex`; `resolveIcon(nameOrHex)` accepts readable names (used by the seeder).
- **Category colors**: 6-char hex **without** `#`; sanitize (`hex.replaceFirst('#','')`) then
  `Color(int.parse('FF$sanitized', radix: 16))` with a try/catch fallback.
- **Custom numpad + system keyboard coexistence**: `resizeToAvoidBottomInset: false` +
  `MediaQuery.viewInsets.bottom > 0`; hide the numpad when the keyboard is up (Save stays in AppBar).
- **Shared form widgets/actions**: reuse `ui/widgets/form_widgets.dart` (`NumPad`, `TagsSection`,
  `NoteField`, `DetailRow`, `ScrollableBottomSheet`) and `ui/widgets/form_app_bar_actions.dart`
  across forms; the shared AppBar action renders Save last, secondary (Eliminar/Ocultar) first in
  edit mode. See [features/transaction-forms.md](features/transaction-forms.md).
- **Shared interaction primitives (grep-enforced invariants)**: confirmations go through
  `showConfirmDialog()` (`ui/widgets/confirm_dialog.dart`) — no inline `showDialog<bool>` +
  `AlertDialog`; swipe backgrounds through `DismissibleBackground`
  (`ui/widgets/dismissible_background.dart`, variants `delete`/`archive`/`edit`); form section
  labels through `FormSectionLabel` (`ui/widgets/form_section_label.dart`); all date picking
  through `pickDate()` — no raw `showDatePicker` outside `ui/widgets/form_date_utils.dart`;
  currency selection through `showCurrencyPicker()` (`ui/widgets/currency_picker.dart`) — no
  per-form currency sheets (grep: `_showCurrencySheet|__preferences__` returns nothing); account
  selection through `showAccountPicker()` (`ui/widgets/account_picker.dart`) — no per-form account
  sheets (grep: `_showAccountSheet|_showAccountPicker` returns nothing); date-range filter UI
  through the shared `TemporalPageView` + `TemporalFilterState` interface
  (`ui/widgets/temporal_page_view.dart`) — exactly one `temporal_page_view.dart` in the repo, and
  the canonical `QuickRange`/`PeriodGranularity` enums live there (consumers import them
  explicitly; no re-exports from view models). Two documented dropdown
  exceptions: `advanced_filters.dart` (filter context needs a "Todas" option) and
  `pending_review_sheet.dart` (dense sheet-within-sheet with a `FormField` validator).
  See [decisions/0009](decisions/0009-intentional-behavior-convergence.md).
- **Widget library layering**: a widget used by 2+ features lives in `lib/src/ui/` (`widgets/` or
  `screens/`); a feature's `ui/` never imports another feature's `ui/`. See
  [decisions/0008](decisions/0008-canonical-widget-library-location.md).
- **Providers & bottom sheets**: `showModalBottomSheet` does not inherit the widget-tree providers;
  re-provide dependencies via `MultiProvider` with `.value` — or read them from the caller's
  context *before* opening the sheet, as `showCurrencyPicker()` and `showAccountPicker()` do.

## Version control

- **Commits**: conventional prefixes — `feat:`, `fix:`, `docs:`, `refactor:`, etc.
- **PRs**: break large work into smaller, reviewable pull requests.
