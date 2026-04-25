class DashboardMetrics {
  final String currencyCode;
  final int netWorthCents;
  final int liquidAssetsCents;
  final int safeToSpendCents;
  final int buyingPowerCents;
  final int marketValueOfHoldingsCents;
  final int yieldsValueCents;
  final int debtCents;
  final int revolvingCreditCents;

  const DashboardMetrics({
    required this.currencyCode,
    required this.netWorthCents,
    required this.liquidAssetsCents,
    required this.safeToSpendCents,
    required this.buyingPowerCents,
    this.marketValueOfHoldingsCents = 0,
    this.yieldsValueCents = 0,
    this.debtCents = 0,
    this.revolvingCreditCents = 0,
  });

  DashboardMetrics.empty({required this.currencyCode})
      : netWorthCents = 0,
        liquidAssetsCents = 0,
        safeToSpendCents = 0,
        buyingPowerCents = 0,
        marketValueOfHoldingsCents = 0,
        yieldsValueCents = 0,
        debtCents = 0,
        revolvingCreditCents = 0;
}
