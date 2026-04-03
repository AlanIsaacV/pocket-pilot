import 'package:flutter/foundation.dart';

class DashboardFilterViewModel extends ChangeNotifier {
  String _dateFrom;
  String _dateTo;
  String? _currencyCode;
  Set<String> _accountIds = {};

  DashboardFilterViewModel()
      : _dateFrom = _defaultDateFrom(),
        _dateTo = _defaultDateTo();

  // --- Getters ---

  String get dateFrom => _dateFrom;
  String get dateTo => _dateTo;
  String? get currencyCode => _currencyCode;
  Set<String> get accountIds => _accountIds;

  bool get hasFilters =>
      _currencyCode != null ||
      _accountIds.isNotEmpty ||
      _dateFrom != _defaultDateFrom() ||
      _dateTo != _defaultDateTo();

  // --- Setters ---

  void setDateRange(String from, String to) {
    _dateFrom = from;
    _dateTo = to;
    notifyListeners();
  }

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
    _dateFrom = _defaultDateFrom();
    _dateTo = _defaultDateTo();
    _currencyCode = null;
    _accountIds = {};
    notifyListeners();
  }

  // --- Defaults ---

  static String _defaultDateFrom() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
  }

  static String _defaultDateTo() {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
  }

  static String fmt(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
