import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/capture_repository_factory.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_remote_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('builds capture repositories with and without an LLM parser', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pocket_pilot_capture_factory_',
    );
    databaseFactory = databaseFactoryFfi;
    await databaseFactoryFfi.setDatabasesPath(directory.path);

    try {
      final withoutRemote = await buildCaptureRepository(db: DatabaseHelper());
      final withRemote = await buildCaptureRepository(
        db: DatabaseHelper(),
        parserRemote: ParserRemoteService(),
      );

      expect(withoutRemote.parserRemote, isNull);
      expect(withRemote.parserRemote, isA<ParserRemoteService>());
    } finally {
      await DatabaseHelper.deleteAndReset();
      await directory.delete(recursive: true);
    }
  });
}
