import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/category_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_account_cycle_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/nature_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/tag_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_movement_dto.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';

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
    final where = StringBuffer("a.deleted_at IS NULL AND a.type != 'contact'");
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
      " AND t.lot_id IS NULL"
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

  /// Returns the net spend per nature for the given date range.
  ///
  /// Same accounting rules as [getMonthlySpendByCategory] but grouped
  /// by `t.nature` instead of category.
  Future<List<NatureSpendDTO>> getMonthlySpendByNature(
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
      " AND t.lot_id IS NULL"
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
        t.nature,
        t.currency_code,
        COALESCE(SUM(
          CASE
            WHEN t.type = 'expense' THEN t.amount_cents
            WHEN t.type = 'income' THEN -t.amount_cents
            ELSE 0
          END
        ), 0) AS spent_cents
      FROM transactions t
      WHERE ${where.toString()}
      GROUP BY t.nature, t.currency_code
    ''', args);
    return rows.map(NatureSpendDTO.fromMap).toList();
  }

  /// Returns the net spend per tag for the given date range.
  ///
  /// Uses `json_each` to flatten the JSON tags array so each tag
  /// produces its own row. Same accounting rules as the category
  /// and nature variants.
  Future<List<TagSpendDTO>> getMonthlySpendByTag(
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
      " AND t.lot_id IS NULL"
      ' AND t.date >= ?'
      ' AND t.date <= ?'
      " AND t.tags IS NOT NULL"
      " AND t.tags != '[]'"
      " AND t.tags != ''",
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
        j.value AS tag_name,
        t.currency_code,
        COALESCE(SUM(
          CASE
            WHEN t.type = 'expense' THEN t.amount_cents
            WHEN t.type = 'income' THEN -t.amount_cents
            ELSE 0
          END
        ), 0) AS spent_cents
      FROM transactions t, json_each(t.tags) j
      WHERE ${where.toString()}
      GROUP BY j.value, t.currency_code
    ''', args);
    return rows.map(TagSpendDTO.fromMap).toList();
  }

  /// Returns all active (non-deleted) goals with the fields required to
  /// compute the monthly required contribution per goal.
  Future<List<GoalModel>> getActiveGoals() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT
        id,
        name,
        target_amount_cents,
        currency_code,
        target_date,
        created_at,
        updated_at,
        deleted_at
      FROM goals
      WHERE deleted_at IS NULL
    ''');
    return rows.map(GoalModel.fromMap).toList();
  }

  Future<List<CreditCardAccountCycleDTO>> getCreditCardAccounts({
    Set<String>? accountIds,
  }) async {
    final db = await _db.database;
    final where = StringBuffer("deleted_at IS NULL AND type = 'credit_card'");
    final args = <dynamic>[];

    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      where.write(' AND id IN ($placeholders)');
      args.addAll(accountIds);
    }

    final rows = await db.rawQuery('''
      SELECT
        id AS account_id,
        currency_code,
        statement_day,
        payment_due_day
      FROM accounts
      WHERE ${where.toString()}
    ''', args);

    return rows.map(CreditCardAccountCycleDTO.fromMap).toList();
  }

  Future<List<CreditCardMovementDTO>> getCreditCardMovementsForProjection(
    String maxDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) async {
    final db = await _db.database;
    final where = StringBuffer(
      "t.deleted_at IS NULL"
      " AND t.status = 'cleared'"
      " AND a.deleted_at IS NULL"
      " AND a.type = 'credit_card'"
      " AND t.type IN ('expense', 'transfer_out', 'income', 'transfer_in')"
      ' AND t.date <= ?',
    );
    final args = <dynamic>[maxDate];

    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      where.write(' AND t.account_id IN ($placeholders)');
      args.addAll(accountIds);
    }

    if (currencyCode != null) {
      where.write(' AND a.currency_code = ?');
      args.add(currencyCode);
    }

    final rows = await db.rawQuery('''
      SELECT
        t.account_id,
        t.type,
        t.amount_cents,
        t.installments_count,
        t.date,
        t.nature
      FROM transactions t
      INNER JOIN accounts a ON a.id = t.account_id
      WHERE ${where.toString()}
      ORDER BY t.date ASC
    ''', args);

    return rows.map(CreditCardMovementDTO.fromMap).toList();
  }

  /// Sum of `amount_cents` over active, non-deleted yield_configs grouped by
  /// the currency of their settlement account. Used by the dashboard to size
  /// the `investment_passive` segment of the allocation bar.
  ///
  /// Note on accounting model: yield principals are assumed to already be
  /// included in their account's bank/cash balance (Mexican digital-account
  /// pattern, e.g. BBVA Libretón pagaré). The allocation bar subtracts this
  /// value from `liquidAssetsCents` to avoid double-counting.
  Future<Map<String, int>> getYieldsValueByCurrency({
    Set<String>? accountIds,
  }) async {
    final db = await _db.database;
    final where = StringBuffer(
      "y.deleted_at IS NULL"
      " AND y.status = 'active'"
      " AND a.deleted_at IS NULL",
    );
    final args = <dynamic>[];

    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = List.filled(accountIds.length, '?').join(',');
      where.write(' AND a.id IN ($placeholders)');
      args.addAll(accountIds);
    }

    final rows = await db.rawQuery('''
      SELECT
        a.currency_code AS currency_code,
        COALESCE(SUM(y.amount_cents), 0) AS total_cents
      FROM yield_configs y
      INNER JOIN accounts a ON a.id = y.account_id
      WHERE ${where.toString()}
      GROUP BY a.currency_code
    ''', args);

    final result = <String, int>{};
    for (final row in rows) {
      final ccy = (row['currency_code'] as String).toUpperCase();
      final total = (row['total_cents'] as num?)?.toInt() ?? 0;
      if (total > 0) result[ccy] = total;
    }
    return result;
  }
}
