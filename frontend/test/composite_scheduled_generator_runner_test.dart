import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/sync/composite_scheduled_generator_runner.dart';
import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';

void main() {
  test('composite runner executes child generators in order', () async {
    final order = <String>[];
    final runner = CompositeScheduledGeneratorRunner(
      runners: [_FakeRunner('templates', order), _FakeRunner('yields', order)],
    );

    await runner.run(nowUtc: DateTime.utc(2026, 4, 1));

    expect(order, ['templates', 'yields']);
  });
}

class _FakeRunner implements ScheduledGeneratorRunner {
  final String name;
  final List<String> order;

  _FakeRunner(this.name, this.order);

  @override
  Future<Object?> run({required DateTime nowUtc}) async {
    order.add(name);
    return null;
  }
}
