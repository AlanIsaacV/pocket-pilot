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

/// Computes a trend from two halves of a window.
///
/// - Returns `Trend.flat` if either half is zero (insufficient signal)
///   or if the relative difference is below [kTrendFlatThresholdRatio].
/// - Uses the first-half total as the denominator when non-zero.
Trend computeTrend({
  required int firstHalfCents,
  required int secondHalfCents,
}) {
  if (firstHalfCents == 0 || secondHalfCents == 0) return Trend.flat;
  final diff = secondHalfCents - firstHalfCents;
  final ratio = diff.abs() / firstHalfCents.abs();
  if (ratio < kTrendFlatThresholdRatio) return Trend.flat;
  return diff > 0 ? Trend.up : Trend.down;
}
