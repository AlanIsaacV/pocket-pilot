class AccountBalanceDTO {
  final String accountId;
  final String accountName;
  final String accountType;
  final String currencyCode;
  final int balanceCents;
  final int? creditLimitCents;

  const AccountBalanceDTO({
    required this.accountId,
    required this.accountName,
    required this.accountType,
    required this.currencyCode,
    required this.balanceCents,
    this.creditLimitCents,
  });

  factory AccountBalanceDTO.fromMap(Map<String, dynamic> map) {
    return AccountBalanceDTO(
      accountId: map['account_id'] as String,
      accountName: map['account_name'] as String,
      accountType: map['account_type'] as String,
      currencyCode: map['currency_code'] as String,
      balanceCents: _asInt(map['balance_cents']),
      creditLimitCents: map['credit_limit_cents'] as int?,
    );
  }

  static int _asInt(Object raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.parse(raw.toString());
  }
}
