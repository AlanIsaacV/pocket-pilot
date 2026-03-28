import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_amount_calculator.dart';

void main() {
  group('TransactionAmountCalculator', () {
    test('evaluates left-to-right without precedence', () {
      final calc = TransactionAmountCalculator();

      calc.onDigit('2');
      calc.onOperator(CalcOperator.add);
      calc.onDigit('3');
      calc.onOperator(CalcOperator.multiply);
      calc.onDigit('4');
      calc.onEquals();

      expect(calc.displayAmount, '20');
      expect(calc.expressionDisplay, '2 + 3 * 4 = 20');
    });

    test('multiple operators replace trailing operator', () {
      final calc = TransactionAmountCalculator();

      calc.onDigit('1');
      calc.onDigit('2');
      calc.onOperator(CalcOperator.add);
      calc.onOperator(CalcOperator.multiply);
      calc.onDigit('3');
      calc.onEquals();

      expect(calc.displayAmount, '36');
      expect(calc.expressionDisplay, '12 * 3 = 36');
    });

    test('continue with operator or reset with digit after equals', () {
      final calc = TransactionAmountCalculator();

      calc.onDigit('1');
      calc.onOperator(CalcOperator.add);
      calc.onDigit('2');
      calc.onEquals();
      calc.onOperator(CalcOperator.multiply);
      calc.onDigit('5');
      calc.onEquals();

      expect(calc.displayAmount, '15');

      calc.onDigit('8');
      expect(calc.displayAmount, '8');
      expect(calc.expressionDisplay, '');
    });

    test('auto-commit finalizes pending expression', () {
      final calc = TransactionAmountCalculator();

      calc.onDigit('1');
      calc.onDigit('2');
      calc.onOperator(CalcOperator.add);
      calc.onDigit('3');

      final ok = calc.commitPendingIfAny();

      expect(ok, isTrue);
      expect(calc.displayAmount, '15');
      expect(calc.expressionDisplay, '12 + 3 = 15');
    });

    test('division by zero keeps last valid amount and emits error', () {
      final calc = TransactionAmountCalculator(initialAmount: '7');

      calc.onOperator(CalcOperator.divide);
      calc.onDigit('0');
      final ok = calc.commitPendingIfAny();

      expect(ok, isFalse);
      expect(calc.displayAmount, '7');
      expect(calc.consumeLastError(), isNotNull);
    });

    test('incomplete expression keeps last valid amount and emits error', () {
      final calc = TransactionAmountCalculator(initialAmount: '9');

      calc.onOperator(CalcOperator.add);
      final ok = calc.commitPendingIfAny();

      expect(ok, isFalse);
      expect(calc.displayAmount, '9');
      expect(calc.consumeLastError(), isNotNull);
    });

    test('allows negative results', () {
      final calc = TransactionAmountCalculator();

      calc.onDigit('5');
      calc.onOperator(CalcOperator.subtract);
      calc.onDigit('8');
      calc.onEquals();

      expect(calc.displayAmount, '-3');
      expect(calc.getAmountMinorForSaveRounded2(), -300);
    });

    test('rounds half away from zero for save minor units', () {
      final positive = TransactionAmountCalculator(initialAmount: '1.005');
      final negative = TransactionAmountCalculator(initialAmount: '-1.005');

      expect(positive.getAmountMinorForSaveRounded2(), 101);
      expect(negative.getAmountMinorForSaveRounded2(), -101);
    });
  });
}
