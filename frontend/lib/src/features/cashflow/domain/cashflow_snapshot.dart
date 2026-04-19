// features/cashflow/domain/cashflow_snapshot.dart
//
// Snapshot of inflows / outflows / net for the Cashflow view. Values are
// already sign-stable: `totalInCents` is positive, `totalOutCents` is
// positive (the outflow magnitude), `netCents` is `in - out` and can be
// negative. Grand totals include transfers (transfer_in as inflow,
// transfer_out as outflow, each in its own currency). Breakdown entries
// are ordered descending by absolute amount and top-N capped for the
// category breakdown ("Otros" fold). Transfers show up as a synthetic
// entry flagged with `isTransfer: true`. Nature breakdown returns all
// active natures without fold.

import 'package:flutter/widgets.dart';

enum BreakdownMode { category, nature }

class CashflowBreakdownEntry {
  final String id;
  final String label;
  final String kind; // 'income' | 'expense'
  final int amountCents; // positive magnitude
  final Color? color; // optional tint (categories only)
  final bool isTransfer;

  const CashflowBreakdownEntry({
    required this.id,
    required this.label,
    required this.kind,
    required this.amountCents,
    this.color,
    this.isTransfer = false,
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
