// frontend/lib/src/features/transactions/domain/transaction_filter.dart

/// Immutable value object holding the resolved filter state.
///
/// Dates are YYYY-MM-DD strings matching the SQLite `date` column format.
class TransactionFilter {
  final String dateFrom;
  final String dateTo;
  final String? accountId;
  final List<String> categoryIds;
  final String? type;
  final String? status;
  final String? currencyCode;

  const TransactionFilter({
    required this.dateFrom,
    required this.dateTo,
    this.accountId,
    this.categoryIds = const [],
    this.type,
    this.status,
    this.currencyCode,
  });

  /// Default filter: last 30 days from today.
  factory TransactionFilter.defaultFilter() {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    return TransactionFilter(
      dateFrom: fmt(from),
      dateTo: fmt(now),
    );
  }

  /// SQL-ready type values.
  /// "transfer" → ['transfer_out', 'transfer_in'].
  List<String>? get typeValues {
    if (type == null) return null;
    if (type == 'transfer') return ['transfer_out', 'transfer_in'];
    return [type!];
  }

  /// True if any advanced filter (non-temporal) is active.
  bool get hasAdvancedFilters =>
      accountId != null ||
      categoryIds.isNotEmpty ||
      type != null ||
      status != null ||
      currencyCode != null;

  TransactionFilter copyWith({
    String? dateFrom,
    String? dateTo,
    String? accountId,
    List<String>? categoryIds,
    String? type,
    String? status,
    String? currencyCode,
    bool clearAccountId = false,
    bool clearType = false,
    bool clearStatus = false,
    bool clearCurrencyCode = false,
  }) {
    return TransactionFilter(
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      categoryIds: categoryIds ?? this.categoryIds,
      type: clearType ? null : (type ?? this.type),
      status: clearStatus ? null : (status ?? this.status),
      currencyCode:
          clearCurrencyCode ? null : (currencyCode ?? this.currencyCode),
    );
  }

  static String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
