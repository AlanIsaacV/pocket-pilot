import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';

class CompositeScheduledGeneratorRunner implements ScheduledGeneratorRunner {
  final List<ScheduledGeneratorRunner> _runners;

  CompositeScheduledGeneratorRunner({
    required List<ScheduledGeneratorRunner> runners,
  }) : _runners = List<ScheduledGeneratorRunner>.unmodifiable(runners);

  @override
  Future<Object?> run({required DateTime nowUtc}) async {
    for (final runner in _runners) {
      await runner.run(nowUtc: nowUtc);
    }
    return null;
  }
}
