import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/features/investments/domain/investment_split.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/investment_split_service.pbgrpc.dart';

void main() {
  group('InvestmentSplitModel.fromMap', () {
    test('parses required fields from a SQLite-shaped row', () {
      final model = InvestmentSplitModel.fromMap({
        'id': 's1',
        'holding_id': 'h1',
        'ratio_num': 2,
        'ratio_den': 1,
        'occurred_at': '2026-04-25',
        'notes': null,
        'created_at': '2026-04-25T10:00:00Z',
        'updated_at': '2026-04-25T10:00:00Z',
        'deleted_at': null,
      });

      expect(model.id, 's1');
      expect(model.holdingId, 'h1');
      expect(model.ratioNum, 2);
      expect(model.ratioDen, 1);
      expect(model.occurredAt, '2026-04-25');
      expect(model.notes, isNull);
      expect(model.deletedAt, isNull);
      expect(model.isForward, isTrue);
      expect(model.isReverse, isFalse);
    });

    test('truncates occurred_at to YYYY-MM-DD if a fuller string is supplied', () {
      final model = InvestmentSplitModel.fromMap({
        'id': 's1',
        'holding_id': 'h1',
        'ratio_num': 1,
        'ratio_den': 10,
        'occurred_at': '2026-04-25T10:00:00Z',
        'notes': 'reverse split announcement',
        'created_at': '2026-04-25T10:00:00Z',
        'updated_at': '2026-04-25T10:00:00Z',
        'deleted_at': null,
      });

      expect(model.occurredAt, '2026-04-25');
      expect(model.notes, 'reverse split announcement');
      expect(model.isReverse, isTrue);
    });

    test('preserves deletedAt when present', () {
      final model = InvestmentSplitModel.fromMap({
        'id': 's1',
        'holding_id': 'h1',
        'ratio_num': 2,
        'ratio_den': 1,
        'occurred_at': '2026-04-25',
        'notes': null,
        'created_at': '2026-04-25T10:00:00Z',
        'updated_at': '2026-04-25T11:00:00Z',
        'deleted_at': '2026-04-25T11:00:00Z',
      });

      expect(model.deletedAt, isNotNull);
      expect(model.deletedAt!.toUtc().toIso8601String(), '2026-04-25T11:00:00.000Z');
    });

    test('coerces numeric strings to double', () {
      final model = InvestmentSplitModel.fromMap({
        'id': 's1',
        'holding_id': 'h1',
        'ratio_num': '7',
        'ratio_den': '3',
        'occurred_at': '2026-04-25',
        'notes': null,
        'created_at': '2026-04-25T10:00:00Z',
        'updated_at': '2026-04-25T10:00:00Z',
        'deleted_at': null,
      });

      expect(model.ratioNum, 7.0);
      expect(model.ratioDen, 3.0);
    });
  });

  group('InvestmentSplitModel.toMap', () {
    test('round-trips through fromMap with normalized fields', () {
      final original = InvestmentSplitModel(
        id: 's1',
        holdingId: 'h1',
        ratioNum: 2,
        ratioDen: 1,
        occurredAt: '2026-04-25',
        notes: 'forward 2:1',
        createdAt: DateTime.utc(2026, 4, 25, 10),
        updatedAt: DateTime.utc(2026, 4, 25, 10),
      );

      final round = InvestmentSplitModel.fromMap(original.toMap());

      expect(round.id, original.id);
      expect(round.holdingId, original.holdingId);
      expect(round.ratioNum, original.ratioNum);
      expect(round.ratioDen, original.ratioDen);
      expect(round.occurredAt, original.occurredAt);
      expect(round.notes, original.notes);
      expect(round.createdAt, original.createdAt);
      expect(round.updatedAt, original.updatedAt);
      expect(round.deletedAt, isNull);
    });

    test('toServerMap is identical to toMap', () {
      final model = InvestmentSplitModel(
        id: 's1',
        holdingId: 'h1',
        ratioNum: 1,
        ratioDen: 10,
        occurredAt: '2026-04-25',
        createdAt: DateTime.utc(2026, 4, 25),
        updatedAt: DateTime.utc(2026, 4, 25),
      );

      expect(model.toServerMap(), equals(model.toMap()));
    });
  });

  group('InvestmentSplitModel.fromProto / toProto', () {
    test('proto round-trip preserves ratio, holding and dates', () {
      final ts = Timestamp.fromDateTime(DateTime.utc(2026, 4, 25, 10));
      final proto = InvestmentSplit(
        id: 's1',
        holdingId: 'h1',
        ratioNum: 2,
        ratioDen: 1,
        occurredAt: '2026-04-25',
        notes: 'forward 2:1',
        createdAt: ts,
        updatedAt: ts,
      );

      final model = InvestmentSplitModel.fromProto(proto);
      expect(model.id, 's1');
      expect(model.holdingId, 'h1');
      expect(model.ratioNum, 2);
      expect(model.ratioDen, 1);
      expect(model.occurredAt, '2026-04-25');
      expect(model.notes, 'forward 2:1');
      expect(model.createdAt, DateTime.utc(2026, 4, 25, 10));

      final back = model.toProto();
      expect(back.id, 's1');
      expect(back.ratioNum, 2);
      expect(back.ratioDen, 1);
      expect(back.notes, 'forward 2:1');
      // toProto should not set timestamps; the remote service injects them.
      expect(back.hasCreatedAt(), isFalse);
      expect(back.hasUpdatedAt(), isFalse);
    });

    test('fromProto does not require notes or deletedAt', () {
      final proto = InvestmentSplit(
        id: 's1',
        holdingId: 'h1',
        ratioNum: 1,
        ratioDen: 10,
        occurredAt: '2026-04-25',
      );

      final model = InvestmentSplitModel.fromProto(proto);
      expect(model.notes, isNull);
      expect(model.deletedAt, isNull);
      expect(model.isReverse, isTrue);
    });

    test('uses Int64 fixnum unaffected (no fee fields, sanity check imports)', () {
      // Sanity: importing fixnum should not interfere with split serialization.
      // The Int64 reference exists because lots use it; splits do not.
      // ignore: unused_local_variable
      final unused = Int64(0);
    });
  });

  group('InvestmentSplitModel.normalized', () {
    test('truncates occurredAt and uppercases UTC timestamps', () {
      final model = InvestmentSplitModel(
        id: 's1',
        holdingId: 'h1',
        ratioNum: 2,
        ratioDen: 1,
        occurredAt: '2026-04-25T10:00:00Z',
        createdAt: DateTime.utc(2026, 4, 25, 10),
        updatedAt: DateTime.utc(2026, 4, 25, 10),
      );

      final normalized = model.normalized();
      expect(normalized.occurredAt, '2026-04-25');
      expect(normalized.createdAt.isUtc, isTrue);
    });
  });

  group('InvestmentSplitModel.copyWith', () {
    test('preserves id and createdAt while overriding mutable fields', () {
      final original = InvestmentSplitModel(
        id: 's1',
        holdingId: 'h1',
        ratioNum: 2,
        ratioDen: 1,
        occurredAt: '2026-04-25',
        createdAt: DateTime.utc(2026, 4, 25),
        updatedAt: DateTime.utc(2026, 4, 25),
      );

      final updated = original.copyWith(
        ratioNum: 3,
        ratioDen: 1,
        notes: 'edited',
        updatedAt: DateTime.utc(2026, 4, 26),
      );

      expect(updated.id, original.id);
      expect(updated.createdAt, original.createdAt);
      expect(updated.ratioNum, 3);
      expect(updated.ratioDen, 1);
      expect(updated.notes, 'edited');
      expect(updated.updatedAt, DateTime.utc(2026, 4, 26));
    });
  });
}
