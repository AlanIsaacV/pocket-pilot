import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/category_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/goal_target_dto.dart';

class DashboardLocalStore {
  final DatabaseHelper _db;

  DashboardLocalStore({required DatabaseHelper db}) : _db = db;

  /// Returns the current balance of each account grouped by currency.
  ///
  /// Uses a LEFT JOIN so accounts with zero transactions still appear
  /// with `balanceCents = 0`. Only cleared, non-deleted transactions
  /// are considered. Contact accounts are excluded.
  ///
  /// When [accountIds] is non-null and non-empty, only those accounts
  /// are included.
  Future<List<AccountBalanceDTO>> getBalancesPerAccount({
    Set<String>? accountIds,
  }) async {
    final db = await _db.database;
    final where = StringBuffer(
      "a.deleted_at IS NULL AND a.type != 'contact'",
    );
    final args = <dynamic>[];

    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      where.write(' AND a.id IN ($placeholders)');
      args.addAll(accountIds);
    }

    final rows = await db.rawQuery('''
      SELECT
        a.id AS account_id,
        a.name AS account_name,
        a.type AS account_type,
        a.currency_code,
        a.credit_limit_cents,
        COALESCE(SUM(
          CASE
            WHEN t.type IN ('income', 'transfer_in') THEN t.amount_cents
            WHEN t.type IN ('expense', 'transfer_out') THEN -t.amount_cents
            ELSE 0
          END
        ), 0) AS balance_cents
      FROM accounts a
      LEFT JOIN transactions t
        ON t.account_id = a.id
        AND t.deleted_at IS NULL
        AND t.status = 'cleared'
      WHERE ${where.toString()}
      GROUP BY a.id, a.currency_code
    ''', args);
    return rows.map(AccountBalanceDTO.fromMap).toList();
  }

  /// Returns the net spend per category for the given date range.
  ///
  /// Expenses add to spend, income subtracts (refunds). Transfers are
  /// excluded. Only cleared, non-deleted transactions are considered.
  ///
  /// Optional filters: [accountIds] limits to specific accounts,
  /// [currencyCode] limits to a single currency.
  Future<List<CategorySpendDTO>> getMonthlySpendByCategory(
    String startDate,
    String endDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) async {
    final db = await _db.database;
    final where = StringBuffer(
      "t.deleted_at IS NULL"
      " AND t.status = 'cleared'"
      " AND t.type IN ('expense', 'income')"
      ' AND t.date >= ?'
      ' AND t.date <= ?',
    );
    final args = <dynamic>[startDate, endDate];

    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      where.write(' AND t.account_id IN ($placeholders)');
      args.addAll(accountIds);
    }

    if (currencyCode != null) {
      where.write(' AND t.currency_code = ?');
      args.add(currencyCode);
    }

    final rows = await db.rawQuery('''
      SELECT
        t.category_id,
        c.name AS category_name,
        c.color AS category_color,
        t.currency_code,
        COALESCE(SUM(
          CASE
            WHEN t.type = 'expense' THEN t.amount_cents
            WHEN t.type = 'income' THEN -t.amount_cents
            ELSE 0
          END
        ), 0) AS spent_cents
      FROM transactions t
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE ${where.toString()}
      GROUP BY t.category_id, t.currency_code
    ''', args);
    return rows.map(CategorySpendDTO.fromMap).toList();
  }

  /// Returns the sum of `target_amount_cents` for all active goals,
  /// grouped by currency code.
  Future<List<GoalTargetDTO>> getTotalTargetInGoals() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        currency_code,
        COALESCE(SUM(target_amount_cents), 0) AS total_target_cents
      FROM goals
      WHERE deleted_at IS NULL
      GROUP BY currency_code
    ''');
    return rows.map(GoalTargetDTO.fromMap).toList();
  }
}
