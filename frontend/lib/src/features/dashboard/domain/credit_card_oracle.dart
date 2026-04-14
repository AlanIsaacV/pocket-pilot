import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_account_cycle_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_movement_dto.dart';

class CreditCardOracleResult {
  final Map<String, int> netByCurrency;
  final Map<String, int> netByAccountId;

  const CreditCardOracleResult({
    required this.netByCurrency,
    required this.netByAccountId,
  });
}

class CreditCardOracle {
  CreditCardOracleResult estimateNetMonthlyObligation({
    required DateTime targetMonth,
    required List<CreditCardAccountCycleDTO> accounts,
    required List<CreditCardMovementDTO> movements,
    DateTime? now,
  }) {
    final month = DateTime.utc(targetMonth.year, targetMonth.month, 1);
    final nowUtc = (now ?? DateTime.now()).toUtc();

    final byAccount = <String, List<CreditCardMovementDTO>>{};
    for (final movement in movements) {
      byAccount
          .putIfAbsent(movement.accountId, () => <CreditCardMovementDTO>[])
          .add(movement);
    }

    final netByAccountId = <String, int>{};
    final netByCurrency = <String, int>{};

    for (final account in accounts) {
      final rows =
          byAccount[account.accountId] ?? const <CreditCardMovementDTO>[];
      final net = _estimateForAccount(
        account: account,
        movements: rows,
        month: month,
        nowUtc: nowUtc,
      );
      netByAccountId[account.accountId] = net;
      netByCurrency[account.currencyCode] =
          (netByCurrency[account.currencyCode] ?? 0) + net;
    }

    return CreditCardOracleResult(
      netByCurrency: netByCurrency,
      netByAccountId: netByAccountId,
    );
  }

  int _estimateForAccount({
    required CreditCardAccountCycleDTO account,
    required List<CreditCardMovementDTO> movements,
    required DateTime month,
    required DateTime nowUtc,
  }) {
    if ((account.statementDay ?? 0) < 1 || (account.paymentDueDay ?? 0) < 1) {
      return _estimateFallbackCalendar(
        movements: movements,
        month: month,
        nowUtc: nowUtc,
      );
    }

    return _estimateWithCycle(
      movements: movements,
      month: month,
      nowUtc: nowUtc,
      statementDay: account.statementDay!,
      paymentDueDay: account.paymentDueDay!,
    );
  }

  int _estimateWithCycle({
    required List<CreditCardMovementDTO> movements,
    required DateTime month,
    required DateTime nowUtc,
    required int statementDay,
    required int paymentDueDay,
  }) {
    // The billing cycle closing in the target month.
    final closeCurr = _clampedDate(month.year, month.month, statementDay);
    final closePrevMonth = _addMonths(closeCurr, -1);
    final closePrev = _clampedDate(
      closePrevMonth.year,
      closePrevMonth.month,
      statementDay,
    );

    // Can only count charges that have already happened.
    final chargeCutoff = nowUtc.isBefore(closeCurr) ? nowUtc : closeCurr;

    var gross = 0;
    for (final movement in movements) {
      if (!_isCharge(movement)) continue;
      final txDate = DateTime.parse(movement.date).toUtc();

      if (movement.installmentsCount == 1) {
        if (txDate.isAfter(closePrev) && !txDate.isAfter(chargeCutoff)) {
          gross += movement.amountCents;
        }
        continue;
      }

      final purchaseClose = _firstCloseOnOrAfter(txDate, statementDay);
      final k = _monthIndex(closeCurr) - _monthIndex(purchaseClose);
      if (k >= 0 && k < movement.installmentsCount) {
        gross += _installmentAmount(
          amountCents: movement.amountCents,
          installmentsCount: movement.installmentsCount,
          installmentIndex: k,
        );
      }
    }

    // Payments made after the previous cycle's due date reduce the upcoming
    // obligation.  Anything before that date is assumed to cover a prior bill.
    final prevDueDate = _clampedDate(month.year, month.month, paymentDueDay);
    final paymentWindowEnd = nowUtc.isBefore(closeCurr) ? nowUtc : closeCurr;

    var payments = 0;
    if (!paymentWindowEnd.isBefore(prevDueDate)) {
      for (final movement in movements) {
        if (!_isPayment(movement)) continue;
        final txDate = DateTime.parse(movement.date).toUtc();
        final inWindow =
            !txDate.isBefore(prevDueDate) && !txDate.isAfter(paymentWindowEnd);
        if (inWindow) {
          payments += movement.amountCents;
        }
      }
    }

    final net = gross - payments;
    return net > 0 ? net : 0;
  }

  int _estimateFallbackCalendar({
    required List<CreditCardMovementDTO> movements,
    required DateTime month,
    required DateTime nowUtc,
  }) {
    final prev = _addMonths(month, -1);
    final prevStart = DateTime.utc(prev.year, prev.month, 1);
    final prevEnd = DateTime.utc(
      prev.year,
      prev.month,
      _lastDayOfMonth(prev.year, prev.month),
    );

    var gross = 0;
    for (final movement in movements) {
      if (!_isCharge(movement)) continue;
      final txDate = DateTime.parse(movement.date).toUtc();

      if (movement.installmentsCount == 1) {
        final inPrevMonth =
            !txDate.isBefore(prevStart) && !txDate.isAfter(prevEnd);
        if (inPrevMonth) {
          gross += movement.amountCents;
        }
        continue;
      }

      final purchaseMonth = DateTime.utc(txDate.year, txDate.month, 1);
      final firstDueMonth = _addMonths(purchaseMonth, 1);
      final k = _monthIndex(month) - _monthIndex(firstDueMonth);
      if (k >= 0 && k < movement.installmentsCount) {
        gross += _installmentAmount(
          amountCents: movement.amountCents,
          installmentsCount: movement.installmentsCount,
          installmentIndex: k,
        );
      }
    }

    final monthStart = DateTime.utc(month.year, month.month, 1);
    final monthEnd = DateTime.utc(
      month.year,
      month.month,
      _lastDayOfMonth(month.year, month.month),
    );
    final paymentWindowEnd = nowUtc.isBefore(monthEnd) ? nowUtc : monthEnd;

    var payments = 0;
    if (!paymentWindowEnd.isBefore(monthStart)) {
      for (final movement in movements) {
        if (!_isPayment(movement)) continue;
        final txDate = DateTime.parse(movement.date).toUtc();
        final inWindow =
            !txDate.isBefore(monthStart) && !txDate.isAfter(paymentWindowEnd);
        if (inWindow) {
          payments += movement.amountCents;
        }
      }
    }

    final net = gross - payments;
    return net > 0 ? net : 0;
  }

  DateTime _firstCloseOnOrAfter(DateTime txDate, int statementDay) {
    final closeThisMonth = _clampedDate(
      txDate.year,
      txDate.month,
      statementDay,
    );
    if (!txDate.isAfter(closeThisMonth)) return closeThisMonth;
    final next = _addMonths(txDate, 1);
    return _clampedDate(next.year, next.month, statementDay);
  }

  static bool _isCharge(CreditCardMovementDTO m) =>
      m.type == 'expense' || m.type == 'transfer_out';

  /// Income adjustments represent prior-period balance corrections, not
  /// actual payments for the current cycle.
  static bool _isPayment(CreditCardMovementDTO m) {
    if (m.type != 'income' && m.type != 'transfer_in') return false;
    if (m.nature == 'adjustment') return false;
    return true;
  }

  static int _installmentAmount({
    required int amountCents,
    required int installmentsCount,
    required int installmentIndex,
  }) {
    final base = amountCents ~/ installmentsCount;
    final residual = amountCents % installmentsCount;
    return installmentIndex == 0 ? base + residual : base;
  }

  static DateTime _clampedDate(int year, int month, int requestedDay) {
    final lastDay = _lastDayOfMonth(year, month);
    final day = requestedDay > lastDay ? lastDay : requestedDay;
    return DateTime.utc(year, month, day);
  }

  static DateTime _addMonths(DateTime date, int delta) {
    final monthBase = date.month + delta;
    final year = date.year + ((monthBase - 1) ~/ 12);
    final month = ((monthBase - 1) % 12) + 1;
    final lastDay = _lastDayOfMonth(year, month);
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime.utc(year, month, day);
  }

  static int _lastDayOfMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  static int _monthIndex(DateTime date) => date.year * 12 + (date.month - 1);
}
