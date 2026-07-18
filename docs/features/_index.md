# Features

Each row links to a feature doc (what it does, files involved, data flow, edge cases). Cross-cutting
architecture lives in [../architecture.md](../architecture.md); conventions in
[../conventions.md](../conventions.md).

| Feature | Description | Doc |
| ------- | ----------- | --- |
| Sync protocol | Offline-first delta pull + outbox push, LWW, preflight cursors | [sync-protocol](sync-protocol.md) |
| Auth | Custom auth: Google/Apple social login, JWKS, JWT + refresh rotation | [auth](auth.md) |
| Accounts | Account types, editable type, archive/restore, accounts screen | [accounts](accounts.md) |
| Transactions & transfers | Core ledger: income/expense, paired transfers, filters, tags | [transactions](transactions.md) |
| Transaction forms | Detailed structure of the transaction/transfer form screens | [transaction-forms](transaction-forms.md) |
| Transaction templates | Templates + deterministic scheduled generation (UUIDv5) | [transaction-templates](transaction-templates.md) |
| Yield configs | Yield configs + local interest generation, maturity/auto-renew | [yield-configs](yield-configs.md) |
| Investments | Holdings + lots + market prices, FIFO/avg P&L, portfolio view | [investments](investments.md) |
| Goals | Goals schema, progress/quota/overdue math, liquidity (deferred) | [goals](goals.md) |
| Budgets | Budgets + dynamic spend from transactions, AccountsScreen tab | [budgets](budgets.md) |
| Financial nature | REQUIRED/OBLIGATION/LIFESTYLE/ACTIVE/PASSIVE/WINDFALL + auto-charge | [financial-nature](financial-nature.md) |
| Adjustment nature | Balance-adjustment transactions + tap-routing guard | [adjustment-nature](adjustment-nature.md) |
| Dashboard | Net worth, metrics grid, credit cards, spend breakdowns | [dashboard](dashboard.md) |
| Statistics tab | Stats hub + unified filter + full-screen visualizations | [statistics-tab](statistics-tab.md) |
| Cashflow tab | Flujo view: in/out/net cards + waterfall + detail | [cashflow-tab](cashflow-tab.md) |
| Proactive notifications | Date-projection engine + notification center + OS scheduler + statement-import reminders | [proactive-notifications](proactive-notifications.md) |
| Notification capture | Android bank-notification capture → pending suggestions + gated auto-confirm | [notification-capture](notification-capture.md) |
| AI assistant | Gemini provider: chat + notification parser, per-feature models | [ai-assistant](ai-assistant.md) |
| CSV import | Extract→Map→Insert importer with account/category mapping + duplicate detection | [csv-import](csv-import.md) |
| Bank statement parser | Python `scripts/` PDF→CSV parsers (BBVA TC/Deb, RappiCard) | [bank-statement-parser](bank-statement-parser.md) |

> **Gap**: the frontend `features/debts/` module is not documented yet. `categories`, `tags` and
> `user_preferences` are covered in architecture/conventions rather than dedicated feature docs.
