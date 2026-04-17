# Project Context Manifest

This manifest serves as a map for all AI agents and developers working on the Pocket Pilot project. It categorizes technical documentation and conventions to ensure consistency across the codebase.

## How to use this Context
Before starting any task, identify the relevant domain (Backend, Frontend, or Proto) and read the corresponding files. If you make architectural decisions or change conventions during a session, log them in `.journal.md` and update the permanent documents at the end of the session.

## Document Index

### Core Architecture
- [architecture/system_overview.md](architecture/system_overview.md) - High-level system design (Client-Server-DB) and data flow.
- [architecture/sync_protocol.md](architecture/sync_protocol.md) - Detailed Offline-First protocol (Delta Pull, Outbox, LWW).
- [architecture/backend_go.md](architecture/backend_go.md) - Go gRPC server structure, Repository patterns, and PostgreSQL rules.
- [architecture/frontend_flutter.md](architecture/frontend_flutter.md) - Flutter app structure, State Management (Provider), and SQLite patterns.
- [architecture/transaction_templates_and_scheduled_generation.md](architecture/transaction_templates_and_scheduled_generation.md) - Transaction templates, scheduled generator (`sync -> generate -> sync`), deterministic UUIDv5 occurrences, transfer-pair reconciliation, and tags/template linkage behavior.
- [architecture/yield_configs_and_interest_generation.md](architecture/yield_configs_and_interest_generation.md) - Yield config schema/contracts, local interest generation with deterministic UUIDv5, maturity/auto-renew behavior, `transactions.yield_id` linkage, and sync order integration.
- [architecture/goals_and_liquidity.md](architecture/goals_and_liquidity.md) - Goals schema/contracts, computed properties (progress, monthly quota, overdue), liquidity concept (deferred), and integration points for when liquidity is available.
- [architecture/budgets.md](architecture/budgets.md) - Budgets schema/contracts (with visual-only `currency_code`), dynamic spend calculation from transactions, BudgetStatus DTO, UI integration as third tab in AccountsScreen, category picker via `CategoryPickerScreen`.
- [architecture/accounts.md](architecture/accounts.md) - Account types (type-specific fields, editable type with orphaned field cleanup), archive/restore (soft-delete reinterpretation, no permanent deletion), accounts screen structure (type-grouped sections, archived section with restore). Archived-account accessibility pattern for historical references: `getByIdIncludingArchived`, transactions-list account-map merge, edit-only injection in transaction/transfer forms.
- [architecture/auth.md](architecture/auth.md) - Custom auth with Google/Apple social login, JWKS validation, JWT access tokens, refresh token rotation, account linking by email, DB wipe on user change, platform-specific login (Apple iOS only).
- [architecture/financial_nature_and_auto_charge.md](architecture/financial_nature_and_auto_charge.md) - Financial nature classification (REQUIRED, OBLIGATION, LIFESTYLE, ACTIVE, PASSIVE, WINDFALL), default-with-override pattern on categories/transactions, auto charge indicator and active/inactive toggle on transaction templates, generator compliance.
- [architecture/proactive_notifications.md](architecture/proactive_notifications.md) - Offline-first proactive notifications: date projection engine from accounts/templates, persistent notification center with read/deleted state (migration 004), OS local notification scheduler (64-day window, idempotent clean-slate), bell widget with badge, deep linking.
- [architecture/dashboard_sections.md](architecture/dashboard_sections.md) - Dashboard screen layout: currency tabs, net worth card, metrics grid (liquidez real/libre, poder de compra). Key formulas: `safeToSpend = liquid - goalMonthly - cardPayment` (goalMonthly via `GoalMath.totalMonthlyRequiredCents`, NOT lifetime target); `buyingPower = liquid + revolving` (NOT safeToSpend-based, to avoid double-counting). Credit card payments section (per-card via CreditCardOracle). CreditCardOracle cycle logic: anchors on statementDay of target month, chargeCutoff=min(now,closeCurr), payment window starts at previous due date, excludes income adjustments. Accounts list, spend by category/nature/tags. Data flow: DashboardLocalStore SQL → DashboardRepository → DashboardViewModel → DashboardScreen.
- [architecture/adjustment_nature.md](architecture/adjustment_nature.md) - Balance adjustment transactions: `nature='adjustment'` + `categoryId=null` distinguishes from initial balance (`nature=''` + `categoryId=null`). Tap routing: 3-layer guard prevents adjustments from opening account editor. Transaction form: `_isCategoryOptional` allows saving without category. CreditCardOracle: `_isPayment()` excludes income adjustments. Proto `NATURE_ADJUSTMENT=7`, PostgreSQL `nature_type`. UI: grey `sync_alt` icon, "Ajuste de saldo" label.

### Utility Scripts
- [architecture/frontend_flutter.md#python-scripts-bank-statement-parser](architecture/frontend_flutter.md#python-scripts-bank-statement-parser) - Python scripts for parsing bank statement PDFs (BBVA TC, BBVA Debit, RappiCard) into CSV format for app import. Located in `scripts/`.

### Development Conventions
- [conventions/coding_standards.md](conventions/coding_standards.md) - Naming conventions, error handling, and style guides for Go and Dart.
- [conventions/proto_guidelines.md](conventions/proto_guidelines.md) - Rules for defining gRPC services and messages.
- [conventions/database_schema.md](conventions/database_schema.md) - Migration rules and schema design for PostgreSQL and SQLite.

### Decision Records & Dependencies
- [decisions/0001-sync-strategy.md](decisions/0001-sync-strategy.md) - Initial ADR: Why we chose Last Write Wins (LWW) and Delta Pull.
- [decisions/0002-sync-coalescing-and-user-preferences.md](decisions/0002-sync-coalescing-and-user-preferences.md) - Ensures concurrent sync requests are coalesced and preference saves flush to server immediately.
- [decisions/0003-sync-preflight-cursors.md](decisions/0003-sync-preflight-cursors.md) - Adds `SyncService.GetSyncStatus` preflight + per-user cursor table (`user_sync_cursors`) to skip pulls for untouched entities (9 RPCs → 1 on cold sync).
- [dependencies/module_map.md](dependencies/module_map.md) - Dependency graph between internal modules and external libraries.

### Deferred Work
- [todos.md](todos.md) - Index of code-level TODOs grouped by dependency (e.g. `TODO(liquidity)`). Revisit when the blocking feature is implemented.

### Session Logs
- [.journal.md](.journal.md) - Temporary log for technical decisions made during the current session.
