import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

class MigrationsRunner {
  MigrationsRunner._();

  static Future<void> run(
    Database db, {
    required int from,
    required int to,
  }) async {
    for (int v = from + 1; v <= to; v++) {
      final filename = v.toString().padLeft(3, '0');
      final path = 'assets/migrations/$filename.sql';
      final sql = await rootBundle.loadString(path);

      await db.transaction((txn) async {
        await _executeScript(txn, sql, migrationName: filename);
      });
    }
  }

  static Future<void> _executeScript(
    DatabaseExecutor db,
    String sql, {
    required String migrationName,
  }) async {
    final statements = _splitSqlStatements(sql);

    for (var i = 0; i < statements.length; i++) {
      final statement = statements[i].trim();
      if (statement.isEmpty) continue;

      try {
        await db.execute(statement);
      } catch (e) {
        rethrow;
      }
    }
  }

  static List<String> _splitSqlStatements(String sql) {
    final cleaned = sql
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');

    final statements = <String>[];
    final buffer = StringBuffer();
    var inTriggerBlock = false;

    for (final rawLine in cleaned.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.toUpperCase().startsWith('CREATE TRIGGER')) {
        inTriggerBlock = true;
      }

      buffer.writeln(rawLine);

      if (inTriggerBlock) {
        if (line.toUpperCase() == 'END;') {
          statements.add(buffer.toString().trim());
          buffer.clear();
          inTriggerBlock = false;
        }
      } else {
        if (line.endsWith(';')) {
          statements.add(buffer.toString().trim());
          buffer.clear();
        }
      }
    }

    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) {
      statements.add(tail);
    }

    return statements;
  }
}
