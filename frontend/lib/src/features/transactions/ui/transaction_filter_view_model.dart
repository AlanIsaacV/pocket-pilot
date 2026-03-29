// frontend/lib/src/features/transactions/ui/transaction_filter_view_model.dart

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/features/transactions/domain/transaction_filter.dart';

// ----------------------------------------------------------
// Enums
// ----------------------------------------------------------

enum QuickRange { d7, d30, m6, y1 }

enum PeriodGranularity { week, month, year }

// ----------------------------------------------------------
// ViewModel
// ----------------------------------------------------------

class TransactionFilterViewModel extends ChangeNotifier {
  // --- Temporal state ---
  int _activePageIndex = 0;
  QuickRange _quickSelection = QuickRange.d30;
  PeriodGranularity _periodGranularity = PeriodGranularity.month;
  int _periodOffset = 0;
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _customTo = DateTime.now();

  // --- Advanced filter state ---
  String? _accountId;
  List<String> _categoryIds = [];
  String? _type;
  String? _status;
  String? _currencyCode;

  // --- Getters ---
  int get activePageIndex => _activePageIndex;
  QuickRange get quickSelection => _quickSelection;
  PeriodGranularity get periodGranularity => _periodGranularity;
  int get periodOffset => _periodOffset;
  DateTime get customFrom => _customFrom;
  DateTime get customTo => _customTo;
  String? get accountId => _accountId;
  List<String> get categoryIds => List.unmodifiable(_categoryIds);
  String? get type => _type;
  String? get status => _status;
  String? get currencyCode => _currencyCode;

  // ----------------------------------------------------------
  // Temporal setters
  // ----------------------------------------------------------

  void setActivePageIndex(int index) {
    _activePageIndex = index;
    notifyListeners();
  }

  void setQuickSelection(QuickRange range) {
    _quickSelection = range;
    _activePageIndex = 0;
    notifyListeners();
  }

  void setPeriodGranularity(PeriodGranularity g) {
    _periodGranularity = g;
    _periodOffset = 0;
    _activePageIndex = 1;
    notifyListeners();
  }

  void navigatePeriod(int delta) {
    final next = _periodOffset + delta;
    if (next > 0) return; // cannot go past current period
    _periodOffset = next;
    notifyListeners();
  }

  void setCustomRange(DateTime from, DateTime to) {
    _customFrom = from;
    _customTo = to;
    _activePageIndex = 2;
    notifyListeners();
  }

  // ----------------------------------------------------------
  // Advanced setters
  // ----------------------------------------------------------

  void setAccountId(String? id) {
    _accountId = id;
    notifyListeners();
  }

  void toggleCategory(String id) {
    if (_categoryIds.contains(id)) {
      _categoryIds = _categoryIds.where((c) => c != id).toList();
    } else {
      _categoryIds = [..._categoryIds, id];
    }
    notifyListeners();
  }

  void setCategoryIds(List<String> ids) {
    _categoryIds = ids;
    notifyListeners();
  }

  void setType(String? t) {
    _type = t;
    notifyListeners();
  }

  void setStatus(String? s) {
    _status = s;
    notifyListeners();
  }

  void setCurrencyCode(String? c) {
    _currencyCode = c;
    notifyListeners();
  }

  void clearAll() {
    _activePageIndex = 0;
    _quickSelection = QuickRange.d30;
    _periodGranularity = PeriodGranularity.month;
    _periodOffset = 0;
    _customFrom = DateTime.now().subtract(const Duration(days: 30));
    _customTo = DateTime.now();
    _accountId = null;
    _categoryIds = [];
    _type = null;
    _status = null;
    _currencyCode = null;
    notifyListeners();
  }

  // ----------------------------------------------------------
  // Resolved filter
  // ----------------------------------------------------------

  TransactionFilter get resolvedFilter {
    final (from, to) = _resolveDateRange();
    return TransactionFilter(
      dateFrom: from,
      dateTo: to,
      accountId: _accountId,
      categoryIds: _categoryIds,
      type: _type,
      status: _status,
      currencyCode: _currencyCode,
    );
  }

  (String, String) _resolveDateRange() {
    switch (_activePageIndex) {
      case 0:
        return _resolveQuick();
      case 1:
        return _resolvePeriod();
      case 2:
        return (TransactionFilter.fmt(_customFrom),
            TransactionFilter.fmt(_customTo));
      default:
        return _resolveQuick();
    }
  }

  (String, String) _resolveQuick() {
    final now = DateTime.now();
    final Duration duration;
    switch (_quickSelection) {
      case QuickRange.d7:
        duration = const Duration(days: 7);
      case QuickRange.d30:
        duration = const Duration(days: 30);
      case QuickRange.m6:
        duration = const Duration(days: 182);
      case QuickRange.y1:
        duration = const Duration(days: 365);
    }
    final from = now.subtract(duration);
    return (TransactionFilter.fmt(from), TransactionFilter.fmt(now));
  }

  (String, String) _resolvePeriod() {
    final now = DateTime.now();
    switch (_periodGranularity) {
      case PeriodGranularity.week:
        final currentMonday = now.subtract(Duration(days: now.weekday - 1));
        final targetMonday =
            currentMonday.add(Duration(days: 7 * _periodOffset));
        final targetSunday = targetMonday.add(const Duration(days: 6));
        return (TransactionFilter.fmt(targetMonday),
            TransactionFilter.fmt(targetSunday));
      case PeriodGranularity.month:
        final targetMonth =
            DateTime(now.year, now.month + _periodOffset, 1);
        final lastDay =
            DateTime(targetMonth.year, targetMonth.month + 1, 0);
        return (TransactionFilter.fmt(targetMonth),
            TransactionFilter.fmt(lastDay));
      case PeriodGranularity.year:
        final targetYear = DateTime(now.year + _periodOffset, 1, 1);
        final lastDay = DateTime(targetYear.year, 12, 31);
        return (TransactionFilter.fmt(targetYear),
            TransactionFilter.fmt(lastDay));
    }
  }

  // ----------------------------------------------------------
  // Period label for display
  // ----------------------------------------------------------

  String get periodLabel {
    if (_periodOffset == 0) return _periodGranularityLabel;
    final now = DateTime.now();
    switch (_periodGranularity) {
      case PeriodGranularity.week:
        final currentMonday = now.subtract(Duration(days: now.weekday - 1));
        final targetMonday =
            currentMonday.add(Duration(days: 7 * _periodOffset));
        return '${targetMonday.day}/${targetMonday.month}';
      case PeriodGranularity.month:
        final target = DateTime(now.year, now.month + _periodOffset, 1);
        return _monthName(target.month);
      case PeriodGranularity.year:
        return '${now.year + _periodOffset}';
    }
  }

  String get _periodGranularityLabel {
    switch (_periodGranularity) {
      case PeriodGranularity.week:
        return 'Week';
      case PeriodGranularity.month:
        return 'Month';
      case PeriodGranularity.year:
        return 'Year';
    }
  }

  bool get isAtCurrentPeriod => _periodOffset == 0;

  static String _monthName(int month) {
    const names = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    return names[month - 1];
  }
}
