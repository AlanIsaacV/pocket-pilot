import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_interest_math.dart';

void main() {
  test('simple interest rounds to nearest cent', () {
    expect(
      computeInterestCents(amountCents: 100000, apyRate: 14.5, daysElapsed: 30),
      1192,
    );
  });

  test('tiny values can round to zero', () {
    expect(
      computeInterestCents(amountCents: 1, apyRate: 1.0, daysElapsed: 1),
      0,
    );
  });
}
