// features/statistics/domain/trend.dart
//
// Trend signal for historical category aggregates. Shared between the
// list row (arrow chip) and the detail stat row (neutral-delta color).

/// Relative delta below this ratio counts as "flat" for trend and for
/// neutral-delta coloring. Keeping both in the same constant ensures
/// the arrow chip on the list row and the delta color in the detail
/// screen never disagree.
const double kTrendFlatThresholdRatio = 0.05;

enum Trend { up, down, flat }

/// Computes a trend comparing the current month against the window
/// average. Semantics match `StatDeltaRow._deltaColor` exactly so the
/// list row arrow never disagrees with the detail ±N% badge.
///
/// - Returns `Trend.flat` if `avgCents` is zero (no denominator) or
///   if the rounded percent delta is below [kTrendFlatThresholdRatio].
Trend computeTrend({
  required int currentCents,
  required int avgCents,
}) {
  if (avgCents == 0) return Trend.flat;
  final pct = ((currentCents - avgCents) / avgCents * 100).round();
  final ratio = pct.abs() / 100;
  if (ratio < kTrendFlatThresholdRatio) return Trend.flat;
  return pct > 0 ? Trend.up : Trend.down;
}
