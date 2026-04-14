class NatureSpendDTO {
  final String nature;
  final String currencyCode;
  final int spentCents;

  const NatureSpendDTO({
    required this.nature,
    required this.currencyCode,
    required this.spentCents,
  });

  factory NatureSpendDTO.fromMap(Map<String, dynamic> map) {
    return NatureSpendDTO(
      nature: (map['nature'] as String?) ?? '',
      currencyCode: map['currency_code'] as String,
      spentCents: _asInt(map['spent_cents']),
    );
  }

  static int _asInt(Object raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.parse(raw.toString());
  }
}
