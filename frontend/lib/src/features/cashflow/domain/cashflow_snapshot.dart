// features/cashflow/domain/cashflow_snapshot.dart
//
// Snapshot of inflows / outflows / net for the Cashflow view. Values are
// already sign-stable: `totalInCents` is positive, `totalOutCents` is
// positive (the outflow magnitude), `netCents` is `in - out` and can be
// negative. Transfers are excluded upstream (SQL layer). Breakdown entries
// are ordered descending by absolute amount and top-N capped for the
// category breakdown ("Otros" fold). Nature breakdown returns all active
// categories without fold.

import 'package:flutter/widgets.dart';

enum BreakdownMode { category, nature }

class CashflowBreakdownEntry {
  final String id;
  final String label;
  final String kind; // 'income' | 'expense'
  final int amountCents; // positive magnitude
  final Color? color; // optional tint (categories only)

  const CashflowBreakdownEntry({
    required this.id,
    required this.label,
    required this.kind,
    required this.amountCents,
    this.color,
  });
}

class CashflowSnapshot {
  final String currencyCode;
  final int windowMonths;
  final int totalInCents;
  final int totalOutCents;
  final int netCents;
  final List<CashflowBreakdownEntry> byCategory;
  final List<CashflowBreakdownEntry> byNature;

  const CashflowSnapshot({
    required this.currencyCode,
    required this.windowMonths,
    required this.totalInCents,
    required this.totalOutCents,
    required this.netCents,
    required this.byCategory,
    required this.byNature,
  });

  bool get isEmpty => totalInCents == 0 && totalOutCents == 0;

  List<CashflowBreakdownEntry> entriesFor(BreakdownMode mode) =>
      mode == BreakdownMode.category ? byCategory : byNature;
}
