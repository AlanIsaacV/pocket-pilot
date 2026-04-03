import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/debts/domain/contact_balance.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:sqflite/sqflite.dart';

typedef DebtDeltaEntry = ({String date, int deltaCents});

class DebtLocalStore {
  final DatabaseHelper _db;

  DebtLocalStore({required DatabaseHelper db}) : _db = db;

  static const _includedTxnTypes =
      "'income', 'expense', 'transfer_in', 'transfer_out'";

  /// Retorna el saldo por contacto agrupado por moneda de transaccion.
  /// Incluye cuentas activas y eliminadas.
  Future<List<ContactBalance>> getContactsBalances() async {
    final db = await _db.database;

    final accountRows = await db.query(
      'accounts',
      columns: ['id', 'name', 'currency_code', 'deleted_at'],
      where: "type = 'contact'",
      orderBy: 'name COLLATE NOCASE ASC',
    );

    final contacts = <ContactBalance>[];

    for (final account in accountRows) {
      final accountId = account['id'] as String;
      final accountCurrency = account['currency_code'] as String;

      final balanceRows = await db.rawQuery(
        '''
        SELECT
          currency_code,
          COALESCE(SUM(
            CASE
              WHEN type IN ('income', 'transfer_in') THEN amount_cents
              WHEN type IN ('expense', 'transfer_out') THEN -amount_cents
              ELSE 0
            END
          ), 0) AS balance_cents
        FROM transactions
        WHERE account_id = ?
          AND deleted_at IS NULL
          AND type IN ($_includedTxnTypes)
        GROUP BY currency_code
        ORDER BY currency_code ASC
      ''',
        [accountId],
      );

      final balances = <ContactCurrencyBalance>[];
      for (final row in balanceRows) {
        final currency = row['currency_code'] as String;
        final rawBalance = row['balance_cents'];
        final balanceCents = switch (rawBalance) {
          int v => v,
          num v => v.toInt(),
          _ => 0,
        };

        final originDate = balanceCents == 0
            ? null
            : await _findDebtOriginDateByCurrency(db, accountId, currency);

        balances.add(
          ContactCurrencyBalance(
            currencyCode: currency,
            balanceCents: balanceCents,
            debtOriginDate: originDate,
          ),
        );
      }

      if (balances.isEmpty) {
        balances.add(
          ContactCurrencyBalance(
            currencyCode: accountCurrency,
            balanceCents: 0,
          ),
        );
      }

      balances.sort((a, b) {
        final aZero = a.balanceCents == 0;
        final bZero = b.balanceCents == 0;
        if (aZero != bZero) {
          return aZero ? 1 : -1;
        }
        return a.currencyCode.compareTo(b.currencyCode);
      });

      contacts.add(
        ContactBalance(
          accountId: accountId,
          contactName: account['name'] as String,
          balances: balances,
          isDeleted: account['deleted_at'] != null,
        ),
      );
    }

    return contacts;
  }

  Future<ContactBalance?> getContactBalanceByAccountId(String accountId) async {
    final contacts = await getContactsBalances();
    for (final contact in contacts) {
      if (contact.accountId == accountId) {
        return contact;
      }
    }
    return null;
  }

  /// Busca la fecha de inicio del saldo activo para una moneda de un contacto.
  /// Recorre transacciones cronológicamente y resetea inicio cuando:
  /// - el saldo vuelve a 0
  /// - el saldo cruza de signo (p.ej. de positivo a negativo)
  Future<String?> _findDebtOriginDateByCurrency(
    Database db,
    String accountId,
    String currencyCode,
  ) async {
    final txnRows = await db.rawQuery(
      'SELECT type, amount_cents, date FROM transactions '
      'WHERE account_id = ? AND currency_code = ? '
      'AND deleted_at IS NULL AND type IN ($_includedTxnTypes) '
      'ORDER BY date ASC, created_at ASC',
      [accountId, currencyCode],
    );

    final entries = <DebtDeltaEntry>[];

    for (final txn in txnRows) {
      final type = txn['type'] as String;
      final amount = (txn['amount_cents'] as int?) ?? 0;

      final delta = switch (type) {
        'income' || 'transfer_in' => amount,
        'expense' || 'transfer_out' => -amount,
        _ => 0,
      };

      if (delta == 0) {
        continue;
      }

      entries.add((date: txn['date'] as String, deltaCents: delta));
    }

    return findDebtOriginDateFromDeltas(entries);
  }

  static String? findDebtOriginDateFromDeltas(List<DebtDeltaEntry> entries) {
    int runningBalance = 0;
    String? originDate;

    for (final entry in entries) {
      if (runningBalance == 0) {
        originDate = entry.date;
      }

      final nextBalance = runningBalance + entry.deltaCents;

      if ((runningBalance > 0 && nextBalance < 0) ||
          (runningBalance < 0 && nextBalance > 0)) {
        originDate = entry.date;
      }

      runningBalance = nextBalance;

      if (runningBalance == 0) {
        originDate = null;
      }
    }

    if (runningBalance == 0) {
      return null;
    }

    return originDate;
  }

  /// Retorna las transacciones de una cuenta de contacto.
  Future<List<TransactionModel>> getContactTransactions(
    String accountId,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      'transactions',
      where: 'account_id = ? AND deleted_at IS NULL',
      whereArgs: [accountId],
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map((r) => TransactionModel.fromMap(r)).toList();
  }

  /// Busca cuentas de contacto activas cuyos nombres coincidan con [query].
  Future<List<Map<String, dynamic>>> searchContacts(String query) async {
    final db = await _db.database;
    return db.query(
      'accounts',
      where: "type = 'contact' AND deleted_at IS NULL AND name LIKE ?",
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
    );
  }
}
