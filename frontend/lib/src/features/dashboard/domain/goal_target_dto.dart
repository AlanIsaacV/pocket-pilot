class GoalTargetDTO {
  final String currencyCode;
  final int totalTargetCents;

  const GoalTargetDTO({
    required this.currencyCode,
    required this.totalTargetCents,
  });

  factory GoalTargetDTO.fromMap(Map<String, dynamic> map) {
    return GoalTargetDTO(
      currencyCode: map['currency_code'] as String,
      totalTargetCents: _asInt(map['total_target_cents']),
    );
  }

  static int _asInt(Object raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.parse(raw.toString());
  }
}
