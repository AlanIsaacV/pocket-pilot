# Archive Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace account deletion with archive/restore — archived accounts stay visible (dimmed, grouped by type) and can be restored.

**Architecture:** Reinterpret the existing `deleted_at` column as "archived". Rename Delete→Archive in proto/backend/frontend. Restore works via the existing `UpsertAccount` RPC (same pattern as category restore). Fix backend upsert SQL to include `deleted_at`. Restructure accounts screen with type-grouped sections + archived section.

**Tech Stack:** Protobuf + gRPC, Go (backend), Flutter/Dart (frontend), SQLite (local), PostgreSQL (server)

---

### Task 1: Rename proto DeleteAccount → ArchiveAccount + regenerate

**Files:**
- Modify: `proto/pocket_pilot/v1/account_service.proto`
- Regenerate: `backend/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1/account_service.pb.go`
- Regenerate: `backend/internal/gen/proto/pocket_pilot/v1/pocket_pilot/v1/account_service_grpc.pb.go`
- Regenerate: `frontend/lib/src/generated/pocket_pilot/v1/account_service.pb*.dart`

- [ ] **Step 1: Rename the RPC and message types in the proto file**

In `proto/pocket_pilot/v1/account_service.proto`, change:

```protobuf
  // Archiva lógicamente una cuenta (soft delete con LWW por deleted_at).
  rpc ArchiveAccount(ArchiveAccountRequest) returns (google.protobuf.Empty);
```

And rename the request message:

```protobuf
message ArchiveAccountRequest {
  string id = 1;
  // Timestamp de la eliminación en el cliente, usado para LWW.
  google.protobuf.Timestamp deleted_at = 2;
}
```

The full diff from the original:
- Line 48-49: `rpc DeleteAccount(DeleteAccountRequest)` → `rpc ArchiveAccount(ArchiveAccountRequest)`
- Line 48 comment: `Elimina lógicamente` → `Archiva lógicamente`
- Line 79: `message DeleteAccountRequest` → `message ArchiveAccountRequest`

- [ ] **Step 2: Regenerate protobuf code**

Run:
```bash
cd /Volumes/rusty-drive/projects/pocket-pilot && make proto
```

Expected: `✓ Done. Generated files:` with Go and Dart output paths.

- [ ] **Step 3: Verify generated code compiles**

Run:
```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...
```

Expected: Compilation error in `handler.go` because `DeleteAccount` method and `DeleteAccountRequest` type no longer exist. This is expected — we fix it in Task 2.

- [ ] **Step 4: Do NOT commit yet** — the backend won't compile until the handler is updated in the next steps.

---

### Task 2: Backend — fix handler, repository, and list query

**Files:**
- Modify: `backend/internal/account/handler.go:141-171,241-263`
- Modify: `backend/internal/account/repository.go:92-103,132-155`

- [ ] **Step 1: Rename DeleteAccount handler to ArchiveAccount in handler.go**

In `backend/internal/account/handler.go`, replace the `DeleteAccount` method (lines 241-263) with:

```go
func (h *Handler) ArchiveAccount(ctx context.Context, req *pb.ArchiveAccountRequest) (*emptypb.Empty, error) {
	userID, err := middleware.UserIDFromCtx(ctx)
	if err != nil {
		return nil, err
	}

	id, err := parseUUID(req.Id, "id")
	if err != nil {
		return nil, err
	}

	var deletedAt time.Time
	if req.DeletedAt != nil {
		deletedAt = req.DeletedAt.AsTime()
	} else {
		deletedAt = time.Now().UTC()
	}

	if err := h.repo.SoftDelete(ctx, id, userID, deletedAt); err != nil {
		return nil, status.Errorf(codes.Internal, "archive account: %v", err)
	}
	return &emptypb.Empty{}, nil
}
```

- [ ] **Step 2: Update fromProto to read deleted_at in handler.go**

In `backend/internal/account/handler.go`, add `deleted_at` handling at the end of the `fromProto` function (before the final `return nil` on line 170):

```go
	if p.DeletedAt != nil {
		t := p.DeletedAt.AsTime()
		a.DeletedAt = &t
	}
	return nil
```

This replaces the existing `return nil` on line 170. The full block after `TermMonths` (lines 166-170) becomes:

```go
	if p.TermMonths != 0 {
		v := p.TermMonths
		a.TermMonths = &v
	}
	if p.DeletedAt != nil {
		t := p.DeletedAt.AsTime()
		a.DeletedAt = &t
	}
	return nil
```

- [ ] **Step 3: Fix Upsert SQL to include deleted_at in repository.go**

In `backend/internal/account/repository.go`, replace the `Upsert` method's SQL query (lines 133-155) with:

```go
	row := r.pool.QueryRow(ctx, `
		INSERT INTO accounts (id, user_id, name, type, currency_code, credit_limit_cents, statement_day, payment_due_day, interest_rate_apr, term_months, created_at, updated_at, deleted_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		ON CONFLICT (id) DO UPDATE SET
			name              = EXCLUDED.name,
			type              = EXCLUDED.type,
			currency_code     = EXCLUDED.currency_code,
			credit_limit_cents = EXCLUDED.credit_limit_cents,
			statement_day     = EXCLUDED.statement_day,
			payment_due_day   = EXCLUDED.payment_due_day,
			interest_rate_apr = EXCLUDED.interest_rate_apr,
			term_months       = EXCLUDED.term_months,
			updated_at        = EXCLUDED.updated_at,
			deleted_at        = EXCLUDED.deleted_at
		WHERE accounts.updated_at < EXCLUDED.updated_at
		RETURNING id, user_id, name, type, currency_code, credit_limit_cents,
			statement_day, payment_due_day, interest_rate_apr,
			term_months, created_at, updated_at, deleted_at`,
		a.ID, a.UserID, a.Name, a.Type,
		a.CurrencyCode,
		a.CreditLimitCents, a.StatementDay, a.PaymentDueDay,
		a.InterestRateApr, a.TermMonths,
		a.CreatedAt, a.UpdatedAt, a.DeletedAt,
	)
```

Changes from original:
- INSERT column list: added `deleted_at` at end
- VALUES: added `$13`
- ON CONFLICT: added `deleted_at = EXCLUDED.deleted_at`
- Parameters: added `a.DeletedAt` as 13th parameter

- [ ] **Step 4: Remove deleted_at IS NULL filter from full sync in repository.go**

In `backend/internal/account/repository.go`, replace the full sync query (lines 93-103) with:

```go
		// Full sync: return all records (active + archived) with pagination.
		rows, err = r.pool.Query(ctx,
			`SELECT id, user_id, name, type, currency_code, credit_limit_cents,
				statement_day, payment_due_day, interest_rate_apr,
				term_months, created_at, updated_at, deleted_at
			 FROM accounts
			 WHERE user_id = $1
			 ORDER BY created_at DESC
			 LIMIT $2 OFFSET $3`,
			userID, limit, offset,
		)
```

Only change: removed `AND deleted_at IS NULL` from the WHERE clause. Also updated the comment from "return all active records" to "return all records (active + archived)".

- [ ] **Step 5: Verify backend compiles**

Run:
```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/backend && go build ./...
```

Expected: Clean build, no errors.

- [ ] **Step 6: Commit proto + backend changes together**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add proto/pocket_pilot/v1/account_service.proto \
        backend/internal/gen/ \
        frontend/lib/src/generated/ \
        backend/internal/account/handler.go \
        backend/internal/account/repository.go
git commit -m "feat(backend): rename Delete→Archive, add deleted_at to upsert, include archived in full sync"
```

---

### Task 3: Frontend — model + local store + repository

**Files:**
- Modify: `frontend/lib/src/features/accounts/domain/account.dart:4`
- Modify: `frontend/lib/src/features/accounts/data/account_local_store.dart:49-89`
- Modify: `frontend/lib/src/features/accounts/data/account_repository.dart:88-104`

- [ ] **Step 1: Add isArchived getter to AccountModel**

In `frontend/lib/src/features/accounts/domain/account.dart`, add a getter after the `deletedAt` field declaration (after line 19):

```dart
  bool get isArchived => deletedAt != null;
```

The block becomes:

```dart
  final DateTime? deletedAt;

  bool get isArchived => deletedAt != null;

  const AccountModel({
```

- [ ] **Step 2: Add getArchivedAccounts and restore methods to AccountLocalStore**

In `frontend/lib/src/features/accounts/data/account_local_store.dart`, add two new methods after the `getById` method (after line 49, before the WRITE section comment):

```dart
  /// Retorna todas las cuentas archivadas, ordenadas por fecha de archivado descendente.
  Future<List<AccountModel>> getArchivedAccounts() async {
    final db = await _db.database;
    final rows = await db.query(
      'accounts',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return rows.map(AccountModel.fromMap).toList();
  }
```

And add a `restore` method after the `softDelete` method (after line 88, before the closing `}`):

```dart
  /// Restaura una cuenta archivada: limpia deleted_at y actualiza updated_at.
  Future<void> restore(String id, DateTime updatedAt) async {
    final db = await _db.database;
    await db.update(
      'accounts',
      {
        'deleted_at': null,
        'updated_at': updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
```

- [ ] **Step 3: Rename deleteAccount to archiveAccount and add restoreAccount + getArchivedAccounts in repository**

In `frontend/lib/src/features/accounts/data/account_repository.dart`, replace the `deleteAccount` method (lines 88-104) with:

```dart
  Future<List<AccountModel>> getArchivedAccounts() =>
      _local.getArchivedAccounts();

  Future<void> archiveAccount(String id) async {
    final now = DateTime.now().toUtc();
    final current = await _local.getById(id);

    var deletedAt = now;
    if (current != null && !current.updatedAt.isBefore(now)) {
      deletedAt = current.updatedAt.add(const Duration(milliseconds: 1));
    }

    await _local.softDelete(id, deletedAt);
    await _outbox.enqueue(
      entityType: 'account',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': deletedAt.toIso8601String()}),
    );
  }

  Future<void> restoreAccount(String id) async {
    final now = DateTime.now().toUtc();
    await _local.restore(id, now);
    final model = await _local.getById(id);
    if (model == null) return;
    await _outbox.enqueue(
      entityType: 'account',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }
```

- [ ] **Step 4: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/accounts/domain/account.dart \
        frontend/lib/src/features/accounts/data/account_local_store.dart \
        frontend/lib/src/features/accounts/data/account_repository.dart
git commit -m "feat(frontend-data): add archive/restore account + getArchivedAccounts"
```

---

### Task 4: Frontend — remote service + sync handler renames

**Files:**
- Modify: `frontend/lib/src/features/accounts/data/account_remote_service.dart:42-56,58-84`
- Modify: `frontend/lib/src/features/accounts/data/account_sync_handler.dart:64-66`

- [ ] **Step 1: Rename deleteAccount to archiveAccount and update _buildProto in remote service**

In `frontend/lib/src/features/accounts/data/account_remote_service.dart`, rename the `deleteAccount` method (lines 42-56) to `archiveAccount`:

```dart
  Future<void> archiveAccount({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.archiveAccount(
        ArchiveAccountRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC archiveAccount error: ${e.message}');
    }
  }
```

- [ ] **Step 2: Update _buildProto to include deleted_at**

In `frontend/lib/src/features/accounts/data/account_remote_service.dart`, replace the `_buildProto` method (lines 58-84) with:

```dart
  Account _buildProto(Map<String, dynamic> map) {
    final creditLimitCents = map['credit_limit_cents'] as int?;
    final statementDay = map['statement_day'] as int?;
    final paymentDueDay = map['payment_due_day'] as int?;
    final interestRateApr = map['interest_rate_apr'] as int?;
    final termMonths = map['term_months'] as int?;
    final deletedAtStr = map['deleted_at'] as String?;

    final proto = Account(
      id: map['id'] as String,
      name: map['name'] as String,
      type: AccountModel.stringToAccountType(map['type'] as String),
      currencyCode: map['currency_code'] as String,
      creditLimitCents: creditLimitCents != null
          ? Int64(creditLimitCents)
          : null,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      interestRateApr: interestRateApr,
      termMonths: termMonths,
      createdAt: Timestamp.fromDateTime(
        DateTime.parse(map['created_at'] as String).toUtc(),
      ),
      updatedAt: Timestamp.fromDateTime(
        DateTime.parse(map['updated_at'] as String).toUtc(),
      ),
    );

    if (deletedAtStr != null) {
      proto.deletedAt = Timestamp.fromDateTime(
        DateTime.parse(deletedAtStr).toUtc(),
      );
    }

    return proto;
  }
```

- [ ] **Step 3: Update sync handler pushDelete to call archiveAccount**

In `frontend/lib/src/features/accounts/data/account_sync_handler.dart`, rename the method body on line 65:

```dart
  @override
  Future<void> pushDelete(String entityId, DateTime deletedAt) async {
    await _remote.archiveAccount(id: entityId, deletedAt: deletedAt);
  }
```

Only change: `_remote.deleteAccount` → `_remote.archiveAccount`.

- [ ] **Step 4: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/accounts/data/account_remote_service.dart \
        frontend/lib/src/features/accounts/data/account_sync_handler.dart
git commit -m "feat(frontend-sync): rename deleteAccount→archiveAccount, add deleted_at to _buildProto"
```

---

### Task 5: Frontend — update callers (view model, debt repo, form screen)

**Files:**
- Modify: `frontend/lib/src/features/accounts/ui/accounts_view_model.dart:176-180,196-199`
- Modify: `frontend/lib/src/features/debts/data/debt_repository.dart:278-279`
- Modify: `frontend/lib/src/features/accounts/ui/account_form_screen.dart:292-333`

- [ ] **Step 1: Update AccountsViewModel — add archivedAccounts, rename deleteAccount, add restoreAccount**

In `frontend/lib/src/features/accounts/ui/accounts_view_model.dart`:

First, add the `archivedAccounts` field after the `accounts` field (line 33):

```dart
  List<AccountModel> accounts = [];
  List<AccountModel> archivedAccounts = [];
```

Then add the grouping getters and restoreAccount. Replace the `deleteAccount` method (lines 176-180) with:

```dart
  Map<String, List<AccountModel>> get accountsByType {
    final grouped = <String, List<AccountModel>>{};
    for (final account in accounts) {
      grouped.putIfAbsent(account.type, () => []).add(account);
    }
    return grouped;
  }

  Map<String, List<AccountModel>> get archivedAccountsByType {
    final grouped = <String, List<AccountModel>>{};
    for (final account in archivedAccounts) {
      grouped.putIfAbsent(account.type, () => []).add(account);
    }
    return grouped;
  }

  Future<void> archiveAccount(String id) async {
    await _repository.archiveAccount(id);
    await _reloadAll();
  }

  Future<void> restoreAccount(String id) async {
    await _repository.restoreAccount(id);
    await _reloadAll();
  }
```

Then replace the `_loadAccounts` method (lines 196-199) with two methods:

```dart
  Future<List<AccountModel>> _loadAccounts() async {
    return (await _repository.getAccounts())
        .where((a) => a.type != 'contact')
        .toList();
  }

  Future<List<AccountModel>> _loadArchivedAccounts() async {
    return (await _repository.getArchivedAccounts())
        .where((a) => a.type != 'contact')
        .toList();
  }

  Future<void> _reloadAll() async {
    accounts = await _loadAccounts();
    archivedAccounts = await _loadArchivedAccounts();
    _safeNotify();
  }
```

Then update all places that reload accounts to use `_reloadAll()`:

In `createAccount` (line 99-100), replace:
```dart
    accounts = await _loadAccounts();
    _safeNotify();
```
with:
```dart
    await _reloadAll();
```

In `updateAccount` (line 163-164), replace:
```dart
    accounts = await _loadAccounts();
    _safeNotify();
```
with:
```dart
    await _reloadAll();
```

In `_loadLocalThenMaybeSync` (lines 203-204), replace:
```dart
    accounts = await _loadAccounts();
    _safeNotify();
```
with:
```dart
    await _reloadAll();
```

In `_runSync` (lines 224-225), replace:
```dart
      accounts = await _loadAccounts();
```
with:
```dart
      accounts = await _loadAccounts();
      archivedAccounts = await _loadArchivedAccounts();
```

- [ ] **Step 2: Update debt repository — rename deleteAccount call**

In `frontend/lib/src/features/debts/data/debt_repository.dart`, line 279, replace:

```dart
  Future<void> forgiveDebt(String accountId) =>
      _accountRepo.deleteAccount(accountId);
```

with:

```dart
  Future<void> forgiveDebt(String accountId) =>
      _accountRepo.archiveAccount(accountId);
```

- [ ] **Step 3: Update account form screen — rename delete to archive**

In `frontend/lib/src/features/accounts/ui/account_form_screen.dart`, update the `_onDelete` method (around lines 292-333).

Change the dialog text and button labels:
- `'Eliminar cuenta'` → `'Archivar cuenta'`
- `'Se eliminará la cuenta "${account.name}".'` → `'Se archivará la cuenta "${account.name}".'`
- `'Eliminar'` (button) → `'Archivar'`

Change the view model call on line 320:
```dart
      await context.read<AccountsViewModel>().archiveAccount(account.id);
```

Change the error message:
```dart
      SnackBar(content: Text('No se pudo archivar la cuenta: $e')),
```

- [ ] **Step 4: Verify flutter project compiles**

Run:
```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze
```

Expected: No analysis errors related to account deletion (there may be pre-existing warnings).

- [ ] **Step 5: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/accounts/ui/accounts_view_model.dart \
        frontend/lib/src/features/debts/data/debt_repository.dart \
        frontend/lib/src/features/accounts/ui/account_form_screen.dart
git commit -m "feat(frontend): update callers to use archiveAccount, add restoreAccount + grouping"
```

---

### Task 6: Frontend — rebuild accounts screen with type sections + archived section

**Files:**
- Modify: `frontend/lib/src/features/accounts/ui/accounts_screen.dart:169-423`

- [ ] **Step 1: Add type order constant and label/icon helpers as top-level**

At the top of the file (after imports, before `AccountsScreen` class), add:

```dart
const _typeOrder = [
  'bank',
  'cash',
  'credit_card',
  'loan',
  'investment',
  'crypto',
  'other',
];

const _typeLabels = {
  'bank': 'Banco',
  'cash': 'Efectivo',
  'credit_card': 'Tarjeta de credito',
  'loan': 'Prestamo',
  'investment': 'Inversion',
  'crypto': 'Criptomonedas',
  'other': 'Otra cuenta',
};

const _typeIcons = {
  'bank': Icons.account_balance_outlined,
  'cash': Icons.payments_outlined,
  'credit_card': Icons.credit_card_outlined,
  'loan': Icons.request_quote_outlined,
  'investment': Icons.trending_up_rounded,
  'crypto': Icons.currency_bitcoin,
  'other': Icons.account_balance_wallet_outlined,
};
```

- [ ] **Step 2: Replace _AccountsListTab with CustomScrollView + type sections**

Replace the entire `_AccountsListTab` class (lines 169-271) with:

```dart
class _AccountsListTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AccountsViewModel>(
      builder: (context, vm, _) {
        final byType = vm.accountsByType;
        final archivedByType = vm.archivedAccountsByType;
        final hasArchived = archivedByType.isNotEmpty;

        return Column(
          children: [
            if (vm.isSyncing && !vm.isLoading)
              LinearProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh,
                minHeight: 2,
              ),
            Expanded(
              child: PpScreenState(
                isLoading: vm.isLoading,
                errorMessage:
                    vm.accounts.isEmpty && !hasArchived
                        ? vm.errorMessage
                        : null,
                isEmpty: vm.accounts.isEmpty && !hasArchived,
                emptyIcon: Icons.account_balance_wallet_outlined,
                emptyLabel: 'No tienes cuentas aun',
                emptySubLabel: 'Presiona + para agregar una',
                onRefresh: vm.refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ── Active accounts grouped by type ──
                    for (final type in _typeOrder)
                      if (byType.containsKey(type)) ...[
                        _SectionHeader(
                          title: _typeLabels[type] ?? type,
                          color: Theme.of(context).colorScheme.onSurface,
                          icon: _typeIcons[type] ??
                              Icons.account_balance_wallet_outlined,
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final account = byType[type]![index];
                                return Dismissible(
                                  key: ValueKey(account.id),
                                  direction: DismissDirection.endToStart,
                                  background: _ArchiveBackground(),
                                  confirmDismiss: (_) =>
                                      _confirmArchive(context, account.name),
                                  onDismissed: (_) async {
                                    try {
                                      await vm.archiveAccount(account.id);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Cuenta "${account.name}" archivada',
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'No se pudo archivar la cuenta: $e',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: _AccountCard(
                                    account: account,
                                    onTap: () =>
                                        _onAccountTap(context, account),
                                  ),
                                );
                              },
                              childCount: byType[type]!.length,
                            ),
                          ),
                        ),
                      ],

                    // ── Archived accounts section ──
                    if (hasArchived) ...[
                      _SectionHeader(
                        title: 'Archivadas',
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                        icon: Icons.visibility_off_outlined,
                      ),
                      for (final type in _typeOrder)
                        if (archivedByType.containsKey(type)) ...[
                          _SectionHeader(
                            title: _typeLabels[type] ?? type,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            icon: _typeIcons[type] ??
                                Icons.account_balance_wallet_outlined,
                          ),
                          SliverPadding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final account =
                                      archivedByType[type]![index];
                                  return _ArchivedAccountCard(
                                    account: account,
                                    onRestore: () =>
                                        vm.restoreAccount(account.id),
                                  );
                                },
                                childCount: archivedByType[type]!.length,
                              ),
                            ),
                          ),
                        ],
                    ],

                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onAccountTap(BuildContext context, AccountModel account) {
    context
        .push('/accounts/${account.id}/edit', extra: account)
        .then((result) {
      if (result == true && context.mounted) {
        context.read<AccountsViewModel>().loadOnAppear();
      }
    });
  }

  Future<bool?> _confirmArchive(BuildContext context, String accountName) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archivar cuenta'),
        content: Text('Se archivara la cuenta "$accountName".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Add _SectionHeader widget**

Add after the `_AccountsListTab` class (replacing `_DeleteBackground`):

```dart
class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Replace _DeleteBackground with _ArchiveBackground**

Remove the `_DeleteBackground` class and replace it with:

```dart
class _ArchiveBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.18),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.5),
        ),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Archivar',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.archive_outlined,
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ],
      ),
    );
  }
}
```

Uses `tertiary` color instead of `error` to differentiate archive (non-destructive) from delete (destructive).

- [ ] **Step 5: Add _ArchivedAccountCard widget**

Add after `_ArchiveBackground`:

```dart
class _ArchivedAccountCard extends StatelessWidget {
  final AccountModel account;
  final VoidCallback onRestore;

  const _ArchivedAccountCard({
    required this.account,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final icon = _typeIcons[account.type] ??
        Icons.account_balance_wallet_outlined;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: AppTheme.radiusFull,
          border: Border.all(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: AppTheme.radiusFull,
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18,
            ),
          ),
          title: Text(
            account.name,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: TextButton(
            onPressed: onRestore,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'RESTAURAR',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Verify flutter project compiles**

Run:
```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter analyze
```

Expected: No analysis errors related to accounts.

- [ ] **Step 7: Commit**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot
git add frontend/lib/src/features/accounts/ui/accounts_screen.dart
git commit -m "feat(frontend-ui): rebuild accounts screen with type sections + archived section"
```

---

### Task 7: Manual smoke test

- [ ] **Step 1: Start the backend**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot && make run
```

- [ ] **Step 2: Run the Flutter app**

```bash
cd /Volumes/rusty-drive/projects/pocket-pilot/frontend && flutter run
```

- [ ] **Step 3: Test the archive flow**

1. Navigate to `/accounts` tab
2. Verify accounts are grouped by type with section headers
3. Swipe left on an account → confirm "Archivar cuenta" dialog appears
4. Confirm archive → account moves to "ARCHIVADAS" section at bottom with dimmed styling
5. Verify the archived account shows "RESTAURAR" button
6. Tap "RESTAURAR" → account moves back to its type section
7. Navigate to Dashboard → verify archived account balance does not affect metrics

- [ ] **Step 4: Test from account form**

1. Tap an account to open the edit form
2. Tap the delete/archive button → confirm "Archivar cuenta" dialog
3. Confirm → should navigate back, account should be in archived section

- [ ] **Step 5: Log decision in journal**

Add entry to `docs/context/.journal.md`:

```markdown
## 2026-04-11 — Archive Accounts

- Reinterpreted `deleted_at` as "archived_at"; removed permanent deletion concept
- Restore uses existing `UpsertAccount` RPC (same pattern as category restore)
- Fixed backend `Upsert` SQL to include `deleted_at` in ON CONFLICT clause
- Full sync now returns archived accounts (removed `deleted_at IS NULL` filter)
- Accounts screen restructured: grouped by type + archived section at bottom
```
