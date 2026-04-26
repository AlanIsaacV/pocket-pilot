// Tests del sweeper de retención. Verifican el gating por `lastPurgeAt`,
// el cómputo de cutoff (now-90d en ISO UTC), y la persistencia de
// `lastPurgeAt` tras cada corrida. La query SQL real se valida vía smoke
// manual (ver plan); aquí solo nos importa la orquestación.

import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/notification_capture/data/captured_notifications_retention_sweeper.dart';

class _RecordingPurge {
  final List<({String cutoffIso, String purgedAtIso})> calls = [];
  int returnValue = 0;

  Future<int> call({
    required String cutoffIso,
    required String purgedAtIso,
  }) async {
    calls.add((cutoffIso: cutoffIso, purgedAtIso: purgedAtIso));
    return returnValue;
  }
}

class _InMemoryLastPurgeAt implements LastPurgeAtStore {
  DateTime? value;

  @override
  Future<DateTime?> read() async => value;

  @override
  Future<void> write(DateTime v) async {
    value = v;
  }
}

void main() {
  group('CapturedNotificationsRetentionSweeper', () {
    test('primera corrida (lastPurgeAt null) ejecuta la purga', () async {
      final purge = _RecordingPurge()..returnValue = 7;
      final last = _InMemoryLastPurgeAt();
      final now = DateTime.utc(2026, 4, 26, 12, 0, 0);
      final sweeper = CapturedNotificationsRetentionSweeper.forTesting(
        purge: purge.call,
        lastPurgeAt: last,
        now: () => now,
      );

      final affected = await sweeper.sweepIfDue();

      expect(affected, 7);
      expect(purge.calls, hasLength(1));
      // cutoff = now - 90d = 2026-01-26 12:00:00Z
      expect(purge.calls.single.cutoffIso, '2026-01-26T12:00:00.000Z');
      expect(purge.calls.single.purgedAtIso, '2026-04-26T12:00:00.000Z');
      // lastPurgeAt persistido para el próximo gate.
      expect(last.value, now);
    });

    test('skip si pasaron <24h desde la última corrida', () async {
      final purge = _RecordingPurge();
      final last = _InMemoryLastPurgeAt()
        ..value = DateTime.utc(2026, 4, 26, 8, 0, 0);
      final now = DateTime.utc(2026, 4, 26, 20, 0, 0); // +12h
      final sweeper = CapturedNotificationsRetentionSweeper.forTesting(
        purge: purge.call,
        lastPurgeAt: last,
        now: () => now,
      );

      final affected = await sweeper.sweepIfDue();

      expect(affected, 0);
      expect(purge.calls, isEmpty);
      // lastPurgeAt no se mueve para preservar el gate real.
      expect(last.value, DateTime.utc(2026, 4, 26, 8, 0, 0));
    });

    test('vuelve a correr después de 24h exactas', () async {
      final purge = _RecordingPurge()..returnValue = 3;
      final last = _InMemoryLastPurgeAt()
        ..value = DateTime.utc(2026, 4, 25, 12, 0, 0);
      final now = DateTime.utc(2026, 4, 26, 12, 0, 0); // +24h exactas
      final sweeper = CapturedNotificationsRetentionSweeper.forTesting(
        purge: purge.call,
        lastPurgeAt: last,
        now: () => now,
      );

      final affected = await sweeper.sweepIfDue();

      expect(affected, 3);
      expect(purge.calls, hasLength(1));
      expect(last.value, now);
    });

    test('sweepNow ignora el gate', () async {
      final purge = _RecordingPurge()..returnValue = 1;
      final last = _InMemoryLastPurgeAt()
        ..value = DateTime.utc(2026, 4, 26, 11, 59, 0);
      final now = DateTime.utc(2026, 4, 26, 12, 0, 0); // +1min — gate activo
      final sweeper = CapturedNotificationsRetentionSweeper.forTesting(
        purge: purge.call,
        lastPurgeAt: last,
        now: () => now,
      );

      final affected = await sweeper.sweepNow();

      expect(affected, 1);
      expect(purge.calls, hasLength(1));
      expect(last.value, now);
    });

    test('cutoff usa exactamente 90 días', () async {
      final purge = _RecordingPurge();
      final last = _InMemoryLastPurgeAt();
      final now = DateTime.utc(2026, 6, 1, 0, 0, 0);
      final sweeper = CapturedNotificationsRetentionSweeper.forTesting(
        purge: purge.call,
        lastPurgeAt: last,
        now: () => now,
      );

      await sweeper.sweepIfDue();

      // 90 días antes de 2026-06-01 → 2026-03-03 (Mar tiene 31 días, Feb 28).
      expect(purge.calls.single.cutoffIso, '2026-03-03T00:00:00.000Z');
    });
  });
}
