// ============================================================
// DatabaseHelper — singleton que abre y gestiona la base SQLite
// ============================================================
//
// Las migraciones viven en assets/migrations/:
//   001.sql → esquema inicial (siempre se ejecuta en instalaciones nuevas)
//   002.sql → próxima migración (ALTER TABLE, CREATE INDEX, etc.)
//   ...
//
// Regla: el número de la última migración debe coincidir con `_version`.
// Para agregar un cambio de esquema:
//   1. Crea assets/migrations/002.sql con el SQL del cambio.
//   2. Incrementa `_version` a 2.
//   ¡Nunca modifiques un archivo .sql ya publicado!

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/migrations_runner.dart';

class DatabaseHelper {
  // Incrementa este número cada vez que agregues un nuevo archivo .sql.
  static const int _version = 1;

  // Singleton: una sola instancia en toda la app.
  static final DatabaseHelper _instance = DatabaseHelper._();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._();

  Database? _db;

  /// Devuelve la instancia de la BD, abriéndola la primera vez que se llama.
  Future<Database> get database async => _db ??= await _init();

  Future<Database> _init() async {
    final dbPath = join(await getDatabasesPath(), 'pocket_pilot.db');
    return openDatabase(
      dbPath,
      version: _version,
      onCreate: (db, version) =>
          MigrationsRunner.run(db, from: 0, to: version),
      onUpgrade: (db, oldVersion, newVersion) =>
          MigrationsRunner.run(db, from: oldVersion, to: newVersion),
    );
  }
}
