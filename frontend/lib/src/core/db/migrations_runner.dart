// ============================================================
// MigrationsRunner — ejecuta scripts .sql sobre la base de datos
// ============================================================
//
// Responsabilidad única: leer archivos assets/migrations/NNN.sql
// y ejecutarlos en orden sobre la instancia de Database recibida.
//
// DatabaseHelper delega aquí para mantenerse limpio de lógica de I/O.

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

class MigrationsRunner {
  MigrationsRunner._();

  /// Ejecuta los archivos .sql desde [from]+1 hasta [to] (inclusive).
  ///
  /// Ejemplo: dispositivo con v1 que actualiza a v3 ejecuta 002.sql y 003.sql.
  /// Dispositivo nuevo (from=0) ejecuta 001.sql, 002.sql, 003.sql.
  static Future<void> run(
    Database db, {
    required int from,
    required int to,
  }) async {
    for (int v = from + 1; v <= to; v++) {
      final filename = v.toString().padLeft(3, '0');
      final sql =
          await rootBundle.loadString('assets/migrations/$filename.sql');
      await _executeScript(db, sql);
    }
  }

  /// Divide el script SQL en sentencias individuales y las ejecuta.
  ///
  /// Separa por ';', descarta líneas de comentarios (--) y sentencias vacías.
  static Future<void> _executeScript(Database db, String sql) async {
    final statements = sql
        .split(';')
        .map((s) =>
            s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    for (final statement in statements) {
      await db.execute(statement);
    }
  }
}
