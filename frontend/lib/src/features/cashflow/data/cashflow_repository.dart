// features/cashflow/data/cashflow_repository.dart
//
// Orchestrates CashflowLocalStore to produce a CashflowSnapshot. Does the
// top-N + "Otros" fold per kind in Dart (same pattern as StatisticsRepo
// keeping SQL simple and aggregation client-side).

import 'package:flutter/material.dart' show Color;

import 'package:pocket_pilot/src/features/cashflow/data/cashflow_local_store.dart';
import 'package:pocket_pilot/src/features/cashflow/domain/cashflow_snapshot.dart';
import 'package:pocket_pilot/src/features/statistics/domain/window_math.dart';

class CashflowRepository {
  static const int defaultTopN = 6;

  final CashflowLocalStore _local;

  CashflowRepository({required CashflowLocalStore local}) : _local = local;

  Future<CashflowSnapshot> getSnapshot({
    required String currencyCode,
    required String from,
    required String to,
    int topN = defaultTopN,
    Set<String>? accountIds,
  }) async {
    final window = StatisticsWindow.fromRange(from: from, to: to);

    final totals = await _local.getTotals(
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
      accountIds: accountIds,
    );
    final income = totals['income'] ?? 0;
    final expense = totals['expense'] ?? 0;
    final transferIn = totals['transfer_in'] ?? 0;
    final transferOut = totals['transfer_out'] ?? 0;

    final totalIn = income + transferIn;
    final totalOut = expense + transferOut;

    final catRows = await _local.getCategoryTotals(
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
      accountIds: accountIds,
    );
    final natRows = await _local.getNatureTotals(
      currencyCode: currencyCode,
      windowStart: window.windowStart,
      windowEnd: window.windowEnd,
      accountIds: accountIds,
    );

    return CashflowSnapshot(
      currencyCode: currencyCode,
      windowMonths: window.months,
      totalInCents: totalIn,
      totalOutCents: totalOut,
      netCents: totalIn - totalOut,
      byCategory: [
        ..._foldCategories(catRows, topN: topN),
        if (transferIn > 0) _transferEntry('income', transferIn),
        if (transferOut > 0) _transferEntry('expense', transferOut),
      ],
      byNature: [
        ..._mapNatures(natRows),
        if (transferIn > 0) _transferEntry('income', transferIn),
        if (transferOut > 0) _transferEntry('expense', transferOut),
      ],
    );
  }

  static CashflowBreakdownEntry _transferEntry(String kind, int amountCents) =>
      CashflowBreakdownEntry(
        id: 'transfers_$kind',
        label: 'Transferencias',
        kind: kind,
        amountCents: amountCents,
        isTransfer: true,
      );

  List<CashflowBreakdownEntry> _foldCategories(
    List<Map<String, dynamic>> rows, {
    required int topN,
  }) {
    final income = <CashflowBreakdownEntry>[];
    final expense = <CashflowBreakdownEntry>[];
    final incomeTail = <Map<String, dynamic>>[];
    final expenseTail = <Map<String, dynamic>>[];

    final byKind = <String, List<Map<String, dynamic>>>{
      'income': [],
      'expense': [],
    };
    for (final r in rows) {
      final kind = r['kind'] as String;
      (byKind[kind] ?? []).add(r);
    }

    void fold(
      List<Map<String, dynamic>> src,
      List<CashflowBreakdownEntry> dst,
      List<Map<String, dynamic>> tail,
      String kind,
    ) {
      for (var i = 0; i < src.length; i++) {
        if (i < topN) {
          final r = src[i];
          dst.add(
            CashflowBreakdownEntry(
              id: r['category_id'] as String,
              label: (r['name'] as String?) ?? '',
              kind: kind,
              amountCents: _asInt(r['total_cents']),
              color: _parseHex(r['color'] as String?),
            ),
          );
        } else {
          tail.add(src[i]);
        }
      }
      if (tail.isNotEmpty) {
        final sum = tail.fold<int>(
          0,
          (acc, r) => acc + _asInt(r['total_cents']),
        );
        dst.add(
          CashflowBreakdownEntry(
            id: 'otros_$kind',
            label: 'Otros',
            kind: kind,
            amountCents: sum,
          ),
        );
      }
    }

    fold(byKind['income']!, income, incomeTail, 'income');
    fold(byKind['expense']!, expense, expenseTail, 'expense');

    return [...income, ...expense];
  }

  List<CashflowBreakdownEntry> _mapNatures(List<Map<String, dynamic>> rows) {
    return rows
        .map(
          (r) => CashflowBreakdownEntry(
            id: '${r['nature']}_${r['kind']}',
            label: r['nature'] as String,
            kind: r['kind'] as String,
            amountCents: _asInt(r['total_cents']),
          ),
        )
        .toList(growable: false);
  }

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw == null) return 0;
    return int.parse(raw.toString());
  }

  static Color? _parseHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final cleaned = hex.replaceFirst('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return null;
    }
  }
}
