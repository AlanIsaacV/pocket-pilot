import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/ui/widgets/account_picker.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart';

void main() {
  testWidgets('applies filter and exclusion when rendering account rows', (
    tester,
  ) async {
    final keep = _account(id: 'keep', name: 'Cuenta visible', type: 'bank');
    final excluded = _account(id: 'excluded', name: 'Cuenta excluida');
    final contact = _account(id: 'contact', name: 'Contacto', type: 'contact');

    await _pumpPicker(
      tester,
      store: _FakeAccountLocalStore([keep, excluded, contact]),
      onOpen: (context) => showAccountPicker(
        context,
        filter: (account) => account.type != 'contact',
        excludeAccountId: excluded.id,
        showCreateRow: false,
      ),
    );

    expect(find.text('Cuenta visible'), findsOneWidget);
    expect(find.text('Cuenta excluida'), findsNothing);
    expect(find.text('Contacto'), findsNothing);
  });

  testWidgets('exclusion wins over a must-included archived account', (
    tester,
  ) async {
    final excluded = _account(id: 'excluded', name: 'Cuenta excluida');

    await _pumpPicker(
      tester,
      store: _FakeAccountLocalStore([], includingArchived: [excluded]),
      onOpen: (context) => showAccountPicker(
        context,
        mustIncludeAccountId: excluded.id,
        excludeAccountId: excluded.id,
        showCreateRow: false,
      ),
    );

    expect(find.text('Cuenta excluida'), findsNothing);
  });

  testWidgets('shows the selected row and returns the tapped account', (
    tester,
  ) async {
    final selected = _account(id: 'selected', name: 'Cuenta seleccionada');
    final other = _account(id: 'other', name: 'Otra cuenta');
    AccountModel? result;

    await _pumpPicker(
      tester,
      store: _FakeAccountLocalStore([selected, other]),
      onOpen: (context) async {
        result = await showAccountPicker(
          context,
          selectedAccountId: selected.id,
          showCurrency: true,
          showCreateRow: false,
        );
      },
    );

    expect(find.text('Cuenta seleccionada · MXN'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('Otra cuenta · MXN'));
    await tester.pumpAndSettle();

    expect(result, same(other));
  });

  testWidgets('invokes top action and resolves with null', (tester) async {
    var topActionCalls = 0;
    AccountModel? result = _account(id: 'placeholder', name: 'Placeholder');

    await _pumpPicker(
      tester,
      store: _FakeAccountLocalStore([]),
      onOpen: (context) async {
        result = await showAccountPicker(
          context,
          showCreateRow: false,
          topAction: AccountPickerTopAction(
            icon: Icons.bolt_rounded,
            label: 'Acción rápida',
            onTap: () async {
              topActionCalls++;
            },
          ),
        );
      },
    );

    expect(
      find
          .byType(SheetItem)
          .evaluate()
          .map((element) => (element.widget as SheetItem).label),
      ['Acción rápida'],
    );

    await tester.tap(find.text('Acción rápida'));
    await tester.pumpAndSettle();

    expect(topActionCalls, 1);
    expect(result, isNull);
  });
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  required AccountLocalStore store,
  required Future<void> Function(BuildContext context) onOpen,
}) async {
  await tester.pumpWidget(
    Provider<AccountLocalStore>.value(
      value: store,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => onOpen(context),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

AccountModel _account({
  required String id,
  required String name,
  String type = 'cash',
}) {
  final now = DateTime.utc(2026);
  return AccountModel(
    id: id,
    name: name,
    type: type,
    currencyCode: 'MXN',
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeAccountLocalStore extends AccountLocalStore {
  final List<AccountModel> accounts;
  final List<AccountModel> includingArchived;

  _FakeAccountLocalStore(this.accounts, {this.includingArchived = const []})
    : super(db: DatabaseHelper());

  @override
  Future<List<AccountModel>> getAccounts() async => accounts;

  @override
  Future<AccountModel?> getByIdIncludingArchived(String id) async {
    for (final account in [...accounts, ...includingArchived]) {
      if (account.id == id) return account;
    }
    return null;
  }
}
