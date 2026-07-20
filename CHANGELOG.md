# Changelog

All notable changes to this project are documented here.

## [0.1.0] - 2026-07-20

### Bug Fixes
- Split sql files to process step-by-step
- Sync on save, and avoid discard in sync queue
- Add tags index
- Remove foreign contraint
- Hide numpad when device's keyboard is open
- Missing ids on fresh device
- Deterministic `category_id`
- Autoreload list & dispose accounts
- Consume pagination to get all items
- Calc for safe-spend an buying power
- Future transactions and orphan accounts
- Currency-related issues
- Include transfers
- Allow linkage in templates

### Documentation
- Define AppBar form actions design spec
- Update docs
- Add transaction templates scheduling spec
- Update `transaction_template` related changes
- Add yield config design spec
- Add accounts architecture doc, update MANIFEST and journal
- Journal entry for statistics tab
- Document statistics tab architecture
- Migrate repo knowledge to docs/ layout (features/decisions/runbook + routers)
- Close out frictionless-capture phase 5
- Sync with reliable-os-notifications feature

### Features
- Initial schemas
- Init backend
- Add docker compose to init local DB
- Init flutter project
- Add base screens
- Update models and add outbox sync
- Add tags RPC
- Impement account RPC handlers
- Implement RPC handlers
- Update dependencies
- Implement offline-first feature and sync
- Add system design
- Update theme
- Add dashboard and settings
- Send auth token, uuid & remove user_id
- Add structured docs
- Add screens to edit and delete accounts
- Update list of default categories
- Add debug log to print sql path location
- Add categories screens
- Remove horizontal scroll to select color
- Adjust border radius
- Round ui
- Screen to add transactions
- Update front documents
- Polish UI
- Use system theme correctly
- Update ai contexts
- Save & sync user preferences for currencies and themes
- Add `currency_code`
- Add flows to edit and delete transactions
- Sync default category & improve default values
- Improve defaults and navigation
- Add special transaction-transfer feature
- Add initial amount
- Add calculator to transaction's numpad
- Add button to save/delete items
- Improve sync resilience
- Add FAB to add new transaction
- Prefill accounts and description
- Add transaction filters
- Add feature to create a transaction template
- Add screens to manage templates
- Add feature to create yields transactions
- Add screens to manage yields
- Add new feature
- Add `currency_code` and calculate progress
- New feature
- New feature
- Add UI screens
- Implement a basic dashboard
- Add credit card monthly payment
- Add import options from csv
- Add ai assitant
- Add login with Apple & Google
- Add transaction nature
- Schedule local notifications
- Adjust account balance
- Move transaction related screens
- Improve defaults
- Fix errors and improve logging
- Improve UX importing transactions
- Rename DeleteAccount→ArchiveAccount, add deleted_at to upsert, include archived in full sync
- Add archive/restore account + getArchivedAccounts
- Rename deleteAccount→archiveAccount, add deleted_at to _buildProto
- Update callers to use archiveAccount, add restoreAccount + grouping
- Rebuild accounts screen with type sections + archived section
- Allow editing account type with initial balance type flip handling
- Make interest rate APR field optional in account form
- Parse bbva & rappi statements
- Update rappi parser
- Refresh auth token and send always
- Show detailed transactions
- Improve dashboard and adjusments
- Credit card oracle
- Prepare for production
- Only sync when needed and reduce round-trips
- Add findByCategory lookup
- Pre-fill form via route query params
- Add Trend enum and threshold constant
- Add domain DTOs
- Add window bounds helpers
- Add local store SQL
- Add repository with trend/avg/zero-fill
- Add view model with filter reactivity
- Add time window chips
- Add category list row widget
- Add stat delta row widget
- Add monthly bar chart widget
- Add statistics tab list
- Add category history detail screen
- Add Estadísticas tab with route scope
- Goals progress based on its liquidity
- Add cashflow feature
- Improve filters
- Add investments
- Average cost
- Marketprice
- Portfolio distribution
- Add splits feature
- Add dynamic parsers nd dedup old entries
- Llm parser and candidates
- Add parser feedback
- Purge data to keep PII after 90 days
- Add specify model per feature chat or parser
- Expand packages to listen notifications
- Move entries to transaction list
- Add tags history
- Resolve card mappings by merchant pattern
- Batch-approve resolved suggestions and quick-pick categories
- Auto-confirm high-confidence suggestions into transactions
- Detect duplicates on statement import
- Add monthly statement-import reminder
- Run capture pipeline in background via workmanager
- Notify capture results with actionable category buttons
- Close delivery holes so scheduled reminders actually fire
- Derive per-event reminder content instead of one generic daily message
- Let users configure reminder types, time, and anticipation
- Add homelab CI/CD kit for the gRPC backend

### Miscellaneous
- Add fl_chart dependency
- Update plan

### Refactor
- Extract and reorganize transfer form components
- Extract transaction widgets and add documentation
- Make lib/src/ui the canonical home for shared widgets
- Add shared confirm/swipe/label primitives and adopt them everywhere
- Replace per-form currency sheets with one shared showCurrencyPicker
- Replace per-form account sheets with one shared showAccountPicker
- Collapse the two temporal page view copies into one shared widget
- Rename list tabs to list bodies and delete dead standalone screens

### Testing
- Add tab smoke tests

### Fear
- Implement RPC handlers

### Ref
- Format code
- Organize field
- Compact migrations & reorder protos
- Merge migrations


