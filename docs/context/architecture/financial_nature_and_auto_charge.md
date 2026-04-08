# Financial Nature Classification and Auto Charge Management

Classifies each financial movement by its economic nature (beyond income/expense type) and allows recurring templates to be marked as automatic charges with active/inactive state.

## Scope

- **FinancialNature enum** shared across Category, Transaction, and generation engines.
- **Default-with-Override pattern:** categories carry a `default_nature` that pre-populates transactions, but each transaction stores its own `nature` which can be overridden individually.
- **Auto Charge indicator** (`is_auto_charge`) on transaction templates to mark subscriptions and direct debits.
- **Active/Inactive toggle** (`is_active`) on transaction templates to pause recurring generation without deleting the template.
- **Generator compliance:** `ScheduledTransactionGenerator` respects `is_active` and inherits `nature` from the template's category. `YieldTransactionGenerator` forces `nature = 'passive'` on all interest transactions.

## Data Model

### FinancialNature Enum Values

| Value         | Code String   | Use Case                                    |
|---------------|---------------|---------------------------------------------|
| UNSPECIFIED   | `""`          | Default for existing/unclassified data      |
| REQUIRED      | `"required"`  | Expenses: groceries, rent, healthcare       |
| OBLIGATION    | `"obligation"`| Expenses: taxes, debt payments, insurance   |
| LIFESTYLE     | `"lifestyle"` | Expenses: entertainment, luxuries, hobbies  |
| ACTIVE        | `"active"`    | Income: salary, freelance                   |
| PASSIVE       | `"passive"`   | Income: investment yields, rental income    |
| WINDFALL      | `"windfall"`  | Income: bonuses, gifts, occasional sales    |

The enum is **unrestricted** — any nature value can be assigned to any category type. The UI filters options contextually (expense natures for expense categories, income natures for income categories) but does not enforce this at the data layer.

### Proto Definitions

The `FinancialNature` enum is defined in `proto/pocket_pilot/v1/common.proto` to avoid circular imports, since both `category_service.proto` and `transaction_service.proto` reference it.

**New/modified fields:**

- `Category.default_nature` (field 10) — `FinancialNature` in `proto/pocket_pilot/v1/category_service.proto`
- `Transaction.nature` (field 18) — `FinancialNature` in `proto/pocket_pilot/v1/transaction_service.proto`
- `TransactionTemplate.is_auto_charge` (field 17) — `bool` in `proto/pocket_pilot/v1/transaction_template_service.proto`
- `TransactionTemplate.is_active` (field 18) — `bool` in `proto/pocket_pilot/v1/transaction_template_service.proto`

### Backend PostgreSQL

Migration: `backend/migrations/002_financial_nature_and_auto_charge.sql`

| Table                    | Column           | Type      | Default   |
|--------------------------|------------------|-----------|-----------|
| `categories`             | `default_nature` | `TEXT`    | `''`      |
| `transactions`           | `nature`         | `TEXT`    | `''`      |
| `transaction_templates`  | `is_auto_charge` | `BOOLEAN` | `FALSE`  |
| `transaction_templates`  | `is_active`      | `BOOLEAN` | `TRUE`   |

Nature is stored as lowercase TEXT matching the enum code strings above. Empty string maps to `NATURE_UNSPECIFIED`. Defaults ensure backward compatibility with existing rows.

### Frontend SQLite

Migration: `frontend/assets/migrations/002.sql`
Database version bumped to 2 in `frontend/lib/src/core/db/database_helper.dart`.

| Table                    | Column           | Type      | Default |
|--------------------------|------------------|-----------|---------|
| `categories`             | `default_nature` | `TEXT`    | `''`    |
| `transactions`           | `nature`         | `TEXT`    | `''`    |
| `transaction_templates`  | `is_auto_charge` | `INTEGER` | `0`    |
| `transaction_templates`  | `is_active`      | `INTEGER` | `1`    |

SQLite uses `INTEGER` for booleans (0/1). Nature uses `TEXT` matching the backend convention.

## Backend Services

### Category Module

- **Model:** `DefaultNature string` field added to `Category` struct in `backend/internal/category/repository.go`.
- **Repository:** `scanColumns` includes `default_nature`; `Upsert` INSERT/ON CONFLICT includes the column.
- **Handler:** `backend/internal/category/handler.go` — `financialNatureToString()` and `stringToFinancialNature()` helpers convert between proto enum and TEXT. `toProto()`/`fromProto()` map the field.

### Transaction Module

- **Model:** `Nature string` field added to `Transaction` struct in `backend/internal/transaction/repository.go`.
- **Repository:** `scanColumns` includes `nature`; `Upsert` INSERT/ON CONFLICT includes the column.
- **Handler:** `backend/internal/transaction/handler.go` — same `financialNatureToString()`/`stringToFinancialNature()` helpers (duplicated per package, following existing pattern). `toProto()`/`fromProto()` map the field.

### Transaction Template Module

- **Model:** `IsAutoCharge bool` and `IsActive bool` fields added to `Template` struct in `backend/internal/transactiontemplate/model.go`.
- **Repository:** `scanColumns` includes `is_auto_charge, is_active`; `Upsert` INSERT/ON CONFLICT includes both columns. `backend/internal/transactiontemplate/repository.go`.
- **Handler:** `backend/internal/transactiontemplate/handler.go` — `toProto()`/`fromProto()` map `IsAutoCharge` and `IsActive` directly (bool-to-bool, no conversion needed).

## Frontend Feature Structure

### Domain Models

**CategoryModel** (`frontend/lib/src/features/categories/domain/category.dart`):
- `defaultNature` field (String, default `''`).
- `_financialNatureToString()` converts proto enum to string for `fromProto()`.
- `stringToFinancialNature()` (public static) converts string back to proto enum for sync handlers.
- `fromMap()` reads `map['default_nature']`; `toMap()` writes `'default_nature'`.
- `copyWith()` supports `defaultNature`.

**TransactionModel** (`frontend/lib/src/features/transactions/domain/transaction.dart`):
- `nature` field (String, default `''`).
- Same `_financialNatureToString()`/`stringToFinancialNature()` helpers.
- `fromMap()`/`toMap()`/`toServerMap()` include `'nature'`.

**TransactionTemplateModel** (`frontend/lib/src/features/transaction_templates/domain/transaction_template.dart`):
- `isAutoCharge` field (bool, default `false`), `isActive` field (bool, default `true`).
- `fromProto()` reads `proto.isAutoCharge` / `proto.isActive`.
- `fromMap()` converts `int` to `bool` (`(map['is_auto_charge'] as int? ?? 0) == 1`).
- `toMap()` writes as `int` (for SQLite); `toServerMap()` writes as `bool` (for outbox JSON).

### Data Layer

**TransactionTemplateLocalStore** (`frontend/lib/src/features/transaction_templates/data/transaction_template_local_store.dart`):
- `querySchedulableRows()` — WHERE clause now includes `AND is_active = 1`. Paused templates are excluded from generation.
- `queryAutoChargeRows()` — new method returning all templates where `is_auto_charge = 1`, ordered by `is_active DESC, name ASC`.

**TransactionTemplateRepository** (`frontend/lib/src/features/transaction_templates/data/transaction_template_repository.dart`):
- `getAutoCharges()` — new method wrapping `queryAutoChargeRows()`, returns `List<TransactionTemplateModel>`.

**TransactionRepository** (`frontend/lib/src/features/transactions/data/transaction_repository.dart`):
- `createTransaction()` and `updateTransaction()` accept optional `String nature` parameter (default `''`).

**CategoryRepository** (`frontend/lib/src/features/categories/data/category_repository.dart`):
- `createCategory()` accepts optional `String defaultNature` parameter.
- `updateCategory()` accepts optional `String? defaultNature` parameter.

### Generation Engines

**ScheduledTransactionGenerator** (`frontend/lib/src/features/transaction_templates/data/scheduled_transaction_generator.dart`):
1. `CategoryLookup` interface extended with `Future<String> getDefaultNatureById(String id)`.
2. `CategoryLookupAdapter` implements it by looking up the category and returning `defaultNature`.
3. `_insertSingleOccurrence()` resolves nature from the template's category via `_categories.getDefaultNatureById()` and includes `'nature': nature` in the generated transaction row.
4. `_generateTransferOccurrence()` sets `'nature': ''` (transfers have no category).
5. `_copyWithNextDate()` preserves `isAutoCharge` and `isActive` fields.

**YieldTransactionGenerator** (`frontend/lib/src/features/yield_configs/data/yield_transaction_generator.dart`):
- All generated interest transactions include `'nature': 'passive'` in the row map, hardcoded per business requirement.

### UI Integration

**Category Form** (`frontend/lib/src/features/categories/ui/category_form_screen.dart`):
- Nature picker widget (`_NaturePicker`) with chip-style options filtered by category type.
- Expense categories show: Sin definir, Necesario, Obligacion, Estilo de vida.
- Income categories show: Sin definir, Activo, Pasivo, Extraordinario.
- Switching category type resets incompatible nature selections.

**Transaction Form** (`frontend/lib/src/features/transactions/ui/transaction_form_screen.dart`):
- `DetailRow` labeled "Naturaleza" with bottom sheet selector.
- Auto-populates from `category.defaultNature` when user selects a category (from picker or recent chips).
- User can override via the bottom sheet before saving.
- Options filtered by transaction type (expense vs income).

**Template Form** (`frontend/lib/src/features/transaction_templates/ui/transaction_template_form_screen.dart`):
- `DetailRow` labeled "Naturaleza" below the category selector (non-transfer types only). Shows the selected category's `defaultNature` and allows override via bottom sheet. This is a display/UX convenience — the template model does not store nature; generated transactions inherit it from the category at generation time.
- `SwitchListTile` for "Cargo automatico" (`is_auto_charge`).
- `SwitchListTile` for "Activa" (`is_active`) with dynamic subtitle indicating generation status.

## Sync Integration

No changes to the sync protocol or outbox mechanics. The new fields are included in:
- `toMap()` / `toServerMap()` of each model, so they flow through the existing outbox pipeline.
- `fromProto()` / `fromMap()` of each model, so they are correctly hydrated during delta pull.
- Proto3 default values (empty string for enums, false for bools) ensure backward compatibility when older clients sync payloads without the new fields.

## Tests

- `frontend/test/scheduled_transaction_generator_test.dart` — `_FakeCategories` mock updated with `getDefaultNatureById()` method.
- Backend tests: existing test fixtures in `backend/internal/category/`, `backend/internal/transaction/`, and `backend/internal/transactiontemplate/` need scan column updates to match new `scanColumns` constants.
