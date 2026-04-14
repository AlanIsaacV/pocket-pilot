import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/category_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_payment_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/dashboard_metrics.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/nature_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/tag_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';

class DashboardViewModel extends ChangeNotifier {
  final DashboardRepository _repository;
  final DashboardFilterViewModel _filterVM;

  Map<String, DashboardMetrics> metricsByCurrency = {};
  List<AccountBalanceDTO> accountBalances = [];
  List<CreditCardPaymentDTO> creditCardPayments = [];
  List<CategorySpendDTO> monthlySpend = [];
  List<NatureSpendDTO> monthlySpendByNature = [];
  List<TagSpendDTO> monthlySpendByTag = [];
  bool isLoading = false;
  String? errorMessage;

  bool _disposed = false;

  DashboardViewModel({
    required DashboardRepository repository,
    required DashboardFilterViewModel filterViewModel,
  })  : _repository = repository,
        _filterVM = filterViewModel {
    _filterVM.addListener(_onFilterChanged);
  }

  // --- Computed getters ---

  String? get selectedCurrency => _filterVM.currencyCode ?? _firstCurrency;

  String? get _firstCurrency {
    if (metricsByCurrency.isEmpty) return null;
    final sorted = metricsByCurrency.keys.toList()..sort();
    return sorted.first;
  }

  DashboardMetrics? get activeMetrics {
    final cc = selectedCurrency;
    if (cc == null) return null;
    return metricsByCurrency[cc];
  }

  List<String> get availableCurrencies {
    return metricsByCurrency.keys.toList()..sort();
  }

  List<CreditCardPaymentDTO> get filteredCreditCardPayments {
    final cc = selectedCurrency;
    if (cc == null) return creditCardPayments;
    return creditCardPayments
        .where((p) => p.currencyCode == cc)
        .toList();
  }

  List<AccountBalanceDTO> get filteredAccountBalances {
    final cc = selectedCurrency;
    if (cc == null) return accountBalances;
    return accountBalances.where((b) => b.currencyCode == cc).toList();
  }

  List<CategorySpendDTO> get filteredMonthlySpend {
    final cc = selectedCurrency;
    return monthlySpend
        .where(
          (s) => s.categoryId != null && (cc == null || s.currencyCode == cc),
        )
        .toList();
  }

  List<NatureSpendDTO> get filteredMonthlySpendByNature {
    final cc = selectedCurrency;
    if (cc == null) return monthlySpendByNature;
    return monthlySpendByNature
        .where((s) => s.currencyCode == cc)
        .toList();
  }

  List<TagSpendDTO> get filteredMonthlySpendByTag {
    final cc = selectedCurrency;
    if (cc == null) return monthlySpendByTag;
    return monthlySpendByTag
        .where((s) => s.currencyCode == cc)
        .toList();
  }

  // --- Public API ---

  void loadOnAppear() {
    unawaited(_loadData());
  }

  Future<void> refresh() => _loadData();

  @override
  void dispose() {
    _disposed = true;
    _filterVM.removeListener(_onFilterChanged);
    super.dispose();
  }

  // --- Internal ---

  void _onFilterChanged() {
    unawaited(_loadData());
  }

  Future<void> _loadData() async {
    final hadData = accountBalances.isNotEmpty;
    if (!hadData) {
      isLoading = true;
      _safeNotify();
    }

    try {
      final filterAccountIds = _filterVM.accountIds.isNotEmpty
          ? _filterVM.accountIds
          : null;

      final results = await Future.wait([
        _repository.calculateAllMetrics(accountIds: filterAccountIds),
        _repository.getBalancesPerAccount(accountIds: filterAccountIds),
        _repository.getCreditCardPayments(accountIds: filterAccountIds),
        _repository.getMonthlySpendByCategory(
          _filterVM.dateFrom,
          _filterVM.dateTo,
          accountIds: filterAccountIds,
          currencyCode: _filterVM.currencyCode,
        ),
        _repository.getMonthlySpendByNature(
          _filterVM.dateFrom,
          _filterVM.dateTo,
          accountIds: filterAccountIds,
          currencyCode: _filterVM.currencyCode,
        ),
        _repository.getMonthlySpendByTag(
          _filterVM.dateFrom,
          _filterVM.dateTo,
          accountIds: filterAccountIds,
          currencyCode: _filterVM.currencyCode,
        ),
      ]);

      metricsByCurrency = results[0] as Map<String, DashboardMetrics>;
      accountBalances = results[1] as List<AccountBalanceDTO>;
      creditCardPayments = results[2] as List<CreditCardPaymentDTO>;
      monthlySpend = results[3] as List<CategorySpendDTO>;
      monthlySpendByNature = results[4] as List<NatureSpendDTO>;
      monthlySpendByTag = results[5] as List<TagSpendDTO>;
      errorMessage = null;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
