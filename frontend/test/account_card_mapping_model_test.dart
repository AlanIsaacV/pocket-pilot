import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/notification_capture/domain/account_card_mapping.dart';

void main() {
  test('preserves optional pattern_id through map and proto conversions', () {
    final now = DateTime.utc(2026, 7, 18, 12);
    final model = AccountCardMappingModel(
      id: 'mapping-1',
      bankId: 'bbva_mx',
      lastDigits: '1234',
      patternId: 'purchase_tdc',
      accountId: 'account-1',
      createdAt: now,
      updatedAt: now,
    );

    expect(
      AccountCardMappingModel.fromMap(model.toMap()).patternId,
      'purchase_tdc',
    );
    expect(
      AccountCardMappingModel.fromProto(model.toProto()).patternId,
      'purchase_tdc',
    );
  });

  test(
    'pattern-only mapping (no card digits) round-trips with lastDigits null',
    () {
      final now = DateTime.utc(2026, 7, 18, 12);
      final model = AccountCardMappingModel(
        id: 'mapping-2',
        bankId: 'bbva_mx',
        patternId: 'purchase_tdc',
        accountId: 'account-1',
        createdAt: now,
        updatedAt: now,
      );

      expect(model.lastDigits, isNull);

      final fromMap = AccountCardMappingModel.fromMap(model.toMap());
      expect(fromMap.lastDigits, isNull);
      expect(fromMap.patternId, 'purchase_tdc');

      // El wire proto3 usa "" (no optional) para representar ausencia de
      // last_digits; fromProto debe normalizarlo de vuelta a null.
      final proto = model.toProto();
      expect(proto.lastDigits, '');
      final fromProto = AccountCardMappingModel.fromProto(proto);
      expect(fromProto.lastDigits, isNull);
      expect(fromProto.patternId, 'purchase_tdc');
    },
  );
}
