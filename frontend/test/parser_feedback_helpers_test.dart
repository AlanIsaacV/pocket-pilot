// Tests puros (sin Flutter bindings) para los helpers usados al persistir
// ParserFeedback: descomposición de parserId y normalización de description.
//
// La normalización es CONSERVADORA: trim + lowercase + colapso de
// whitespace. La intención es que un usuario que solo limpie trailing spaces
// o ajuste casing NO dispare description_changed=true.

import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';

// _descriptionChanged vive como método privado en notification_capture_repository.
// Replicamos la lógica acá para testearla aislada — si la regla cambia en el
// repository hay que actualizar este helper también.
String _norm(String? s) =>
    (s ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
bool _descriptionChanged(String? sug, String? fin) => _norm(sug) != _norm(fin);

void main() {
  group('PendingTransactionModel.splitParserId', () {
    test('extrae bank y pattern de un parserId bien formado', () {
      final (bank, pattern) =
          PendingTransactionModel.splitParserId('bbva_mx/purchase_tdc');
      expect(bank, 'bbva_mx');
      expect(pattern, 'purchase_tdc');
    });

    test('null → (null, null)', () {
      final (bank, pattern) = PendingTransactionModel.splitParserId(null);
      expect(bank, isNull);
      expect(pattern, isNull);
    });

    test('sin / → (null, null)', () {
      final (bank, pattern) =
          PendingTransactionModel.splitParserId('bbva_mx_only');
      expect(bank, isNull);
      expect(pattern, isNull);
    });

    test('con / al inicio → (null, null)', () {
      final (bank, pattern) =
          PendingTransactionModel.splitParserId('/purchase_tdc');
      expect(bank, isNull);
      expect(pattern, isNull);
    });

    test('con / al final → (null, null) (pattern vacío no es válido)', () {
      final (bank, pattern) = PendingTransactionModel.splitParserId('bbva_mx/');
      expect(bank, isNull);
      expect(pattern, isNull);
    });

    test('formato LLM con dos slashes → toma el primero', () {
      final (bank, pattern) =
          PendingTransactionModel.splitParserId('llm/llm_purchase_v1');
      expect(bank, 'llm');
      expect(pattern, 'llm_purchase_v1');
    });
  });

  group('_descriptionChanged (normalización)', () {
    test('strings idénticos → false', () {
      expect(_descriptionChanged('STARBUCKS', 'STARBUCKS'), isFalse);
    });

    test('solo trailing spaces removidos → false', () {
      expect(_descriptionChanged('STARBUCKS REFORMA   ', 'STARBUCKS REFORMA'),
          isFalse);
    });

    test('cambio de casing → false (lowercase normaliza)', () {
      expect(_descriptionChanged('STARBUCKS', 'starbucks'), isFalse);
    });

    test('whitespace múltiple colapsado → false', () {
      expect(_descriptionChanged('STARBUCKS    REFORMA', 'STARBUCKS REFORMA'),
          isFalse);
    });

    test('cambio real de palabras → true', () {
      expect(
          _descriptionChanged('STARBUCKS REFORMA', 'STARBUCKS POLANCO'),
          isTrue);
    });

    test('null vs vacío → false (ambos normalizan a "")', () {
      expect(_descriptionChanged(null, ''), isFalse);
      expect(_descriptionChanged('', null), isFalse);
    });

    test('null vs string no vacío → true', () {
      expect(_descriptionChanged(null, 'STARBUCKS'), isTrue);
    });
  });
}
