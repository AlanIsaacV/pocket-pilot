import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';

void main() {
  group('ScheduledGenerationOrchestrator', () {
    test('runs sync, generator, sync in order', () async {
      final log = <String>[];
      final sync = _FakeSync(log);
      final generator = _FakeGenerator(log);
      final orchestrator = ScheduledGenerationOrchestrator(
        sync: sync,
        generator: generator,
      );

      await orchestrator.runCycle();

      expect(log, ['sync', 'generate', 'sync']);
    });

    test('overlapping calls are coalesced to one extra cycle', () async {
      final log = <String>[];
      final firstSyncGate = Completer<void>();
      final sync = _GatedSync(log, firstSyncGate);
      final generator = _FakeGenerator(log);
      final orchestrator = ScheduledGenerationOrchestrator(
        sync: sync,
        generator: generator,
      );

      final firstRun = orchestrator.runCycle();
      await sync.firstCallStarted.future;
      final secondRun = orchestrator.runCycle();

      firstSyncGate.complete();
      await Future.wait([firstRun, secondRun]);

      expect(log, ['sync', 'generate', 'sync', 'sync', 'generate', 'sync']);
    });
  });
}

class _FakeSync implements SyncRunner {
  final List<String> log;

  _FakeSync(this.log);

  @override
  Future<void> sync() async {
    log.add('sync');
  }
}

class _FakeGenerator implements ScheduledGeneratorRunner {
  final List<String> log;

  _FakeGenerator(this.log);

  @override
  Future<Object?> run({required DateTime nowUtc}) async {
    log.add('generate');
    return null;
  }
}

class _GatedSync implements SyncRunner {
  final List<String> log;
  final Completer<void> _firstSyncGate;

  var _calls = 0;
  final firstCallStarted = Completer<void>();

  _GatedSync(this.log, this._firstSyncGate);

  @override
  Future<void> sync() async {
    log.add('sync');
    _calls += 1;
    if (_calls == 1) {
      if (!firstCallStarted.isCompleted) firstCallStarted.complete();
      await _firstSyncGate.future;
    }
  }
}
