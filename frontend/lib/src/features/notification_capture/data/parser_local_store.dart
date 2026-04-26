// ============================================================
// ParserLocalStore — cache SQLite de notification_parsers
// ============================================================

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/notification_parser.dart';

class ParserLocalStore {
  final DatabaseHelper _db;

  ParserLocalStore({required DatabaseHelper db}) : _db = db;

  Future<List<NotificationParserDefinition>> listActive() async {
    final db = await _db.database;
    final rows = await db.query(
      'notification_parsers',
      where: 'deleted_at IS NULL',
    );
    return rows
        .map((r) => NotificationParserDefinition.fromJson(
              jsonDecode(r['definition'] as String) as Map<String, dynamic>,
            ))
        .toList(growable: false);
  }

  Future<NotificationParserDefinition?> getByBankId(String bankId) async {
    final db = await _db.database;
    final rows = await db.query(
      'notification_parsers',
      where: 'bank_id = ? AND deleted_at IS NULL',
      whereArgs: [bankId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NotificationParserDefinition.fromJson(
      jsonDecode(rows.first['definition'] as String) as Map<String, dynamic>,
    );
  }

  /// Asegura que el parser de `bankId` existe localmente, sembrando desde
  /// un asset embebido si no se ha sincronizado aún del backend.
  /// Idempotente: si ya hay una versión >= a la del asset, no hace nada.
  Future<void> seedFromAssetIfMissing({
    required String bankId,
    required String assetPath,
  }) async {
    final existing = await getByBankId(bankId);
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final assetVersion = json['version'] as int? ?? 1;
    if (existing != null && existing.version >= assetVersion) return;

    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'notification_parsers',
      {
        'bank_id': bankId,
        'version': assetVersion,
        'definition': raw,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Upsert desde sync delta-pull. La fila remota gana si su versión es mayor
  /// (o igual con updatedAt más reciente). Si llega `deletedAt` no nulo, se
  /// retira la fila local — el ParserEngine.listActive ya filtra deleted_at.
  Future<void> upsertFromSync({
    required String bankId,
    required int version,
    required String definitionJson,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    final db = await _db.database;
    await db.insert(
      'notification_parsers',
      {
        'bank_id': bankId,
        'version': version,
        'definition': definitionJson,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
