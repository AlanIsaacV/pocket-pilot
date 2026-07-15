// features/statistics/domain/tag_summary_dto.dart
//
// Resumen de un tag para el listado del hub: nombre, moneda y total
// agregado en la ventana actual (gastos netos: expense - income).

class TagSummaryDTO {
  final String tagName;
  final String currencyCode;
  final int totalCents;

  const TagSummaryDTO({
    required this.tagName,
    required this.currencyCode,
    required this.totalCents,
  });
}
