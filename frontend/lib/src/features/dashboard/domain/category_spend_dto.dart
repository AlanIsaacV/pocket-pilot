class CategorySpendDTO {
  final String? categoryId;
  final String? categoryName;
  final String? categoryColor;
  final String currencyCode;
  final int spentCents;

  const CategorySpendDTO({
    required this.categoryId,
    this.categoryName,
    this.categoryColor,
    required this.currencyCode,
    required this.spentCents,
  });

  factory CategorySpendDTO.fromMap(Map<String, dynamic> map) {
    return CategorySpendDTO(
      categoryId: map['category_id'] as String?,
      categoryName: map['category_name'] as String?,
      categoryColor: map['category_color'] as String?,
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
