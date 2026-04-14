class TagSpendDTO {
  final String tagName;
  final String currencyCode;
  final int spentCents;

  const TagSpendDTO({
    required this.tagName,
    required this.currencyCode,
    required this.spentCents,
  });

  factory TagSpendDTO.fromMap(Map<String, dynamic> map) {
    return TagSpendDTO(
      tagName: map['tag_name'] as String,
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
