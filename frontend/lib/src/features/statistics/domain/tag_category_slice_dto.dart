// features/statistics/domain/tag_category_slice_dto.dart
//
// Una rebanada del breakdown por categoría dentro de un tag.
// `kind` indica si la categoría es 'expense' o 'income' para que la UI
// pueda mostrar signos / colores consistentes con CategoriesTab.

class TagCategorySliceDTO {
  final String categoryId;
  final String categoryName;
  final String categoryColor; // hex, e.g. "#A6E3A1"
  final String categoryIcon;
  final String kind; // 'expense' | 'income'
  final int amountCents; // already sign-flipped for income

  const TagCategorySliceDTO({
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.categoryIcon,
    required this.kind,
    required this.amountCents,
  });
}
