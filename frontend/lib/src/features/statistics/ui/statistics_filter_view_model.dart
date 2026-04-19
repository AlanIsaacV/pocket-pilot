// features/statistics/ui/statistics_filter_view_model.dart
//
// Shared filter state for the Statistics section of the dashboard.
// Lives inside DashboardRouteScope so the hub and inline sub-views
// observe the same window. Sub-screens mounted outside this scope
// (navigated via GoRouter) receive the current value as a query param
// and can seed their own local instance from it.

import 'package:flutter/foundation.dart';

class StatisticsFilterViewModel extends ChangeNotifier {
  int _window;

  StatisticsFilterViewModel({int initialWindow = 6})
      : _window = _assertWindow(initialWindow);

  int get window => _window;

  void setWindow(int next) {
    final v = _assertWindow(next);
    if (_window == v) return;
    _window = v;
    notifyListeners();
  }

  static int _assertWindow(int v) {
    assert(v == 3 || v == 6 || v == 12, 'window must be 3, 6, or 12');
    return v;
  }
}
