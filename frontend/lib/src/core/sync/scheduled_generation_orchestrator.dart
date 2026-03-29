abstract class SyncRunner {
  Future<void> sync();
}

abstract class ScheduledGeneratorRunner {
  Future<Object?> run({required DateTime nowUtc});
}

class ScheduledGenerationOrchestrator {
  final SyncRunner _sync;
  final ScheduledGeneratorRunner _generator;

  bool _running = false;
  bool _queued = false;

  ScheduledGenerationOrchestrator({
    required SyncRunner sync,
    required ScheduledGeneratorRunner generator,
  }) : _sync = sync,
       _generator = generator;

  Future<void> runCycle() async {
    if (_running) {
      _queued = true;
      return;
    }

    _running = true;
    try {
      do {
        _queued = false;
        await _sync.sync();
        await _generator.run(nowUtc: DateTime.now().toUtc());
        await _sync.sync();
      } while (_queued);
    } finally {
      _running = false;
    }
  }
}
