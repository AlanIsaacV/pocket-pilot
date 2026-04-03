import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/debts/data/debt_local_store.dart';

void main() {
  test('findDebtOriginDateFromDeltas reinicia origen tras saldo 0', () {
    final entries = <DebtDeltaEntry>[
      (date: '2026-04-02', deltaCents: 10000),
      (date: '2026-04-03', deltaCents: -10000),
      (date: '2026-04-04', deltaCents: -3000),
    ];

    final origin = DebtLocalStore.findDebtOriginDateFromDeltas(entries);
    expect(origin, '2026-04-04');
  });

  test('findDebtOriginDateFromDeltas retorna null cuando termina en 0', () {
    final entries = <DebtDeltaEntry>[
      (date: '2026-04-02', deltaCents: 10000),
      (date: '2026-04-03', deltaCents: -10000),
    ];

    final origin = DebtLocalStore.findDebtOriginDateFromDeltas(entries);
    expect(origin, isNull);
  });

  test('findDebtOriginDateFromDeltas resetea origen en cruce de signo', () {
    final entries = <DebtDeltaEntry>[
      (date: '2026-04-02', deltaCents: 10000),
      (date: '2026-04-05', deltaCents: -15000),
    ];

    final origin = DebtLocalStore.findDebtOriginDateFromDeltas(entries);
    expect(origin, '2026-04-05');
  });
}
