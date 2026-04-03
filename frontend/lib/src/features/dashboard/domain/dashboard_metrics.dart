class DashboardMetrics {
  final String currencyCode;
  final int netWorthCents;
  final int liquidAssetsCents;
  final int safeToSpendCents;
  final int buyingPowerCents;

  const DashboardMetrics({
    required this.currencyCode,
    required this.netWorthCents,
    required this.liquidAssetsCents,
    required this.safeToSpendCents,
    required this.buyingPowerCents,
  });

  DashboardMetrics.empty({required this.currencyCode})
      : netWorthCents = 0,
        liquidAssetsCents = 0,
        safeToSpendCents = 0,
        buyingPowerCents = 0;
}
