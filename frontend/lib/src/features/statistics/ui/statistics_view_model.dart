// features/statistics/ui/statistics_view_model.dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/window_math.dart';

class StatisticsViewModel extends ChangeNotifier {
  final StatisticsRepository _repository;
  final DashboardFilterViewModel _filterVM;
  final DateTime Function() _now;

  int months = 6; // default window
  List<CategorySeriesDTO> series = const [];
  bool isLoading = false;
  String? errorMessage;

  bool _disposed = false;

  StatisticsViewModel({
    required StatisticsRepository repository,
    required DashboardFilterViewModel filterViewModel,
    DateTime Function()? now,
  })  : _repository = repository,
        _filterVM = filterViewModel,
        _now = now ?? DateTime.now {
    _filterVM.addListener(_onFilterChanged);
  }

  void setWindow(int nextMonths) {
    if (nextMonths == months) return;
    assert(nextMonths == 3 || nextMonths == 6 || nextMonths == 12);
    months = nextMonths;
    unawaited(refresh());
  }

  void loadOnAppear() {
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final currency = _filterVM.currencyCode;
    if (currency == null) {
      series = const [];
      errorMessage = null;
      isLoading = false;
      _safeNotify();
      return;
    }

    isLoading = series.isEmpty;
    _safeNotify();

    try {
      final window = StatisticsWindow.fromNow(months: months, now: _now());
      series = await _repository.getSeriesList(
        currencyCode: currency,
        windowStart: window.windowStart,
        windowEnd: window.windowEnd,
        windowMid: window.windowMid,
        currentYm: window.currentYm,
        months: months,
      );
      errorMessage = null;
    } catch (e) {
      series = const [];
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
    super.dispose();
  }

  void _onFilterChanged() {
    unawaited(refresh());
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
