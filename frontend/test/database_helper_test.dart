import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';

void main() {
  sqfliteFfiInit();

  test(
    'concurrent-access configuration enables WAL and a busy timeout',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pocket_pilot_db_',
      );
      final dbPath = '${directory.path}/pocket_pilot.db';
      final db = await databaseFactoryFfi.openDatabase(dbPath);

      try {
        await configureDatabaseForConcurrentAccess(db);

        expect(
          (await db.rawQuery('PRAGMA journal_mode')).single['journal_mode'],
          'wal',
        );
        expect(
          (await db.rawQuery('PRAGMA busy_timeout')).single['timeout'],
          5000,
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
