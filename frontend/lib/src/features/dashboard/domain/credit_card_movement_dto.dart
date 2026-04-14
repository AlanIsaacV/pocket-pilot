class CreditCardMovementDTO {
  final String accountId;
  final String type;
  final int amountCents;
  final int installmentsCount;
  final String date;
  final String? nature;

  const CreditCardMovementDTO({
    required this.accountId,
    required this.type,
    required this.amountCents,
    required this.installmentsCount,
    required this.date,
    this.nature,
  });

  factory CreditCardMovementDTO.fromMap(Map<String, dynamic> map) {
    return CreditCardMovementDTO(
      accountId: map['account_id'] as String,
      type: map['type'] as String,
      amountCents: (map['amount_cents'] as num).toInt(),
      installmentsCount: (map['installments_count'] as num).toInt(),
      date: map['date'] as String,
      nature: map['nature'] as String?,
    );
  }
}
