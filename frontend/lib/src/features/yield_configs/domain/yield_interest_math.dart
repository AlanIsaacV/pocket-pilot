int computeInterestCents({
  required int amountCents,
  required double apyRate,
  required int daysElapsed,
}) {
  final raw = amountCents * (apyRate / 100.0) * (daysElapsed / 365.0);
  return raw.round();
}
