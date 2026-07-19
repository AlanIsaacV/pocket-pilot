import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/ui/widgets/temporal_page_view.dart';

// ----------------------------------------------------------
// ViewModel
// ----------------------------------------------------------

class DashboardFilterViewModel extends ChangeNotifier
    implements TemporalFilterState {
  // Temporal state
  int _activePageIndex = 0;
  QuickRange _quickSelection = QuickRange.m6;
  PeriodGranularity _periodGranularity = PeriodGranularity.month;
  int _periodOffset = 0;
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _customTo = DateTime.now();

  // Scope filters
  String? _currencyCode;
  Set<String> _accountIds = {};

  // --- Temporal getters ---
  @override
  int get activePageIndex => _activePageIndex;
  @override
  QuickRange get quickSelection => _quickSelection;
  @override
  PeriodGranularity get periodGranularity => _periodGranularity;
  int get periodOffset => _periodOffset;
  @override
  DateTime get customFrom => _customFrom;
  @override
  DateTime get customTo => _customTo;

  // --- Scope getters ---
  String? get currencyCode => _currencyCode;
  Set<String> get accountIds => _accountIds;

  // --- Derived date range ---
  (String, String) get resolvedDateRange => _resolveDateRange();
  String get dateFrom => resolvedDateRange.$1;
  String get dateTo => resolvedDateRange.$2;

  bool get hasFilters =>
      _currencyCode != null ||
      _accountIds.isNotEmpty ||
      _activePageIndex != 0 ||
      _quickSelection != QuickRange.m6;

  // --- Temporal setters ---

  @override
  void setActivePageIndex(int index) {
    _activePageIndex = index;
    notifyListeners();
  }

  @override
  void setQuickSelection(QuickRange range) {
    _quickSelection = range;
    _activePageIndex = 0;
    notifyListeners();
  }

  @override
  void setPeriodGranularity(PeriodGranularity g) {
    _periodGranularity = g;
    _periodOffset = 0;
    _activePageIndex = 1;
    notifyListeners();
  }

  @override
  void navigatePeriod(int delta) {
    _periodOffset += delta;
    notifyListeners();
  }

  @override
  void setCustomRange(DateTime from, DateTime to) {
    _customFrom = from;
    _customTo = to;
    _activePageIndex = 2;
    notifyListeners();
  }

  // --- Scope setters ---

  void setCurrencyCode(String? code) {
    _currencyCode = code;
    notifyListeners();
  }

  void toggleAccountId(String id) {
    if (_accountIds.contains(id)) {
      _accountIds = Set.of(_accountIds)..remove(id);
    } else {
      _accountIds = {..._accountIds, id};
    }
    notifyListeners();
  }

  void clearAll() {
    _activePageIndex = 0;
    _quickSelection = QuickRange.m6;
    _periodGranularity = PeriodGranularity.month;
    _periodOffset = 0;
    _customFrom = DateTime.now().subtract(const Duration(days: 30));
    _customTo = DateTime.now();
    _currencyCode = null;
    _accountIds = {};
    notifyListeners();
  }

  // --- Date resolution ---

  (String, String) _resolveDateRange() {
    switch (_activePageIndex) {
      case 0:
        return _resolveQuick();
      case 1:
        return _resolvePeriod();
      case 2:
        return (fmt(_customFrom), fmt(_customTo));
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
    return (fmt(from), fmt(now));
  }

  (String, String) _resolvePeriod() {
    final now = DateTime.now();
    switch (_periodGranularity) {
      case PeriodGranularity.week:
        final currentMonday = now.subtract(Duration(days: now.weekday - 1));
        final targetMonday =
            currentMonday.add(Duration(days: 7 * _periodOffset));
        final targetSunday = targetMonday.add(const Duration(days: 6));
        return (fmt(targetMonday), fmt(targetSunday));
      case PeriodGranularity.month:
        final targetMonth = DateTime(now.year, now.month + _periodOffset, 1);
        final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0);
        return (fmt(targetMonth), fmt(lastDay));
      case PeriodGranularity.year:
        final targetYear = DateTime(now.year + _periodOffset, 1, 1);
        final lastDay = DateTime(targetYear.year, 12, 31);
        return (fmt(targetYear), fmt(lastDay));
    }
  }

  // --- Period label for display ---

  @override
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
        return 'Semana';
      case PeriodGranularity.month:
        return 'Mes';
      case PeriodGranularity.year:
        return 'Año';
    }
  }

  bool get isAtCurrentPeriod => _periodOffset == 0;

  // --- Static helpers ---

  static String fmt(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _monthName(int month) {
    const names = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    return names[month - 1];
  }
}
