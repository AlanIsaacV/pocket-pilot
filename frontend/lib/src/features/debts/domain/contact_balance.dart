class ContactCurrencyBalance {
  final String currencyCode;

  /// Saldo calculado en centavos para esta moneda.
  /// Positivo = me deben dinero.
  /// Negativo = yo debo dinero.
  final int balanceCents;

  /// Fecha en formato YYYY-MM-DD de inicio de la deuda activa para esta moneda.
  /// Si el saldo es 0, es null.
  final String? debtOriginDate;

  const ContactCurrencyBalance({
    required this.currencyCode,
    required this.balanceCents,
    this.debtOriginDate,
  });

  bool get isZero => balanceCents == 0;
}

class ContactBalance {
  final String accountId;
  final String contactName;
  final List<ContactCurrencyBalance> balances;

  /// true si la cuenta fue eliminada (soft delete = deuda perdonada).
  final bool isDeleted;

  const ContactBalance({
    required this.accountId,
    required this.contactName,
    required this.balances,
    this.isDeleted = false,
  });

  List<ContactCurrencyBalance> get activeBalances =>
      balances.where((b) => b.balanceCents != 0).toList(growable: false);

  bool get hasActiveDebt => activeBalances.isNotEmpty;

  ContactCurrencyBalance? get primaryBalance {
    if (activeBalances.isNotEmpty) {
      return activeBalances.first;
    }
    if (balances.isEmpty) {
      return null;
    }
    return balances.first;
  }

  ContactCurrencyBalance? get primaryActiveBalance {
    if (activeBalances.isEmpty) return null;
    return activeBalances.first;
  }

  int get totalBalanceCents =>
      balances.fold(0, (sum, b) => sum + b.balanceCents);
}
