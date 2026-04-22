import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';

/// Read-through cache of server market prices. Populated only by
/// MarketPriceSyncHandler.saveLocally; no upstream write path.
class MarketPriceLocalStore {
  final DatabaseHelper _db;

  MarketPriceLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<Map<String, dynamic>>> queryAll() async {
    final db = await _db.database;
    return db.query('market_prices', orderBy: 'symbol ASC');
  }

  Future<Map<String, dynamic>?> getBySymbolExchange(
    String symbol,
    String exchange,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      'market_prices',
      where: 'symbol = ? AND exchange = ?',
      whereArgs: [symbol.toUpperCase(), exchange.toUpperCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> upsertRow(Map<String, dynamic> row) async {
    final db = await _db.database;
    await db.insert(
      'market_prices',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns the most recent `fetched_at` stored locally, or `null` if
  /// no market prices have been synced yet. Used by the freshness banner
  /// in `HoldingsListTab`.
  Future<DateTime?> getMaxFetchedAt() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT MAX(fetched_at) AS max_fetched_at FROM market_prices',
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['max_fetched_at'];
    if (raw == null) return null;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }
}
