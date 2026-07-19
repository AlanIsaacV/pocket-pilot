import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/ui/widgets/account_icon.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart';

/// An optional action displayed before the account and creation rows.
///
/// Tapping it dismisses the picker with `null`; callers must perform their
/// side effect in [onTap] or refresh their state after the picker returns.
class AccountPickerTopAction {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  const AccountPickerTopAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// Shows the standard account picker and returns the selected account.
///
/// The picker owns loading accounts and the create-account round trip. Callers
/// retain responsibility for all side effects after an account is selected.
Future<AccountModel?> showAccountPicker(
  BuildContext context, {
  String title = 'Seleccionar cuenta',
  bool Function(AccountModel)? filter,
  String? excludeAccountId,
  String? mustIncludeAccountId,
  String? selectedAccountId,
  bool showCurrency = false,
  bool showCreateRow = true,
  AccountPickerTopAction? topAction,
  Object? createRouteExtra,
}) async {
  // Bottom-sheet routes do not inherit providers, so capture this dependency
  // from the caller before opening the sheet.
  final accountStore = context.read<AccountLocalStore>();
  var accounts = await _loadAccounts(
    accountStore,
    filter: filter,
    excludeAccountId: excludeAccountId,
    mustIncludeAccountId: mustIncludeAccountId,
  );
  if (!context.mounted) return null;

  while (context.mounted) {
    final selection = await showFormBottomSheet<Object>(
      context: context,
      builder: (sheetContext) => ScrollableBottomSheet(
        title: title,
        children: [
          if (topAction != null)
            SheetItem(
              icon: topAction.icon,
              label: topAction.label,
              onTap: () => Navigator.pop(
                sheetContext,
                _AccountPickerSelection.topAction,
              ),
            ),
          if (showCreateRow)
            SheetItem(
              icon: Icons.add_circle_outline_rounded,
              label: 'Agregar cuenta',
              onTap: () => Navigator.pop(
                sheetContext,
                _AccountPickerSelection.createAccount,
              ),
            ),
          ...accounts.map(
            (account) => SheetItem(
              icon: accountIconForType(account.type),
              label: showCurrency
                  ? '${account.name} · ${account.currencyCode}'
                  : account.name,
              trailing: account.id == selectedAccountId
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(sheetContext, account),
            ),
          ),
        ],
      ),
    );

    if (selection is AccountModel) return selection;
    if (selection == _AccountPickerSelection.topAction) {
      await topAction?.onTap();
      return null;
    }
    if (selection != _AccountPickerSelection.createAccount) return null;

    if (!context.mounted) return null;
    final created = await context.push<bool>(
      '/accounts/new',
      extra: createRouteExtra,
    );
    if (!context.mounted) return null;
    if (created != true) return null;

    accounts = await _loadAccounts(
      accountStore,
      filter: filter,
      excludeAccountId: excludeAccountId,
      mustIncludeAccountId: mustIncludeAccountId,
    );
    if (!context.mounted) return null;
  }

  return null;
}

Future<List<AccountModel>> _loadAccounts(
  AccountLocalStore accountStore, {
  bool Function(AccountModel)? filter,
  String? excludeAccountId,
  String? mustIncludeAccountId,
}) async {
  final accountFilter = filter ?? (account) => account.type != 'contact';
  final accounts = (await accountStore.getAccounts())
      .where(accountFilter)
      .toList();

  if (mustIncludeAccountId != null &&
      !accounts.any((account) => account.id == mustIncludeAccountId)) {
    final included = await accountStore.getByIdIncludingArchived(
      mustIncludeAccountId,
    );
    if (included != null) accounts.add(included);
  }

  return accounts.where((account) => account.id != excludeAccountId).toList();
}

enum _AccountPickerSelection { createAccount, topAction }
