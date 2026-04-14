class CreditCardPaymentDTO {
  final String accountId;
  final String accountName;
  final String currencyCode;
  final int estimatedPaymentCents;

  const CreditCardPaymentDTO({
    required this.accountId,
    required this.accountName,
    required this.currencyCode,
    required this.estimatedPaymentCents,
  });
}
