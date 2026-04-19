// features/cashflow/ui/cashflow_view_model.dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/features/cashflow/data/cashflow_repository.dart';
import 'package:pocket_pilot/src/features/cashflow/domain/cashflow_snapshot.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_filter_view_model.dart';

class CashflowViewModel extends ChangeNotifier {
  final CashflowRepository _repository;
  final DashboardFilterViewModel _filterVM;
  final StatisticsFilterViewModel _statsFilterVM;
  final DateTime Function() _now;

  BreakdownMode _mode = BreakdownMode.category;
  CashflowSnapshot? snapshot;
  bool isLoading = false;
  String? errorMessage;

  bool _disposed = false;

  CashflowViewModel({
    required CashflowRepository repository,
    required DashboardFilterViewModel filterViewModel,
    required StatisticsFilterViewModel statsFilterViewModel,
    DateTime Function()? now,
  })  : _repository = repository,
        _filterVM = filterViewModel,
        _statsFilterVM = statsFilterViewModel,
        _now = now ?? DateTime.now {
    _filterVM.addListener(_onFilterChanged);
    _statsFilterVM.addListener(_onFilterChanged);
  }

  BreakdownMode get mode => _mode;

  void setMode(BreakdownMode next) {
    if (_mode == next) return;
    _mode = next;
    _safeNotify();
  }

  void loadOnAppear() {
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final currency = _filterVM.currencyCode;
    if (currency == null) {
      snapshot = null;
      errorMessage = null;
      isLoading = false;
      _safeNotify();
      return;
    }

    isLoading = snapshot == null;
    _safeNotify();

    try {
      final next = await _repository.getSnapshot(
        currencyCode: currency,
        months: _statsFilterVM.window,
        now: _now(),
      );
      snapshot = next;
      errorMessage = null;
    } catch (e) {
      snapshot = null;
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _filterVM.removeListener(_onFilterChanged);
    _statsFilterVM.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onFilterChanged() {
    unawaited(refresh());
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
