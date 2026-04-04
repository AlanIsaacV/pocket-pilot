class CreditCardAccountCycleDTO {
  final String accountId;
  final String currencyCode;
  final int? statementDay;
  final int? paymentDueDay;

  const CreditCardAccountCycleDTO({
    required this.accountId,
    required this.currencyCode,
    required this.statementDay,
    required this.paymentDueDay,
  });

  factory CreditCardAccountCycleDTO.fromMap(Map<String, dynamic> map) {
    return CreditCardAccountCycleDTO(
      accountId: map['account_id'] as String,
      currencyCode: map['currency_code'] as String,
      statementDay: map['statement_day'] as int?,
      paymentDueDay: map['payment_due_day'] as int?,
    );
  }
}
